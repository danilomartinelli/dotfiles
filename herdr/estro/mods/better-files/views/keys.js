// The tree from the keyboard. A click on a row, or the `focus` command, gives the tree the
// keyboard; a marker then shows the row the keys act on, by its path, so it survives a refresh.
import { parentOf } from "../files/model.js";

const PAGE = 10;

export const keyMethods = {
  // The marker shows only while the keys reach it: the tree has the keyboard, or the filter
  // box has it and there are matches to move through.
  showsCursor() {
    return this.treeFocus.is_focused() || Boolean(this.filterFocused && this.filterText());
  },

  focusTree(cx) {
    this.treeFocus.focus();
    if (!this.cursor) this.cursor = this.visibleRows()[0]?.relative ?? null;
    cx.notify();
  },

  // Moves the marker by `step` rows, staying inside the list, and scrolls it into view.
  moveCursor(step, cx, rows = this.visibleRows()) {
    if (!rows.length) return;
    const at = rows.findIndex((r) => r.relative === this.cursor);
    this.markRow(at === -1 ? (step > 0 ? 0 : rows.length - 1) : Math.max(0, Math.min(rows.length - 1, at + step)), cx, rows);
  },

  // Puts the marker on the row at `index` and scrolls it into view.
  markRow(index, cx, rows) {
    this.cursor = rows[index].relative;
    this.treeScroll.scroll_to_item(index);
    cx.notify();
  },

  // What a click on the row does: a file opens in the shared tab, a folder opens or closes,
  // and a matching folder opens in the tree.
  activateRow(row, cx) {
    if (!row.dir) this.openFile(this.fileOf(row.relative), cx);
    else if (this.filterText()) this.revealFolder(row.relative, cx);
    else this.toggleFolder(row.relative, cx);
  },

  treeKey(event, cx) {
    const rows = this.visibleRows();
    const at = rows.findIndex((r) => r.relative === this.cursor);
    const row = rows[at];
    const open = row?.dir && (row.open ?? this.folders.has(row.relative));
    switch (event.keystroke) {
      case "down":
      case "j":
        this.moveCursor(1, cx, rows);
        break;
      case "up":
      case "k":
        this.moveCursor(-1, cx, rows);
        break;
      case "pagedown":
        this.moveCursor(PAGE, cx, rows);
        break;
      case "pageup":
        this.moveCursor(-PAGE, cx, rows);
        break;
      case "home":
        if (rows.length) this.markRow(0, cx, rows);
        break;
      case "end":
        if (rows.length) this.markRow(rows.length - 1, cx, rows);
        break;
      // Opens a closed folder, else steps into it.
      case "right":
      case "l":
        if (!row?.dir) return;
        if (!open && this.filterText()) this.revealFolder(row.relative, cx);
        else if (!open) this.toggleFolder(row.relative, cx);
        else if (rows[at + 1]?.depth > row.depth) this.moveCursor(1, cx, rows);
        break;
      // Closes an open folder, else steps out to the folder above.
      case "left":
      case "h": {
        if (!row) return;
        if (open && !this.filterText()) {
          this.toggleFolder(row.relative, cx);
          break;
        }
        const above = rows.findIndex((r) => r.relative === parentOf(`/${row.relative}`).slice(1));
        if (above !== -1) this.moveCursor(above - at, cx, rows);
        break;
      }
      case "enter":
        if (!row) return;
        this.activateRow(row, cx);
        break;
      case "/":
        this.filter.focus();
        break;
      case ".":
        this.toggleDotfiles(cx);
        break;
      case "escape":
        if (!this.cursor) return;
        this.cursor = null;
        break;
      default:
        return;
    }
    cx.stop_propagation();
    cx.notify();
  },
};
