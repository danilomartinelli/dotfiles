// Platform seam for every shell-out in this mod. Each platform's commands live in
// files/shell/<platform>.js as one object with the same methods (listing, cleanupListing,
// copyImage, fetchImage, removeCopies, openInEditor, openWithDefault, reveal, detectEditors, fileManager);
// this file only picks the object. To support a platform, add its file and its entry below.
// Herdr only says what this computer runs, so anything else gets macOS's commands.
import { BUSY, COPY_IMAGE } from "./shell/posix.js";
import { macos } from "./shell/macos.js";
import { windows, psQuote } from "./shell/windows.js";
import { linux, fileUri } from "./shell/linux.js";

export { BUSY, COPY_IMAGE, psQuote, fileUri };

const PLATFORMS = { macos, windows, linux };
const shellFor = (platform) => PLATFORMS[platform] ?? macos;

export const pickListing = (path, perFolder, platform) => shellFor(platform).listing(path, perFolder);
export const pickCleanupListing = (path, offset, platform) => shellFor(platform).cleanupListing(path, offset);
export const pickCopyImage = (src, cacheDir, start, ext, old, platform, retain = false) => shellFor(platform).copyImage(src, cacheDir, start, ext, old, retain);
export const pickFetchImage = (url, base, platform) => shellFor(platform).fetchImage(url, base);
export const pickRm = (paths, platform) => shellFor(platform).removeCopies(paths);
export const pickOpenInEditor = (editor, path, platform) => shellFor(platform).openInEditor(editor, path);
export const pickOpenWithDefault = (path, platform) => shellFor(platform).openWithDefault(path);
export const pickReveal = (path, platform) => shellFor(platform).reveal(path);
// Only Windows builds its file index with one command; other platforms walk the tree with listings.
export const pickIndex = (root, depth, bytes) => windows.index(root, depth, bytes);
export const pickDetectEditors = (baseEditors, extra, platform) => shellFor(platform).detectEditors([...baseEditors, ...extra]);

// --- A file manager of the person's own (settings.fileManager) ---
// Its command, then the file or folder: for Show in, the item; for the folder menu, the folder. On any platform.
export const pickOwnFileManager = (own, path) => ({ program: own.command[0], args: [...own.command.slice(1), path] });

// `own`: the person's file manager, named or not; else the platform's.
const fileManagerName = (platform, own) => (own ? own.name || "file manager" : shellFor(platform).fileManager);
export const revealLabel = (platform, own) => `Show in ${fileManagerName(platform, own)}`;
export const openFolderLabel = (platform, own) => `Open in ${fileManagerName(platform, own)}`;
export const revealError = (platform, own) => {
  const name = fileManagerName(platform, own);
  return `show it in ${name === "file manager" ? "the file manager" : name}`;
};
