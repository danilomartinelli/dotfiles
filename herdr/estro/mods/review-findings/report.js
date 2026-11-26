export function importReport(raw, previous) {
  const { findings } = JSON.parse(raw);
  if (!Array.isArray(findings)) throw new Error("The report needs a findings array.");
  const key = ({ comment, paths }) => JSON.stringify([comment, [...paths].sort()]);
  const existing = new Map(previous.map((item) => [key(item), item]));
  const items = new Map();
  for (const [index, finding] of findings.entries()) {
    const comment = typeof finding?.comment === "string" ? finding.comment.trim() : "";
    const paths = finding?.paths;
    if (!comment || !Array.isArray(paths) || !paths.length || !paths.every((path) =>
      typeof path === "string" && path.trim() && !path.startsWith("/") &&
      !path.split("/").includes("..") && !/[\x00-\x1f]/.test(path)))
      throw new Error(`Finding ${index + 1} needs a comment and repository-relative paths.`);
    const item = { comment, paths: [...new Set(paths)] };
    const id = key(item);
    const prior = existing.get(id);
    items.set(id, { ...item, selected: prior?.selected ?? true, ignored: prior?.ignored ?? false });
  }
  return [...items.values()];
}

export function selectedFindings(items) {
  return items.filter((item) => item.selected && !item.ignored).map(({ comment, paths }) => ({ comment, paths }));
}
