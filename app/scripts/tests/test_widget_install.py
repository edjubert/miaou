import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("miaou_builder", Path(__file__).resolve().parents[2] / "build-app.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CLIEmbeddingTests(unittest.TestCase):
    def test_default_build_rebuilds_checkout_cli_instead_of_using_path_or_old_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = root / "cli/target/release/miaou"
            cli.parent.mkdir(parents=True)
            cli.write_text("old binary")
            cli.chmod(0o755)

            def rebuild(*args, **kwargs):
                cli.write_text("rebuilt from current checkout")

            with patch.object(builder, "APP", root / "app"), \
                    patch.dict(os.environ, {"CLI_BIN": ""}), \
                    patch.object(builder.shutil, "which", return_value="/old/bin/miaou") as lookup, \
                    patch.object(builder, "run", side_effect=rebuild) as build:
                embedded = builder.cli_for_bundle()
            self.assertEqual(embedded.read_text(), "rebuilt from current checkout")
            build.assert_called_once_with(
                "cargo", "build", "--release",
                "--manifest-path", str(root / "cli/Cargo.toml"),
                "--target-dir", str(root / "cli/target"))
            lookup.assert_not_called()

    def test_explicit_cli_artifact_is_preserved_without_rebuilding(self):
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory) / "miaou"
            cli.write_text("release artifact")
            cli.chmod(0o755)
            with patch.dict(os.environ, {"CLI_BIN": str(cli)}), \
                    patch.object(builder, "run") as build:
                self.assertEqual(builder.cli_for_bundle(), cli)
            build.assert_not_called()


class CLIActivityTests(unittest.TestCase):
    def test_checks_checkpoint_completion_and_journal_resume_in_an_isolated_home(self):
        calls = []

        def cli_result(*args, **kwargs):
            home = Path(args[2])
            self.assertEqual(args[3:], ("status", "--json"))
            self.assertEqual(kwargs["env"]["VIBE_HOME"], str(home))
            self.assertEqual(kwargs["env"]["MIAOU_ARCHIVE_PATH"], str(home / "archive.jsonl"))
            session = home / "logs/session/unified/activity-check"
            state = json.loads((session / "generations/0000000000000001/projection-state.json")
                               .read_text())["snapshot"]
            tail = session / "journal/0000000000000002.jsonl"
            if tail.exists():
                state = json.loads(tail.read_text().splitlines()[-1])["payload"]["delta"][0]["state"]
            calls.append(state["latestTurn"]["status"])
            active = [{"id": "activity-check"}] if calls[-1] == "in_progress" else []
            return subprocess.CompletedProcess(args, 0, stdout=json.dumps({"active": active}))

        with patch.object(builder, "run", side_effect=cli_result):
            builder.verify_cli_activity(Path("/selected/miaou"))
        self.assertEqual(calls, ["in_progress", "completed", "in_progress", "completed"])

    def test_rejects_a_cli_that_keeps_completed_tasks_active(self):
        response = subprocess.CompletedProcess([], 0,
                                               stdout='{"active":[{"id":"activity-check"}]}')
        with patch.object(builder, "run", return_value=response) as cli:
            with self.assertRaisesRegex(SystemExit, "activity detection \\(completed\\)"):
                builder.verify_cli_activity(Path("/stale/miaou"))
        self.assertEqual(cli.call_count, 2)

    def test_rejects_a_cli_that_hides_running_tasks(self):
        with patch.object(builder, "run",
                          return_value=subprocess.CompletedProcess([], 0, stdout='{"active":[]}')):
            with self.assertRaisesRegex(SystemExit, "activity detection \\(in_progress\\)"):
                builder.verify_cli_activity(Path("/stale/miaou"))


class WidgetInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / "app"
        self.build = self.root / "build"
        self.install_root = self.root / "installed"
        self.build.mkdir()
        self.source = self.app / "Miaou.app"
        self.destination = self.install_root / "Miaou.app"
        self.bundle(self.source, "2")
        self.bundle(self.destination, "1")
        environment = dict(os.environ)
        environment.pop("BUILD_NUMBER", None)
        environment["INSTALL_DIR"] = str(self.install_root)
        self.stop_old_app_patch = patch.object(builder, "stop_old_app")
        self.patches = [
            patch.object(builder, "APP", self.app),
            patch.object(builder, "BUILD", self.build),
            patch.dict(os.environ, environment, clear=True),
            patch.object(builder, "stop_old_widget"),
            patch.object(builder, "verify_widget_entitlements"),
            patch.object(builder, "verify_cli_activity"),
            self.stop_old_app_patch,
            patch.object(builder.subprocess, "run",
                         return_value=subprocess.CompletedProcess([], 0, stdout="", stderr="")),
        ]
        for item in self.patches:
            item.start()
        self.addCleanup(self.temporary.cleanup)
        for item in self.patches:
            self.addCleanup(item.stop)

    def bundle(self, path, number, identifier=builder.BUNDLE_ID):
        contents = path / "Contents"
        contents.mkdir(parents=True, exist_ok=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps(
            {"CFBundleIdentifier": identifier, "CFBundleVersion": number}))
        extension = contents / "PlugIns/MiaouWidget.appex/Contents"
        extension.mkdir(parents=True, exist_ok=True)
        (extension / "Info.plist").write_bytes(plistlib.dumps(
            {"CFBundleIdentifier": builder.WIDGET_ID, "CFBundleVersion": number}))

    def number(self, bundle):
        return plistlib.loads((bundle / "Contents/Info.plist").read_bytes())["CFBundleVersion"]

    def test_install_preserves_previous_bundle_and_registers_only_installed_extension(self):
        calls = []

        def run(*args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

        with patch.object(builder, "run", side_effect=run):
            builder.install()
        self.assertEqual(self.number(self.destination), "2")
        self.assertEqual(self.number(self.install_root / ".Miaou.previous.app"), "1")
        self.assertEqual(self.number(self.source), "2")
        self.assertIn((builder.LSREGISTER, "-f", "-R", str(self.destination)), calls)
        self.assertIn(("pluginkit", "-a", str(self.destination / "Contents/PlugIns/MiaouWidget.appex")), calls)
        removed = [call.args for call in builder.subprocess.run.call_args_list
                   if call.args[0][0] == "pluginkit" and call.args[0][1] == "-r"]
        self.assertTrue(removed)
        self.assertTrue(all(str(self.destination / "Contents/PlugIns/MiaouWidget.appex") not in call[0]
                            for call in removed))

    def test_unsigned_staging_failure_does_not_replace_installed_app(self):
        with patch.object(builder, "run", side_effect=subprocess.CalledProcessError(1, "codesign")):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.install()
        self.assertEqual(self.number(self.destination), "1")
        self.assertFalse((self.install_root / ".Miaou.installing.app").exists())

    def test_install_unregisters_superseded_widget_from_another_worktree(self):
        stale = self.root / "old worktree/Miaou.app"
        self.bundle(stale, "1")
        extension = stale / "Contents/PlugIns/MiaouWidget.appex"
        listing = ("pluginkit", "-m", "-A", "-D", "-v", "-i", builder.WIDGET_ID)

        def run(*args, **kwargs):
            output = f"  {builder.WIDGET_ID}(0.3.0)\told-uuid\t{extension}\n" if args == listing else ""
            return subprocess.CompletedProcess(args, 0, stdout=output, stderr="")

        with patch.object(builder, "run", side_effect=run) as checked:
            builder.install()
        self.assertIn(listing, [call.args for call in checked.call_args_list])
        removed = [call.args[0] for call in builder.subprocess.run.call_args_list
                   if call.args[0][:2] == ["pluginkit", "-r"]]
        self.assertIn(["pluginkit", "-r", str(extension)], removed)

    def test_unrelated_app_is_never_replaced(self):
        self.bundle(self.destination, "99", identifier="another.app")
        with self.assertRaises(SystemExit):
            builder.install()
        self.assertEqual(self.number(self.destination), "99")

    def test_restricted_widget_failure_keeps_the_installed_app(self):
        with patch.object(builder, "verify_widget_entitlements", side_effect=SystemExit("restricted")):
            with self.assertRaises(SystemExit):
                builder.install()
        self.assertEqual(self.number(self.destination), "1")
        self.assertFalse((self.install_root / ".Miaou.installing.app").exists())

    def test_stale_cli_failure_keeps_the_installed_app_running(self):
        with patch.object(builder, "verify_cli_activity", side_effect=SystemExit("stale CLI")):
            with self.assertRaisesRegex(SystemExit, "stale CLI"):
                builder.install()
        self.assertEqual(self.number(self.destination), "1")
        builder.stop_old_app.assert_not_called()
        self.assertFalse((self.install_root / ".Miaou.installing.app").exists())

    def test_build_number_advances_past_installed_version_and_local_counter(self):
        self.bundle(self.destination, "8")
        (self.build / "build-number").write_text("4")
        self.assertEqual(builder.build_number(), "9")
        self.assertEqual(builder.build_number(), "10")

    def test_stop_old_app_kills_only_the_process_from_the_installed_bundle(self):
        self.stop_old_app_patch.stop()
        self.addCleanup(self.stop_old_app_patch.start)
        installed = self.install_root / "Miaou.app/Contents/MacOS/Miaou"
        elsewhere = Path("/somewhere/else/Miaou.app/Contents/MacOS/Miaou")

        def fake_run(cmd, **kwargs):
            if cmd[:2] == ["pgrep", "-x"]:
                return subprocess.CompletedProcess(cmd, 0, stdout="111\n222\n", stderr="")
            if cmd[0] == "ps":
                comm = str(installed) if cmd[2] == "111" else str(elsewhere)
                return subprocess.CompletedProcess(cmd, 0, stdout=comm + "\n", stderr="")
            raise AssertionError(f"unexpected command: {cmd}")

        killed = []
        with patch.object(builder.subprocess, "run", side_effect=fake_run), \
                patch.object(builder.os, "kill",
                             side_effect=lambda pid, sig: killed.append((pid, sig))):
            builder.stop_old_app()
        self.assertEqual(killed, [(111, signal.SIGTERM)])


class WidgetSignatureTests(unittest.TestCase):
    def verify(self, entitlements):
        result = subprocess.CompletedProcess([], 0, stdout=plistlib.dumps(entitlements), stderr=b"")
        with patch.object(builder, "run", return_value=result):
            builder.verify_widget_entitlements(Path("/Miaou.app"))

    def test_native_development_entitlements_are_accepted(self):
        self.verify({"com.apple.security.app-sandbox": True,
                     "com.apple.security.get-task-allow": True,
                     "com.apple.security.application-groups": ["TEAM.com.edjubert.miaou"]})

    def test_restricted_host_entitlement_is_rejected_even_if_false(self):
        for value in [True, False]:
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.verify({"com.apple.private.chrono-extension-host": value})


if __name__ == "__main__":
    unittest.main()
