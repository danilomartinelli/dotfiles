"""Opt-in real-Mise characterization with a local plugin and an isolated home.

Usage: python3 -B tests/_support/mise-characterization.py /absolute/path/to/mise
No downloads or host tool installations are used. The safe suite uses the fake.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
binary = Path(sys.argv[1]).resolve(strict=True)


def characterize_startup(root, checkout, env, project):
    for name in ("zsh", "pnpm", "functions", "homebrew", "bin"):
        (checkout / name).mkdir()
    for name in ("zsh/zshrc.symlink", "zsh/_startup.zsh", "mise/mise.zsh", "pnpm/path.zsh"):
        shutil.copy2(ROOT / name, checkout / name)
    shutil.copy2(ROOT / "_scripts/topic-catalog", checkout / "_scripts/topic-catalog")
    (checkout / "zsh/prompt.zsh").write_text(":\n")
    (checkout / "functions/compinit").write_text(":\n")
    availability = checkout / "homebrew/_availability.sh"
    availability.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_PREFIX"\n')
    availability.chmod(0o755)
    (root / "home/.zshrc").symlink_to(checkout / "zsh/zshrc.symlink")
    pnpm = root / "home/Library/pnpm/bin"
    pnpm.mkdir(parents=True)
    for directory in (pnpm, *(root / f"data/installs/asdf-fixture/{version}/bin"
                              for version in ("1.0.0", "0.9.0")), checkout / "bin"):
        command = directory / "dot"
        word = "managed" if directory == checkout / "bin" else "foreign"
        command.write_text(f"#!/bin/sh\nprintf '%s\\n' {word}\n")
        command.chmod(0o755)

    program = '''setopt extended_glob
source "$HOME/.zshrc"
set -e
assert_context() {
  [[ $(dot) == managed && $(fixture) == "$1" && $path[1] == "$DOTFILES_ROOT/bin" ]] || {
    print -u2 -r -- "expected managed dot and runtime $1; got $(command -v dot), $(fixture)"
    return 1
  }
}
assert_context 1.0.0
for cycle in 1 2; do
  for hook in $precmd_functions; do "$hook"; done
  assert_context 1.0.0
done
cd "$1"
assert_context 0.9.0
for hook in $precmd_functions; do "$hook"; done
assert_context 0.9.0
source "$HOME/.zshrc"
assert_context 0.9.0
for hook in $precmd_functions; do "$hook"; done
assert_context 0.9.0
cd "$2"
assert_context 1.0.0
for hook in $precmd_functions; do "$hook"; done
assert_context 1.0.0
typeset -a handlers
handlers=("${(M)precmd_functions:#_dotfiles_prioritize_managed_commands}")
(( $#handlers == 1 ))
handlers=("${(M)chpwd_functions:#_dotfiles_prioritize_managed_commands}")
(( $#handlers == 1 ))
'''
    result = subprocess.run(
        ["/bin/zsh", "-f", "-c", program, "zsh", str(project), str(root / "outside")],
        cwd=root / "outside", env={**env, "FIXTURE_PREFIX": str(root),
                                   "MISE_CONFIG_DIR": str(root / "home/.config/mise"),
                                   "MISE_AUTO_INSTALL": "false"},
        text=True, capture_output=True,
    )
    assert result.returncode == 0, f"{result.stdout}\n{result.stderr}"
    assert result.stderr == "", result.stderr
    print("PASS: managed commands keep precedence at prompts, project changes and reload; runtimes still switch")


def characterize(root):
    checkout = root / "checkout"
    for name in ("checkout/mise", "checkout/_scripts", "home/.config/mise",
                 "outside", "bin", "data/plugins/asdf-fixture/bin", "system"):
        (root / name).mkdir(parents=True)
    (root / "bin/mise").symlink_to(binary)
    for name in ("mise-policy", "trusted-roots"):
        shutil.copy2(ROOT / "_scripts" / name, checkout / "_scripts")
    shutil.copy2(ROOT / ".mise.toml", checkout / ".mise.toml")
    plugin = root / "data/plugins/asdf-fixture"
    scripts = {
        "list-all": 'cat "$HOME/releases"',
        "list-bin-paths": "echo bin",
        "install": '''mkdir -p "$ASDF_INSTALL_PATH/bin"
printf '#!/bin/sh\\nprintf "%%s\\\\n" "%s"\\n' "$ASDF_INSTALL_VERSION" > "$ASDF_INSTALL_PATH/bin/fixture"
chmod +x "$ASDF_INSTALL_PATH/bin/fixture"''',
    }
    for name, body in scripts.items():
        script = plugin / "bin" / name
        script.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        script.chmod(0o755)
    env = {
        "HOME": str(root / "home"), "PATH": f"{root / 'bin'}:/usr/bin:/bin",
        "MISE_DATA_DIR": str(root / "data"), "MISE_CACHE_DIR": str(root / "cache"),
        "MISE_STATE_DIR": str(root / "state"), "MISE_SYSTEM_CONFIG_DIR": str(root / "system"),
        "MISE_TRUSTED_CONFIG_PATHS": str(root), "MISE_YES": "1",
        "MISE_FETCH_REMOTE_VERSIONS_CACHE": "0s", "MISE_AUTO_INSTALL": "true",
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
    }
    subprocess.run(["/usr/bin/git", "init", "-q", str(plugin)], env=env, check=True)
    subprocess.run(["/usr/bin/git", "-C", str(plugin), "remote", "add", "origin", str(plugin)],
                   env=env, check=True)
    config = checkout / "mise/config.toml"
    lock = checkout / "mise/mise.lock"
    config.write_text('[tools]\n"asdf:fixture" = "latest" # Fixture\n[settings]\nlockfile = true\n')
    (root / "home/releases").write_text("1.0.0\n")
    global_dir = root / "home/.config/mise"
    (global_dir / "config.toml").symlink_to(config)
    (global_dir / "mise.lock").symlink_to(lock)

    def invoke(*args, managed=False, cwd=checkout, expected=0, **overrides):
        command = [str(binary)]
        if managed:
            command = [str(checkout / "_scripts/mise-policy"), str(checkout)]
        result = subprocess.run([*command, *args], cwd=cwd, env={**env, **overrides},
                                text=True, capture_output=True)
        if (expected == 0 and result.returncode != 0) or (expected != 0 and result.returncode == 0):
            raise AssertionError(f"{command + list(args)}: {result.returncode}\n{result.stdout}\n{result.stderr}")
        if "error loading tracked config file" in result.stderr:
            raise AssertionError(f"{command + list(args)}:\n{result.stderr}")
        return result.stdout

    print(invoke("--version").strip())
    invoke("lock", "asdf:fixture", managed=True)
    original_lock = lock.read_bytes()
    (root / "home/releases").write_text("1.0.0 2.0.0\n")
    assert invoke("exec", "--", "fixture").strip() == "1.0.0"
    assert lock.read_bytes() == original_lock
    print("PASS: direct execution installs the recorded missing tool without changing the linked lock")

    lock.unlink()
    invoke("exec", "--", "fixture", expected=1)
    assert not lock.exists()
    lock.write_bytes(original_lock)
    original_config = config.read_text()
    config.write_text(original_config.replace('"latest"', '"2.0.0"'))
    invoke("exec", "--", "fixture", expected=1)
    assert lock.read_bytes() == original_lock
    print("PASS: missing and incompatible resolutions fail, even with a tool already installed")

    # The accepted external gap: the same global symlink is writable outside
    # the checkout, where its local locked policy is not loaded.
    assert invoke("exec", "--", "fixture", cwd=root / "outside").strip() == "2.0.0"
    assert lock.read_bytes() != original_lock
    print("PASS: execution outside the checkout exposes the documented linked-lock write path")
    config.write_text(original_config)
    lock.write_bytes(original_lock)

    # A project loaded under ordinary discovery remains in Mise's tracker when
    # maintenance suppresses discovery. Reshim and prune must still parse it.
    project = root / "home/Workspace/project"
    project.mkdir(parents=True)
    versions = project / ".tool-versions"
    versions.write_text("asdf:fixture 0.9.0\n")
    (root / "home/releases").write_text("0.9.0 1.0.0 2.0.0\n")
    invoke("install", cwd=project, MISE_LOCKFILE="false")
    project_tool = Path(invoke("where", "asdf:fixture@0.9.0", cwd=project).strip()) / "bin/fixture"
    assert project_tool.is_file()
    assert lock.read_bytes() == original_lock
    invoke("run", "install", managed=True)
    ci_env = dict(line.split("=", 1) for line in invoke("ci", managed=True).splitlines())
    invoke("install", **ci_env)
    invoke("run", "prune", "--yes", managed=True)
    assert project_tool.is_file(), "prune removed a version used by a tracked .tool-versions"
    assert (root / "data/installs/asdf-fixture/1.0.0/bin/fixture").is_file()
    assert not (root / "data/installs/asdf-fixture/2.0.0").exists()
    assert versions.read_text() == "asdf:fixture 0.9.0\n"
    assert lock.read_bytes() == original_lock
    print("PASS: managed and CI installation parse tracked .tool-versions; prune keeps project versions")

    characterize_startup(root, checkout, env, project)
    assert lock.read_bytes() == original_lock

    for extra in (checkout / ".tool-versions", root / "home/.tool-versions"):
        extra.write_text("asdf:fixture 99.0.0\n")
    for extra in (checkout / "mise.local.toml", checkout / ".miserc.toml",
                  checkout / "mise/miserc.toml", root / "system/config.toml"):
        extra.write_text("invalid TOML !\n")
    (global_dir / "conf.d").mkdir()
    (global_dir / "conf.d/foreign.toml").write_text("invalid TOML !\n")
    assert invoke("run", "exec", "--", "fixture", managed=True,
                  MISE_GLOBAL_CONFIG_FILE="/wrong/config.toml", MISE_ENV="foreign",
                  MISE_ASDF_FIXTURE_VERSION="2.0.0", MISE_LOCKED="false").strip() == "1.0.0"
    assert lock.read_bytes() == original_lock
    inherited = {"MISE_ASDF_FIXTURE_VERSION": "2.0.0", "MISE_ASDF__FIXTURE_VERSION": "2.0.0"}
    ci_env = dict(line.split("=", 1) for line in invoke("ci", managed=True, **inherited).splitlines())
    assert invoke("exec", "--", "fixture", **{**inherited, **ci_env}).strip() == "1.0.0"
    assert lock.read_bytes() == original_lock
    print("PASS: managed and CI execution exclude foreign configuration and inherited selectors")

    stage = root / "stage"
    stage.mkdir()
    (stage / "config.toml").write_text(original_config.replace('"latest"', '"2.0.0"'))
    (stage / "mise.lock").write_bytes(original_lock)
    invoke("--declarations", str(stage), "lock", "asdf:fixture", managed=True)
    assert invoke("--declarations", str(stage), "run", "exec", "--", "fixture", managed=True).strip() == "2.0.0"
    assert lock.read_bytes() == original_lock
    print("PASS: selected regeneration and installation use staged declarations only")


with tempfile.TemporaryDirectory(prefix="dotfiles-mise-characterization-") as directory:
    characterize(Path(directory).resolve())
