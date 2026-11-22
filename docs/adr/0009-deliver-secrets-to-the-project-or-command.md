---
status: accepted
---

# Deliver a secret to the project or the command that needs it, never to a shell

`.localrc` exported every API key into every shell, so every process started
from one inherited all of them, including coding agents running without
permission prompts. No shell exports a credential any more. A **project
secret** lives in the project, in a SOPS-encrypted `secrets.sops.env` that
direnv loads inside that directory through `use sops`. A **provider key**, which
a tool needs wherever it runs, is injected at the point the tool is launched:
`with-provider-keys <tool> -- <command>` decrypts that tool's store into the
environment of that one command.

Bitwarden is the origin of provider keys: one secure note per tool. The
explicit `provider-keys-sync` copies the notes into stores under
`~/.config/dotfiles/provider-keys`, encrypted to the default age identity. A
new Mac gets its keys by running that one command, and nothing secret is
tracked here.

## Considered options

- **Export keys only in a person's shell.** Rejected: an agent started from
  that shell still inherits them, which is the case that mattered.
- **Fetch from Bitwarden at every launch.** Rejected: it needs an unlocked
  vault each time a tool starts, including from an editor.
- **Keep the stores in the macOS Keychain.** Rejected: SOPS already holds
  project secrets, and one mechanism with one identity to back up is simpler.
- **Track the encrypted stores in this repository.** Rejected: the repository
  is public, and an encrypted secret there is one leaked identity from open.

## Consequences

- The local stores protect against inheritance, not against a process running
  as this user, which can read the age identity as well.
- Something launched outside a shell or the launcher gets no keys. An app or
  MCP server that expects one in its inherited environment must be started
  through `with-provider-keys`, as Zed starts OpenCode.
- Without a store the command runs without keys and says so, so a tool signed
  in by subscription still starts on a Mac that has not synced.
- Losing the age identity loses every store and every project secret encrypted
  to it; the stores can be rebuilt from Bitwarden, project secrets cannot.
