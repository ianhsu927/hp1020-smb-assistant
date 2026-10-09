"""Run the uninstaller against temporary fixtures; never touch system printers."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hp1020-uninstall-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "driver"
        self.ppds = self.root / "ppd"
        self.ppds.mkdir()
        self.queue = self.root / "queue"
        self.actions = self.root / "actions"
        self.env = dict(os.environ, FIXTURE=str(self.root), MOCK_UID="0")
        mocks = {
            "id": 'echo "$MOCK_UID"',
            "cupsctl": 'exit "${CUPS_FAILURE:-0}"',
            "lpstat": '[ -f "$FIXTURE/queue" ]',
            "lpadmin": '''
                [ "${QUEUE_FAILURE:-0}" = 0 ] || exit 1
                echo queue >> "$FIXTURE/actions"
                /bin/rm "$FIXTURE/queue" "$FIXTURE/ppd/HP1020_SMB.ppd"
            ''',
            "rm": '''
                [ "$1" = -rf ] && [ "$2" = "$FIXTURE/driver" ] || exit 99
                [ "${REMOVE_FAILURE:-0}" = 0 ] || exit 1
                echo driver >> "$FIXTURE/actions"
                /bin/rm -rf "$FIXTURE/driver"
            ''',
        }
        script = (Path(__file__).resolve().parents[1] / "Resources/uninstall.sh").read_text()
        script = script.replace("BASE=/Library/Printers/hp-legacy-mac", "BASE=" + shlex.quote(str(self.base)))
        script = script.replace("PPDS=/etc/cups/ppd", "PPDS=" + shlex.quote(str(self.ppds)))
        for name, body in mocks.items():
            path = self.root / name
            path.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
            path.chmod(0o755)
            command = "$(id -u)" if name == "id" else {
                "cupsctl": "/usr/sbin/cupsctl", "lpstat": "/usr/bin/lpstat",
                "lpadmin": "/usr/sbin/lpadmin", "rm": "/bin/rm",
            }[name]
            replacement = "$(" + shlex.quote(str(path)) + " -u)" if name == "id" else shlex.quote(str(path))
            script = script.replace(command, replacement)
        self.script = self.root / "uninstall.sh"
        self.script.write_text(script)

    def installed(self, with_queue=True):
        self.base.mkdir()
        (self.base / "hp1020-smb-filter").write_text(f"#!/bin/sh\nBASE={self.base}\n")
        (self.base / "payload").write_text("driver files")
        if with_queue:
            self.add_queue()

    def add_queue(self):
        self.queue.touch()
        (self.ppds / "HP1020_SMB.ppd").write_text(
            f'*cupsFilter: "application/vnd.cups-pdf 0 {self.base}/hp1020-smb-filter"\n'
        )

    def run_uninstaller(self):
        return subprocess.run(["/bin/sh", str(self.script)], env=self.env, text=True, capture_output=True)

    def assert_blocked(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.actions.exists(), "Preflight failure must not change queues or drivers")

    def test_removes_owned_queue_and_driver(self):
        self.installed()
        result = self.run_uninstaller()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.base.exists())
        self.assertFalse(self.queue.exists())
        self.assertEqual(self.actions.read_text().splitlines(), ["queue", "driver"])

    def test_removes_driver_after_queue_was_deleted(self):
        self.installed(with_queue=False)
        self.assertEqual(self.run_uninstaller().returncode, 0)
        self.assertFalse(self.base.exists())
        self.assertEqual(self.actions.read_text().strip(), "driver")

    def test_removes_queue_when_driver_files_are_missing(self):
        self.add_queue()
        self.assertEqual(self.run_uninstaller().returncode, 0)
        self.assertFalse(self.queue.exists())

    def test_repeated_uninstall_is_harmless(self):
        self.installed()
        self.assertEqual(self.run_uninstaller().returncode, 0)
        result = self.run_uninstaller()
        self.assertEqual(result.returncode, 0)
        self.assertIn("无需删除", result.stdout)
        self.assertEqual(self.actions.read_text().splitlines(), ["queue", "driver"])

    def test_shared_driver_blocks_all_changes(self):
        self.installed()
        other = self.ppds / "Other_Printer.ppd"
        other.write_text(f'*cupsFilter: "application/pdf 0 {self.base}/another-filter"\n')
        result = self.run_uninstaller()
        self.assert_blocked(result)
        self.assertIn("Other_Printer", result.stdout)
        self.assertTrue(self.queue.exists())
        self.assertTrue(self.base.exists())

    def test_unrelated_printer_is_preserved(self):
        self.installed()
        other = self.ppds / "Other_Printer.ppd"
        other.write_text('*cupsFilter: "application/pdf 0 /some/other/filter"\n')
        self.assertEqual(self.run_uninstaller().returncode, 0)
        self.assertTrue(other.exists())

    def test_same_queue_with_other_driver_is_preserved(self):
        self.installed()
        (self.ppds / "HP1020_SMB.ppd").write_text('*cupsFilter: "application/pdf 0 /other/filter"\n')
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.queue.exists())
        self.assertTrue(self.base.exists())

    def test_unknown_driver_directory_is_preserved(self):
        self.installed()
        (self.base / "hp1020-smb-filter").write_text("unrelated driver")
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.base.exists())

    def test_symlinked_driver_directory_is_preserved(self):
        self.installed()
        actual = self.root / "actual-driver"
        self.base.rename(actual)
        self.base.symlink_to(actual, target_is_directory=True)
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(actual.exists())

    def test_unreadable_other_ppd_blocks_all_changes(self):
        self.installed()
        (self.ppds / "Broken.ppd").symlink_to(self.root / "missing-file")
        self.assert_blocked(self.run_uninstaller())

    def test_missing_ppd_directory_blocks_driver_removal(self):
        self.installed(with_queue=False)
        self.ppds.rmdir()
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.base.exists())

    def test_queue_without_ppd_is_preserved(self):
        self.installed()
        (self.ppds / "HP1020_SMB.ppd").unlink()
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.queue.exists())
        self.assertTrue(self.base.exists())

    def test_cups_failure_preserves_installation(self):
        self.installed()
        self.env["CUPS_FAILURE"] = "1"
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.queue.exists())
        self.assertTrue(self.base.exists())

    def test_queue_removal_failure_preserves_driver(self):
        self.installed()
        self.env["QUEUE_FAILURE"] = "1"
        self.assert_blocked(self.run_uninstaller())
        self.assertTrue(self.base.exists())

    def test_driver_removal_failure_reports_partial_result(self):
        self.installed()
        self.env["REMOVE_FAILURE"] = "1"
        result = self.run_uninstaller()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.queue.exists())
        self.assertTrue(self.base.exists())
        self.assertIn("驱动文件未能完整删除", result.stdout)

    def test_requires_admin_before_changing_anything(self):
        self.installed()
        self.env["MOCK_UID"] = "501"
        self.assert_blocked(self.run_uninstaller())


if __name__ == "__main__":
    unittest.main()
