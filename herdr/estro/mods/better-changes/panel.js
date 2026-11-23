// What a key does to the panel, as the commands to run. No Herdr calls, so it stays testable.

// The nodes from the root to the block showing this mod, or null.
// shortcut: floating blocks aren't searched, upgrade when a layout floats the panel.
function pathTo(node, mod) {
  if (node?.content?.mod === mod) return [node];
  for (const child of node?.children ?? []) {
    const path = pathTo(child, mod);
    if (path) return [node, ...path];
  }
  return null;
}

/**
 * Opens the panel: shows every hidden node above it and selects it in its stacks.
 * When it's already open, `toggle` closes it, otherwise nothing happens. Null when
 * the layout has no panel.
 */
export function panelCommands(root, mod, toggle) {
  const path = pathTo(root, mod);
  if (!path) return null;
  const stacked = (node, next) =>
    node.type === "stack" && (node.active ?? node.children[0]?.id) !== next?.id;
  const open = path.every((node, i) => !node.hidden && !stacked(node, path[i + 1]));
  if (!open) {
    const commands = [];
    path.forEach((node, i) => {
      if (stacked(node, path[i + 1]))
        commands.push(["layout.select", { stack: node.id, child: path[i + 1].id }]);
      if (node.hidden) commands.push(["layout.show", { id: node.id }]);
    });
    return commands;
  }
  if (!toggle) return [];
  // Hide the whole slot it fills, so closing leaves no empty frame or sibling behind.
  let slot = path.length - 1;
  while (slot > 1 && (path[slot - 1].type === "stack" || path[slot - 1].children.length === 1))
    slot--;
  return [["layout.hide", { id: path[slot].id }]];
}
