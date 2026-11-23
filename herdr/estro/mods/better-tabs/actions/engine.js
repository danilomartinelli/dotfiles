// What a toolbar button does: run a command, or show and hide a panel.
import { layout, run } from "herdr";

export function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const result = find(child, id);
    if (result) return result;
  }
  return null;
}

// `when: { node }` shows a button only if that layout node exists and isn't hidden.
function shown(button, root) {
  if (!button.when) return true;
  const node = find(root, button.when.node);
  return Boolean(node) && !node.hidden;
}

export function isActive(action, root = layout()) {
  if (action?.type !== "panel") return false;
  const panel = find(root, action.container);
  const stack = find(root, action.stack);
  return Boolean(panel && !panel.hidden && stack?.active === action.target);
}

// The layout's buttons, skipping malformed ones and repeated IDs.
export function buttons(config, root = layout()) {
  const own = Array.isArray(config.buttons) ? config.buttons : [];
  const ids = new Set();
  return own.filter((button) => {
    if (typeof button?.id !== "string" || !button.id || ids.has(button.id)) return false;
    ids.add(button.id);
    return shown(button, root);
  });
}

function togglePanel(action) {
  const root = layout();
  const panel = find(root, action.container);
  const stack = find(root, action.stack);
  if (!panel || !stack?.children?.some((child) => child.id === action.target))
    throw Error("Panel action references a missing container, stack, or child");
  if (isActive(action, root)) return run("layout.hide", { id: action.container });
  run("layout.select", { stack: action.stack, child: action.target });
  return run("layout.show", { id: action.container });
}

export function execute(action) {
  if (action?.type === "panel") return togglePanel(action);
  if (action?.type === "command") {
    if (typeof action.name !== "string" || !action.name) throw Error("Command name is required");
    return run(action.name, action.args ?? {});
  }
  throw Error(`Unknown Better Tabs action type: ${action?.type}`);
}
