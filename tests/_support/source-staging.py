"""Source publication contracts using real temporary files."""

from pathlib import Path
import sys
import tempfile
import unittest
import shutil
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_scripts"))
from source_staging import StagedSources, write_source


class SourceStagingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-staging-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.work = self.root / "temporary"
        self.work.mkdir()
        # Isolate the filesystem's temporary namespace, including recovery copies.
        temporary_directory = patch.object(tempfile, "tempdir", str(self.work))
        temporary_directory.start()
        self.addCleanup(temporary_directory.stop)
        self.outputs = (Path("config/settings"), Path("lock"), Path("catalog"))
        self.original = {}
        for path in (*self.outputs, Path("declarations")):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            content = f"original {path}\n".encode()
            target.write_bytes(content)
            self.original[path] = content

    def test_unchanged_sources_publish_only_outputs_and_preserve_mode(self):
        (self.root / self.outputs[0]).chmod(0o640)
        with StagedSources(self.root, self.outputs, inputs=(Path("declarations"),)) as sources:
            stage = sources.path
            self.assertEqual(self.original[Path("declarations")], (stage / "declarations").read_bytes())
            for path in self.outputs:
                (stage / path).write_bytes(b"new\n")
            (stage / "declarations").write_bytes(b"staged input is not published\n")
            sources.publish()
        self.assertFalse(stage.exists())
        for path in self.outputs:
            self.assertEqual(b"new\n", (self.root / path).read_bytes())
        self.assertEqual(self.original[Path("declarations")], (self.root / "declarations").read_bytes())
        self.assertEqual(0o640, (self.root / self.outputs[0]).stat().st_mode & 0o777)
        self.assertEqual([], list(self.work.iterdir()))

    def test_concurrent_edits_to_outputs_or_read_only_inputs_abort_publication(self):
        for changed in self.original:
            with self.subTest(changed=changed):
                for path, content in self.original.items():
                    (self.root / path).write_bytes(content)
                with StagedSources(self.root, self.outputs, inputs=(Path("declarations"),)) as sources:
                    for path in self.outputs:
                        (sources.path / path).write_bytes(b"new\n")
                    (self.root / changed).write_bytes(b"owner edit\n")
                    with self.assertRaisesRegex(RuntimeError, "source changed"):
                        sources.publish()
                for path, original in self.original.items():
                    self.assertEqual(b"owner edit\n" if path == changed else original, (self.root / path).read_bytes())
                self.assertEqual([], list(self.work.iterdir()))

    def test_failed_publication_restores_every_published_source(self):
        def failing_write(path, content):
            if path.name == "catalog" and content == b"new\n":
                raise OSError("publication denied")
            write_source(path, content)

        with StagedSources(self.root, self.outputs, write=failing_write) as sources:
            for path in self.outputs:
                (sources.path / path).write_bytes(b"new\n")
            with self.assertRaisesRegex((OSError, RuntimeError), "publication denied"):
                sources.publish()
        for path, original in self.original.items():
            self.assertEqual(original, (self.root / path).read_bytes())
        self.assertEqual([], list(self.work.iterdir()))

    def test_incomplete_restoration_continues_and_retains_originals_with_both_errors(self):
        def failing_write(path, content):
            if path.name == "catalog" and content == b"new\n":
                raise OSError("publication denied")
            if path.name == "settings" and content != b"new\n":
                raise OSError("restoration denied")
            write_source(path, content)

        with StagedSources(self.root, self.outputs, write=failing_write) as sources:
            for path in self.outputs:
                (sources.path / path).write_bytes(b"new\n")
            with self.assertRaisesRegex(RuntimeError, "publication denied.*restoration denied") as caught:
                sources.publish()
        recovery = caught.exception.recovery_path
        self.addCleanup(shutil.rmtree, recovery)
        self.assertIn(str(recovery), str(caught.exception))
        self.assertIn("config/settings", str(caught.exception))
        self.assertEqual(b"new\n", (self.root / self.outputs[0]).read_bytes())
        self.assertEqual(self.original[Path("lock")], (self.root / "lock").read_bytes())
        for path in self.outputs:
            self.assertEqual(self.original[path], (recovery / path).read_bytes())

    def test_failure_to_prepare_recovery_copy_prevents_every_source_write(self):
        original_write = Path.write_bytes

        def deny_backup(path, content):
            if "dotfiles-source-recovery-" in str(path):
                raise OSError("recovery storage full")
            return original_write(path, content)

        with StagedSources(self.root, self.outputs) as sources:
            for path in self.outputs:
                (sources.path / path).write_bytes(b"new\n")
            with patch.object(Path, "write_bytes", deny_backup):
                with self.assertRaisesRegex(OSError, "recovery storage full"):
                    sources.publish()
        self.assertEqual([], list(self.work.iterdir()))
        for path, original in self.original.items():
            self.assertEqual(original, (self.root / path).read_bytes())

    def test_deleted_source_aborts_before_publication(self):
        with StagedSources(self.root, self.outputs) as sources:
            (self.root / "lock").unlink()
            (sources.path / self.outputs[0]).write_bytes(b"new\n")
            with self.assertRaises(FileNotFoundError):
                sources.publish()
        self.assertEqual(self.original[self.outputs[0]], (self.root / self.outputs[0]).read_bytes())
        self.assertFalse((self.root / "lock").exists())
        self.assertEqual([], list(self.work.iterdir()))

    def test_cleanup_failure_does_not_hide_publication_or_restoration_errors(self):
        def failing_write(path, content):
            if path.name == "catalog":
                raise OSError("publication denied")
            if content != b"new\n":
                raise OSError(f"cannot restore {path.name}")
            write_source(path, content)

        import contextlib
        import io

        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            with self.assertRaisesRegex(RuntimeError, "publication denied.*cannot restore settings.*cannot restore lock") as caught:
                with patch.object(shutil, "rmtree", side_effect=OSError("cleanup denied")):
                    with StagedSources(self.root, self.outputs, write=failing_write) as sources:
                        for path in self.outputs:
                            (sources.path / path).write_bytes(b"new\n")
                        sources.publish()
        self.assertIn("cleanup denied", errors.getvalue())
        recovery = caught.exception.recovery_path
        self.assertTrue(recovery.is_dir())
        for path in self.outputs:
            self.assertEqual(self.original[path], (recovery / path).read_bytes())


if __name__ == "__main__":
    unittest.main()
