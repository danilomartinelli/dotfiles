// The selected path is a positional argument, including when its name contains shell syntax.
import { exec, setShared } from "herdr";

const DISCARD_FILE = `
file=./$2
if [ -d "$file" ] && [ ! -L "$file" ]; then
  echo "This path is a directory. Refresh Changes and select a file." >&2
  exit 1
fi
if [ "$1" = restore ]; then
  exec git --literal-pathspecs restore --worktree --no-recurse-submodules -- "$2"
fi
if [ ! -f "$file" ] && [ ! -L "$file" ]; then
  echo "The selected file no longer exists." >&2
  exit 1
fi
if command -v trash >/dev/null 2>&1; then exec trash "$file"; fi
if command -v gio >/dev/null 2>&1; then exec gio trash -- "$file"; fi
echo "No Trash command is available on this machine (trash or gio)." >&2
exit 1
`;

export const discardMethods = {
  askDiscard(file, cx) {
    if (!this.root || this.busy || !file.unstaged || file.conflict ||
        file.path.endsWith("/") || !this.isCurrent(this.context)) return;
    this.discardRequest = { file, root: this.root, on: this.on, context: this.context };
    cx.notify();
  },

  confirmDiscard(request, cx) {
    if (!request || request !== this.discardRequest || this.busy ||
        this.root !== request.root || !this.isCurrent(request.context)) return;
    this.discardRequest = null;
    this.busy = true;
    this.note = null;
    cx.notify();
    cx.spawn(async (cx) => {
      const { file, root, on, context } = request;
      try {
        const status = await this.git(["--literal-pathspecs", "status", "--porcelain=v1", "-z",
          "--no-renames", "--untracked-files=all", "--ignore-submodules=all", "--", file.path], root, on);
        if (status.code !== 0) throw Error(status.stderr || "Cannot check the selected file.");
        const xy = file.fresh ? "??" : file.stagedStatus + file.unstagedStatus;
        if (!status.stdout.split("\0").includes(`${xy} ${file.path}`))
          throw Error("The file's status changed. Refresh Changes and try again.");
        if (!this.isCurrent(context)) return;
        const action = file.fresh ? "trash" : "restore";
        const result = await exec("sh", ["-c", DISCARD_FILE, "discard-file", action, file.path], { cwd: root, on });
        if (result.code !== 0) throw Error(result.stderr.trim() || "The file could not be discarded.");
        this.reload = Date.now();
        setShared("better-changes.reload", { root, on: on ?? null, at: this.reload });
      } catch (error) {
        if (this.isCurrent(context)) this.note = error.message;
      } finally {
        this.busy = false;
        this.refresh(cx);
        cx.notify();
      }
    });
  },
};
