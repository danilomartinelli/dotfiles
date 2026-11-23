// The world outside Herdr: code editors, Finder/Explorer/the file manager. This computer only: a
// path on another machine means nothing to an app here.
import { appHome, exec, knownAgents, readTextFile, setShared, shared, window } from "herdr";
import { EDITORS } from "../files/model.js";
import {
  pickDetectEditors,
  pickOpenInEditor,
  pickOpenWithDefault,
  pickOwnFileManager,
  pickReveal,
  revealError,
} from "../files/shell.js";

const FOUND = "better-files.editors";
const ERROR = "better-files.error";
const FILE_MANAGER = "better-files.file-manager";

export const foundEditors = () => shared(FOUND) ?? [];

// settings.fileManager as { name, command }, or null for the platform's own: a command of
// one or more non-empty strings, else none. The sidebar shares it, since the menu is a copy
// of its own that reads no settings.
export function fileManagerOf(setting) {
  const command = Array.isArray(setting?.command) ? setting.command : [];
  if (!command.length || !command.every((part) => typeof part === "string" && part)) return null;
  return { name: typeof setting.name === "string" ? setting.name.trim() : "", command };
}
export const ownFileManager = () => fileManagerOf(shared(FILE_MANAGER));

// macOS entries are known by app ID, Windows and Linux ones by their program's path.
export const editorId = (e) => e.bundle ?? e.exe;

export const outsideMethods = {
  // macOS: one lookup per app ID, done once: Spotlight knows apps wherever they're
  // installed. Windows: one PowerShell process probes App Paths, PATH, and well-known
  // dirs for every candidate; first hit wins. Linux: one sh process looks each editor's
  // commands up on PATH. They store { name, bundle } or { name, exe } entries in shared
  // state.
  findEditors(cx, extra = []) {
    const pick = pickDetectEditors(EDITORS, extra, window()?.platform);
    cx.spawn(async (cx) => {
      const found = [];
      if (pick.kind === "single") {
        const r = await exec(pick.program, pick.args, {}).catch(() => null);
        const fields = r?.code === 0 ? r.stdout.split("\0") : [];
        for (let i = 0; i + 1 < fields.length; i += 2) found.push({ name: fields[i], exe: fields[i + 1] });
      } else {
        for (const probe of pick.probes) {
          const r = await exec(probe.program, probe.args, {}).catch(() => null);
          if (r?.code === 0 && r.stdout.trim()) found.push(probe.editor);
        }
      }
      setShared(FOUND, found);
      cx.notify();
    });
  },

  shareFileManager(setting) {
    setShared(FILE_MANAGER, fileManagerOf(setting));
  },

  // Show diff is only offered where Better Changes can answer it.
  findBetterChanges(cx) {
    cx.spawn(async (cx) => {
      const manifest = await readTextFile(`${appHome()}/mods/better-changes/mod.json`).catch(
        () => null,
      );
      setShared("better-files.has-changes", Boolean(manifest));
      cx.notify();
    });
  },

  findNewAgents(on, cx) {
    cx.spawn(async (cx) => {
      try {
        const known = await knownAgents({ on: on ?? null });
        setShared(
          "better-files.new-agents",
          known.filter((a) => a.installed).map((a) => ({ key: a.key, name: a.name, run: a.run })),
        );
      } catch {
        setShared("better-files.new-agents", []);
      }
      cx.notify();
    });
  },

  // Runs the platform's open command; a failure lands in the shared error slot the
  // sidebar renders as a message.
  async outside(cmd, what) {
    const r = await exec(cmd.program, cmd.args, {}).catch((e) => ({ code: 1, stderr: String(e) }));
    if (r.code !== 0) setShared(ERROR, `Could not ${what}: ${r.stderr?.trim() || "it failed"}`);
    else setShared(ERROR, null);
  },

  openInEditor(editor, path) {
    return this.outside(pickOpenInEditor(editor, path, window()?.platform), `open it in ${editor.name}`);
  },

  openWithDefault(path) {
    return this.outside(pickOpenWithDefault(path, window()?.platform), "open it");
  },

  reveal(path) {
    const platform = window()?.platform, own = ownFileManager();
    return this.outside(own ? pickOwnFileManager(own, path) : pickReveal(path, platform), revealError(platform, own));
  },

  // The folder menu's Open in: the person's file manager, else whatever opens a folder here.
  openFolder(path) {
    const own = ownFileManager();
    if (!own) return this.openWithDefault(path);
    return this.outside(pickOwnFileManager(own, path), `open it in ${own.name || "the file manager"}`);
  },
};
