# shellcheck shell=bash
#
# Find a project directory by a few typed characters, for the Raycast script
# commands that open one. A script command takes typed arguments only and
# cannot offer a list to pick from, so the best match is chosen here.
#
# Projects are the <owner>/<repository> directories under $PROJECTS, the same
# root `c` jumps into.

# Print the projects root. Raycast starts a script without the shell's
# environment, so $PROJECTS is asked of a shell started the way a person's is,
# which also honours an override in ~/.localrc.
project_root() {
  local root=${PROJECTS:-}

  if [ -z "$root" ]; then
    # shellcheck disable=SC2016 # Expanded by the Zsh this starts.
    root=$(/bin/zsh -lic 'print -r -- "$PROJECTS"' 2>/dev/null </dev/null | tail -n 1) || root=
  fi
  [ -n "$root" ] || root=${WORKSPACE:-$HOME/Workspace}/github.com
  printf '%s\n' "$root"
}

# Print the absolute path of the project that best matches the query, or
# return 1 when none does. A repository named exactly as typed wins, then one
# whose name starts with it, then one whose name contains it, then one whose
# owner/name contains it; among equals the shortest name wins. Case is ignored.
# Usage: project_find <query>
project_find() {
  local root best

  root=$(project_root)
  [ -d "$root" ] || return 1
  best=$(
    cd "$root" || exit 1
    for candidate in */*/; do
      [ -d "$candidate" ] && printf '%s\n' "${candidate%/}"
    done | awk -v query="$1" '
      BEGIN { query = tolower(query) }
      {
        path = tolower($0)
        name = path
        sub(/^.*\//, "", name)
        if (name == query) rank = 1
        else if (index(name, query) == 1) rank = 2
        else if (index(name, query) > 0) rank = 3
        else if (index(path, query) > 0) rank = 4
        else next
        printf "%d\t%04d\t%s\n", rank, length(name), $0
      }' | sort | head -n 1 | cut -f 3
  )
  [ -n "$best" ] || return 1
  printf '%s/%s\n' "$root" "$best"
}
