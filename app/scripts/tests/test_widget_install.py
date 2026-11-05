import importlib.util
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

    def test_unrelated_app_is_never_replaced(self):
        self.bundle(self.destination, "99", identifier="another.app")
        with self.assertRaises(SystemExit):
            builder.install()
        self.assertEqual(self.number(self.destination), "99")

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


if __name__ == "__main__":
    unittest.main()
