# cheers, @ehrenmurdick
# http://github.com/ehrenmurdick/config/blob/master/zsh/prompt.zsh

if (( $+commands[git] ))
then
  git="$commands[git]"
else
  git="/usr/bin/git"
fi

. "$DOTFILES_ROOT/git/_branch-state.sh"

git_dirty() {
  local branch
  branch=$(git_prompt_info) || return 0

  if ! $git status -s &> /dev/null
  then
    return
  else
    if [[ $($git status --porcelain) == "" ]]
    then
      echo "on %{$fg_bold[green]%}$branch%{$reset_color%}"
    else
      echo "on %{$fg_bold[red]%}$branch%{$reset_color%}"
    fi
  fi
}

git_prompt_info () {
  _dotfiles_git_state_current_branch "$git" 2>/dev/null
}

need_push () {
  local branch number

  branch=$(_dotfiles_git_state_current_branch "$git" 2>/dev/null) || return 0
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

directory_name() {
  echo "%{$fg_bold[cyan]%}%1/%\/%{$reset_color%}"
}

battery_status() {
  if test ! "$(uname)" = "Darwin"
  then
    exit 0
  fi

  if [[ $(sysctl -n hw.model) == *"Book"* ]]
  then
    $DOTFILES_ROOT/bin/battery-status
  fi
}

export PROMPT=$'\n$(battery_status)in $(directory_name) $(git_dirty)$(need_push)\n› '
set_prompt () {
  export RPROMPT="%{$fg_bold[cyan]%}%{$reset_color%}"
}

precmd() {
  title "zsh" "%m" "%55<...<%~"
  set_prompt
}
