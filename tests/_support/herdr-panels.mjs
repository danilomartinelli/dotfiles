import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";

// Stand in for the desktop host. Record text passed to the real sidebar view.
const host = {
  herdr: "export const theme = () => ({}); export let exec, shared, setShared, settings, appHome, readTextFile, watchFolder;",
  "gpui-kit": `
    export const text = [];
    export function div() {
      const element = new Proxy({}, {
        get: (_, method) => (value) => {
          if (method === "child" && typeof value === "string") text.push(value);
          return element;
        },
      });
      return element;
    }
    export let image, svg;`,
  "gpui-base": 'export { div as v_flex, div as h_flex } from "gpui-kit"; export let Popover, Textarea;',
};
registerHooks({
  resolve(name, context, next) {
    if (Object.hasOwn(host, name))
      return { url: "data:text/javascript," + encodeURIComponent(host[name]), shortCircuit: true };
    return next(name, context);
  },
});

const { discoveryMethods } = await import("../../herdr/estro/mods/branch-pr/github/discovery.js");
const { sidebarMethods } = await import("../../herdr/estro/mods/better-changes/views/sidebar.js");
const { text } = await import("gpui-kit");

test("switching spaces while a PR opens allows the new branch PR to open", () => {
  const opened = [];
  const panel = {
    ...discoveryMethods,
    view: "branch",
    opening: { number: 1 },
    detailLoading: true,
    detailToken: 1,
    leavePR() {},
    rememberView() {},
    loadNewAgents() {},
    refresh() {},
    search: { value: () => "" },
    openPR(number) { opened.push(number); },
  };
  panel.changeSpace({ folder: "/second" }, "second", {});
  panel.branchPRs = [{ number: 2 }];
  panel.openSoleBranchPR({});
  assert.equal(panel.detailToken, 2);
  assert.deepEqual(opened, [2]);
});

test("a clean checkout stays visible while its status refreshes", () => {
  const panel = {
    files: [],
    settings: { limits: { files: 10 } },
    loading: true,
    addGroup() {},
    renderCommitBox() {},
  };
  function renderText() {
    text.length = 0;
    sidebarMethods.renderChanges.call(panel);
    return text;
  }
  assert.deepEqual(renderText(), ["Loading changes…"]);
  panel.root = "/checkout";
  assert.deepEqual(renderText(), ["No changes"]);
});
