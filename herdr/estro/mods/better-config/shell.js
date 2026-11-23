// Platform seam for the two shell-outs in this mod: the installed-mod listing
// and the kept-folder mkdir. macOS/POSIX branches are byte-for-byte identical
// to the original calls; Windows uses powershell.exe with the PS 5.1
// `& { ... } '<arg>'` scriptblock wrapper (required on 5.1, where bare trailing
// -Command args are appended to the command text). PS listing output is one
// directory name per LF line (no trailing slash — the JS-side `/` strip is a
// no-op), and a missing folder is lenient via -ErrorAction SilentlyContinue
// (mirrors 2>/dev/null).

export const psQuote = (s) => "'" + String(s).replace(/'/g, "''") + "'";

export function pickListMods(modsDir, platform) {
  if (platform === "windows") {
    return {
      program: "powershell.exe",
      args: [
        "-NoProfile",
        "-NoLogo",
        "-Command",
        `& { [Console]::OutputEncoding=[Text.Encoding]::UTF8; $mods=Get-ChildItem -LiteralPath $args[0] -Directory -ErrorAction SilentlyContinue; foreach ($m in $mods) { [Console]::Out.Write($m.Name + [char]10) } } ${psQuote(modsDir)}`,
      ],
    };
  }
  return { program: "/bin/sh", args: ["-c", 'cd "$1" && ls -d */ 2>/dev/null', "sh", modsDir] };
}

export function pickMkdir(dir, platform) {
  if (platform === "windows") {
    return {
      program: "powershell.exe",
      args: [
        "-NoProfile",
        "-NoLogo",
        "-Command",
        `& { New-Item -ItemType Directory -Force -Path $args[0] -ErrorAction SilentlyContinue | Out-Null } ${psQuote(dir)}`,
      ],
    };
  }
  return { program: "mkdir", args: ["-p", dir] };
}
