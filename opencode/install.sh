#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up OpenCode configuration"

CONFIG_DIR=$(installer_config_dir opencode)
CATALOG="${DOTFILES_OPENCODE_CATALOG:-$TOPIC_DIR/_managed-entries.tsv}"

if [ ! -f "$CATALOG" ]; then
  installer_fail "OpenCode entry catalog not found: $CATALOG"
fi

installer_require_command opencode
installer_require_command ocx
installer_require_command bun

validate_catalog_row() {
  catalog_kind=$1
  catalog_name=$2
  catalog_clone=$3

  if [ -z "$catalog_name" ] || [ -z "$catalog_clone" ]; then
    installer_fail "invalid OpenCode catalog row: $catalog_kind $catalog_name"
  fi

  case "$catalog_kind" in
    entry)
      [ -e "$TOPIC_DIR/$catalog_name" ] \
        || installer_fail "OpenCode config source not found: $TOPIC_DIR/$catalog_name"
      ;;
    profile)
      [ -d "$TOPIC_DIR/profiles/$catalog_name" ] \
        || installer_fail "OpenCode profile source not found: $TOPIC_DIR/profiles/$catalog_name"
      ;;
    *)
      installer_fail "unknown OpenCode catalog kind: $catalog_kind"
      ;;
  esac
  return 0
}

# A missing source or failed dependency install must leave the active plugin
# configuration in place. Resolve these prerequisites before the OCX migration.
catalog_each_row "$CATALOG" validate_catalog_row
bun install --frozen-lockfile --ignore-scripts --cwd "$TOPIC_DIR/orchestrator"

mkdir -p "$CONFIG_DIR"

ocx init --global
ocx registry add https://registry.kdco.dev --name kdco --global

OCX_RECEIPT="$CONFIG_DIR/.ocx/receipt.jsonc"
install_runtime_plugins() {
  set --
  for runtime_component in worktree notify; do
    if [ ! -f "$OCX_RECEIPT" ] \
      || ! grep -Fq "::kdco/$runtime_component@" "$OCX_RECEIPT"; then
      set -- "$@" "kdco/$runtime_component"
    fi
  done
  [ "$#" -gt 0 ] || return 0
  ocx add "$@" --global
}

remove_replaced_workspace_plugins() {
  set --
  for workspace_component in workspace-plugin background-agents; do
    if [ -f "$OCX_RECEIPT" ] \
      && grep -Fq "::kdco/$workspace_component@" "$OCX_RECEIPT"; then
      set -- "$@" "kdco/$workspace_component"
    elif [ -e "$CONFIG_DIR/plugins/$workspace_component.ts" ] \
      || [ -L "$CONFIG_DIR/plugins/$workspace_component.ts" ]; then
      installer_fail "Untracked OpenCode plugin conflicts with orchestrator: $CONFIG_DIR/plugins/$workspace_component.ts"
    fi
  done

  [ "$#" -gt 0 ] || return 0
  # OCX checks integrity for both components before removing either. Never
  # force through a modified file; worktree, notify and their receipts remain.
  ocx remove "$@" --cwd "$CONFIG_DIR"
}

remove_replaced_workspace_plugins

retired_components=
collect_retired_component() {
  retired_components="$retired_components $1"
}
catalog_each_row "$TOPIC_DIR/_retired-components.tsv" collect_retired_component

# OCX refuses external symlinks and missing files. Materialize only our exact
# old links; force is reserved for receipt metadata with every file absent.
bun - "$CONFIG_DIR" "$TOPIC_DIR" "$retired_components" <<'JS'
import * as fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [configDir, topicDir, retiredNames] = process.argv.slice(2);
const legacyDirectories = ["agents", "commands", "skills", "tools"];
const inspect = (target) => {
  try { return fs.lstatSync(target); }
  catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return undefined;
    throw error;
  }
};
const receiptPath = path.join(configDir, ".ocx/receipt.jsonc");
const receipt = inspect(receiptPath) ? (await import(pathToFileURL(receiptPath).href)).default : { installed: {} };
if (!receipt?.installed || typeof receipt.installed !== "object") {
  throw new Error("Cannot read the OCX receipt for legacy migration");
}
const retired = new Set(retiredNames.trim().split(/\s+/));
const components = Object.entries(receipt.installed).filter(([key, entry]) =>
  retired.has(entry.name) && entry.registryName === "kdco" && key.includes(`::kdco/${entry.name}@`)
);
for (const [, component] of components) {
  if (!Array.isArray(component.files)) throw new Error("Invalid OCX component file list");
  for (const file of component.files) {
    if (typeof file.path !== "string" || path.isAbsolute(file.path) || file.path.split("/").includes("..") || !legacyDirectories.includes(file.path.split("/")[0])) {
      throw new Error("Unexpected file path in retired OCX component");
    }
  }
}
for (const directory of legacyDirectories) {
  const target = path.join(configDir, directory);
  const source = path.join(topicDir, directory);
  if (!inspect(target)?.isSymbolicLink() || fs.readlinkSync(target) !== source) continue;
  if (inspect(source)) {
    const staging = fs.mkdtempSync(path.join(configDir, ".ocx-retired-"));
    fs.cpSync(source, path.join(staging, directory), { recursive: true });
    fs.unlinkSync(target);
    fs.renameSync(path.join(staging, directory), target);
    fs.rmdirSync(staging);
  } else {
    fs.unlinkSync(target);
  }
}
const allAbsent = (component) => component.files.length > 0 && component.files.every((file) => !inspect(path.join(configDir, file.path)));
const normal = components.filter(([, component]) => !allAbsent(component));
const absent = components.filter(([, component]) => allAbsent(component));
const remove = (selected, force = false) => {
  if (!selected.length) return;
  if (force && selected.some(([, component]) => !allAbsent(component))) {
    throw new Error("A retired OCX file reappeared before metadata removal");
  }
  const args = ["remove", ...selected.map(([key]) => key), "--cwd", configDir, ...(force ? ["--force"] : [])];
  const result = spawnSync("ocx", args, { stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
};
remove(normal);
remove(absent, true);
JS

install_runtime_plugins

# Every managed target is regenerated by its tool, so the catalog's conflict
# policy is stated once here rather than repeated at each call site.
link_managed_target() {
  installer_link_config \
    --policy replace-generated \
    --label "$1" \
    "$2" "$3"
}

configure_managed_entry() {
  entry_name=$1
  entry_source="$TOPIC_DIR/$entry_name"
  entry_target="$CONFIG_DIR/$entry_name"

  if [ ! -e "$entry_source" ]; then
    installer_fail "OpenCode config source not found: $entry_source"
  fi

  # The local orchestrator and configuration are versioned here; OCX owns the
  # remaining plugin files, receipt and package dependencies.
  link_managed_target "OpenCode $entry_name" "$entry_source" "$entry_target"
}

configure_profile() {
  profile_name=$1
  clone_source=${2:-}
  profile_source="$TOPIC_DIR/profiles/$profile_name"
  profile_target="$CONFIG_DIR/profiles/$profile_name"

  if [ ! -d "$profile_source" ]; then
    installer_fail "OpenCode profile source not found: $profile_source"
  fi

  if [ -e "$profile_target" ] || [ -L "$profile_target" ]; then
    ocx profile remove "$profile_name" --global
  fi
  if [ -n "$clone_source" ]; then
    ocx profile add "$profile_name" --clone "$clone_source" --global
  else
    ocx profile add "$profile_name" --global
  fi

  # OCX creates a profile directory. Replace that generated directory with the
  # repository-owned profile so edits remain versioned in dotfiles.
  link_managed_target "OpenCode $profile_name profile" \
    "$profile_source" "$profile_target"
}

# One catalog row, applied in file order so a clone source is always
# materialized before the profiles that clone it.
configure_catalog_row() {
  catalog_kind=$1
  catalog_name=$2
  catalog_clone=$3

  case "$catalog_kind" in
    entry)
      configure_managed_entry "$catalog_name"
      ;;
    profile)
      if [ "$catalog_clone" = - ]; then
        configure_profile "$catalog_name"
      else
        configure_profile "$catalog_name" "$catalog_clone"
      fi
      ;;
    *)
      installer_fail "unknown OpenCode catalog kind: $catalog_kind"
      ;;
  esac
  return 0
}

catalog_each_row "$CATALOG" configure_catalog_row

# Retire only links created by the former catalog. A same-named local profile
# or a link to any other source belongs to the user and remains untouched.
remove_retired_managed_profiles() {
  for retired_profile in go boost; do
    retired_target=$CONFIG_DIR/profiles/$retired_profile
    if [ -L "$retired_target" ] \
      && [ "$(readlink "$retired_target")" = "$TOPIC_DIR/profiles/$retired_profile" ]; then
      unlink "$retired_target"
      installer_item "removed retired OpenCode $retired_profile profile link"
    elif [ -e "$retired_target" ] || [ -L "$retired_target" ]; then
      installer_note "preserving local OpenCode $retired_profile profile"
    fi
  done
}

remove_retired_managed_profiles

installer_success "OpenCode configured"
