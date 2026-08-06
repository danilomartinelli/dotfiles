# cheers, @ehrenmurdick
# http://github.com/ehrenmurdick/config/blob/master/zsh/prompt.zsh

if (( $+commands[git] ))
then
  git="$commands[git]"
else
  git="/usr/bin/git"
fi

. "$DOTFILES_ROOT/git/_branch-state.sh"

# Shared tail of the git segment: a trailing space when there is nothing to
# push, or the unpushed count. Silent without an origin tracking branch.
_dotfiles_prompt_push_segment() {
  local branch=$1 number

  [[ -n $branch ]] || return 0
  if ! _dotfiles_git_state_origin_tracking_branch_exists "$git" "$branch"; then
    return 0
  fi
  number=$(_dotfiles_git_state_ahead_count "$git" "$branch" 2>/dev/null) || return 0

  if [[ $number == 0 ]]
  then
    echo " "
  else
    echo " with %{$fg_bold[magenta]%}$number unpushed%{$reset_color%}"
  fi
}

# Full git segment for the prompt. The branch is resolved once per render.
prompt_git_segment() {
  local branch
  branch=$(_dotfiles_git_state_current_branch "$git" 2>/dev/null) || return 0

  if [[ $($git status --porcelain 2>/dev/null) == "" ]]
  then
    echo -n "on %{$fg_bold[green]%}$branch%{$reset_color%}"
  else
    echo -n "on %{$fg_bold[red]%}$branch%{$reset_color%}"
  fi

  _dotfiles_prompt_push_segment "$branch"
}

# Standalone push indicator, exercised directly by the branch-state tests.
need_push() {
  local branch
  branch=$(_dotfiles_git_state_current_branch "$git" 2>/dev/null) || return 0
  _dotfiles_prompt_push_segment "$branch"
}

directory_name() {
  echo "%{$fg_bold[cyan]%}%1/%\/%{$reset_color%}"
}

battery_status() {
  if [[ -n $_prompt_has_battery ]]
  then
    $DOTFILES_ROOT/bin/battery-status
  fi
}

# Battery presence is resolved once when this file is sourced; each prompt
# render runs in a subshell and could not cache it. hw.model no longer says
# "MacBook" on Apple Silicon, so ask the power manager directly.
typeset -g _prompt_has_battery=''
if [[ $(uname) == Darwin ]] && pmset -g batt 2>/dev/null | grep -q InternalBattery; then
  _prompt_has_battery=1
fi
export PROMPT=$'\n$(battery_status)in $(directory_name) $(prompt_git_segment)\n› '

_dotfiles_prompt_window_title() {
  title "zsh" "%m" "%55<...<%~"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _dotfiles_prompt_window_title
