# Topic installers do not create credentials

`ssh-key-create` and `sops-key-create` are the only paths in this repository
that generate key material. A topic installer that finds a key missing says so
and names the command; it does not run a generator. `homelab/install.sh` used
to, and no longer does.

## Considered options

Keeping the generation and routing it through `ssh/create-key` was the obvious
repair, and it does not work. `ssh-keygen` prompts for a passphrase, and a topic
installer runs unattended inside `dot`. The only way homelab could call the
explicit command is by forcing an empty passphrase, which is what it was already
doing by hand and is the part worth removing.

What it did by hand was weaker than the command it bypassed in four ways: it
tested `! -e` where `ssh/create-key` also tests `-L` and the public half, it
forced `-N ""`, it set no modes, and it had no test. It also wrote
`$HOME/.ssh/id_ed25519` — the ssh topic's default identity, not a homelab-
specific one — so a first `dot` on a new machine silently produced the
passphrase-less key that `ssh-key-create default` would then refuse to replace.
The unattended path pre-empted the explicit one.

Generating a distinct homelab key, at a homelab path, was the other option. It
keeps a fresh machine one step shorter and it is still a topic installer
creating credentials during an unattended run, which is the boundary
`AGENTS.md` states. One key managed by one command is also what the SSH config
already assumes.

## Consequences

A new machine no longer gets a homelab SSH key from `dot`. The installer prints
the missing path and the command that creates one, which is what
`sops/install.sh` and `git/install.sh` already do for the same situation, so the
three now behave alike rather than one of them being the exception.

`HOMELAB_SSH_KEY` still selects which key the appended `config_local` block
points at, so pointing homelab at a non-default identity remains a matter of
setting that variable and creating the key explicitly.
