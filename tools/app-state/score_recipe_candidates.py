#!/usr/bin/env python3
"""Rank Homebrew catalog entries for future app-state recipe work."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SCALE = 10_000
WEIGHTS = {"impact": 45, "feasibility": 40, "risk_adjusted": 15}
IMPACT_WEIGHTS = {"installs": 70, "catalog_reach": 30}
FEASIBILITY_BASE = {
    "defaults_dominant": 90,
    "file_driven": 85,
    "hybrid": 65,
    "cloud_or_opaque": 20,
}
FEASIBILITY_CONFIDENCE = {"high": 10, "medium": 0, "low": -15}
FEASIBILITY_EVIDENCE = {
    "curated": 5,
    "homebrew_zap_paths": 0,
    "homebrew_app_artifact": -10,
}
RISK_BASE = {
    "defaults_dominant": 20,
    "file_driven": 25,
    "hybrid": 50,
    "cloud_or_opaque": 90,
}
RISK_CONFIDENCE = {"high": -10, "medium": 0, "low": 15}
RISK_EVIDENCE = {
    "curated": -10,
    "homebrew_zap_paths": 0,
    "homebrew_app_artifact": 10,
}

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = REPO_ROOT / "packages/app-state/catalog/homebrew-top-200-apps.json"
DEFAULT_METRICS = REPO_ROOT / "packages/app-state/metrics/zero-click.json"
DEFAULT_OUTPUT = REPO_ROOT / "packages/app-state/metrics/recipe-candidates.json"


class ScoringError(ValueError):
    """Raised when scoring inputs or generated output violate the v1 contract."""


def _required(mapping: Any, key: str, path: str) -> Any:
    if not isinstance(mapping, dict):
        raise ScoringError(f"{path} must be an object")
    if key not in mapping:
        raise ScoringError(f"{path}.{key} is required")
    return mapping[key]


def _integer(value: Any, path: str, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ScoringError(f"{path} must be an integer")
    if minimum is not None and value < minimum:
        raise ScoringError(f"{path} must be at least {minimum}")
    return value


def _number(value: Any, path: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ScoringError(f"{path} must be a number")
    numeric = float(value)
    if not minimum <= numeric <= maximum:
        raise ScoringError(f"{path} must be between {minimum} and {maximum}")
    return numeric


def _string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value:
        raise ScoringError(f"{path} must be a non-empty string")
    return value


def _string_list(value: Any, path: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ScoringError(f"{path} must be an array of strings")
    return value


def _rounded_div(numerator: int, denominator: int) -> int:
    if denominator <= 0 or numerator < 0:
        raise ScoringError("internal scoring division requires non-negative values")
    return (2 * numerator + denominator) // (2 * denominator)


def _clamp_percent(value: int) -> int:
    return max(0, min(100, value))


def _score_number(basis_points: int) -> int | float:
    if basis_points % 100 == 0:
        return basis_points // 100
    return basis_points / 100


def _format_score(basis_points: int) -> str:
    return f"{basis_points / 100:.2f}"


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise ScoringError(f"cannot read {label} {path}: {error}") from error
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ScoringError(f"invalid JSON in {label} {path}: {error}") from error
    if not isinstance(value, dict):
        raise ScoringError(f"{label} must contain a JSON object")
    return value, raw


def _validate_inputs(
    catalog: dict[str, Any], metrics: dict[str, Any]
) -> tuple[list[dict[str, Any]], int, dict[str, int]]:
    if _required(catalog, "version", "catalog") != 1:
        raise ScoringError("catalog.version must be 1")
    selection = _required(catalog, "selection", "catalog")
    denominator = _integer(
        _required(selection, "denominator", "catalog.selection"),
        "catalog.selection.denominator",
        1,
    )
    source = _required(catalog, "source", "catalog")
    _string(_required(source, "start_date", "catalog.source"), "catalog.source.start_date")
    _string(_required(source, "end_date", "catalog.source"), "catalog.source.end_date")

    applications = _required(catalog, "applications", "catalog")
    if not isinstance(applications, list):
        raise ScoringError("catalog.applications must be an array")
    if len(applications) != denominator:
        raise ScoringError(
            "catalog.applications length must equal catalog.selection.denominator"
        )

    ranks: set[int] = set()
    casks: set[str] = set()
    supported_count = 0
    for index, app in enumerate(applications):
        path = f"catalog.applications[{index}]"
        rank = _integer(_required(app, "rank", path), f"{path}.rank", 1)
        if rank > denominator:
            raise ScoringError(f"{path}.rank must not exceed {denominator}")
        if rank in ranks:
            raise ScoringError(f"{path}.rank duplicates rank {rank}")
        ranks.add(rank)

        cask = _string(_required(app, "cask", path), f"{path}.cask")
        if cask in casks:
            raise ScoringError(f"{path}.cask duplicates {cask}")
        casks.add(cask)

        _integer(_required(app, "analytics_rank", path), f"{path}.analytics_rank", 1)
        _integer(_required(app, "installs", path), f"{path}.installs", 1)
        _number(_required(app, "percent", path), f"{path}.percent", 0, 100)
        _string(_required(app, "name", path), f"{path}.name")
        _string(_required(app, "description", path), f"{path}.description")
        _string(_required(app, "homepage", path), f"{path}.homepage")

        behavior = _required(app, "behavior", path)
        mechanism = _required(behavior, "mechanism", f"{path}.behavior")
        confidence = _required(behavior, "confidence", f"{path}.behavior")
        evidence = _required(behavior, "evidence", f"{path}.behavior")
        if mechanism not in FEASIBILITY_BASE:
            raise ScoringError(f"{path}.behavior.mechanism is not supported")
        if confidence not in FEASIBILITY_CONFIDENCE:
            raise ScoringError(f"{path}.behavior.confidence is not supported")
        if evidence not in FEASIBILITY_EVIDENCE:
            raise ScoringError(f"{path}.behavior.evidence is not supported")
        _string(_required(behavior, "note", f"{path}.behavior"), f"{path}.behavior.note")

        signals = _required(app, "signals", path)
        _string_list(
            _required(signals, "preference_paths", f"{path}.signals"),
            f"{path}.signals.preference_paths",
        )
        _string_list(
            _required(signals, "config_paths", f"{path}.signals"),
            f"{path}.signals.config_paths",
        )

        local_recipe = _required(app, "local_recipe", path)
        if local_recipe is not None:
            _string(local_recipe, f"{path}.local_recipe")
            supported_count += 1

    if ranks != set(range(1, denominator + 1)):
        raise ScoringError("catalog application ranks must cover 1 through denominator")

    if _required(metrics, "version", "metrics") != 1:
        raise ScoringError("metrics.version must be 1")
    metric_fields = (
        "denominator",
        "behavior_mapped_apps",
        "local_recipe_apps",
        "zero_click_apps",
        "one_click_apps",
        "full_manual_apps",
        "uncovered_apps",
    )
    metric_summary = {
        field: _integer(_required(metrics, field, "metrics"), f"metrics.{field}", 0)
        for field in metric_fields
    }
    if metric_summary["denominator"] != denominator:
        raise ScoringError("metrics.denominator must match the catalog denominator")
    if metric_summary["behavior_mapped_apps"] != denominator:
        raise ScoringError("metrics.behavior_mapped_apps must match the catalog denominator")
    if metric_summary["local_recipe_apps"] != supported_count:
        raise ScoringError("metrics.local_recipe_apps must match catalog local_recipe entries")
    covered = (
        metric_summary["zero_click_apps"]
        + metric_summary["one_click_apps"]
        + metric_summary["full_manual_apps"]
    )
    if covered != supported_count:
        raise ScoringError("metric interaction counts must sum to metrics.local_recipe_apps")
    if metric_summary["uncovered_apps"] != denominator - supported_count:
        raise ScoringError("metrics.uncovered_apps must equal denominator minus local recipes")

    return applications, denominator, metric_summary


def _impact_score(
    app: dict[str, Any], denominator: int, maximum_installs: int
) -> tuple[int, str]:
    install_score = _rounded_div(app["installs"] * SCALE, maximum_installs)
    reach_score = _rounded_div((denominator - app["rank"] + 1) * SCALE, denominator)
    score = _rounded_div(
        install_score * IMPACT_WEIGHTS["installs"]
        + reach_score * IMPACT_WEIGHTS["catalog_reach"],
        100,
    )
    rationale = (
        f"{_format_score(install_score)} normalized installs x 70%; "
        f"{_format_score(reach_score)} catalog reach x 30%"
    )
    return score, rationale


def _feasibility_score(app: dict[str, Any]) -> tuple[int, str]:
    behavior = app["behavior"]
    mechanism = behavior["mechanism"]
    confidence = behavior["confidence"]
    evidence = behavior["evidence"]
    signals = app["signals"]
    preference_bonus = (
        5
        if signals["preference_paths"]
        and mechanism in ("defaults_dominant", "hybrid")
        else 0
    )
    config_bonus = (
        5
        if signals["config_paths"] and mechanism in ("file_driven", "hybrid")
        else 0
    )
    raw_score = (
        FEASIBILITY_BASE[mechanism]
        + FEASIBILITY_CONFIDENCE[confidence]
        + FEASIBILITY_EVIDENCE[evidence]
        + preference_bonus
        + config_bonus
    )
    score = _clamp_percent(raw_score) * 100
    rationale = (
        f"{mechanism} base {FEASIBILITY_BASE[mechanism]}; "
        f"confidence {confidence} {FEASIBILITY_CONFIDENCE[confidence]:+d}; "
        f"evidence {evidence} {FEASIBILITY_EVIDENCE[evidence]:+d}; "
        f"preference signal {preference_bonus:+d}; config signal {config_bonus:+d}"
    )
    return score, rationale


def _risk_score(app: dict[str, Any]) -> tuple[int, str]:
    behavior = app["behavior"]
    mechanism = behavior["mechanism"]
    confidence = behavior["confidence"]
    evidence = behavior["evidence"]
    signals = app["signals"]
    no_path_penalty = 10 if not (
        signals["preference_paths"] or signals["config_paths"]
    ) else 0
    multi_surface_penalty = (
        5
        if mechanism == "hybrid"
        and signals["preference_paths"]
        and signals["config_paths"]
        else 0
    )
    raw_score = (
        RISK_BASE[mechanism]
        + RISK_CONFIDENCE[confidence]
        + RISK_EVIDENCE[evidence]
        + no_path_penalty
        + multi_surface_penalty
    )
    score = _clamp_percent(raw_score) * 100
    rationale = (
        f"{mechanism} base {RISK_BASE[mechanism]}; "
        f"confidence {confidence} {RISK_CONFIDENCE[confidence]:+d}; "
        f"evidence {evidence} {RISK_EVIDENCE[evidence]:+d}; "
        f"no path {no_path_penalty:+d}; multi-surface {multi_surface_penalty:+d}"
    )
    return score, rationale


def _score_candidate(
    app: dict[str, Any], denominator: int, maximum_installs: int
) -> dict[str, Any]:
    impact, impact_rationale = _impact_score(app, denominator, maximum_installs)
    feasibility, feasibility_rationale = _feasibility_score(app)
    risk, risk_rationale = _risk_score(app)
    total = _rounded_div(
        impact * WEIGHTS["impact"]
        + feasibility * WEIGHTS["feasibility"]
        + (SCALE - risk) * WEIGHTS["risk_adjusted"],
        100,
    )
    return {
        "_sort": (total, app["rank"], app["cask"]),
        "catalog_rank": app["rank"],
        "analytics_rank": app["analytics_rank"],
        "cask": app["cask"],
        "name": app["name"],
        "description": app["description"],
        "homepage": app["homepage"],
        "installs": app["installs"],
        "percent": app["percent"],
        "behavior": {
            "mechanism": app["behavior"]["mechanism"],
            "confidence": app["behavior"]["confidence"],
            "evidence": app["behavior"]["evidence"],
            "note": app["behavior"]["note"],
        },
        "signals": {
            "preference_paths": app["signals"]["preference_paths"],
            "config_paths": app["signals"]["config_paths"],
        },
        "score": {
            "total": _score_number(total),
            "impact": _score_number(impact),
            "feasibility": _score_number(feasibility),
            "risk": _score_number(risk),
        },
        "rationale": {
            "impact": impact_rationale,
            "feasibility": feasibility_rationale,
            "risk": risk_rationale,
        },
    }


def sort_scored_candidates(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Sort by score descending, then catalog rank and cask ascending."""
    return sorted(
        candidates,
        key=lambda candidate: (
            -candidate["_sort"][0],
            candidate["_sort"][1],
            candidate["_sort"][2],
        ),
    )


def build_artifact(
    catalog: dict[str, Any],
    metrics: dict[str, Any],
    catalog_raw: bytes,
    metrics_raw: bytes,
    catalog_source: str,
    metrics_source: str,
) -> dict[str, Any]:
    applications, denominator, metric_summary = _validate_inputs(catalog, metrics)
    candidates = [app for app in applications if app["local_recipe"] is None]
    if not candidates:
        raise ScoringError("catalog has no unsupported applications to score")
    maximum_installs = max(app["installs"] for app in candidates)
    scored = sort_scored_candidates(
        [_score_candidate(app, denominator, maximum_installs) for app in candidates]
    )
    for candidate_rank, candidate in enumerate(scored, start=1):
        candidate.pop("_sort")
        candidate["candidate_rank"] = candidate_rank

    supported = [
        {
            "catalog_rank": app["rank"],
            "cask": app["cask"],
            "local_recipe": app["local_recipe"],
        }
        for app in applications
        if app["local_recipe"] is not None
    ]
    artifact = {
        "schema_version": SCHEMA_VERSION,
        "generated_from": {
            "catalog": catalog_source,
            "catalog_version": catalog["version"],
            "catalog_sha256": _sha256(catalog_raw),
            "metrics": metrics_source,
            "metrics_version": metrics["version"],
            "metrics_sha256": _sha256(metrics_raw),
            "analytics_start_date": catalog["source"]["start_date"],
            "analytics_end_date": catalog["source"]["end_date"],
        },
        "metric_summary": metric_summary,
        "policy": {
            "score_minimum": 0,
            "score_maximum": 100,
            "formula": "impact * 0.45 + feasibility * 0.40 + (100 - risk) * 0.15",
            "weights": {
                "impact": 0.45,
                "feasibility": 0.40,
                "risk_adjusted": 0.15,
            },
            "backlog_dimensions": {
                "installed_profile_frequency": (
                    "365-day Homebrew installs are the deterministic proxy; the "
                    "repository has no per-profile usage telemetry."
                ),
                "configurability": (
                    "Catalog mechanism and preference/config path signals contribute "
                    "to feasibility and risk."
                ),
                "impact": (
                    "Normalized installs and top-200 catalog reach estimate the benefit "
                    "of adding a recipe."
                ),
                "implementation_confidence": (
                    "Catalog confidence and evidence quality adjust feasibility and risk."
                ),
                "t3_cost": (
                    "Mechanism complexity, missing paths, and hybrid multi-surface work "
                    "contribute to risk."
                ),
            },
            "tie_breakers": [
                "total score descending",
                "catalog rank ascending",
                "cask ascending",
            ],
            "impact": {
                "rationale": (
                    "Estimated reach from installs and position in the top-200 app "
                    "catalog."
                ),
                "installs_weight": 0.70,
                "catalog_reach_weight": 0.30,
                "normalization": (
                    "Candidate installs divided by the highest unsupported candidate "
                    "installs; catalog reach is (201 - catalog rank) / 200."
                ),
            },
            "feasibility": {
                "rationale": (
                    "Higher values favor well-understood local configuration surfaces "
                    "with concrete path signals."
                ),
                "mechanism_base": FEASIBILITY_BASE,
                "confidence_adjustment": FEASIBILITY_CONFIDENCE,
                "evidence_adjustment": FEASIBILITY_EVIDENCE,
                "preference_signal_bonus": 5,
                "config_signal_bonus": 5,
            },
            "risk": {
                "rationale": (
                    "Higher values mean more implementation or fidelity risk and reduce "
                    "the total score."
                ),
                "mechanism_base": RISK_BASE,
                "confidence_adjustment": RISK_CONFIDENCE,
                "evidence_adjustment": RISK_EVIDENCE,
                "no_path_penalty": 10,
                "hybrid_multi_surface_penalty": 5,
            },
        },
        "exclusions": {
            "rule": "Exclude catalog entries whose local_recipe is not null.",
            "already_supported_count": len(supported),
            "already_supported": supported,
        },
        "candidate_count": len(scored),
        "candidates": scored,
    }
    validate_output(artifact)
    return artifact


def validate_output(artifact: dict[str, Any]) -> None:
    if artifact.get("schema_version") != SCHEMA_VERSION:
        raise ScoringError(f"output.schema_version must be {SCHEMA_VERSION}")
    candidates = artifact.get("candidates")
    if not isinstance(candidates, list):
        raise ScoringError("output.candidates must be an array")
    if artifact.get("candidate_count") != len(candidates):
        raise ScoringError("output.candidate_count must match output.candidates length")
    previous_key: tuple[float, int, str] | None = None
    for index, candidate in enumerate(candidates):
        path = f"output.candidates[{index}]"
        if candidate.get("candidate_rank") != index + 1:
            raise ScoringError(f"{path}.candidate_rank must be {index + 1}")
        score = _required(candidate, "score", path)
        for component in ("total", "impact", "feasibility", "risk"):
            _number(
                _required(score, component, f"{path}.score"),
                f"{path}.score.{component}",
                0,
                100,
            )
        catalog_rank = _integer(
            _required(candidate, "catalog_rank", path), f"{path}.catalog_rank", 1
        )
        cask = _string(_required(candidate, "cask", path), f"{path}.cask")
        key = (-float(score["total"]), catalog_rank, cask)
        if previous_key is not None and key < previous_key:
            raise ScoringError("output.candidates do not follow the stable ordering policy")
        previous_key = key


def render_artifact(artifact: dict[str, Any]) -> str:
    validate_output(artifact)
    return json.dumps(artifact, indent=2, sort_keys=False) + "\n"


def _display_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rank unsupported Homebrew apps for app-state recipe implementation."
    )
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--metrics", type=Path, default=DEFAULT_METRICS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in output differs from a fresh scoring run",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        catalog, catalog_raw = _load_json(args.catalog, "catalog")
        metrics, metrics_raw = _load_json(args.metrics, "metrics")
        artifact = build_artifact(
            catalog,
            metrics,
            catalog_raw,
            metrics_raw,
            _display_path(args.catalog),
            _display_path(args.metrics),
        )
        rendered = render_artifact(artifact)
        if args.check:
            try:
                current = args.output.read_text(encoding="utf-8")
            except OSError as error:
                raise ScoringError(f"cannot read output {args.output}: {error}") from error
            if current != rendered:
                print(
                    f"error: {args.output} is stale; run {Path(__file__).relative_to(REPO_ROOT)}",
                    file=sys.stderr,
                )
                return 3
            print(f"Recipe candidate ranking is current: {args.output}")
            return 0

        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {len(artifact['candidates'])} candidates to {args.output}")
        return 0
    except ScoringError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"error: cannot write output {args.output}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
