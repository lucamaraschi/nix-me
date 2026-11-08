"""Read-only drift scans and explicitly reviewed, selective reconciliation.

No Git mutations, sudo, broad cleanup, or arbitrary command execution. All
action targets are regenerated from the manifest and live inventory, never
accepted as filesystem paths or command lines from the client.
"""

import contextlib
import datetime
import difflib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

MAX_TEXT = 512 * 1024
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9@+._/-]*$")
HOST = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
PRIVATE = re.compile(r"(^|/)(\.ssh|\.gnupg|\.aws|\.kube|\.netrc|\.npmrc|\.pypirc|credentials[^/]*|secrets?[^/]*|auth\.json|.*\.key)(/|$)", re.I)
SECRET = re.compile(r"-----BEGIN .*PRIVATE KEY-----|(?:password|api[_-]?key|(?:access|refresh|auth)[_-]?token|client[_-]?secret)[\"']?\s*[=:]\s*[\"']?[^\s\"'$}]{2,}|(?:ghp_|github_pat_|sk-)[A-Za-z0-9_\-]{16,}", re.I)


class DriftError(Exception):
    pass


def digest(value):
    if not isinstance(value, bytes):
        value = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(value).hexdigest()


def nix_string(value):
    return json.dumps(value, ensure_ascii=False).replace("${", "\\${")


def text_diff(before, after, path):
    return "\n".join(difflib.unified_diff((before or "").splitlines(), after.splitlines(),
        fromfile="a/" + path if before is not None else "/dev/null", tofile="b/" + path, lineterm=""))


def run(args, cwd=None, timeout=120):
    result = subprocess.run(args, cwd=cwd, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1"), timeout=timeout)
    if result.returncode:
        message = (result.stderr or result.stdout).decode(errors="replace")[-8000:]
        raise DriftError(message.strip() or "Command failed: " + args[0])
    return result.stdout


def json_file(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text())


def safe_relative(value):
    return isinstance(value, str) and bool(value) and not value.startswith("/") and all(
        part not in ("", ".", "..") for part in value.split("/"))


def path_state(path, store_root="/nix/store/"):
    try:
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            resolved = str(path.resolve())
            trusted = resolved.startswith(store_root)
            return {"type": "link", "target": os.readlink(path), "resolved": str(path.resolve()),
                    "hash": digest(path.read_bytes()) if trusted and path.is_file() and path.stat().st_size <= MAX_TEXT else None,
                    "executable": bool(path.stat().st_mode & 0o111) if trusted and path.is_file() else None}
        if not stat.S_ISREG(info.st_mode):
            return {"type": "unsupported"}
        if info.st_size > MAX_TEXT:
            return {"type": "large", "size": info.st_size, "modified": info.st_mtime_ns}
        return {"type": "file", "hash": digest(path.read_bytes()), "executable": bool(info.st_mode & 0o111)}
    except FileNotFoundError:
        return {"type": "missing"}
    except OSError:
        return {"type": "unreadable"}


def file_target(home, relative):
    if not safe_relative(relative) or PRIVATE.search(relative):
        raise DriftError("Private or unsafe file path is excluded: " + str(relative))
    target = home / relative
    # Never mutate through a redirected parent (including Home Manager directory links).
    if target.parent.resolve() != target.parent:
        raise DriftError("A parent directory is a symbolic link: " + relative)
    return target


def brew_inventory(data):
    installed = {"formula": {}, "cask": {}}
    for entry in data.get("formulae", []):
        receipts = entry.get("installed", [])
        if not receipts:
            continue
        name = entry.get("full_name") or entry["name"]
        aliases = set([name, entry["name"]] + entry.get("aliases", []) + entry.get("oldnames", []))
        installed["formula"][name] = {
            "aliases": sorted(aliases), "versions": sorted({r["version"] for r in receipts}),
            # Unknown provenance is not evidence that a dependency was installed manually.
            "explicit": any(r.get("installed_on_request") is True for r in receipts),
        }
    for entry in data.get("casks", []):
        versions = entry.get("installed")
        if not versions:
            continue
        name = entry.get("full_token") or entry["token"]
        installed["cask"][name] = {"aliases": sorted(set([name, entry["token"]] + entry.get("old_tokens", []))),
                                   "versions": versions if isinstance(versions, list) else [versions], "explicit": True}
    return installed


def software_rows(desired, applied, installed):
    rows = []
    for kind, field in [("formula", "formulae"), ("cask", "casks")]:
        wanted = set(desired.get(field, []))
        baseline = set(applied.get(field, [])) if applied is not None else None
        found = installed[kind]
        aliases = {alias for item in found.values() for alias in item["aliases"]}
        for name in sorted(wanted - aliases):
            # A newly declared package is pending configuration, not local drift.
            if baseline is not None and name not in baseline:
                continue
            rows.append({"id": kind + ":" + name, "kind": kind, "name": name, "change": "missing",
                         "current": "Not installed", "expected": "Installed", "canKeep": True, "canRestore": True,
                         "note": "Saving removes this package from the chosen configuration scope. Review the affected hosts first."})
        for name, item in sorted(found.items()):
            if not item["explicit"] or wanted.intersection(item["aliases"]):
                continue
            if baseline is not None and baseline.intersection(item["aliases"]):
                continue  # A configured removal is already listed under pending changes.
            rows.append({"id": kind + ":" + name, "kind": kind, "name": name, "change": "extra",
                         "current": "Installed: " + ", ".join(item["versions"]), "expected": "Not declared",
                         "canKeep": True, "canRestore": True,
                         "note": "Restore uninstalls only this package, without --zap, --force, or dependency cleanup."})
    return rows


class DriftService:
    def __init__(self, checkout, host, home=None, applied_path=None, runner=run, store_root="/nix/store", support_template=None):
        self.checkout = Path(checkout).resolve()
        self.host = host
        if not HOST.fullmatch(host):
            raise DriftError("Invalid host name")
        self.home = Path(home or Path.home()).resolve()
        self.applied_path = Path(applied_path or "/etc/nix-me/manifest.json")
        self.runner = runner
        self.store_root = str(Path(store_root).resolve()) + "/"
        self.destination = self.checkout / "config/machine-state/machines" / (host + ".json")
        bundled = Path(__file__).with_name("machine-state.nix")
        self.support_template = Path(support_template) if support_template else (
            bundled if bundled.is_file() else Path(__file__).resolve().parents[3] / "nix/modules/darwin/machine-state.nix")

    def support_changes(self):
        module = self.checkout / "nix/modules/darwin/machine-state.nix"
        imports = self.checkout / "nix/modules/darwin/default.nix"
        try:
            self.validate_destination(module)
            self.validate_destination(imports)
            if module.exists() or not imports.is_file() or not self.support_template.is_file():
                return []
            before = imports.read_bytes().decode()
            anchor = r"(?m)^([ \t]+)\./management-api\.nix[ \t]*$"
            if len(re.findall(anchor, before)) != 1 or "./machine-state.nix" in before or len(re.findall(r"imports\s*=\s*\[", before)) != 1:
                return []
            after = re.sub(anchor, r"\g<0>\n\1./machine-state.nix", before)
            return [{"path": str(module.relative_to(self.checkout)), "before": None, "after": self.support_template.read_text()},
                    {"path": str(imports.relative_to(self.checkout)), "before": before, "after": after}]
        except (OSError, DriftError):
            return []

    def publication(self):
        state_root = self.checkout / "config/machine-state"
        if not state_root.is_dir() or not any(state_root.rglob("*.json")):
            return None
        path = "config/machine-state"
        files = [path, "nix/modules/darwin/machine-state.nix", "nix/modules/darwin/default.nix"]
        git = shutil.which("git")
        state = "unavailable"
        if git:
            try:
                # Local metadata only. Never stage, commit, fetch, or push.
                dirty = self.runner([git, "status", "--porcelain=v1", "--untracked-files=all", "--", *files], cwd=self.checkout, timeout=5)
                if dirty.strip():
                    state = "localChanges"
                else:
                    changed = self.runner([git, "diff", "--name-only", "@{upstream}", "--", *files], cwd=self.checkout, timeout=5)
                    state = "differentFromUpstream" if changed.strip() else "matchesLastKnownUpstream"
            except (DriftError, subprocess.TimeoutExpired):
                pass
        return {"path": path, "state": state}

    def desired(self):
        nix = shutil.which("nix")
        if not nix:
            raise DriftError("Nix is required to compare the selected configuration.")
        return json.loads(self.runner([nix, "--extra-experimental-features", "nix-command flakes", "eval",
                                      "--json", "--impure", "path:" + str(self.checkout) +
                                      "#darwinConfigurations." + self.host + ".config.nixMe.manifest"], cwd=self.checkout))

    def evaluate_scopes(self, candidate=None):
        """Evaluate actual host membership, never infer it by parsing Nix source."""
        template = self.checkout / "nix/modules/darwin/machine-state.nix"
        if not template.is_file():
            template = self.support_template
        payload = nix_string(json.dumps(candidate))
        expression = '''let
          flake = builtins.getFlake %s;
          candidate = builtins.fromJSON %s;
          prepare = system: if system.config.nixMe ? driftDestinations then system
            else system.extendModules { modules = [ (builtins.toPath %s) ]; };
          selected = items: cfg: map (item: {
            inherit (item) id name;
            installed = builtins.elem item.name (if item.kind == "formula"
              then map (v: v.name) cfg.homebrew.brews else map (v: v.name) cfg.homebrew.casks);
          }) items;
        in builtins.mapAttrs (host: original:
          let system = prepare original;
              layers = system.config.nixMe.driftDestinations;
              layerIDs = map (item: item.id) layers;
              included = candidate != null && builtins.any (id: builtins.elem id layerIDs) (builtins.attrNames candidate.states);
              items = builtins.filter (item: builtins.elem item.destinationID layerIDs) candidate.items;
              proposed = system.extendModules { modules = [{
                nixMe.machineStateOverrides = candidate.states;
              }]; };
          in if candidate == null then { inherit layers; }
          else if !included then null else {
            before = selected items system.config;
            after = selected items proposed.config;
            errors = map (a: a.message) (builtins.filter (a: !a.assertion) proposed.config.assertions);
          }
        ) flake.darwinConfigurations''' % (nix_string("path:" + str(self.checkout)), payload, nix_string(str(template)))
        nix = shutil.which("nix")
        if not nix:
            raise DriftError("Nix is required to check configuration destinations.")
        return json.loads(self.runner([nix, "--extra-experimental-features", "nix-command flakes", "eval",
                                       "--json", "--impure", "--expr", expression], cwd=self.checkout))

    def destinations(self, matrix):
        result = []
        for layer in matrix.get(self.host, {}).get("layers", []):
            scope, name = layer["scope"], layer["name"]
            if scope not in ("shared", "type", "profile", "machine") or not HOST.fullmatch(name):
                raise DriftError("Unsupported configuration layer.")
            path = "config/machine-state/" + ("shared.json" if scope == "shared" else
                    {"type": "types", "profile": "profiles", "machine": "machines"}[scope] + "/" + name + ".json")
            if layer["path"] != path or layer["id"] != scope + ":" + name:
                raise DriftError("Invalid configuration destination.")
            result.append({key: layer[key] for key in ("id", "scope", "name", "source", "path")})
            result[-1]["hosts"] = sorted(host for host, value in matrix.items()
                if any(item["id"] == layer["id"] for item in value["layers"]))
        return result

    def scan(self):
        desired = self.desired()
        if desired.get("host", {}).get("username") != self.home.name:
            raise DriftError("This configuration belongs to a different user; choose this Mac's configuration.")
        applied = json_file(self.applied_path)
        if applied and applied.get("host", {}).get("hostname") != self.host:
            raise DriftError("The active system belongs to another host. Apply the selected host before reviewing machine drift.")
        warnings, rows, evidence = [], [], {}
        coverage = {"homebrew": False, "files": []}
        brew = shutil.which("brew")
        if brew:
            try:
                inventory = brew_inventory(json.loads(self.runner([brew, "info", "--json=v2", "--installed"])))
                rows = software_rows(desired["software"]["homebrew"],
                                     applied["software"]["homebrew"] if applied else None, inventory)
                evidence["brew"] = inventory
                coverage["homebrew"] = True
            except (DriftError, subprocess.TimeoutExpired) as error:
                warnings.append("Homebrew was not checked: " + str(error))
        else:
            warnings.append("Homebrew is unavailable; software drift was not checked.")
        sources = {f["target"]: f for f in (applied or {}).get("managedFiles", [])}
        if "managedFiles" not in desired:
            warnings.append("Update the configuration checkout to enable managed-dotfile comparison.")
        elif applied and "managedFiles" not in applied:
            warnings.append("The applied generation has no dotfile baseline. File differences are against the current configuration, not proven changes since apply.")
        for entry in desired.get("managedFiles", []):
            relative = entry["target"]
            if applied and "managedFiles" in applied and relative not in sources:
                continue  # Newly declared files belong to Repository -> Mac, not live drift.
            try:
                target = file_target(self.home, relative)
            except DriftError as error:
                warnings.append(str(error))
                continue
            source = Path(entry["source"])
            if not str(source).startswith(self.store_root) or not str(source.resolve()).startswith(self.store_root):
                warnings.append("Unmanaged file source excluded: " + relative)
                continue
            actual, expected = path_state(target, self.store_root), path_state(source, self.store_root)
            evidence[relative] = {"actual": actual, "expected": expected}
            if source.is_dir():
                warnings.append("Directory-managed content is not compared: " + relative)
                continue
            if expected["type"] not in ("file", "link") or not expected.get("hash"):
                warnings.append("Build and apply the configuration to compare: " + relative)
                continue
            if actual["type"] in ("unsupported", "large", "unreadable"):
                warnings.append("Cannot safely inspect file: " + relative)
                continue
            coverage["files"].append(relative)
            same_content = actual.get("hash") == expected["hash"]
            baseline = sources.get(relative)
            baseline_state = path_state(Path(baseline["source"]), self.store_root) if baseline else None
            executable = entry.get("executable")
            executable = expected.get("executable", False) if executable is None else executable
            baseline_executable = baseline.get("executable") if baseline else None
            if baseline_state and baseline_executable is None:
                baseline_executable = baseline_state.get("executable")
            declaration_changed = bool(baseline_state and (
                baseline_state.get("hash") != expected["hash"] or baseline_executable != executable))
            if declaration_changed and actual.get("hash") == baseline_state.get("hash") and actual.get("executable") == baseline_executable:
                continue
            same_mode = actual.get("executable") == executable
            if same_content and same_mode:
                continue
            change = "missing" if actual["type"] == "missing" else "modified"
            rows.append({"id": "file:" + relative, "kind": "file", "name": relative, "change": change,
                         "current": "Missing" if change == "missing" else "Changed locally",
                         "expected": "Managed file", "canKeep": actual["type"] in ("missing", "file"),
                         "canRestore": True, "note": "Restore backs up the local entry, then restores the configured contents and executable flag.",
                         "conflict": declaration_changed,
                         "source": str(source), "executable": executable, "declaration": entry["name"], "state": actual})
        for row in rows:
            if row["kind"] != "file" and (not NAME.fullmatch(row["name"]) or ".." in row["name"].split("/")):
                row.update(canKeep=False, canRestore=False)
        supported = desired.get("reconciliationVersion") == 1
        support = self.support_changes() if not supported else []
        if not supported and not support:
            for row in rows:
                row["canKeep"] = False
            warnings.append("Update the configuration checkout before keeping local changes.")
        if not applied:
            warnings.append("No applied baseline found. These are current differences, not proven changes since an apply.")
        evidence["override"] = path_state(self.destination)
        evidence["support"] = support
        destinations = [{"id": "machine:" + self.host, "scope": "machine", "name": self.host,
                         "source": "nix/hosts/machines/" + self.host + "/default.nix",
                         "path": str(self.destination.relative_to(self.checkout)), "hosts": [self.host]}]
        if desired.get("reconciliationScopesVersion") == 1 or support:
            try:
                matrix = self.evaluate_scopes()
                evaluated = self.destinations(matrix)
                if not evaluated or evaluated[-1]["id"] != "machine:" + self.host:
                    raise DriftError("The selected host has no machine destination.")
                destinations = evaluated
                evidence["hierarchy"] = matrix
                evidence["layerFiles"] = {item["path"]: path_state(self.checkout / item["path"]) for item in destinations}
            except (DriftError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
                warnings.append("Shared destinations unavailable; saving is machine-only: " + str(error))
        token = digest({"checkout": str(self.checkout), "host": self.host, "home": str(self.home),
                        "desired": desired, "applied": applied, "evidence": evidence})
        return {"schemaVersion": 1, "host": self.host, "token": token, "coverage": coverage,
                "canKeepChanges": supported or bool(support), "needsSavingSupport": bool(support), "publication": self.publication(),
                "configurationToken": digest([desired, applied, evidence["override"], evidence.get("hierarchy")]),
                "checkedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "destination": str(self.destination.relative_to(self.checkout)), "destinations": destinations,
                "items": rows, "warnings": warnings}

    def selected(self, request):
        plan = self.scan()
        if request.get("token") != plan["token"]:
            raise DriftError("The machine or configuration changed. Scan and review again before continuing.")
        ids = request.get("ids")
        if not isinstance(ids, list) or not ids or len(ids) > 100 or len(set(ids)) != len(ids):
            raise DriftError("Select between 1 and 100 distinct changes.")
        items = {item["id"]: item for item in plan["items"]}
        if any(key not in items for key in ids):
            raise DriftError("The selection is no longer available. Scan again.")
        return plan, [items[key] for key in ids]

    def preview(self, request):
        plan, rows = self.selected(request)
        previews = []
        for row in rows:
            if row["kind"] != "file":
                continue
            target = file_target(self.home, row["name"])
            if row["state"]["type"] not in ("missing", "file"):
                raise DriftError("Redirected files cannot be captured. Restore the managed link instead.")
            current = target.read_bytes().decode() if target.exists() else None
            expected = Path(row["source"]).read_bytes().decode()
            if SECRET.search(current or "") or SECRET.search(expected):
                raise DriftError("Potential credentials found in " + row["name"] + ". Review this file outside Nix Me; it will not be exported.")
            difference = "\n".join(difflib.unified_diff(expected.splitlines(), (current or "").splitlines(),
                fromfile="Configuration", tofile="This Mac", lineterm=""))
            if not difference:
                difference = ("Only line endings differ. The exact local contents will be saved." if current is not None and current != expected
                              else "Contents match. The executable flag or presence of this file differs.")
            previews.append({"id": row["id"], "current": current, "expected": expected, "difference": difference})
        # Consent is bound to the exact displayed bytes, not just a client checkbox.
        return {"schemaVersion": 1, "files": previews, "reviewToken": digest([plan["token"], previews])}

    def prepare(self, request):
        plan, rows = self.selected(request)
        if any(not row["canKeep"] for row in rows):
            raise DriftError("Some selected changes cannot be kept automatically.")
        assignments = request.get("destinationsByItem")
        if assignments is None:
            assignments = {row["id"]: request.get("destinationID") or "machine:" + self.host for row in rows}
        elif (not isinstance(assignments, dict) or set(assignments) != {row["id"] for row in rows}
              or request.get("destinationID") is not None):
            raise DriftError("Choose exactly one destination for each selected item, without a batch destination.")
        available = {item["id"]: item for item in plan["destinations"]}
        if any(not isinstance(value, str) or value not in available for value in assignments.values()):
            raise DriftError("Choose a destination used by this host, then review again.")
        destinations = [item for item in plan["destinations"] if item["id"] in assignments.values()]
        files = [row for row in rows if row["kind"] == "file"]
        if any(available[assignments[row["id"]]]["scope"] != "machine" for row in files):
            raise DriftError("Dotfiles can only be saved for this machine. Choose a machine destination for each file.")
        previews = self.preview(dict(request, ids=[r["id"] for r in files])) if files else None
        changes = self.support_changes() if plan["needsSavingSupport"] else []
        states = {}
        for destination in destinations:
            path = self.checkout / destination["path"]
            self.validate_destination(path)
            previous = path.read_bytes() if path.exists() else None
            state = json.loads(previous) if previous else {"schemaVersion": 1, "software": {}, "files": {}}
            if state.get("schemaVersion") != 1 or set(state) - {"schemaVersion", "software", "files"}:
                raise DriftError("Unsupported machine-state file; refusing to overwrite it.")
            for row in rows:
                if assignments[row["id"]] != destination["id"]:
                    continue
                if row["kind"] == "file":
                    preview = next(p for p in previews["files"] if p["id"] == row["id"])
                    value = {"enable": False} if preview["current"] is None else {
                        "text": preview["current"], "executable": row["state"].get("executable", False)}
                    value["target"] = row["name"]
                    state.setdefault("files", {})[row["declaration"]] = value
                else:
                    state.setdefault("software", {}).setdefault(row["kind"], {})[row["name"]] = row["change"] == "extra"
            states[destination["id"]] = state
            changes.append({"path": destination["path"], "before": previous.decode() if previous else None,
                            "after": json.dumps(state, indent=2, ensure_ascii=True) + "\n"})
        affected_hosts = sorted({host for destination in destinations for host in destination["hosts"]})
        impact = []
        if len(plan["destinations"]) > 1:
            # Evaluate the complete proposal at once: choices in different layers
            # may interact, so isolated previews would miss conflicting overrides.
            matrix = self.evaluate_scopes({"states": states,
                "items": [{"id": r["id"], "kind": r["kind"], "name": r["name"],
                           "destinationID": assignments[r["id"]]} for r in rows if r["kind"] != "file"]})
            evaluated_hosts = sorted(host for host, value in matrix.items() if value is not None)
            if evaluated_hosts != affected_hosts:
                raise DriftError("Host membership changed. Scan and review again.")
            for host in evaluated_hosts:
                value = matrix[host]
                if value["errors"]:
                    raise DriftError("Cannot save for " + host + ": " + "; ".join(value["errors"]))
                effects = []
                for before, after in zip(value["before"], value["after"]):
                    row = next(row for row in rows if row["id"] == after["id"])
                    matches = after["installed"] == (row["change"] == "extra")
                    if not matches and host == self.host:
                        raise DriftError("A more specific choice overrides " + row["name"] +
                                         " for this Mac. Choose This machine instead, or edit that exception.")
                    effect = ("Install" if after["installed"] else "Remove") if before["installed"] != after["installed"] else (
                        "Already matches" if matches else "Kept as a host exception")
                    effects.append(effect + ": " + row["name"])
                impact.append({"host": host, "effects": effects})
        for change in changes:
            change["difference"] = text_diff(change["before"], change["after"], change["path"])
        return {"schemaVersion": 1, "token": plan["token"], "ids": [row["id"] for row in rows],
                "proposalToken": digest([plan["token"], assignments, destinations, impact, changes]),
                "destination": destinations[0]["path"],
                "destinationID": destinations[0]["id"] if len(destinations) == 1 else None,
                "destinationsByItem": assignments, "destinations": destinations,
                "affectedHosts": affected_hosts, "impact": impact,
                "needsSavingSupport": plan["needsSavingSupport"], "files": changes,
                "localFiles": previews["files"] if previews else []}

    def keep(self, request):
        proposal = self.prepare(request)
        if request.get("proposalToken") != proposal["proposalToken"]:
            raise DriftError("Review the configuration changes before saving. Nothing has been written.")
        _, rows = self.selected(request)
        written = []
        try:
            for change in proposal["files"]:
                path = self.checkout / change["path"]
                self.validate_destination(path)
                previous = path.read_bytes() if path.exists() else None
                expected = change["before"].encode() if change["before"] is not None else None
                if previous != expected:
                    raise DriftError("A configuration file changed during review. Review again.")
                mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
                path.parent.mkdir(parents=True, exist_ok=True)
                self.validate_destination(path)
                encoded = change["after"].encode()
                self.atomic_write(path, encoded, mode=mode)
                written.append((path, previous, encoded, mode))
            manifest = self.desired()
            if manifest.get("reconciliationVersion") != 1:
                raise DriftError("The configuration does not consume these changes. The save was rolled back.")
            for row in rows:
                if row["kind"] != "file":
                    names = manifest["software"]["homebrew"]["formulae" if row["kind"] == "formula" else "casks"]
                    if (row["name"] in names) != (row["change"] == "extra"):
                        raise DriftError("The configuration overrides this selection: " + row["name"])
        except Exception:
            # Do not overwrite a concurrent user's edit while rolling back our failed write.
            for path, previous, encoded, mode in reversed(written):
                if not path.is_symlink() and path.exists() and path.read_bytes() == encoded:
                    if previous is None:
                        path.unlink()
                    else:
                        self.atomic_write(path, previous, mode=mode)
            raise
        return {"schemaVersion": 1, "success": True, "action": "keep", "filesWritten": [c["path"] for c in proposal["files"]],
                "message": "Saved to the configuration repository. This Mac is unchanged. Review, commit, and push with your Git client when ready.",
                "results": [{"id": row["id"], "success": True, "message": "Saved to " + next(
                    d["path"] for d in proposal["destinations"] if d["id"] == proposal["destinationsByItem"][row["id"]]
                )} for row in rows]}

    def validate_destination(self, path=None):
        cursor = path or self.destination
        if not cursor.is_relative_to(self.checkout):
            raise DriftError("The destination must be inside the configuration checkout.")
        while cursor != self.checkout:
            if cursor.is_symlink():
                raise DriftError("Refusing to save through a symbolic link: " + str(cursor))
            cursor = cursor.parent

    @staticmethod
    def atomic_write(path, data, mode=0o600):
        fd, temp = tempfile.mkstemp(prefix=".nix-me-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                os.fchmod(stream.fileno(), mode)
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp, path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)

    def restore(self, request):
        plan, rows = self.selected(request)
        if any(not row["canRestore"] for row in rows):
            raise DriftError("Some selected changes cannot be restored automatically.")
        results = []
        for index, row in enumerate(rows):
            print("Restoring " + row["name"] + " (" + str(index + 1) + "/" + str(len(rows)) + ")", file=sys.stderr, flush=True)
            try:
                fresh = self.scan()
                if fresh["configurationToken"] != plan["configurationToken"] or row not in fresh["items"]:
                    raise DriftError("This change or its configuration changed during the operation. Scan again.")
                if row["kind"] == "file":
                    target = file_target(self.home, row["name"])
                    if path_state(target, self.store_root) != row["state"]:
                        raise DriftError("File changed during review; scan again.")
                    backup = None
                    if target.exists() or target.is_symlink():
                        # Same-directory rename preserves permissions and never follows the old link.
                        backup = target.with_name(target.name + ".nix-me-backup-" + uuid.uuid4().hex)
                        target.rename(backup)
                    try:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        source = Path(row["source"])
                        if bool(source.stat().st_mode & 0o111) == row["executable"]:
                            target.symlink_to(source)
                        else:
                            self.atomic_write(target, source.read_bytes())
                            target.chmod(0o700 if row["executable"] else 0o600)
                    except Exception:
                        if backup and not target.exists() and not target.is_symlink():
                            backup.rename(target)
                        raise
                    message = "Configured file restored" + (". Backup: " + str(backup) if backup else "")
                else:
                    if not NAME.fullmatch(row["name"]) or ".." in row["name"].split("/"):
                        raise DriftError("Invalid package name")
                    brew = shutil.which("brew")
                    if not brew:
                        raise DriftError("Homebrew is unavailable")
                    verb = "uninstall" if row["change"] == "extra" else "install"
                    self.runner([brew, verb, "--" + row["kind"], row["name"]], timeout=1800)
                    message = "Uninstalled" if verb == "uninstall" else "Installed"
                results.append({"id": row["id"], "success": True, "message": message})
            except Exception as error:
                results.append({"id": row["id"], "success": False, "message": str(error)})
        # A command exit code alone is not proof that the expected state now exists.
        try:
            verification = self.scan()
            remaining = {row["id"] for row in verification["items"]}
            for result in results:
                file_id = result["id"].removeprefix("file:")
                checked = file_id in verification["coverage"]["files"] if result["id"].startswith("file:") else verification["coverage"]["homebrew"]
                if result["success"] and (not checked or verification["configurationToken"] != plan["configurationToken"]):
                    result.update(success=False, message="Action completed, but this item could not be verified. Scan again before treating it as restored.")
                elif result["success"] and result["id"] in remaining:
                    result.update(success=False, message="The change is still present after restoring. Scan and review again.")
        except Exception as error:
            for result in results:
                if result["success"]:
                    result.update(success=False, message="Action completed but verification failed: " + str(error))
        return {"schemaVersion": 1, "action": "restore", "success": all(r["success"] for r in results),
                "message": "Selected actions finished. Review the results below.", "results": results}

    @contextlib.contextmanager
    def lock(self):
        # Lock this checkout only; never unlink the inode while another process may hold it.
        root = self.home / "Library/Application Support/Nix Me/reconciliation"
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (root / (digest(str(self.checkout)) + ".lock")).open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise DriftError("Another reconciliation is running. Wait for it to finish.")
            yield


def main():
    os.umask(0o077)
    if os.geteuid() == 0:
        raise DriftError("Run machine drift as the logged-in user, never as root.")
    action = sys.argv[1] if len(sys.argv) > 1 else "scan"
    checkout = os.environ.get("NIX_ME_CONFIG_DIR")
    host = os.environ.get("NIX_ME_HOSTNAME")
    if not checkout or not host:
        raise DriftError("NIX_ME_CONFIG_DIR and NIX_ME_HOSTNAME are required.")
    service = DriftService(checkout, host, applied_path=os.environ.get("NIX_ME_APPLIED_MANIFEST"))
    if action == "scan":
        response = service.scan()
    elif action in ("preview", "prepare", "keep", "restore"):
        request = json.load(sys.stdin)
        with service.lock():
            response = getattr(service, action)(request)
    else:
        raise DriftError("Unknown drift action")
    print(json.dumps(response))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"schemaVersion": 1, "error": {"message": str(error)}}))
        sys.exit(1)
