# Private shell-startup orchestrator. This file is sourced only by ~/.zshrc.

# `c [tab]` uses this as its project root. Local and shared environment files
# retain their existing ability to override it.
export PROJECTS="$HOME/Code"

# Keep secrets outside the repository, then apply shared non-sensitive values.
[[ -r "$HOME/.localrc" ]] && source "$HOME/.localrc"
[[ -r "$DOTFILES_ROOT/.commonrc" ]] && source "$DOTFILES_ROOT/.commonrc"

# Discover Homebrew once. The exported prefix is reused by the baseline path,
# topic configuration, completions, and syntax highlighting.
if (( $+commands[brew] )) && \
  _dotfiles_homebrew_prefix=$("$commands[brew]" --prefix 2>/dev/null)
then
  HOMEBREW_PREFIX=$_dotfiles_homebrew_prefix
elif [[ -d /opt/homebrew ]]; then
  HOMEBREW_PREFIX=/opt/homebrew
elif [[ -d /usr/local/Homebrew ]]; then
  HOMEBREW_PREFIX=/usr/local
else
  HOMEBREW_PREFIX=/usr/local
fi
export HOMEBREW_PREFIX

# Establish the portable baseline before topics extend it. Zsh's unique path
# array removes repeated entries without changing the first entry's precedence.
typeset -gU path
path=(
  "$HOMEBREW_PREFIX/bin"
  "$HOMEBREW_PREFIX/sbin"
  /usr/local/bin
  /usr/local/sbin
  "$DOTFILES_ROOT/bin"
  $path
)
export PATH

# Preserve the empty MANPATH entry that asks `man` to include its system
# defaults while removing duplicate directories.
typeset -gaU _dotfiles_manpath
_dotfiles_manpath=(
  "$HOMEBREW_PREFIX/man"
  /usr/local/man
  /usr/local/mysql/man
  /usr/local/git/man
  "${(@s/:/)MANPATH}"
)
if [[ -z ${MANPATH+x} || $MANPATH == *: ]]; then
  _dotfiles_manpath+=("")
fi
export MANPATH="${(j/:/)_dotfiles_manpath}"

# Collect visible topic files in deterministic order. Both reserved topics and
# private files/directories inside a topic are intentionally excluded.
typeset -ga _dotfiles_topic_dirs
typeset -ga _dotfiles_path_files
typeset -ga _dotfiles_main_files
typeset -ga _dotfiles_completion_files
_dotfiles_topic_dirs=()
_dotfiles_path_files=()
_dotfiles_main_files=()
_dotfiles_completion_files=()

for _dotfiles_topic_dir in "$DOTFILES_ROOT"/*(N/); do
  [[ ${_dotfiles_topic_dir:t} == _* ]] && continue
  _dotfiles_topic_dirs+=("$_dotfiles_topic_dir")

  for _dotfiles_file in "$_dotfiles_topic_dir"/**/*.zsh(N); do
    _dotfiles_relative=${_dotfiles_file#"$DOTFILES_ROOT"/}
    [[ $_dotfiles_relative == _* || $_dotfiles_relative == */_* ]] && continue

    case ${_dotfiles_file:t} in
      path.zsh)
        _dotfiles_path_files+=("$_dotfiles_file")
        ;;
      completion.zsh)
        _dotfiles_completion_files+=("$_dotfiles_file")
        ;;
      prompt.zsh)
        [[ $_dotfiles_file == "$DOTFILES_ROOT/zsh/prompt.zsh" ]] || \
          _dotfiles_main_files+=("$_dotfiles_file")
        ;;
      *)
        _dotfiles_main_files+=("$_dotfiles_file")
        ;;
    esac
  done
done

# Make repository functions and visible topics available for autoloading before
# topic extensions and main configuration run.
typeset -gU fpath
fpath=(
  "$DOTFILES_ROOT/functions"
  "${_dotfiles_topic_dirs[@]}"
  "$HOMEBREW_PREFIX/share/zsh/site-functions"
  $fpath
)
autoload -U "$DOTFILES_ROOT"/functions/*(N:t)

# Topic path extensions run before the rest of the topic configuration.
for _dotfiles_file in "${_dotfiles_path_files[@]}"; do
  source "$_dotfiles_file"
done

for _dotfiles_file in "${_dotfiles_main_files[@]}"; do
  source "$_dotfiles_file"
done

# The custom battery/git prompt is authoritative and loads after every general
# topic file, so no topic can accidentally replace it through discovery order.
source "$DOTFILES_ROOT/zsh/prompt.zsh"

# Initialize completion exactly once in this startup pass, then let topics add
# their completion definitions and styles.
autoload -U compinit
compinit

for _dotfiles_file in "${_dotfiles_completion_files[@]}"; do
  source "$_dotfiles_file"
done

# Syntax highlighting must be sourced last and remains optional.
_dotfiles_syntax_highlighting="$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
if [[ -r $_dotfiles_syntax_highlighting ]]; then
  source "$_dotfiles_syntax_highlighting"
  ZSH_HIGHLIGHT_STYLES[path]=
  ZSH_HIGHLIGHT_STYLES[path_pathseparator]=fg=black,bold
  ZSH_HIGHLIGHT_STYLES[path_prefix]=
fi

# Keep pipx and similar user-level tools portable and at their current trailing
# precedence. The unique path array also makes reloading ~/.zshrc idempotent.
path+=("$HOME/.local/bin")

# Do not leak loader implementation details into the interactive shell.
unset ${(k)parameters[(I)_dotfiles_*]}
