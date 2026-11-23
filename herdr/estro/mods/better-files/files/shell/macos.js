// macOS: the POSIX listing, copies and cleanup, `open` for opening and revealing,
// and Spotlight (mdfind) to find editors by bundle ID. Byte-for-byte the original
// commands; tests/shell.test.cjs holds them to that.
import { posix } from "./posix.js";

export const macos = {
  ...posix,
  fileManager: "Finder",
  openInEditor: (editor, path) => ({ program: "open", args: ["-b", editor.bundle, path] }),
  openWithDefault: (path) => ({ program: "open", args: [path] }),
  reveal: (path) => ({ program: "open", args: ["-R", path] }),
  // One mdfind per bundle ID.
  detectEditors: (editors) => ({
    kind: "perEditor",
    probes: editors.map((e) => ({
      editor: e,
      program: "mdfind",
      args: [`kMDItemCFBundleIdentifier == '${String(e.bundle).replace(/'/g, "")}'`],
    })),
  }),
};
