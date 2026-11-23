// The POSIX commands macOS uses as they are, and other POSIX platforms can share:
// directory listing, image copies and cache cleanup. Each returns { program, args }.

// --- Directory listing ---
// Wire contract (every platform): NUL-delimited kind/name pairs, .git skipped,
// UTF-8, at most perFolder + 1 entries (one past the cap, so overflow is visible). Missing folder → non-zero exit + stderr.

function listingSh(perFolder) {
  return `n=0; for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do [ -e "$p" ] || [ -L "$p" ] || continue; name=\${p##*/}; [ "$name" = .git ] && continue; if [ -d "$p" ]; then kind=d; else kind=f; fi; printf "%s\\0%s\\0" "$kind" "$name"; n=$((n+1)); [ "$n" -gt ${perFolder} ] && break; done; test -d "$1"`;
}

// The cleanup sweep's own contract, which differs from the tree listing above: a missing cache
// folder is an empty, successful listing, because the sweep must be able to finish; a path that
// exists but cannot be listed is still an error, so a real fault never clears the warning.
const CLEANUP_LISTING = 'n=0; for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do [ -e "$p" ] || [ -L "$p" ] || continue; n=$((n+1)); [ "$n" -le "$2" ] && continue; [ "$n" -gt $(($2+501)) ] && break; if [ -d "$p" ]; then k=d; else k=f; fi; printf "%s\\0%s\\0" "$k" "${p##*/}"; done; [ -d "$1" ] || [ ! -e "$1" ]';

// --- Image copy (viewer + markdown) ---
// Copies go in a hidden folder: saving any other file in a mod's folder makes Herdr reload
// the mod, which threw the tree away on every picture opened. Herdr doesn't see a hidden file
// change either, and keeps what it loaded under a name, so a name is never given to other
// bytes: it's the picture's checksum and size, and a changed picture gets a new one.
// $1 the file, $2 the cache folder, $3 the name's start, $4 its extension, $5 the copy this one
// replaces, removed once the new one is in. With no $5, as when a tab starts again after a
// reload, every other copy under the same start goes instead, so none outlives what tracked
// it. Prints the copy's name. No file name reaches the script itself, and only the cache's
// own copies are ever removed. A picture that changes while it's copied exits BUSY, and a
// copy that fails or is BUSY leaves nothing half-made behind; it's copied on the next check.
export const BUSY = 75;
export const COPY_IMAGE = `sum=$(cksum < "$1") || exit 1
name="$3-\${sum%% *}-\${sum##* }.$4"; copy="$2/$name"
if [ ! -e "$copy" ]; then
  trap 'rm -f -- "$copy.part"' EXIT
  mkdir -p -- "$2" && cp -- "$1" "$copy.part" || exit 1
  [ "$(cksum < "$copy.part")" = "$sum" ] || exit ${BUSY}
  mv -f -- "$copy.part" "$copy" || exit 1
fi
if [ "$6" != retain ]; then
  if [ -n "$5" ]; then set -- "$5"; else set -- "$2/$3"-[0-9]*; fi
  for old in "$@"; do [ "$old" = "$copy" ] || [ ! -e "$old" ] || rm -f -- "$old"; done
fi
printf %s "$name"`;

// --- Cache cleanup on tab close ---
// Missing paths are harmless, but a failed removal must be reported for retry.

// --- Web pictures (markdown) ---
// $1 a picture's web address, $2 its copy without an extension. A copy under a day old is used
// as it is; otherwise it's downloaded (5 MB and 20 s at most) and named by the type the server
// gives, which is how a badge with no extension in its address is known as SVG. A download that
// fails leaves its `.part`, which the next try writes over. Prints the copy's path. Its name is
// kept when it's downloaded again, so Herdr may show the old bytes until it restarts: a badge.
export const FETCH_IMAGE = `for c in "$2".*; do case "$c" in *.part) continue;; esac; [ -f "$c" ] && [ -n "$(find "$c" -mmin -1440)" ] && { printf %s "$c"; exit 0; }; done
mkdir -p -- "$(dirname -- "$2")" && t="$2.part" || exit 1
type=$(curl -fsSL --max-time 20 --max-filesize 5000000 -o "$t" -w '%{content_type}' -- "$1") || exit 1
case "$type" in *svg*) e=svg;; *png*) e=png;; *jpeg*|*jpg*) e=jpg;; *gif*) e=gif;; *webp*) e=webp;; *) exit 1;; esac
mv -f -- "$t" "$2.$e" && printf %s "$2.$e"`;

export const posix = {
  listing: (path, perFolder) => ({ program: "sh", args: ["-c", listingSh(perFolder), "files", path] }),
  cleanupListing: (path, offset) => ({ program: "sh", args: ["-c", CLEANUP_LISTING, "cleanup-list", path, String(offset)] }),
  copyImage: (src, cacheDir, start, ext, old, retain = false) => ({ program: "sh", args: ["-c", COPY_IMAGE, "copy-image", src, cacheDir, start, ext, old, ...(retain ? ["retain"] : [])] }),
  fetchImage: (url, base) => ({ program: "sh", args: ["-c", FETCH_IMAGE, "fetch-image", url, base] }),
  removeCopies: (paths) => ({ program: "rm", args: ["-f", "--", ...paths] }),
};
