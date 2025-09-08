# Kubectl shortcuts
alias k='kubectl'
alias kk='kubectl'

# Context and config management
alias kctx='kubectl config use-context'
alias kctx-list='kubectl config get-contexts'
alias kcurrent='kubectl config current-context'
alias konfig='kubectl config view --minify --raw'
alias kctx-witek='kubectl config use-context witek-cluster'

# Resource shortcuts
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kgs='kubectl get services'
alias kgsa='kubectl get services --all-namespaces'
alias kgd='kubectl get deployments'
alias kgda='kubectl get deployments --all-namespaces'
alias kgn='kubectl get nodes'
alias kgns='kubectl get namespaces'

# Describe shortcuts
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdd='kubectl describe deployment'
alias kdn='kubectl describe node'

# Logs shortcuts
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias klt='kubectl logs --tail=100'

# Apply and delete
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'

# Exec and port-forward
alias kex='kubectl exec -it'
alias kpf='kubectl port-forward'

# Watch resources
alias kwp='watch kubectl get pods'
alias kwpa='watch kubectl get pods --all-namespaces'

# Namespace switching
alias kns='kubectl config set-context --current --namespace'
