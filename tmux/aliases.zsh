# tmux session shortcuts
alias ta='tmux attach -t'
alias tls='tmux ls'
alias tn='tmux new -s'
alias tk='tmux kill-session -t'

# Fuzzy session picker: attach to the chosen session, or create one named
# after the current directory when called with no existing sessions.
t() {
  local session
  if [[ -n $1 ]]; then
    tmux new-session -A -s "$1"
    return
  fi
  session=$(tmux ls -F '#S' 2>/dev/null | fzf --prompt='tmux> ' --height=40%)
  if [[ -n $session ]]; then
    tmux attach -t "$session"
  else
    tmux new-session -A -s "${PWD:t}"
  fi
}
