# Git shortcuts
alias g='git'
alias gl='git pull'
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'

# Plain `git diff`; delta (core.pager in gitconfig) handles presentation.
alias gd='git diff'

alias gc='git commit'
alias gca='git commit -a'
alias gcm='git commit -m'
alias gco='git checkout'
alias gsw='git switch'
alias gcb='git copy-branch-name'
alias gb='git branch'
alias gs='git status -sb' # upgrade your git if -sb breaks for you. it's fun.
alias gac='git add -A && git commit -m'
alias ge='git-edit-new'
alias grb='git rebase'
alias gcp='git cherry-pick'
alias gsta='git stash push'
alias gstp='git stash pop'
# --force-with-lease, never --force: pull.rebase=true makes rewritten
# history routine, and the lease refuses to clobber unseen remote commits.
alias gpf='git push --force-with-lease'
