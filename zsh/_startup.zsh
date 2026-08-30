# Private shell-startup orchestrator. This file is sourced only by ~/.zshrc.

# Keep secrets outside the repository, then apply shared non-sensitive values.
# `.commonrc` owns WORKSPACE and the PROJECTS root derived from it, and it is
# sourced after `.localrc` so a WORKSPACE set there reaches that derivation.
# Nothing above may export PROJECTS: an earlier assignment wins the `:-` in
# `.commonrc` and silently pins the project root to the default.
[[ -r "$HOME/.localrc" ]] && source "$HOME/.localrc"
[[ -r "$DOTFILES_ROOT/.commonrc" ]] && source "$DOTFILES_ROOT/.commonrc"

# Resolve Homebrew once. The exported prefix is reused by the baseline path,
# topic configuration, completions, and syntax highlighting.
HOMEBREW_PREFIX=$("$DOTFILES_ROOT/homebrew/_availability.sh" prefix --fallback 2>/dev/null)
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

# Classify the repository layout once. Setup and the documentation checks
# consume the same catalog, so every surface agrees on the visible topics and
# the role of each shell file.
typeset -ga _dotfiles_topic_dirs
typeset -ga _dotfiles_path_files
typeset -ga _dotfiles_main_files
typeset -ga _dotfiles_completion_files
typeset -g _dotfiles_prompt_file=''
typeset -gi _dotfiles_prompt_count=0
_dotfiles_topic_dirs=()
_dotfiles_path_files=()
_dotfiles_main_files=()
_dotfiles_completion_files=()

# Memoized catalog. Classification only changes when files are added,
# removed, or renamed, and those always bump a directory mtime; content
# edits never change the catalog. The cache is keyed by checkout path so
# parallel worktrees never share entries, and the classifier stays the
# single source of truth. See _docs/adr/0002-topic-catalog-cache.md.
typeset -g _dotfiles_catalog_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/topic-catalog${DOTFILES_ROOT//\//%}"
typeset -g _dotfiles_catalog=''
if [[ -r $_dotfiles_catalog_cache ]]; then
  typeset -g _dotfiles_catalog_stale=''
  for _dotfiles_dir in "$DOTFILES_ROOT" "$DOTFILES_ROOT"/*(N/); do
    if [[ $_dotfiles_dir -nt $_dotfiles_catalog_cache ]]; then
      _dotfiles_catalog_stale=1
      break
    fi
  done
  [[ -z $_dotfiles_catalog_stale ]] && _dotfiles_catalog=$(<"$_dotfiles_catalog_cache")
fi

if [[ -z $_dotfiles_catalog ]]; then
  if ! _dotfiles_catalog=$("$DOTFILES_ROOT/_scripts/topic-catalog" "$DOTFILES_ROOT" 2>/dev/null); then
    print -u2 'dotfiles: topic catalog discovery failed'
    unset ${(k)parameters[(I)_dotfiles_*]}
    return 1
  fi
  # Cache writes are best-effort; a read-only cache dir must not break startup.
  mkdir -p "${_dotfiles_catalog_cache:h}" 2>/dev/null \
    && print -r -- "$_dotfiles_catalog" >| "$_dotfiles_catalog_cache" 2>/dev/null
fi

for _dotfiles_record in "${(@f)_dotfiles_catalog}"; do
  _dotfiles_kind=${_dotfiles_record%%$'\t'*}
  _dotfiles_file=${_dotfiles_record#*$'\t'}
  case $_dotfiles_kind in
    topic)
      _dotfiles_topic_dirs+=("$_dotfiles_file")
      ;;
    path)
      _dotfiles_path_files+=("$_dotfiles_file")
      ;;
    main)
      _dotfiles_main_files+=("$_dotfiles_file")
      ;;
    completion)
      _dotfiles_completion_files+=("$_dotfiles_file")
      ;;
    prompt)
      _dotfiles_prompt_file=$_dotfiles_file
      (( _dotfiles_prompt_count += 1 ))
      ;;
  esac
done

# The custom battery/git prompt is authoritative; exactly one topic file may
# claim that role.
if (( _dotfiles_prompt_count != 1 )); then
  print -u2 "dotfiles: expected exactly one authoritative prompt, found $_dotfiles_prompt_count"
  unset ${(k)parameters[(I)_dotfiles_*]}
  return 1
fi

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

# The authoritative prompt loads after every general topic file, so no topic
# can accidentally replace it through discovery order.
source "$_dotfiles_prompt_file"

# Initialize completion exactly once in this startup pass, then let topics add
# their completion definitions and styles. -i silently skips insecure
# directories instead of prompting. When the dump is fresh (<24h), -C reuses
# yesterday's fpath audit instead of rescanning every directory. The (#q)
# qualifier needs EXTENDED_GLOB, set earlier by zsh/config.zsh.
autoload -U compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh-24) ]]; then
  compinit -C -i
else
  compinit -i
fi

for _dotfiles_file in "${_dotfiles_completion_files[@]}"; do
  source "$_dotfiles_file"
done

# Autosuggestions must load before syntax highlighting and after compinit.
_dotfiles_autosuggestions="$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
if [[ -r $_dotfiles_autosuggestions ]]; then
  source "$_dotfiles_autosuggestions"
fi

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
