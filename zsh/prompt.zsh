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

battery_status() {
  if [[ -n $_prompt_has_battery ]]
  then
    $DOTFILES_ROOT/bin/battery-status
  fi
}

# A reload must not leave the previous render's descriptor registered.
(( $+functions[_dotfiles_prompt_cancel_render] )) && _dotfiles_prompt_cancel_render

# Prompt state. None of these names starts with _dotfiles_: startup unsets
# every such parameter when it finishes, and these outlive it.
#
# Battery presence is resolved once when this file is sourced. hw.model no
# longer says "MacBook" on Apple Silicon, so ask the power manager directly.
typeset -g _prompt_has_battery=''
if [[ $(uname) == Darwin ]] && pmset -g batt 2>/dev/null | grep -q InternalBattery; then
  _prompt_has_battery=1
fi
typeset -g _prompt_battery='' _prompt_git='' _prompt_git_directory=''
typeset -g _prompt_render_fd='' _prompt_kube_key='' _prompt_kube_context=''

# The prompt is drawn from parameters, so drawing it starts no process. The
# battery and git segments cost several, in a large repository long enough to
# hold up typing, so a background render fills them in after the prompt is up.
export PROMPT=$'\n${_prompt_battery}in %{$fg_bold[cyan]%}%1/%\\/%{$reset_color%} ${_prompt_git}\n› '

# The context a command would act on sits on the right, so the left prompt
# never moves, and it is dropped from lines already entered.
setopt TRANSIENT_RPROMPT

_dotfiles_prompt_render() {
  print -rn -- "$(battery_status)"$'\x1f'"$(prompt_git_segment)"
}

_dotfiles_prompt_cancel_render() {
  [[ -n $_prompt_render_fd ]] || return 0
  zle -F $_prompt_render_fd 2>/dev/null
  exec {_prompt_render_fd}<&-
  _prompt_render_fd=''
}

_dotfiles_prompt_apply_render() {
  _prompt_battery=${1%%$'\x1f'*}
  _prompt_git=${1#*$'\x1f'}
  _prompt_git_directory=$PWD
}

# Called by zle when the background render has written its answer.
_dotfiles_prompt_finish_render() {
  local answer=''

  IFS= read -r -u $1 -d '' answer
  _dotfiles_prompt_cancel_render
  _dotfiles_prompt_apply_render "$answer"
  zle reset-prompt 2>/dev/null
}

_dotfiles_prompt_start_render() {
  # In the same directory the last answer is a good first guess. After a
  # change of directory it describes another repository.
  [[ $PWD == $_prompt_git_directory ]] || _prompt_git=''
  _dotfiles_prompt_cancel_render

  # Without the line editor nothing could deliver a late answer.
  if [[ ! -o zle ]]; then
    _dotfiles_prompt_apply_render "$(_dotfiles_prompt_render 2>/dev/null)"
    return 0
  fi

  exec {_prompt_render_fd}< <(_dotfiles_prompt_render 2>/dev/null)
  zle -F $_prompt_render_fd _dotfiles_prompt_finish_render
}

# Print the current Kubernetes context without starting kubectl: the first
# kubeconfig that names one wins, as it does for kubectl. The answer is kept
# until a kubeconfig changes.
_dotfiles_prompt_kube_context() {
  emulate -L zsh
  setopt extended_glob
  local file line key=''
  local -a files modified

  files=(${(s.:.)${KUBECONFIG:-$HOME/.kube/config}})
  for file in $files; do
    zstat -A modified +mtime -- $file 2>/dev/null || continue
    key+="$file:$modified[1] "
  done

  if [[ $key != $_prompt_kube_key ]]; then
    _prompt_kube_key=$key
    _prompt_kube_context=''
    for file in $files; do
      [[ -r $file ]] || continue
      while IFS= read -r line; do
        [[ $line == current-context:* ]] || continue
        line=${${line#current-context:}##[[:space:]]##}
        _prompt_kube_context=${(Q)${line%%[[:space:]]##}}
        break
      done <$file
      [[ -z $_prompt_kube_context ]] || break
    done
  fi

  REPLY=$_prompt_kube_context
}

# One labelled context, in red when its name says production.
_dotfiles_prompt_context_part() {
  local style='%F{8}'

  [[ ${2:l} == *prod* ]] && style='%B%F{red}'
  REPLY="$style$1:${2//\%/%%}%f%b"
}

_dotfiles_prompt_show_context() {
  local -a parts
  local REPLY

  _dotfiles_prompt_kube_context
  if [[ -n $REPLY ]]; then
    _dotfiles_prompt_context_part k8s "$REPLY"
    parts+=("$REPLY")
  fi
  if [[ -n ${AWS_PROFILE:-${AWS_VAULT-}} ]]; then
    _dotfiles_prompt_context_part aws "${AWS_PROFILE:-$AWS_VAULT}"
    parts+=("$REPLY")
  fi
  RPROMPT=${(j: :)parts}
}

_dotfiles_prompt_window_title() {
  title "zsh" "%m" "%55<...<%~"
}

zmodload -F zsh/stat b:zstat
autoload -Uz add-zsh-hook
add-zsh-hook precmd _dotfiles_prompt_window_title
add-zsh-hook precmd _dotfiles_prompt_show_context
add-zsh-hook precmd _dotfiles_prompt_start_render
