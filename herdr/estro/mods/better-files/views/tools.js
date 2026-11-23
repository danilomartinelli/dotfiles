// The tree's tools, beside the filter: dotfiles and collapse all.
import { foldersTo } from "../files/filter.js";
import { IconButton } from "./ui.js";

const DOTFILES = "better-files.dotfiles";

// Shown unless turned off, and remembered on this computer. Storage can be missing or
// refuse, and then the choice lasts until Herdr restarts.
export function savedDotfiles() {
  try {
    return localStorage.getItem(DOTFILES) !== "false";
  } catch {
    return true;
  }
}

export const toolMethods = {
  toggleDotfiles(cx) {
    this.dotfiles = !this.dotfiles;
    try {
      localStorage.setItem(DOTFILES, String(this.dotfiles));
    } catch {
      // Not remembered, but still applied.
    }
    cx.notify();
  },

  // A marker in a folder that closes moves to the folder at the top.
  collapseAll(cx) {
    this.folders.clear();
    for (const path of this.entries.keys()) if (path) this.entries.delete(path);
    for (const path of this.folderLists.keys()) if (path) this.folderLists.delete(path);
    this.allocateEntries();
    if (this.cursor?.includes("/")) this.cursor = foldersTo(this.cursor, false)[0];
    cx.notify();
  },

  toolButtons() {
    const filtering = Boolean(this.filterText());
    return [
      IconButton({
        id: "files-tool-dotfiles",
        icon: this.dotfiles ? "eye" : "eye-off",
        label: this.dotfiles ? "Hide dotfiles" : "Show dotfiles",
        small: true,
        onClick: (cx) => this.toggleDotfiles(cx),
      }),
      IconButton({
        id: "files-tool-collapse",
        icon: "chevrons-down-up",
        label: "Collapse all",
        small: true,
        disabled: filtering || this.folders.size === 0,
        onClick: (cx) => this.collapseAll(cx),
      }),
    ];
  },
};
