# Shared branch-state queries for Git command and prompt adapters.
#
# Every function accepts the Git executable as its first argument. Function
# bodies run in subshells so sourcing this file does not leak temporary state
# into either POSIX shell commands or the interactive Zsh session.

_dotfiles_git_state_require_worktree() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_inside=$(
    "$_dotfiles_git_state_git" rev-parse --is-inside-work-tree 2>/dev/null
  ) || _dotfiles_git_state_inside=

  if [ "$_dotfiles_git_state_inside" != true ]; then
    echo "Error: Not in a git repository." >&2
    exit 1
  fi
)

_dotfiles_git_state_current_branch() (
  _dotfiles_git_state_git=$1

  _dotfiles_git_state_require_worktree "$_dotfiles_git_state_git" || exit 1

  if ! _dotfiles_git_state_branch=$(
    "$_dotfiles_git_state_git" symbolic-ref --quiet --short HEAD 2>/dev/null
  ); then
    echo "Error: Not on a branch (detached HEAD state)." >&2
    exit 1
  fi

  printf '%s\n' "$_dotfiles_git_state_branch"
)

# Print the current branch name, or nothing when HEAD is detached.
_dotfiles_git_state_current_branch_or_empty() (
  _dotfiles_git_state_git=$1

  _dotfiles_git_state_require_worktree "$_dotfiles_git_state_git" || exit 1

  _dotfiles_git_state_branch=$(
    "$_dotfiles_git_state_git" symbolic-ref --quiet --short HEAD 2>/dev/null
  ) || _dotfiles_git_state_branch=

  printf '%s\n' "$_dotfiles_git_state_branch"
)

_dotfiles_git_state_local_branch_exists() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2

  "$_dotfiles_git_state_git" show-ref --verify --quiet \
    "refs/heads/$_dotfiles_git_state_branch"
)

_dotfiles_git_state_origin_tracking_branch_exists() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2

  "$_dotfiles_git_state_git" show-ref --verify --quiet \
    "refs/remotes/origin/$_dotfiles_git_state_branch"
)

_dotfiles_git_state_require_origin_tracking_branch() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2

  if ! _dotfiles_git_state_origin_tracking_branch_exists \
    "$_dotfiles_git_state_git" "$_dotfiles_git_state_branch"; then
    echo "Error: Remote-tracking branch 'origin/$_dotfiles_git_state_branch' is not available locally. Run 'git fetch origin'." >&2
    exit 1
  fi
)

# Return 0 when the exact branch exists on origin, 1 when it is absent, and 2
# when origin cannot be queried. Git itself uses status 2 for an unmatched
# ls-remote pattern, so transport failures are normalized separately.
_dotfiles_git_state_live_origin_branch_exists() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2

  "$_dotfiles_git_state_git" ls-remote --exit-code --heads origin \
    "refs/heads/$_dotfiles_git_state_branch" >/dev/null
  _dotfiles_git_state_status=$?

  case $_dotfiles_git_state_status in
    0)
      exit 0
      ;;
    2)
      exit 1
      ;;
    *)
      echo "Error: Unable to query origin for branch '$_dotfiles_git_state_branch'." >&2
      exit 2
      ;;
  esac
)

_dotfiles_git_state_tracks_matching_origin() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2
  _dotfiles_git_state_remote=$(
    "$_dotfiles_git_state_git" config --get \
      "branch.$_dotfiles_git_state_branch.remote" 2>/dev/null
  ) || _dotfiles_git_state_remote=
  _dotfiles_git_state_merge=$(
    "$_dotfiles_git_state_git" config --get \
      "branch.$_dotfiles_git_state_branch.merge" 2>/dev/null
  ) || _dotfiles_git_state_merge=

  [ "$_dotfiles_git_state_remote" = origin ] && \
    [ "$_dotfiles_git_state_merge" = "refs/heads/$_dotfiles_git_state_branch" ]
)

_dotfiles_git_state_ahead_count() (
  _dotfiles_git_state_git=$1
  _dotfiles_git_state_branch=$2

  "$_dotfiles_git_state_git" rev-list --count \
    "refs/remotes/origin/$_dotfiles_git_state_branch..refs/heads/$_dotfiles_git_state_branch"
)
