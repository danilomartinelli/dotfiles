"""Stage and publish a fixed set of source files without knowing their formats."""

import os
from pathlib import Path
import shutil
import sys
import tempfile


def write_source(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class PublicationError(RuntimeError):
    def __init__(self, error, failures, recovery_path):
        self.recovery_path = recovery_path
        message = f"source publication failed: {error}"
        if failures:
            message += "; restoration failed: " + "; ".join(
                f"{path}: {failure}" for path, failure in failures
            )
            message += f"; original snapshots retained at {recovery_path}"
        else:
            message += "; source snapshot restored"
        super().__init__(message)


class SourceChangedError(RuntimeError):
    pass


def cleanup(path):
    # Cleanup must not hide a publication error or its recovery instructions.
    active_error = sys.exception()
    try:
        shutil.rmtree(path)
    except OSError as error:
        if active_error is None:
            raise
        print(f"Warning: cannot remove temporary files at {path}: {error}", file=sys.stderr)


class StagedSources:
    def __init__(self, root, outputs, *, inputs=(), write=write_source):
        self.root = root
        self.outputs = tuple(outputs)
        self.inputs = tuple(dict.fromkeys((*self.outputs, *inputs)))
        self.write = write

    def __enter__(self):
        self.original = {path: (self.root / path).read_bytes() for path in self.inputs}
        self.path = Path(tempfile.mkdtemp(prefix="dotfiles-stage-"))
        try:
            for path, content in self.original.items():
                target = self.path / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
        except OSError:
            cleanup(self.path)
            raise
        return self

    def __exit__(self, kind, error, traceback):
        cleanup(self.path)

    def publish(self):
        prepared = {path: (self.path / path).read_bytes() for path in self.outputs}
        recovery = Path(tempfile.mkdtemp(prefix="dotfiles-source-recovery-"))
        keep_recovery = False
        try:
            for path in self.outputs:
                target = recovery / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(self.original[path])
            for path, content in self.original.items():
                if (self.root / path).read_bytes() != content:
                    raise SourceChangedError(f"source changed during staging: {path}")
            written = []
            keep_recovery = True
            try:
                for path, content in prepared.items():
                    self.write(self.root / path, content)
                    written.append(path)
            except OSError as error:
                failures = []
                for path in written:
                    try:
                        self.write(self.root / path, self.original[path])
                    except OSError as failure:
                        failures.append((path, failure))
                keep_recovery = bool(failures)
                raise PublicationError(error, failures, recovery if failures else None) from error
            keep_recovery = False
        finally:
            if not keep_recovery:
                cleanup(recovery)
