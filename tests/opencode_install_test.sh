#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/opencode-catalog.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/opencode-catalog.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
scenario_init dotfiles-opencode-install-tests

TAB=$'\t'

write_retired_fixture_row() {
  printf '  "%s": "%s",\n' "$1" "$2"
}

make_fake_clis() {
  local home=$1
  local fake_bin=$home/fake-bin

  mkdir -p "$fake_bin"
  ln -s "$(command -v bun)" "$fake_bin/real-bun"
  stub_uname "$fake_bin"
  {
    printf '{\n'
    catalog_each_row "$REPOSITORY_ROOT/opencode/_retired-components.tsv" write_retired_fixture_row
    printf '}\n'
  } >"$fake_bin/retired.jsonc"

  scenario_write_executable "$fake_bin/opencode" <<'EOF'
#!/bin/sh
printf 'native opencode %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  scenario_write_executable "$fake_bin/bun" <<'EOF'
#!/bin/sh
if [ "$1" != install ]; then
  exec "$(dirname -- "$0")/real-bun" "$@"
fi
printf 'bun %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
[ "$1 $2 $3 $4" = 'install --frozen-lockfile --ignore-scripts --cwd' ] \
  && [ "$#" -eq 5 ] && [ -f "$5/package.json" ] && [ -f "$5/bun.lock" ] \
  || exit 2
if [ "${STUB_BUN_FAIL:-}" = true ]; then
  printf 'fixture dependency installation failed\n' >&2
  exit 1
fi
EOF

  scenario_write_executable "$fake_bin/ocx" <<'EOF'
#!/bin/sh
exec "$(dirname -- "$0")/real-bun" "$(dirname -- "$0")/ocx.js" "$@"
EOF
  cat >"$fake_bin/ocx.js" <<'EOF'
import * as fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import retired from "./retired.jsonc";
const args = process.argv.slice(2);
const config = path.join(process.env.HOME, ".config/opencode");
const receiptPath = path.join(config, ".ocx/receipt.jsonc");
fs.appendFileSync(process.env.SCENARIO_EVENT_LOG, `ocx ${args.join(" ")}\n`);
const receipt = fs.existsSync(receiptPath) ? (await import(pathToFileURL(receiptPath).href)).default : { version: 1, installed: {} };
const fail = (message, status = 1) => { console.error(message); process.exit(status); };
const hash = (text) => createHash("sha256").update(text).digest("hex");
const save = () => {
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2));
};
const add = (name, files) => {
  const key = `https://registry.kdco.dev::kdco/${name}@sha256:test`;
  if (receipt.installed[key]) return;
  const entries = files.map((file) => {
    const target = path.join(config, file);
    const contents = file.startsWith("plugins/") ? `runtime plugin ${name}\n` : `registry payload ${name}\n`;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, contents);
    return { path: file, hash: hash(contents) };
  });
  receipt.installed[key] = { registryUrl: "https://registry.kdco.dev", registryName: "kdco", name, revision: "sha256:test", hash: "test", installedAt: "2026-01-01T00:00:00Z", files: entries };
};
if (args[0] === "init") {
  fs.mkdirSync(path.join(config, "profiles/default"), { recursive: true });
  if (!fs.existsSync(path.join(config, "ocx.jsonc"))) fs.writeFileSync(path.join(config, "ocx.jsonc"), "{}\n");
} else if (args[0] === "add") {
  if (!args.includes("--global")) fail("missing --global", 2);
  const names = args.slice(1).filter((name) => name !== "--global");
  if (names.includes("kdco/workspace")) {
    for (const [name, file] of Object.entries(retired)) add(name, file === "-" ? [] : [file]);
    for (const name of ["workspace-plugin", "background-agents"]) add(name, [`plugins/${name}.ts`]);
    names.push("kdco/worktree", "kdco/notify");
  }
  for (const name of names) {
    if (name === "kdco/workspace") continue;
    if (!["kdco/worktree", "kdco/notify"].includes(name)) fail("unexpected component", 2);
    add(name.slice(5), [`plugins/${name.slice(5)}.ts`]);
    add("kdco-primitives", ["plugins/kdco-primitives/index.ts"]);
  }
  save();
  for (const [file, contents] of [["package.json", '{"dependencies":{}}\n'], [".gitignore", "node_modules\n"], ["opencode.jsonc", "{}\n"]]) {
    if (!fs.existsSync(path.join(config, file))) fs.writeFileSync(path.join(config, file), contents);
  }
} else if (args[0] === "remove") {
  const cwd = args.indexOf("--cwd");
  if (cwd < 2 || args[cwd + 1] !== config) fail("unexpected remove cwd", 2);
  const force = args.includes("--force");
  const keys = args.slice(1, cwd).map((ref) => Object.keys(receipt.installed).find((key) => key === ref || key.includes(`::${ref}@`)));
  if (keys.some((key) => !key)) fail("component not installed", 66);
  const targets = [];
  for (const key of keys) {
    if (process.env.STUB_OCX_REMOVE_FAIL === "true") fail("modified original plugin; removal refused");
    for (const file of receipt.installed[key].files) {
      const target = path.join(config, file.path);
      let actual;
      try { actual = fs.realpathSync(target); }
      catch (error) { if (!["ENOENT", "ENOTDIR"].includes(error.code)) throw error; }
      if (actual && !actual.startsWith(`${fs.realpathSync(config)}${path.sep}`)) fail("Security violation: path escapes project directory");
      if (!force && (!actual || hash(fs.readFileSync(actual)) !== file.hash)) fail(`modified or missing payload: ${file.path}`);
      if (actual) targets.push(actual);
    }
  }
  for (const target of targets) fs.unlinkSync(target);
  for (const key of keys) delete receipt.installed[key];
  save();
} else if (args[0] === "profile") {
  const target = path.join(config, "profiles", args[2]);
  if (args[1] === "remove") {
    let stat;
    try { stat = fs.lstatSync(target); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    if (!stat) fail(`Profile ${args[2]} not found`, 66);
    fs.rmSync(target, { recursive: !stat.isSymbolicLink() });
  } else if (args[1] === "add") {
    if (args[3] === "--clone" && !fs.existsSync(path.join(config, "profiles", args[4]))) fail(`clone source missing: ${args[4]}`);
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, "generated"), "generated profile\n");
  }
}
EOF

  printf '%s\n' "$fake_bin"
}

assert_link_target() {
  local expected=$1
  local link=$2
  local description=$3

  [[ -L $link ]] || scenario_fail "$description is not a symbolic link"
  assert_equal "$expected" "$(readlink "$link")" "$description target"
}

opencode_profile_add_line() {
  local name=$1
  local clone=$2

  if [[ $clone == - ]]; then
    printf 'ocx profile add %s --global\n' "$name"
  else
    printf 'ocx profile add %s --clone %s --global\n' "$name" "$clone"
  fi
}

assert_catalog_links() {
  local config_dir=$1
  local phase=$2
  local name

  while IFS= read -r name; do
    assert_link_target "$REPOSITORY_ROOT/opencode/$name" \
      "$config_dir/$name" "OpenCode $name ($phase)"
  done < <(opencode_catalog_names entry)

  while IFS= read -r name; do
    assert_link_target "$REPOSITORY_ROOT/opencode/profiles/$name" \
      "$config_dir/profiles/$name" "OpenCode $name profile ($phase)"
  done < <(opencode_catalog_names profile)
}

copy_opencode_fixture() {
  local target=$1

  mkdir -p "$target"
  tar -C "$REPOSITORY_ROOT/opencode" --exclude=node_modules -cf - . \
    | tar -C "$target" -xf -
}

test_shell_uses_regular_ocx_profile_and_shortcuts() {
  local fake_bin home output

  home=$(scenario_tmpdir shell)
  fake_bin=$(make_fake_clis "$home")

  # shellcheck disable=SC2016 # Expanded by the nested Zsh.
  output=$(env HOME="$home" /bin/zsh -f -c \
    'source "$1"; print -r -- "$OCX_PROFILE|$OPENCODE_EXPERIMENTAL_WORKSPACES|$OPENCODE_DISABLE_PROJECT_CONFIG|$OPENCODE_DISABLE_EXTERNAL_SKILLS|$OPENCODE_DISABLE_CLAUDE_CODE_SKILLS"' \
    zsh "$REPOSITORY_ROOT/opencode/env.zsh") || return 1

  assert_equal 'regular|true|true|true|true' "$output" \
    'OpenCode shell environment'

  # shellcheck disable=SC2016 # Expanded by the nested Zsh.
  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" /bin/zsh -f -c \
    'source "$1"; for shortcut in opencode oc oc:regular oc:example; do eval "$shortcut"; done; (( ! $+aliases[oc:go] && ! $+aliases[oc:boost] ))' \
    zsh "$REPOSITORY_ROOT/opencode/aliases.zsh"

  assert_count "$home/events.log" 'ocx opencode' 4
  assert_contains "$home/events.log" 'ocx opencode -p regular'
  assert_contains "$home/events.log" 'ocx opencode -p example'
  assert_not_contains "$home/events.log" 'native opencode'
}

test_gui_adapter_preserves_project_loading_and_pins_selected_profile_routes() {
  local fixture checkout home selected
  fixture=$(scenario_tmpdir gui-adapter)
  checkout=$fixture/checkout
  home=$fixture/home
  mkdir -p "$checkout/bin" "$checkout/_scripts" "$checkout/homebrew" "$checkout/opencode" "$fixture/brew/bin" "$home"
  cp "$REPOSITORY_ROOT/bin/opencode-profile" "$checkout/bin/"
  cp "$REPOSITORY_ROOT/_scripts/adapter-checkout.sh" "$checkout/_scripts/"
  cp "$REPOSITORY_ROOT/opencode/env.zsh" "$checkout/opencode/"
  scenario_write_executable "$fixture/resolver" <<'EOF'
#!/bin/sh
printf '%s\n' "$FIXTURE_CHECKOUT"
EOF
  ln -s "$fixture/resolver" "$home/.dotfiles-root"
  scenario_write_executable "$checkout/homebrew/_availability.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$FIXTURE_BREW"
EOF
  scenario_write_executable "$fixture/brew/bin/mise" <<'EOF'
#!/bin/sh
[ "$*" = 'which opencode' ] || exit 1
printf '%s\n' "$FIXTURE_BREW/bin/opencode"
EOF
  scenario_write_executable "$fixture/brew/bin/opencode" <<'EOF'
#!/bin/sh
printf '%s\n' "$OPENCODE_DISABLE_PROJECT_CONFIG|$OPENCODE_DISABLE_EXTERNAL_SKILLS|${OPENCODE_CONFIG:-absent}|${DOTFILES_OPENCODE_PROFILE_CONFIG:-absent}"
printf 'args:%s\n' "$*"
EOF
  for selected in regular example; do
    mkdir -p "$home/.config/opencode/profiles/$selected"
    printf '{}\n' >"$home/.config/opencode/profiles/$selected/opencode.jsonc"
    scenario_capture "$fixture" env HOME="$home" OCX_PROFILE="$selected" \
      FIXTURE_CHECKOUT="$checkout" FIXTURE_BREW="$fixture/brew" \
      "$checkout/bin/opencode-profile" --version
    assert_contains "$fixture/stdout.log" "false|true|$home/.config/opencode/profiles/$selected/opencode.jsonc|$home/.config/opencode/profiles/$selected/opencode.jsonc"
    assert_contains "$fixture/stdout.log" 'args:--version'
  done
  scenario_capture "$fixture" env HOME="$home" OCX_PROFILE=missing \
    OPENCODE_CONFIG=stale DOTFILES_OPENCODE_PROFILE_CONFIG=stale \
    FIXTURE_CHECKOUT="$checkout" FIXTURE_BREW="$fixture/brew" \
    "$checkout/bin/opencode-profile" --help
  assert_contains "$fixture/stdout.log" 'false|true|absent|absent'
  assert_contains "$fixture/stderr.log" 'no configuration for profile missing'
}

test_managed_payload_is_complete_and_runtime_payload_is_excluded() {
  local jsonc_path managed_path name
  local -a managed_paths

  # Rendered profiles still require their owning sources.
  managed_paths=(
    profiles/_routing.tsv
    profiles/_shared/AGENTS.md
    profiles/_shared/ocx.jsonc
    profiles/_shared/opencode.jsonc
  )

  while IFS= read -r name; do
    opencode_entry_is_directory "$name" || managed_paths+=("$name")
  done < <(opencode_catalog_names entry)

  while IFS= read -r name; do
    managed_paths+=(
      "profiles/$name/AGENTS.md"
      "profiles/$name/ocx.jsonc"
      "profiles/$name/opencode.jsonc"
    )
  done < <(opencode_catalog_names profile)

  for managed_path in "${managed_paths[@]}"; do
    [[ -f $REPOSITORY_ROOT/opencode/$managed_path ]] \
      || scenario_fail "managed OpenCode payload is missing: $managed_path"
  done

  while IFS= read -r jsonc_path; do
    jsonc_to_json "$jsonc_path" >/dev/null \
      || scenario_fail "OpenCode JSONC is invalid: ${jsonc_path#"$REPOSITORY_ROOT/"}"
  done < <(find "$REPOSITORY_ROOT/opencode" -type d -name node_modules -prune \
    -o -type f -name '*.jsonc' -print | sort)

  for managed_path in agents commands skills tools plugins .ocx package.json .gitignore; do
    [[ ! -e $REPOSITORY_ROOT/opencode/$managed_path ]] \
      || scenario_fail "runtime or legacy OpenCode payload is versioned: $managed_path"
  done

  # Versioned content with no catalog row would never be linked, so the
  # catalog and the checkout have to agree in both directions. Between them
  # these three cover every row the catalog can declare.
  while IFS= read -r name; do
    opencode_catalog_has entry "$name" \
      || scenario_fail "versioned OpenCode config has no catalog row: $name"
  done < <(find "$REPOSITORY_ROOT/opencode" -maxdepth 1 -type f \
    -name '*.jsonc' -exec basename -- {} \; | sort)

  while IFS= read -r name; do
    opencode_catalog_has profile "$name" \
      || scenario_fail "versioned OpenCode profile has no catalog row: $name"
  done < <(find "$REPOSITORY_ROOT/opencode/profiles" -mindepth 1 -maxdepth 1 \
    -type d ! -name '_*' -exec basename -- {} \; | sort)
}

test_tui_matches_terminal_theme_and_interaction_defaults() {
  local tui_config

  tui_config=$REPOSITORY_ROOT/opencode/tui.jsonc

  jsonc_to_json "$tui_config" | jq -e '
		."$schema" == "https://opencode.ai/tui.json" and
		.theme == "catppuccin-macchiato" and
		.leader_timeout == 2000 and
		.keybinds == {
			"leader": "ctrl+x",
			"command_list": "ctrl+p"
		} and
		.scroll_speed == 3 and
		.scroll_acceleration == {"enabled": true} and
		.diff_style == "auto" and
		.cursor == {"style": "block", "blinking": true} and
		.mouse == true and
		.attention == {
			"enabled": true,
			"notifications": true,
			"sound": false
		} and
		(has("plugin") | not)
	' >/dev/null \
    || scenario_fail 'OpenCode TUI theme or interaction defaults are incorrect'
}

test_profiles_trust_project_configuration() {
  local profile ocx_config opencode_config

  while IFS= read -r profile; do
    ocx_config=$REPOSITORY_ROOT/opencode/profiles/$profile/ocx.jsonc

    jsonc_to_json "$ocx_config" | jq -e \
      '.exclude == [] and .include == []' >/dev/null \
      || scenario_fail "$profile profile visibility policy is incorrect"
  done < <(opencode_catalog_names profile)

  opencode_config=$REPOSITORY_ROOT/opencode/opencode.jsonc
  jsonc_to_json "$opencode_config" | jq -e '
    (.mcp | keys) == ["context7", "exa", "gh_grep"] and
    all(.mcp[]; .enabled == true)
  ' >/dev/null \
    || scenario_fail 'global research MCP defaults are incorrect'
}

test_profile_payloads_are_composed_from_the_shared_base() {
  local fixture stored

  # OCX cannot layer a profile, so the shared half of every payload is composed
  # here instead. Checking the render is what replaces comparing the three
  # stored copies against each other: it catches a payload whose shared policy
  # drifted, and a shared edit that was never rendered out.
  "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check >/dev/null \
    || scenario_fail 'checked-in OpenCode profiles differ from the composed result'

  fixture=$(scenario_tmpdir compose)
  copy_opencode_fixture "$fixture/opencode"
  stored=$fixture/opencode/profiles/example/opencode.jsonc

  jq --indent 2 '.permission["project_*"] = "ask"' "$stored" >"$fixture/drifted"
  mv "$fixture/drifted" "$stored"

  assert_fails_with_output 'drifted shared policy' \
    'profiles/example/opencode.jsonc' \
    "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"

  cp "$REPOSITORY_ROOT/opencode/profiles/_routing.tsv" "$stored.routing"
  grep -v "^example${TAB}reviewer" "$stored.routing" \
    >"$fixture/opencode/profiles/_routing.tsv"

  assert_fails_with_output 'unrouted agent' \
    'example has no routing row for: reviewer' \
    "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"

  # A row carrying the retired reasoningEffort and textVerbosity columns still
  # parses, because the reader pads every row to seven. Rendering it would put
  # keys OpenCode ignores back into a payload, so the renderer refuses instead.
  sed "s|^regular${TAB}plan${TAB}.*|regular${TAB}plan${TAB}openai/gpt-5.6-sol${TAB}high${TAB}0.3${TAB}xhigh${TAB}low|" \
    "$stored.routing" >"$fixture/opencode/profiles/_routing.tsv"

  assert_fails_with_output 'retired routing columns' \
    'routing row has columns past temperature: regular plan' \
    "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"
}

test_profile_overrides_are_isolated_and_cannot_override_routes() {
  local fixture override key

  fixture=$(scenario_tmpdir profile-overrides)
  copy_opencode_fixture "$fixture/opencode"
  mkdir -p "$fixture/opencode/profiles/_overrides"
  override=$fixture/opencode/profiles/_overrides/regular.jsonc

  printf '{"permission":{"project_*":"ask"}}\n' >"$override"
  "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" "$fixture/opencode" \
    >/dev/null || return 1
  jq -e '.permission["project_*"] == "ask" and .agent.coder.model == "openai/gpt-5.6-luna"' \
    "$fixture/opencode/profiles/regular/opencode.jsonc" >/dev/null \
    || scenario_fail 'regular override did not merge with shared policy'

  cmp "$REPOSITORY_ROOT/opencode/profiles/example/opencode.jsonc" \
    "$fixture/opencode/profiles/example/opencode.jsonc" \
    || scenario_fail 'example changed when only regular policy changed'

  grep -v "^regular${TAB}coder" \
    "$REPOSITORY_ROOT/opencode/profiles/_routing.tsv" \
    >"$fixture/opencode/profiles/_routing.tsv"
  assert_fails_with_output 'unrouted agent' \
    'regular has no routing row for: coder' \
    "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"

  cp "$REPOSITORY_ROOT/opencode/profiles/_routing.tsv" \
    "$fixture/opencode/profiles/_routing.tsv"
  printf 'example\tunknown-role\topenai/gpt-5.6-luna\thigh\t-\n' \
    >>"$fixture/opencode/profiles/_routing.tsv"
  assert_fails_with_output 'undeclared agent' \
    'routing row names an undeclared agent: example unknown-role' \
    "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"

  cp "$REPOSITORY_ROOT/opencode/profiles/_routing.tsv" \
    "$fixture/opencode/profiles/_routing.tsv"
  for key in model variant temperature reasoningEffort textVerbosity; do
    jq -n --arg key "$key" '.agent.coder[$key] = "conflict"' >"$override"
    assert_fails_with_output "override must not set $key" \
      'routing options outside _routing.tsv' \
      "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"
  done
  for key in model small_model; do
    jq -n --arg key "$key" '.[$key] = "conflict"' >"$override"
    assert_fails_with_output "override must not set $key" \
      'routing options outside _routing.tsv' \
      "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check "$fixture/opencode"
  done
}

test_profiles_route_models() {
  local profile config

  assert_equal $'regular\nexample' "$(opencode_catalog_names profile)" \
    'managed OpenCode profile roster'

  while IFS= read -r profile; do
    config=$REPOSITORY_ROOT/opencode/profiles/$profile/opencode.jsonc
    jsonc_to_json "$config" | jq -e '
      .model == "openai/gpt-5.6-sol" and
      .small_model == "openai/gpt-5.6-luna" and
      .agent == {
        "plan": {"model": "openai/gpt-5.6-sol", "variant": "xhigh"},
        "build": {"model": "openai/gpt-5.6-sol", "variant": "xhigh"},
        "coder": {"model": "openai/gpt-5.6-luna", "variant": "high"},
        "explore": {"model": "openai/gpt-5.6-luna", "variant": "high"},
        "researcher": {"model": "openai/gpt-5.6-luna", "variant": "high"},
        "scribe": {"model": "openai/gpt-5.6-luna", "variant": "high"},
        "reviewer": {"model": "openai/gpt-5.6-luna", "variant": "high"}
      }
    ' >/dev/null \
      || scenario_fail "$profile profile model routing is incorrect"
  done < <(opencode_catalog_names profile)

  cmp "$REPOSITORY_ROOT/opencode/profiles/regular/opencode.jsonc" \
    "$REPOSITORY_ROOT/opencode/profiles/example/opencode.jsonc" \
    || scenario_fail 'example must demonstrate the same routing as regular'
}

test_catalog_declares_each_clone_source_before_its_clones() {
  local kind name clone
  local -a declared=()

  while IFS=$'\t' read -r kind name clone; do
    [[ $kind == entry || $kind == profile ]] \
      || scenario_fail "unknown OpenCode catalog kind: $kind"
    [[ -n $name && -n $clone ]] \
      || scenario_fail "incomplete OpenCode catalog row: $kind $name"

    if [[ $kind == profile ]]; then
      if [[ $clone != - ]]; then
        [[ " ${declared[*]:-} " == *" $clone "* ]] \
          || scenario_fail "profile $name clones $clone before it is declared"
      fi
      declared+=("$name")
    fi
  done < <(opencode_catalog_rows)

  [[ ${#declared[@]} -gt 0 ]] \
    || scenario_fail 'OpenCode catalog declares no profiles'
}

test_opencode_catalog_reader_preserves_catalog_row_contract() {
  local fixture actual expected
  fixture=$(scenario_tmpdir catalog-reader)
  mkdir -p "$fixture/opencode"
  {
    printf '# comment\n\n'
    printf 'entry\tfirst\t-\n'
    printf 'profile\tsecond\tfirst\n'
    printf 'profile\tfinal\t-'
  } >"$fixture/opencode/_managed-entries.tsv"

  local REPOSITORY_ROOT=$fixture
  expected=$'entry\tfirst\t-\nprofile\tsecond\tfirst\nprofile\tfinal\t-'
  actual=$(opencode_catalog_rows)
  assert_equal "$expected" "$actual" \
    'OpenCode catalog rows preserve comments, order, and final rows'

  expected=$'second\nfinal'
  actual=$(opencode_catalog_names profile)
  assert_equal "$expected" "$actual" \
    'OpenCode catalog names preserve final profile rows'
}

# By the second install the profile path is a link into this checkout, and the
# installer calls ocx profile remove against it on every rerun. Real ocx unlinks
# rather than descending, which is the only reason that is safe. An unfaithful
# fake would delete the versioned payload out of the repository, so every
# scenario that runs the installer proves this against a fixture link first.
assert_fake_ocx_unlinks_profiles() {
  local fake_bin=$1
  local probe profiles source

  probe=$(scenario_tmpdir probe)
  profiles=$probe/.config/opencode/profiles
  source=$probe/versioned/regular

  mkdir -p "$profiles" "$source"
  printf 'versioned payload\n' >"$source/opencode.jsonc"
  ln -s "$source" "$profiles/regular"

  scenario_capture "$probe" env HOME="$probe" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" profile remove regular --global

  [[ ! -e $profiles/regular && ! -L $profiles/regular ]] \
    || scenario_fail 'fake ocx left the managed profile link in place'
  [[ -f $source/opencode.jsonc ]] \
    || scenario_fail 'fake ocx deleted versioned content through the profile link'
}

test_profile_removal_unlinks_instead_of_descending() {
  assert_fake_ocx_unlinks_profiles "$(make_fake_clis "$(scenario_tmpdir removal)")"
}

test_profile_removal_reports_absent_profiles() {
  local home fake_bin

  home=$(scenario_tmpdir absent-profile)
  fake_bin=$(make_fake_clis "$home")
  assert_fails_with_status 66 scenario_capture "$home" \
    env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" profile remove example --global
  assert_contains "$home/stderr.log" 'Profile example not found'
}

test_installer_rejects_an_unusable_catalog() {
  local fake_bin home
  local -a run

  home=$(scenario_tmpdir catalog)
  fake_bin=$(make_fake_clis "$home")
  run=(env HOME="$home" PATH="$fake_bin:/usr/bin:/bin")

  assert_fails_with_output 'missing catalog' 'entry catalog not found' \
    "${run[@]}" DOTFILES_OPENCODE_CATALOG="$home/absent.tsv" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  printf 'widget\tagents\t-\n' >"$home/unknown-kind.tsv"
  assert_fails_with_output 'unknown catalog kind' \
    'unknown OpenCode catalog kind' \
    "${run[@]}" DOTFILES_OPENCODE_CATALOG="$home/unknown-kind.tsv" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  printf 'entry\tagents\n' >"$home/incomplete.tsv"
  assert_fails_with_output 'incomplete catalog row' \
    'invalid OpenCode catalog row' \
    "${run[@]}" DOTFILES_OPENCODE_CATALOG="$home/incomplete.tsv" \
    "$REPOSITORY_ROOT/opencode/install.sh"
}

test_installer_links_only_dotfiles_owned_entries() {
  local config_dir current_add fake_bin home kind clone name previous_add
  local runtime_path

  home=$(scenario_tmpdir install)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  mkdir -p "$config_dir"

  # The reinstall below points the fake at profile links into this checkout.
  assert_fake_ocx_unlinks_profiles "$fake_bin"

  # Seed a real target for every managed entry. The default
  # replace-with-backup policy would park each one in a sibling .backup, so
  # the absence of those below is what proves the installer selects
  # replace-generated for the whole catalog and not one arbitrary member.
  while IFS= read -r name; do
    if opencode_entry_is_directory "$name"; then
      mkdir -p "$config_dir/$name"
      printf 'stale generated entry\n' >"$config_dir/$name/stale.marker"
    else
      printf 'stale generated entry\n' >"$config_dir/$name"
    fi
  done < <(opencode_catalog_names entry)

  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  [[ -z $(find "$config_dir" -maxdepth 2 -name '*.backup' -print -quit) ]] \
    || scenario_fail 'installer backed up a generated OpenCode entry or profile'

  while IFS= read -r name; do
    opencode_entry_is_directory "$name" || continue
    [[ ! -e $config_dir/$name/stale.marker ]] \
      || scenario_fail "installer kept stale generated content: $name"
  done < <(opencode_catalog_names entry)

  while IFS= read -r name; do
    [[ ! -e $config_dir/profiles/$name/generated ]] \
      || scenario_fail "installer kept the generated $name profile directory"
  done < <(opencode_catalog_names profile)

  assert_catalog_links "$config_dir" 'first install'

  # OCX creates every profile, and the installer applies catalog rows in file
  # order, which is what keeps a clone source materialized before its clones.
  previous_add=
  while IFS=$'\t' read -r kind name clone; do
    [[ $kind == profile ]] || continue
    current_add=$(opencode_profile_add_line "$name" "$clone")
    assert_contains "$home/events.log" "$current_add"
    if [[ -n $previous_add ]]; then
      assert_before "$home/events.log" "$previous_add" "$current_add"
    fi
    previous_add=$current_add
  done < <(opencode_catalog_rows)

  for runtime_path in plugins .ocx package.json .gitignore profiles/default; do
    [[ -e $config_dir/$runtime_path ]] \
      || scenario_fail "OCX runtime entry was removed: $runtime_path"
    [[ ! -L $config_dir/$runtime_path ]] \
      || scenario_fail "OCX runtime entry was linked: $runtime_path"
  done

  assert_contains "$config_dir/plugins/worktree.ts" 'runtime plugin worktree'
  assert_contains "$config_dir/plugins/notify.ts" 'runtime plugin notify'
  [[ ! -e $config_dir/plugins/workspace-plugin.ts &&
    ! -e $config_dir/plugins/background-agents.ts ]] \
    || scenario_fail 'installer left competing orchestration plugins installed'
  assert_not_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace@'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/worktree@'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/notify@'
  assert_not_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace-plugin@'
  assert_not_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/background-agents@'
  assert_contains "$home/events.log" 'ocx add kdco/worktree kdco/notify --global'
  assert_not_contains "$home/events.log" 'ocx add kdco/workspace'
  assert_not_contains "$home/events.log" 'ocx remove kdco/'
  assert_before "$home/events.log" \
    "bun install --frozen-lockfile --ignore-scripts --cwd $REPOSITORY_ROOT/opencode/orchestrator" \
    'ocx init --global'
  assert_not_contains "$home/events.log" 'ocx profile remove'
  assert_not_contains "$home/events.log" '--force'

  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_catalog_links "$config_dir" 'reinstall'
  assert_contains "$home/events.log" 'ocx profile remove regular --global'
  assert_contains "$home/events.log" 'ocx profile remove example --global'

  assert_contains "$config_dir/plugins/worktree.ts" 'runtime plugin worktree'
  assert_contains "$config_dir/plugins/notify.ts" 'runtime plugin notify'
  assert_not_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace@'
  assert_not_contains "$home/events.log" 'ocx add kdco/workspace'
  assert_not_contains "$home/events.log" 'ocx remove kdco/'
}

test_installer_adds_a_missing_profile_on_existing_installation() {
  local home fake_bin config_dir

  home=$(scenario_tmpdir add-profile)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"
  unlink "$config_dir/profiles/example"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/events.log" 'ocx profile remove regular --global'
  assert_not_contains "$home/events.log" 'ocx profile remove example'
  assert_contains "$home/events.log" 'ocx profile add example --clone regular --global'
  assert_catalog_links "$config_dir" 'new profile on existing installation'
}

test_installer_preserves_activation_when_dependencies_fail() {
  local fake_bin home config_dir

  home=$(scenario_tmpdir dependency-failure)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  mkdir -p "$config_dir/plugins"
  printf 'existing activation\n' >"$config_dir/opencode.jsonc"
  printf 'existing plugin\n' >"$config_dir/plugins/workspace-plugin.ts"

  assert_fails_with_output 'failed dependency install' \
    'fixture dependency installation failed' \
    env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" STUB_BUN_FAIL=true \
    SCENARIO_EVENT_LOG="$home/events.log" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$config_dir/opencode.jsonc" 'existing activation'
  assert_contains "$config_dir/plugins/workspace-plugin.ts" 'existing plugin'
  assert_not_contains "$home/events.log" 'ocx '
  [[ ! -e $config_dir/orchestrator ]] \
    || scenario_fail 'installer activated orchestrator after dependency failure'
}

test_installer_preserves_modified_original_plugins() {
  local fake_bin home config_dir

  home=$(scenario_tmpdir modified-plugin)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  printf 'existing activation\n' >"$config_dir/opencode.jsonc"
  printf 'modified original\n' >"$config_dir/plugins/workspace-plugin.ts"

  assert_fails_with_output 'modified original plugin' \
    'modified original plugin; removal refused' \
    env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" STUB_OCX_REMOVE_FAIL=true \
    SCENARIO_EVENT_LOG="$home/events.log" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$config_dir/opencode.jsonc" 'existing activation'
  assert_contains "$config_dir/plugins/workspace-plugin.ts" 'modified original'
  assert_contains "$config_dir/plugins/background-agents.ts" 'runtime plugin'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace-plugin@'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/background-agents@'
  assert_not_contains "$home/events.log" 'ocx profile remove'
  assert_not_contains "$home/events.log" '--force'
  [[ ! -e $config_dir/orchestrator ]] \
    || scenario_fail 'installer activated orchestrator after migration refusal'
}

test_installer_removes_only_receipted_original_plugins() {
  local fake_bin home config_dir

  home=$(scenario_tmpdir single-component)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" remove kdco/workspace-plugin --cwd "$config_dir"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/events.log" \
    "ocx remove kdco/background-agents --cwd $config_dir"
  assert_not_contains "$home/events.log" 'ocx remove kdco/workspace-plugin'
  assert_catalog_links "$config_dir" 'partial migration'
}

test_installer_refuses_untracked_competing_plugins() {
  local fake_bin home config_dir

  home=$(scenario_tmpdir untracked-plugin)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" remove kdco/workspace-plugin --cwd "$config_dir"
  printf 'untracked plugin\n' >"$config_dir/plugins/workspace-plugin.ts"
  printf 'existing activation\n' >"$config_dir/opencode.jsonc"

  assert_fails_with_output 'untracked competing plugin' \
    'Untracked OpenCode plugin conflicts with orchestrator' \
    env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    SCENARIO_EVENT_LOG="$home/events.log" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$config_dir/plugins/workspace-plugin.ts" 'untracked plugin'
  assert_contains "$config_dir/plugins/background-agents.ts" 'runtime plugin'
  assert_contains "$config_dir/opencode.jsonc" 'existing activation'
  assert_not_contains "$home/events.log" 'ocx remove kdco/background-agents'
  [[ ! -e $config_dir/orchestrator ]] \
    || scenario_fail 'installer activated orchestrator alongside an untracked plugin'
}

test_installer_removes_only_retired_managed_profile_links() {
  local fake_bin home profiles

  home=$(scenario_tmpdir retired-profiles)
  fake_bin=$(make_fake_clis "$home")
  profiles=$home/.config/opencode/profiles
  mkdir -p "$profiles/default" "$profiles/custom"
  printf 'OCX default state\n' >"$profiles/default/keep.marker"
  printf 'custom profile state\n' >"$profiles/custom/keep.marker"
  ln -s "$REPOSITORY_ROOT/opencode/profiles/go" "$profiles/go"
  ln -s "$REPOSITORY_ROOT/opencode/profiles/boost" "$profiles/boost"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  [[ ! -e $profiles/go && ! -L $profiles/go &&
    ! -e $profiles/boost && ! -L $profiles/boost ]] \
    || scenario_fail 'installer kept retired dotfiles profile links'
  assert_contains "$profiles/default/keep.marker" 'OCX default state'
  assert_contains "$profiles/custom/keep.marker" 'custom profile state'
  assert_catalog_links "$home/.config/opencode" 'retired profile migration'
  assert_not_contains "$home/events.log" 'ocx profile remove go'
  assert_not_contains "$home/events.log" 'ocx profile remove boost'
  assert_not_contains "$home/events.log" 'ocx profile remove default'

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_not_contains "$home/stdout.log" 'removed retired OpenCode'
  assert_contains "$profiles/default/keep.marker" 'OCX default state'
  assert_contains "$profiles/custom/keep.marker" 'custom profile state'
  assert_catalog_links "$home/.config/opencode" 'retired profile migration rerun'
}

test_installer_preserves_local_profiles_with_retired_names() {
  local fake_bin home profiles custom_source

  home=$(scenario_tmpdir local-retired-profiles)
  fake_bin=$(make_fake_clis "$home")
  profiles=$home/.config/opencode/profiles
  custom_source=$home/custom-boost
  mkdir -p "$profiles/go" "$profiles/default" "$custom_source"
  printf 'local go state\n' >"$profiles/go/keep.marker"
  printf 'custom boost state\n' >"$custom_source/keep.marker"
  printf 'OCX default state\n' >"$profiles/default/keep.marker"
  ln -s "$custom_source" "$profiles/boost"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  [[ -d $profiles/go && ! -L $profiles/go ]] \
    || scenario_fail 'installer replaced a local profile named go'
  assert_contains "$profiles/go/keep.marker" 'local go state'
  assert_link_target "$custom_source" "$profiles/boost" 'custom boost profile'
  assert_contains "$custom_source/keep.marker" 'custom boost state'
  assert_contains "$profiles/default/keep.marker" 'OCX default state'
  assert_not_contains "$home/events.log" 'ocx profile remove go'
  assert_not_contains "$home/events.log" 'ocx profile remove boost'
  assert_not_contains "$home/events.log" 'ocx profile remove default'
}

assert_minimal_ocx_runtime() {
  local config_dir=$1
  local actual

  actual=$(jq -r '[.installed[].name] | sort | join(" ")' "$config_dir/.ocx/receipt.jsonc")
  assert_equal 'kdco-primitives notify worktree' "$actual" 'remaining OCX components'
  assert_contains "$config_dir/plugins/worktree.ts" 'runtime plugin worktree'
  assert_contains "$config_dir/plugins/notify.ts" 'runtime plugin notify'
  assert_contains "$config_dir/plugins/kdco-primitives/index.ts" 'runtime plugin kdco-primitives'
}

test_installer_removes_missing_legacy_payload_receipts() {
  local home fake_bin config_dir directory

  home=$(scenario_tmpdir missing-legacy)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  for directory in agents commands skills tools; do
    rm -r -- "${config_dir:?}/$directory"
    ln -s "$REPOSITORY_ROOT/opencode/$directory" "$config_dir/$directory"
  done
  # Real receipts are JSONC: keep comments and a trailing comma in this case.
  sed '1s/{/{\/\/ fixture comment/' "$config_dir/.ocx/receipt.jsonc" \
    | sed '$s/}/,}/' >"$home/receipt.jsonc"
  mv "$home/receipt.jsonc" "$config_dir/.ocx/receipt.jsonc"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_minimal_ocx_runtime "$config_dir"
  assert_contains "$home/events.log" '--force'
  assert_not_contains "$home/events.log" 'ocx add kdco/workspace'
  for directory in agents commands skills tools; do
    [[ ! -e $config_dir/$directory && ! -L $config_dir/$directory ]] \
      || scenario_fail "installer kept retired managed link: $directory"
  done
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"
  assert_minimal_ocx_runtime "$config_dir"
  assert_not_contains "$home/events.log" 'ocx remove'
  assert_not_contains "$home/events.log" 'ocx add kdco/'
}

test_installer_removes_intact_legacy_payloads_and_preserves_custom_files() {
  local home fake_bin config_dir directory

  home=$(scenario_tmpdir intact-legacy)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  for directory in agents commands skills tools; do
    printf 'custom content\n' >"$config_dir/$directory/keep.md"
  done

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_minimal_ocx_runtime "$config_dir"
  assert_not_contains "$home/events.log" '--force'
  for directory in agents commands skills tools; do
    assert_contains "$config_dir/$directory/keep.md" 'custom content'
    [[ ! -L $config_dir/$directory ]] \
      || scenario_fail "installer replaced custom directory: $directory"
  done
  [[ ! -e $config_dir/agents/coder.md && ! -e $config_dir/commands/review.md ]] \
    || scenario_fail 'installer kept retired registry payloads'
}

test_installer_materializes_only_exact_legacy_links() {
  local home fake_bin config_dir checkout directory

  home=$(scenario_tmpdir linked-legacy)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  checkout=$home/checkout
  copy_opencode_fixture "$checkout/opencode"
  cp -R "$REPOSITORY_ROOT/_scripts" "$checkout/_scripts"
  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$fake_bin/ocx" add kdco/workspace --global
  for directory in agents commands skills tools; do
    mv "$config_dir/$directory" "$checkout/opencode/$directory"
    printf 'custom linked content\n' >"$checkout/opencode/$directory/keep.md"
    ln -s "$checkout/opencode/$directory" "$config_dir/$directory"
  done

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$checkout/opencode/install.sh"

  assert_minimal_ocx_runtime "$config_dir"
  assert_not_contains "$home/events.log" '--force'
  assert_contains "$checkout/opencode/agents/coder.md" 'registry payload coder'
  for directory in agents commands skills tools; do
    assert_contains "$config_dir/$directory/keep.md" 'custom linked content'
    [[ ! -L $config_dir/$directory ]] \
      || scenario_fail "installer kept an external managed link: $directory"
  done
}

test_installer_preserves_custom_legacy_directories_and_links() {
  local home fake_bin config_dir

  home=$(scenario_tmpdir custom-legacy)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode
  mkdir -p "$config_dir/agents" "$home/custom-skills"
  printf 'custom agent\n' >"$config_dir/agents/coder.md"
  printf 'custom skill\n' >"$home/custom-skills/keep.md"
  ln -s "$home/custom-skills" "$config_dir/skills"
  printf 'custom file\n' >"$config_dir/tools"

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$config_dir/agents/coder.md" 'custom agent'
  assert_contains "$config_dir/tools" 'custom file'
  assert_link_target "$home/custom-skills" "$config_dir/skills" 'custom skills'
  assert_contains "$home/custom-skills/keep.md" 'custom skill'
  assert_not_contains "$home/events.log" 'ocx remove'
}

test_installer_refuses_modified_or_partially_missing_legacy_components() {
  local home fake_bin config_dir mode

  for mode in modified partially-missing external-link; do
    home=$(scenario_tmpdir "legacy-$mode")
    fake_bin=$(make_fake_clis "$home")
    config_dir=$home/.config/opencode
    scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
      "$fake_bin/ocx" add kdco/workspace --global
    printf 'existing activation\n' >"$config_dir/opencode.jsonc"
    case "$mode" in
      modified)
        printf 'customized coder\n' >"$config_dir/agents/coder.md"
        ;;
      partially-missing)
        jq '(.installed[] | select(.name == "coder")).files += [{"path":"agents/extra.md","hash":"absent"}]' \
          "$config_dir/.ocx/receipt.jsonc" >"$home/receipt.jsonc"
        mv "$home/receipt.jsonc" "$config_dir/.ocx/receipt.jsonc"
        ;;
      external-link)
        mv "$config_dir/agents" "$home/custom-agents"
        ln -s "$home/custom-agents" "$config_dir/agents"
        ;;
    esac

    assert_fails_with_status 1 scenario_capture "$home" \
      env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
      "$REPOSITORY_ROOT/opencode/install.sh"

    assert_contains "$config_dir/opencode.jsonc" 'existing activation'
    assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/coder@'
    assert_not_contains "$home/events.log" '--force'
    assert_not_contains "$home/events.log" 'ocx profile remove'
    if [[ $mode == modified ]]; then
      assert_contains "$config_dir/agents/coder.md" 'customized coder'
    else
      assert_contains "$config_dir/agents/coder.md" 'registry payload coder'
    fi
  done
}

scenario_run 'OpenCode shell defaults to the regular OCX profile' \
  test_shell_uses_regular_ocx_profile_and_shortcuts
scenario_run 'OpenCode versions only the intended editable payload' \
  test_managed_payload_is_complete_and_runtime_payload_is_excluded
scenario_run 'OpenCode TUI matches terminal theme and interaction defaults' \
  test_tui_matches_terminal_theme_and_interaction_defaults
scenario_run 'OpenCode profiles trust project configuration' \
  test_profiles_trust_project_configuration
scenario_run 'OpenCode profiles are composed from the shared base' \
  test_profile_payloads_are_composed_from_the_shared_base
scenario_run 'OpenCode profile overrides isolate policy and preserve model authority' \
  test_profile_overrides_are_isolated_and_cannot_override_routes
scenario_run 'OpenCode profiles route models through published variants' \
  test_profiles_route_models
scenario_run 'OpenCode catalog declares each clone source before its clones' \
  test_catalog_declares_each_clone_source_before_its_clones
scenario_run 'OpenCode catalog support preserves the shared row contract' \
  test_opencode_catalog_reader_preserves_catalog_row_contract
scenario_run 'OpenCode profile removal unlinks instead of descending' \
  test_profile_removal_unlinks_instead_of_descending
scenario_run 'OpenCode profile removal reports absent profiles with exit 66' \
  test_profile_removal_reports_absent_profiles
scenario_run 'OpenCode installer rejects an unusable catalog' \
  test_installer_rejects_an_unusable_catalog
scenario_run 'OpenCode installer links managed entries and preserves OCX runtime state' \
  test_installer_links_only_dotfiles_owned_entries
scenario_run 'OpenCode installer adds a missing profile on an existing installation' \
  test_installer_adds_a_missing_profile_on_existing_installation
scenario_run 'OpenCode installer preserves activation when dependency installation fails' \
  test_installer_preserves_activation_when_dependencies_fail
scenario_run 'OpenCode installer preserves modified original plugins on migration refusal' \
  test_installer_preserves_modified_original_plugins
scenario_run 'OpenCode installer removes only receipted original plugins' \
  test_installer_removes_only_receipted_original_plugins
scenario_run 'OpenCode installer refuses untracked competing plugins' \
  test_installer_refuses_untracked_competing_plugins
scenario_run 'OpenCode installer retires only its exact go and boost profile links' \
  test_installer_removes_only_retired_managed_profile_links
scenario_run 'OpenCode installer preserves local profiles with retired names' \
  test_installer_preserves_local_profiles_with_retired_names
scenario_run 'OpenCode installer retires missing payload receipts and dangling links idempotently' \
  test_installer_removes_missing_legacy_payload_receipts
scenario_run 'OpenCode installer removes intact legacy payloads and preserves custom files' \
  test_installer_removes_intact_legacy_payloads_and_preserves_custom_files
scenario_run 'OpenCode installer materializes only exact managed legacy links' \
  test_installer_materializes_only_exact_legacy_links
scenario_run 'OpenCode installer preserves custom legacy directories, files and links' \
  test_installer_preserves_custom_legacy_directories_and_links
scenario_run 'OpenCode installer refuses modified, partial or external legacy components' \
  test_installer_refuses_modified_or_partially_missing_legacy_components

scenario_run 'OpenCode GUI adapter loads project configuration and preserves profile routing' \
  test_gui_adapter_preserves_project_loading_and_pins_selected_profile_routes

scenario_finish
