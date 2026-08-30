# Tool config directories are not derived from XDG_CONFIG_HOME

A tool's configuration directory is spelled `$HOME/.config/<tool>` because that
is where these tools actually read it on macOS. `installer_config_dir` returns
that path and nothing derives it from `XDG_CONFIG_HOME`, because whether a tool
honours that variable is the tool's fact to state, not a convention this
repository can adopt on its behalf.

## Considered options

Honouring `XDG_CONFIG_HOME` uniformly was the obvious path, and the one the
original ticket specified: three installers already did it, five hardcoded
`~/.config`, and a resolver in the preamble would have made the honouring
spelling the easy one. Checking the tools rather than the installers is what
ruled it out.

| Tool               | Reads `XDG_CONFIG_HOME`                    |
| ------------------ | ------------------------------------------ |
| git, mise, nvim    | yes                                        |
| ghostty, aerospace | yes; the variable is in the shipped binary |
| opencode           | yes                                        |
| sops/age           | yes, but moot: see below                   |
| zed                | **no** on macOS                            |

Zed hardcodes `~/.config/zed` on macOS: its binary carries the literal
`sudo chown $(whoami):staff ~/.config` in the message it prints when that
directory is unwritable, and its only `XDG_CONFIG_HOME` references belong to
its gitconfig lookup and its Python environment detector. Routing Zed through
an XDG-derived resolver would write settings to a directory Zed never reads.

sops is the one entry where the variable does something and it still does not
decide anything. On macOS sops defaults its age keys to
`~/Library/Application Support/sops/age/`, and `XDG_CONFIG_HOME` overrides that
default. This repository keeps them in `~/.config/sops/age/` regardless, which
works because `sops/env.zsh` exports `SOPS_AGE_KEY_FILE` outright. Naming the
path through the tool's own variable is how a tool config directory moves;
setting `XDG_CONFIG_HOME` and hoping is not.

So uniform honouring buys one permanent exception — re-creating exactly the
divergence the resolver was meant to remove — in exchange for portability this
repository has never used: `XDG_CONFIG_HOME` is read in eight places here and
set in none.

The remaining argument for honouring it was that the divergence lived in one
layer and could be fixed in one place. It does not. `git/gitconfig.symlink`
pointed `gpg.ssh.allowedSignersFile` at `~/.config/git/allowed_signers` while
`git/install.sh` wrote to `${XDG_CONFIG_HOME:-$HOME/.config}/git`, so setting
the variable silently broke signature verification. A preamble helper cannot
reach that bug, because a gitconfig is static text that computes nothing.
Hardcoding the path makes the installer agree with the config that was already
correct.

## Consequences

No path changes under any environment, which is the point: this is a change of
intent recorded in code, not a migration.

Seven of the eight tools do read `XDG_CONFIG_HOME`, so an installer ignoring it
is only half an answer: set the variable and those seven would look somewhere
the installers never linked, which is this ticket's original complaint with the
arrow reversed. `.commonrc` therefore pins `XDG_CONFIG_HOME` to `$HOME/.config`
rather than defaulting it. That is the one place able to make the tools agree
with the installers, and it forecloses relocation, which is what this decision
already gave up.

The asymmetry with `_installer_state_dir`, which still honours
`XDG_STATE_HOME`, is deliberate. Run-once markers are this repository's own
state and nothing else has to agree with us about where they live, so honouring
the variable there is free. A tool config directory has a second party.

`tests/installer_preamble_test.sh` asserts that `installer_config_dir` ignores
`XDG_CONFIG_HOME`, so the decision fails loudly rather than drifting back. That
test is the reason this file can stay short about the eight tools: reverting is
cheap in lines and expensive in re-verification, and the table above is the
verification.
