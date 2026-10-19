#!/usr/bin/env python3

import copy
import json
import unittest
from pathlib import Path

import score_recipe_candidates as scoring


class RecipeCandidateScoringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog_path = scoring.DEFAULT_CATALOG
        cls.metrics_path = scoring.DEFAULT_METRICS
        cls.catalog_raw = cls.catalog_path.read_bytes()
        cls.metrics_raw = cls.metrics_path.read_bytes()
        cls.catalog = json.loads(cls.catalog_raw)
        cls.metrics = json.loads(cls.metrics_raw)

    def build(
        self,
        catalog=None,
        metrics=None,
    ):
        catalog = self.catalog if catalog is None else catalog
        metrics = self.metrics if metrics is None else metrics
        return scoring.build_artifact(
            catalog,
            metrics,
            json.dumps(catalog, sort_keys=True).encode(),
            json.dumps(metrics, sort_keys=True).encode(),
            "catalog.json",
            "metrics.json",
        )

    def test_output_is_deterministic_and_stably_ordered(self) -> None:
        first = self.build()
        second = self.build()

        self.assertEqual(first, second)
        self.assertEqual(
            set(first["policy"]["backlog_dimensions"]),
            {
                "installed_profile_frequency",
                "configurability",
                "impact",
                "implementation_confidence",
                "t3_cost",
            },
        )
        self.assertEqual(
            [candidate["candidate_rank"] for candidate in first["candidates"]],
            list(range(1, first["candidate_count"] + 1)),
        )
        actual_order = [
            (
                -candidate["score"]["total"],
                candidate["catalog_rank"],
                candidate["cask"],
            )
            for candidate in first["candidates"]
        ]
        self.assertEqual(actual_order, sorted(actual_order))
        supported = {
            app["cask"]
            for app in self.catalog["applications"]
            if app["local_recipe"] is not None
        }
        self.assertTrue(
            supported.isdisjoint(
                candidate["cask"] for candidate in first["candidates"]
            )
        )

    def test_explicit_tie_breakers(self) -> None:
        candidates = [
            {"_sort": (5000, 8, "zulu")},
            {"_sort": (6000, 9, "alpha")},
            {"_sort": (5000, 8, "alpha")},
            {"_sort": (5000, 7, "zulu")},
        ]
        ordered = scoring.sort_scored_candidates(candidates)
        self.assertEqual(
            [candidate["_sort"] for candidate in ordered],
            [(6000, 9, "alpha"), (5000, 7, "zulu"), (5000, 8, "alpha"), (5000, 8, "zulu")],
        )

    def test_missing_catalog_and_metric_data_are_rejected(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        del catalog["applications"][0]["behavior"]["mechanism"]
        with self.assertRaisesRegex(
            scoring.ScoringError,
            r"catalog\.applications\[0\]\.behavior\.mechanism is required",
        ):
            self.build(catalog=catalog)

        metrics = copy.deepcopy(self.metrics)
        del metrics["local_recipe_apps"]
        with self.assertRaisesRegex(
            scoring.ScoringError, r"metrics\.local_recipe_apps is required"
        ):
            self.build(metrics=metrics)

    def test_every_score_is_bounded_and_output_validation_enforces_bounds(self) -> None:
        artifact = self.build()
        for candidate in artifact["candidates"]:
            for component in ("total", "impact", "feasibility", "risk"):
                self.assertGreaterEqual(candidate["score"][component], 0)
                self.assertLessEqual(candidate["score"][component], 100)

        artifact["candidates"][0]["score"]["risk"] = 100.01
        with self.assertRaisesRegex(scoring.ScoringError, "must be between 0 and 100"):
            scoring.validate_output(artifact)

    def test_checked_in_artifact_is_current(self) -> None:
        artifact = scoring.build_artifact(
            self.catalog,
            self.metrics,
            self.catalog_raw,
            self.metrics_raw,
            "packages/app-state/catalog/homebrew-top-200-apps.json",
            "packages/app-state/metrics/zero-click.json",
        )
        expected = scoring.render_artifact(artifact)
        output = Path(scoring.DEFAULT_OUTPUT).read_text(encoding="utf-8")
        self.assertEqual(output, expected)


if __name__ == "__main__":
    unittest.main()
