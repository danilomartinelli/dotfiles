// Linux: the POSIX listing, copies, downloads and cleanup, with its own opening,
// revealing and editor lookup, since `open` and Spotlight are macOS's.
import { posix } from "./posix.js";

// A file goes to the app the desktop's MIME associations name. `gio open` launches it
// and returns; xdg-open on a desktop it doesn't know (Hyprland, Sway…) runs the app in
// the foreground until it closes, past exec's timeout, so it's started in a session of
// its own instead, and then can't report a failure.
const OPEN_SH = `[ -e "$1" ] || { echo 'It is no longer there.' >&2; exit 1; }
if command -v gio >/dev/null 2>&1; then exec gio open "$1"; fi
command -v xdg-open >/dev/null 2>&1 || { echo 'Neither gio nor xdg-open is installed.' >&2; exit 1; }
setsid -f xdg-open "$1" >/dev/null 2>&1`;

// The freedesktop FileManager1 interface selects the item in its folder (Nautilus,
// Dolphin, Nemo, Caja, Thunar and others answer it). Without a file manager that does,
// its folder opens instead. $1 the path, $2 its file:// URI, $3 its folder. dbus-send
// splits an array at commas, so the URI encodes them.
const REVEAL_SH = `[ -e "$1" ] || { echo 'It is no longer there.' >&2; exit 1; }
dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems "array:string:$2" string: >/dev/null 2>&1 && exit 0
set -- "$3"
${OPEN_SH}`;

export const fileUri = (path) => "file://" + String(path).split("/").map(encodeURIComponent).join("/");
const containingFolder = (path) => String(path).replace(/\/+$/, "").replace(/\/[^/]*$/, "") || "/";

// --- Editor detection ---
// One sh process looks up each editor's commands (`bins`) on PATH; first hit wins.
// Emits name\0path\0 pairs, like the Windows probe. Arguments are name, then the
// editor's commands separated by spaces; only an absolute path counts as found, so a
// shell function or alias of the same name doesn't. Always exits 0.
const DETECT_EDITORS_SH = `while [ $# -ge 2 ]; do
  for b in $2; do p=$(command -v "$b" 2>/dev/null) && case $p in /*) printf '%s\\0%s\\0' "$1" "$p"; break;; esac; done
  shift 2
done
exit 0`;

const EDITOR_COMMAND = /^[A-Za-z0-9_][A-Za-z0-9._+-]*$/;

export const linux = {
  ...posix,
  fileManager: "file manager",
  // editor.exe is the path the lookup found.
  openInEditor: (editor, path) => ({ program: editor.exe, args: [path] }),
  openWithDefault: (path) => ({ program: "sh", args: ["-c", OPEN_SH, "open", path] }),
  reveal: (path) => ({ program: "sh", args: ["-c", REVEAL_SH, "reveal", path, fileUri(path), containingFolder(path)] }),
  detectEditors: (editors) => {
    const pairs = editors.flatMap((e) => {
      const bins = (Array.isArray(e?.bins) ? e.bins : []).filter((b) => typeof b === "string" && EDITOR_COMMAND.test(b));
      return e?.name && bins.length ? [String(e.name), bins.join(" ")] : [];
    });
    return { kind: "single", program: "sh", args: ["-c", DETECT_EDITORS_SH, "editors", ...pairs] };
  },
};
