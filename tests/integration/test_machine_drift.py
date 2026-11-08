import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / "packages/management-api/bin/machine_drift.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("machine_drift", MODULE)
drift = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drift)


class MachineDriftTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.home = root / "user"
        self.checkout = root / "checkout"
        self.store = root / "store"
        for path in (self.home, self.checkout, self.store):
            path.mkdir()
        self.applied = root / "applied.json"
        self.manifest = {"host": {"hostname": "test", "username": "user"}, "reconciliationVersion": 1,
                         "software": {"homebrew": {"formulae": ["git"], "casks": []}}, "managedFiles": []}
        self.applied.write_text(json.dumps(self.manifest))
        self.inventory = {"formulae": [self.formula("git"), self.formula("extra"), self.formula("dependency", False)], "casks": []}
        self.commands = []
        self.fail_brew = False
        self.fail_eval = False
        self.service = drift.DriftService(self.checkout, "test", home=self.home,
            applied_path=self.applied, runner=self.run_command, store_root=self.store)
        self.service.desired = self.desired
        self.which = patch.object(drift.shutil, "which", side_effect=lambda name: "/fake/" + name)
        self.which.start()
        self.addCleanup(self.which.stop)

    @staticmethod
    def formula(name, explicit=True):
        return {"name": name, "full_name": name, "installed": [{"version": "1.0", "installed_on_request": explicit}]}

    def desired(self):
        if self.fail_eval:
            raise drift.DriftError("Evaluation failed")
        manifest = copy.deepcopy(self.manifest)
        if self.service.destination.exists():
            state = json.loads(self.service.destination.read_text())
            for kind, entries in state.get("software", {}).items():
                key = "formulae" if kind == "formula" else "casks"
                names = set(manifest["software"]["homebrew"][key])
                for name, enabled in entries.items():
                    names.add(name) if enabled else names.discard(name)
                manifest["software"]["homebrew"][key] = sorted(names)
        return manifest

    def run_command(self, args, **kwargs):
        self.commands.append(args)
        if self.fail_brew:
            raise drift.DriftError("Homebrew failed")
        if "info" in args:
            return json.dumps(self.inventory).encode()
        if "uninstall" in args:
            self.inventory["formulae"] = [f for f in self.inventory["formulae"] if f["name"] != args[-1]]
        if "install" in args:
            self.inventory["formulae"].append(self.formula(args[-1]))
        return b""

    def file(self, name=".config/demo", value="local = true\n", expected="local = false\n"):
        source = self.store / "original"
        source.write_text(expected)
        target = self.home / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if value is not None:
            target.write_text(value)
        self.manifest["managedFiles"].append({"name": "declaration", "target": name, "source": str(source), "executable": False})
        self.applied.write_text(json.dumps(self.manifest))
        return target, source

    def request(self, *ids):
        return {"token": self.service.scan()["token"], "ids": list(ids)}

    def reviewed_request(self, *ids):
        request = self.request(*ids)
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        return request

    def scoped_layout(self):
        self.manifest["reconciliationScopesVersion"] = 1
        def layer(scope, name, path):
            return {"id": scope + ":" + name, "scope": scope, "name": name,
                    "source": "nix/hosts/" + name + ".nix", "path": "config/machine-state/" + path, "state": {}}
        shared = layer("shared", "all", "shared.json")
        profile = layer("profile", "dev", "profiles/dev.json")
        self.scope_matrix = {
            "test": {"layers": [shared, profile, layer("machine", "test", "machines/test.json")]},
            "peer": {"layers": [shared, profile, layer("machine", "peer", "machines/peer.json")]},
            "unrelated": {"layers": [shared, layer("machine", "unrelated", "machines/unrelated.json")]}}
        self.scope_exception = False
        self.scope_errors = []
        def evaluate(candidate=None):
            if candidate is None:
                return copy.deepcopy(self.scope_matrix)
            result = {}
            for host, value in self.scope_matrix.items():
                layer_ids = {layer["id"] for layer in value["layers"]}
                if not layer_ids.intersection(candidate["states"]):
                    result[host] = None
                    continue
                before, after = [], []
                for item in candidate["items"]:
                    if item["destinationID"] not in layer_ids:
                        continue
                    before.append({"id": item["id"], "name": item["name"], "installed": False})
                    after.append({"id": item["id"], "name": item["name"], "installed": host != self.scope_exception})
                result[host] = {"before": before, "after": after, "errors": self.scope_errors}
            return result
        self.service.evaluate_scopes = evaluate
        original = self.desired
        def desired():
            manifest = original()
            for layer in self.scope_matrix["test"]["layers"]:
                path = self.checkout / layer["path"]
                if path.exists():
                    for kind, entries in json.loads(path.read_text()).get("software", {}).items():
                        field = "formulae" if kind == "formula" else "casks"
                        names = set(manifest["software"]["homebrew"][field])
                        for name, enabled in entries.items():
                            names.add(name) if enabled else names.discard(name)
                        manifest["software"]["homebrew"][field] = sorted(names)
            return manifest
        self.service.desired = desired

    def test_destinations_only_include_active_layers_and_exact_host_membership(self):
        self.scoped_layout()
        destinations = self.service.scan()["destinations"]
        self.assertEqual([item["id"] for item in destinations], ["shared:all", "profile:dev", "machine:test"])
        self.assertEqual(destinations[1]["hosts"], ["peer", "test"])

    def test_profile_save_is_reviewed_without_mutation_and_does_not_write_machine_file(self):
        self.scoped_layout()
        request = dict(self.request("formula:extra"), destinationID="profile:dev")
        proposal = self.service.prepare(request)
        self.assertEqual(proposal["affectedHosts"], ["peer", "test"])
        self.assertEqual(proposal["impact"][0]["effects"], ["Install: extra"])
        path = self.checkout / "config/machine-state/profiles/dev.json"
        self.assertFalse(path.exists())
        request["proposalToken"] = proposal["proposalToken"]
        self.service.keep(request)
        self.assertTrue(json.loads(path.read_text())["software"]["formula"]["extra"])
        self.assertFalse(self.service.destination.exists())
        self.assertFalse(any("install" in c or "uninstall" in c for c in self.commands))

    def test_destination_changes_invalidate_save_approval(self):
        self.scoped_layout()
        request = self.reviewed_request("formula:extra")
        request["destinationID"] = "shared:all"
        with self.assertRaisesRegex(drift.DriftError, "Review the configuration"):
            self.service.keep(request)

    def mixed_request(self):
        self.scoped_layout()
        self.inventory["casks"] = [{"token": "app", "installed": "1.0"}]
        return dict(self.request("formula:extra", "cask:app"),
                    destinationsByItem={"formula:extra": "profile:dev", "cask:app": "machine:test"})

    def test_mixed_destinations_are_reviewed_and_saved_together(self):
        request = self.mixed_request()
        proposal = self.service.prepare(request)
        self.assertEqual(proposal["destinationsByItem"], request["destinationsByItem"])
        self.assertIsNone(proposal["destinationID"])
        self.assertEqual(len(proposal["files"]), 2)
        self.assertEqual(proposal["impact"][0], {"host": "peer", "effects": ["Install: extra"]})
        self.assertEqual(proposal["impact"][1]["effects"], ["Install: extra", "Install: app"])
        self.assertFalse((self.checkout / "config/machine-state").exists())
        request["proposalToken"] = proposal["proposalToken"]
        result = self.service.keep(request)
        profile = self.checkout / "config/machine-state/profiles/dev.json"
        self.assertEqual(json.loads(profile.read_text())["software"], {"formula": {"extra": True}})
        self.assertEqual(json.loads(self.service.destination.read_text())["software"], {"cask": {"app": True}})
        self.assertIn("profiles/dev.json", result["results"][0]["message"])
        self.assertIn("machines/test.json", result["results"][1]["message"])
        self.assertFalse(any("install" in c or "uninstall" in c for c in self.commands))

    def test_items_at_same_destination_generate_one_file(self):
        request = self.mixed_request()
        request["destinationsByItem"]["cask:app"] = "profile:dev"
        proposal = self.service.prepare(request)
        self.assertEqual(len(proposal["files"]), 1)
        state = json.loads(proposal["files"][0]["after"])
        self.assertEqual(state["software"], {"formula": {"extra": True}, "cask": {"app": True}})

    def test_changing_one_item_destination_requires_new_review(self):
        request = self.mixed_request()
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        request["destinationsByItem"]["cask:app"] = "shared:all"
        with self.assertRaisesRegex(drift.DriftError, "Review the configuration"):
            self.service.keep(request)
        self.assertFalse((self.checkout / "config/machine-state").exists())

    def test_partial_extra_invalid_or_ambiguous_assignments_are_rejected(self):
        request = self.mixed_request()
        for assignments in ({}, {"formula:extra": "profile:dev"}, [],
                            dict(request["destinationsByItem"], unknown="shared:all"),
                            dict(request["destinationsByItem"], **{"cask:app": ["shared:all"]})):
            with self.subTest(assignments=assignments), self.assertRaises(drift.DriftError):
                self.service.prepare(dict(request, destinationsByItem=assignments))
        with self.assertRaisesRegex(drift.DriftError, "batch destination"):
            self.service.prepare(dict(request, destinationID="shared:all"))

    def test_mixed_save_rolls_back_all_destinations_after_validation_failure(self):
        request = self.mixed_request()
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        original = self.service.desired
        def failed():
            if self.service.destination.exists():
                raise drift.DriftError("Validation failed")
            return original()
        self.service.desired = failed
        with self.assertRaisesRegex(drift.DriftError, "Validation failed"):
            self.service.keep(request)
        self.assertFalse(self.service.destination.exists())
        self.assertFalse((self.checkout / "config/machine-state/profiles/dev.json").exists())

    def test_write_failure_rolls_back_previously_written_destination(self):
        request = self.mixed_request()
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        original = self.service.atomic_write
        def fail_second(path, *args, **kwargs):
            if path == self.service.destination:
                raise OSError("Disk full")
            return original(path, *args, **kwargs)
        self.service.atomic_write = fail_second
        with self.assertRaisesRegex(OSError, "Disk full"):
            self.service.keep(request)
        self.assertFalse((self.checkout / "config/machine-state/profiles/dev.json").exists())

    def test_shared_software_and_machine_dotfile_can_be_saved_together(self):
        self.scoped_layout()
        target, _ = self.file()
        request = dict(self.request("formula:extra", "file:.config/demo"), destinationsByItem={
            "formula:extra": "profile:dev", "file:.config/demo": "machine:test"})
        proposal = self.service.prepare(request)
        self.assertEqual(len(proposal["files"]), 2)
        request["proposalToken"] = proposal["proposalToken"]
        self.service.keep(request)
        profile = json.loads((self.checkout / "config/machine-state/profiles/dev.json").read_text())
        self.assertEqual(profile["files"], {})
        self.assertEqual(json.loads(self.service.destination.read_text())["files"]["declaration"]["text"], target.read_text())

    def test_unselected_existing_values_at_each_destination_are_preserved(self):
        request = self.mixed_request()
        profile = self.checkout / "config/machine-state/profiles/dev.json"
        profile.parent.mkdir(parents=True)
        profile.write_text('{"schemaVersion":1,"software":{"formula":{"original":true}}}')
        self.service.destination.parent.mkdir(parents=True)
        self.service.destination.write_text('{"schemaVersion":1,"software":{"cask":{"existing":true}}}')
        request["token"] = self.service.scan()["token"]
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        self.service.keep(request)
        self.assertTrue(json.loads(profile.read_text())["software"]["formula"]["original"])
        self.assertTrue(json.loads(self.service.destination.read_text())["software"]["cask"]["existing"])

    def test_forged_inactive_profile_or_path_is_rejected(self):
        self.scoped_layout()
        for destination in ("profile:inactive", "../outside.json", "machine:peer"):
            with self.subTest(destination=destination), self.assertRaisesRegex(drift.DriftError, "destination used"):
                self.service.prepare(dict(self.request("formula:extra"), destinationID=destination))

    def test_host_membership_changes_invalidate_review(self):
        self.scoped_layout()
        request = dict(self.request("formula:extra"), destinationID="profile:dev")
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        self.scope_matrix["peer"]["layers"] = []
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)

    def test_shared_file_edit_invalidates_review(self):
        self.scoped_layout()
        request = dict(self.request("formula:extra"), destinationID="profile:dev")
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        path = self.checkout / "config/machine-state/profiles/dev.json"
        path.parent.mkdir(parents=True)
        path.write_text('{"schemaVersion":1,"software":{"formula":{"another":true}}}')
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)

    def test_other_hosts_exceptions_are_explained_not_overwritten(self):
        self.scoped_layout()
        self.scope_exception = "peer"
        proposal = self.service.prepare(dict(self.request("formula:extra"), destinationID="profile:dev"))
        self.assertEqual(proposal["impact"][0]["effects"], ["Kept as a host exception: extra"])
        self.assertEqual(len(proposal["files"]), 1)

    def test_current_host_exception_requires_more_specific_destination(self):
        self.scoped_layout()
        self.scope_exception = "test"
        with self.assertRaisesRegex(drift.DriftError, "more specific"):
            self.service.prepare(dict(self.request("formula:extra"), destinationID="profile:dev"))

    def test_invalid_affected_host_blocks_shared_save_before_writing(self):
        self.scoped_layout()
        self.scope_errors = ["Conflicting profile choices"]
        with self.assertRaisesRegex(drift.DriftError, "Conflicting profile"):
            self.service.prepare(dict(self.request("formula:extra"), destinationID="profile:dev"))
        self.assertFalse((self.checkout / "config/machine-state").exists())

    def test_dotfiles_cannot_be_saved_to_shared_scope(self):
        self.scoped_layout()
        self.file()
        with self.assertRaisesRegex(drift.DriftError, "Dotfiles can only"):
            self.service.prepare(dict(self.request("file:.config/demo"), destinationID="shared:all"))

    def test_shared_symlink_destination_is_rejected(self):
        self.scoped_layout()
        path = self.checkout / "config/machine-state/profiles"
        path.parent.mkdir(parents=True)
        path.symlink_to(self.home)
        with self.assertRaisesRegex(drift.DriftError, "symbolic link"):
            self.service.prepare(dict(self.request("formula:extra"), destinationID="profile:dev"))

    def test_dependencies_and_aliases_are_not_stray_packages(self):
        self.inventory["formulae"][0]["name"] = "new-git"
        self.inventory["formulae"][0]["aliases"] = ["git"]
        self.assertEqual([r["id"] for r in self.service.scan()["items"]], ["formula:extra"])

    def test_missing_package_and_pending_repository_additions_are_distinct(self):
        self.inventory["formulae"] = []
        self.manifest["software"]["homebrew"]["formulae"].append("pending")
        self.assertEqual([r["id"] for r in self.service.scan()["items"]], ["formula:git"])

    def test_pending_repository_removal_is_not_machine_drift(self):
        self.manifest["software"]["homebrew"]["formulae"] = []
        self.assertEqual([r["id"] for r in self.service.scan()["items"]], ["formula:extra"])

    def test_missing_brew_does_not_report_packages_as_removed(self):
        with patch.object(drift.shutil, "which", return_value=None):
            plan = self.service.scan()
        self.assertFalse(plan["items"])
        self.assertTrue(plan["warnings"])

    def test_failed_brew_scan_is_not_healthy(self):
        self.fail_brew = True
        plan = self.service.scan()
        self.assertFalse(plan["items"])
        self.assertIn("Homebrew was not checked", plan["warnings"][0])

    def test_keep_only_selected_package_and_no_git_commands(self):
        response = self.service.keep(self.reviewed_request("formula:extra"))
        self.assertTrue(response["success"])
        saved = json.loads(self.service.destination.read_text())
        self.assertEqual(saved["software"], {"formula": {"extra": True}})
        self.assertFalse(any("git" == command[0] for command in self.commands))
        self.assertEqual(self.service.destination.stat().st_mode & 0o777, 0o600)

    def test_stale_review_cannot_mutate(self):
        request = self.request("formula:extra")
        self.inventory["formulae"].append(self.formula("new"))
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)
        self.assertFalse(self.service.destination.exists())

    def test_stale_override_cannot_be_overwritten(self):
        request = self.request("formula:extra")
        self.service.destination.parent.mkdir(parents=True)
        self.service.destination.write_text('{"schemaVersion":1,"files":{}}')
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)

    def test_unknown_selection_rejected(self):
        with self.assertRaisesRegex(drift.DriftError, "selection"):
            self.service.restore(self.request("formula:not-present"))

    def test_file_keep_requires_review_of_exact_bytes(self):
        target, _ = self.file()
        request = self.request("file:.config/demo")
        with self.assertRaisesRegex(drift.DriftError, "Review"):
            self.service.keep(request)
        preview = self.service.preview(request)
        request["reviewToken"] = preview["reviewToken"]
        request["proposalToken"] = self.service.prepare(request)["proposalToken"]
        self.service.keep(request)
        saved = json.loads(self.service.destination.read_text())
        self.assertEqual(saved["files"]["declaration"], {"text": target.read_text(), "executable": False, "target": ".config/demo"})

    def test_file_edit_invalidates_content_review(self):
        target, _ = self.file()
        request = self.request("file:.config/demo")
        request["reviewToken"] = self.service.preview(request)["reviewToken"]
        target.write_text("new content")
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)

    def test_restore_file_preserves_backup_and_unselected_package(self):
        target, source = self.file()
        response = self.service.restore(self.request("file:.config/demo"))
        self.assertTrue(response["success"])
        self.assertEqual(target.resolve(), source)
        backups = list(target.parent.glob("demo.nix-me-backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "local = true\n")
        self.assertTrue(any(f["name"] == "extra" for f in self.inventory["formulae"]))

    def test_restore_only_selected_software_without_force_or_zap(self):
        self.service.restore(self.request("formula:extra"))
        mutations = [c for c in self.commands if "uninstall" in c]
        self.assertEqual(mutations, [["/fake/brew", "uninstall", "--formula", "extra"]])
        self.assertTrue(any(f["name"] == "dependency" for f in self.inventory["formulae"]))

    def test_symlink_parent_is_never_followed(self):
        target, _ = self.file()
        target.unlink()
        target.parent.rmdir()
        elsewhere = self.home / "other"
        elsewhere.mkdir()
        target.parent.symlink_to(elsewhere)
        plan = self.service.scan()
        self.assertFalse(any(r["kind"] == "file" for r in plan["items"]))
        self.assertTrue(any("symbolic link" in warning for warning in plan["warnings"]))

    def test_private_paths_and_potential_credentials_are_excluded(self):
        self.file(name=".ssh/config")
        plan = self.service.scan()
        self.assertFalse(any(r["kind"] == "file" for r in plan["items"]))
        self.manifest["managedFiles"] = []
        self.file(value='api_key = "private-token-value"\n')
        with self.assertRaisesRegex(drift.DriftError, "credentials"):
            self.service.preview(self.request("file:.config/demo"))

    def test_override_symlink_is_rejected(self):
        self.service.destination.parent.mkdir(parents=True)
        outside = self.home / "state.json"
        outside.write_text('{"schemaVersion":1}')
        self.service.destination.symlink_to(outside)
        with self.assertRaisesRegex(drift.DriftError, "symbolic link"):
            self.service.keep(self.request("formula:extra"))
        self.assertEqual(outside.read_text(), '{"schemaVersion":1}')

    def test_failed_evaluation_rolls_back_only_our_write(self):
        request = self.reviewed_request("formula:extra")
        original = self.desired
        self.service.desired = lambda: (_ for _ in ()).throw(drift.DriftError("Bad config")) if self.service.destination.exists() else original()
        with self.assertRaisesRegex(drift.DriftError, "Bad config"):
            self.service.keep(request)
        self.assertFalse(self.service.destination.exists())

    def test_host_mismatch_refuses_actions(self):
        applied = copy.deepcopy(self.manifest)
        applied["host"]["hostname"] = "other"
        self.applied.write_text(json.dumps(applied))
        with self.assertRaisesRegex(drift.DriftError, "another host"):
            self.service.scan()

    def test_old_checkout_does_not_offer_unconsumed_saves(self):
        del self.manifest["reconciliationVersion"]
        plan = self.service.scan()
        self.assertFalse(plan["items"][0]["canKeep"])

    def test_file_preview_includes_line_diff(self):
        self.file()
        preview = self.service.preview(self.request("file:.config/demo"))
        self.assertIn("-local = false", preview["files"][0]["difference"])
        self.assertIn("+local = true", preview["files"][0]["difference"])

    def test_quoted_json_credentials_are_rejected(self):
        self.file(value='{"apiKey": "secret-value"}')
        with self.assertRaisesRegex(drift.DriftError, "credentials"):
            self.service.preview(self.request("file:.config/demo"))

    def test_equal_content_copy_is_not_drift(self):
        self.file(value="same\n", expected="same\n")
        self.assertFalse(any(r["kind"] == "file" for r in self.service.scan()["items"]))

    def test_mode_only_change_is_restored_without_changing_source(self):
        target, source = self.file(value="same\n", expected="same\n")
        self.manifest["managedFiles"][0]["executable"] = True
        self.applied.write_text(json.dumps(self.manifest))
        original_mode = source.stat().st_mode
        result = self.service.restore(self.request("file:.config/demo"))
        self.assertTrue(result["success"])
        self.assertTrue(target.stat().st_mode & 0o111)
        self.assertEqual(source.stat().st_mode, original_mode)

    def test_pending_file_changes_are_not_local_drift(self):
        target, source = self.file(value="old\n", expected="old\n")
        desired = self.store / "new"
        desired.write_text("new\n")
        self.manifest["managedFiles"][0]["source"] = str(desired)
        self.assertFalse(any(r["kind"] == "file" for r in self.service.scan()["items"]))
        target.chmod(0o700)
        row = next(r for r in self.service.scan()["items"] if r["kind"] == "file")
        self.assertTrue(row["conflict"])

    def test_newly_declared_file_is_pending_repository_change(self):
        old = self.applied.read_text()
        self.file(value=None)
        self.applied.write_text(old)
        self.assertFalse(any(r["kind"] == "file" for r in self.service.scan()["items"]))

    def test_foreign_file_symlink_is_not_read_and_only_link_is_restored(self):
        target, source = self.file()
        external = self.home / "outside"
        external.write_text("private = true")
        target.unlink()
        target.symlink_to(external)
        state = drift.path_state(target, self.service.store_root)
        self.assertIsNone(state["hash"])
        row = next(r for r in self.service.scan()["items"] if r["kind"] == "file")
        self.assertFalse(row["canKeep"])
        self.assertTrue(self.service.restore(self.request(row["id"]))["success"])
        self.assertEqual(target.resolve(), source)
        self.assertEqual(external.read_text(), "private = true")
        self.assertTrue(next(target.parent.glob("demo.nix-me-backup-*")).is_symlink())

    def test_restore_reports_failed_verification_not_false_success(self):
        request = self.request("formula:extra")
        original = self.run_command
        def fail_after_action(args, **kwargs):
            result = original(args, **kwargs)
            if "uninstall" in args:
                self.fail_brew = True
            return result
        self.service.runner = fail_after_action
        result = self.service.restore(request)
        self.assertFalse(result["success"])
        self.assertIn("could not be verified", result["results"][0]["message"])

    def test_restore_rechecks_configuration_between_items(self):
        self.inventory["formulae"].append(self.formula("another"))
        request = self.request("formula:extra", "formula:another")
        original = self.run_command
        def change_configuration(args, **kwargs):
            result = original(args, **kwargs)
            if "uninstall" in args:
                self.manifest["software"]["homebrew"]["formulae"].append("new-declaration")
            return result
        self.service.runner = change_configuration
        result = self.service.restore(request)
        self.assertFalse(result["success"])
        self.assertEqual(len([c for c in self.commands if "uninstall" in c]), 1)
        self.assertTrue(any(f["name"] == "another" for f in self.inventory["formulae"]))

    def test_failed_keep_preserves_concurrent_editor_changes(self):
        request = self.reviewed_request("formula:extra")
        original = self.desired
        concurrent = '{"schemaVersion":1,"files":{},"software":{}}'
        def changed_by_editor():
            if self.service.destination.exists():
                self.service.destination.write_text(concurrent)
                raise drift.DriftError("Changed by editor")
            return original()
        self.service.desired = changed_by_editor
        with self.assertRaisesRegex(drift.DriftError, "Changed by editor"):
            self.service.keep(request)
        self.assertEqual(self.service.destination.read_text(), concurrent)

    def test_review_is_read_only_and_shows_only_selected_change(self):
        proposal = self.service.prepare(self.request("formula:extra"))
        self.assertFalse(self.service.destination.exists())
        self.assertEqual(len(proposal["files"]), 1)
        self.assertIn('+      "extra": true', proposal["files"][0]["difference"])
        self.assertNotIn("dependency", proposal["files"][0]["after"])
        self.assertEqual(len(self.inventory["formulae"]), 3)

    def test_file_save_preserves_exact_line_endings(self):
        target, _ = self.file(value="same\n", expected="same\n")
        target.write_bytes(b"same\r\n")
        request = self.reviewed_request("file:.config/demo")
        preview = self.service.prepare(request)
        self.assertIn("Only line endings", preview["localFiles"][0]["difference"])
        self.service.keep(request)
        state = json.loads(self.service.destination.read_text())
        self.assertEqual(state["files"]["declaration"]["text"].encode(), b"same\r\n")
        self.assertEqual(target.read_bytes(), b"same\r\n")

    def test_unreviewed_software_save_is_rejected(self):
        with self.assertRaisesRegex(drift.DriftError, "Review the configuration"):
            self.service.keep(self.request("formula:extra"))
        self.assertFalse(self.service.destination.exists())

    def legacy_layout(self):
        del self.manifest["reconciliationVersion"]
        imports = self.checkout / "nix/modules/darwin/default.nix"
        imports.parent.mkdir(parents=True)
        imports.write_text('{ ... }: {\n  imports = [\n    ./management-api.nix\n  ];\n}\n')
        module = imports.with_name("machine-state.nix")
        original = self.desired
        def upgraded():
            manifest = original()
            if module.exists() and "./machine-state.nix" in imports.read_text():
                manifest["reconciliationVersion"] = 1
            return manifest
        self.service.desired = upgraded
        return imports, module

    def test_old_checkout_gets_reviewed_support_and_save_without_touching_mac(self):
        imports, module = self.legacy_layout()
        before = imports.read_text()
        request = self.request("formula:extra")
        proposal = self.service.prepare(request)
        self.assertTrue(proposal["needsSavingSupport"])
        self.assertEqual(len(proposal["files"]), 3)
        self.assertEqual(imports.read_text(), before)
        self.assertFalse(module.exists())
        request["proposalToken"] = proposal["proposalToken"]
        result = self.service.keep(request)
        self.assertTrue(result["success"])
        self.assertEqual(module.read_text(), self.service.support_template.read_text())
        self.assertEqual(imports.read_text().count("./machine-state.nix"), 1)
        self.assertFalse(any("uninstall" in c or "install" in c for c in self.commands))
        self.assertEqual(len(self.inventory["formulae"]), 3)

    def test_failed_support_upgrade_rolls_back_all_files(self):
        imports, module = self.legacy_layout()
        before = imports.read_text()
        request = self.reviewed_request("formula:extra")
        original = self.service.desired
        def failed_upgrade():
            if module.exists():
                raise drift.DriftError("Module is incompatible")
            return original()
        self.service.desired = failed_upgrade
        with self.assertRaisesRegex(drift.DriftError, "Module is incompatible"):
            self.service.keep(request)
        self.assertFalse(module.exists())
        self.assertFalse(self.service.destination.exists())
        self.assertEqual(imports.read_text(), before)

    def test_changed_support_import_invalidates_review(self):
        imports, module = self.legacy_layout()
        request = self.reviewed_request("formula:extra")
        imports.write_text(imports.read_text() + "# edited\n")
        with self.assertRaisesRegex(drift.DriftError, "changed"):
            self.service.keep(request)
        self.assertFalse(module.exists())

    def test_existing_unknown_support_module_is_not_overwritten(self):
        _, module = self.legacy_layout()
        module.write_text("# custom module")
        del self.manifest["managedFiles"]
        self.service.desired = self.desired
        plan = self.service.scan()
        self.assertFalse(plan["canKeepChanges"])
        self.assertEqual(module.read_text(), "# custom module")

    def test_saved_status_does_not_claim_remote_is_current(self):
        self.service.keep(self.reviewed_request("formula:extra"))
        original = self.run_command
        for output, expected in [(b" M path", "localChanges"), (b"", "matchesLastKnownUpstream")]:
            self.service.runner = lambda args, **kwargs: output if "git" in args[0] else original(args, **kwargs)
            self.assertEqual(self.service.publication()["state"], expected)


if __name__ == "__main__":
    unittest.main()
