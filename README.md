# Dotfiles

Danilo Martinelli ([danilomartinelli](https://github.com/danilomartinelli))

## Table of Contents <!-- omit in toc -->

- [Overview](#overview)
  - [What](#what)
  - [Why](#why)
  - [How](#how)
- [Hardware](#hardware)

## Overview

### What

This repo contains dotfiles, which are application configuration and settings files. They frequently begin with a dot, hence the name. Dotfiles are compatible with Linux and macOS.

### Why

- **Make developer environments automated and disposable**. [Disposability](https://12factor.net/disposability) is an important concept in [infrastructure-as-code DevOps](https://www.terraform.io/intro/use-cases#disposable-environments), [serverless computing](https://www.cloudflare.com/learning/serverless/what-is-serverless/), [CI/CD](https://docs.github.com/en/actions/learn-github-actions/understanding-github-actions), and more recently, [in-browser development environments](https://docs.github.com/en/codespaces/overview). Why aren't developers applying automation and disposability to their own computers? With an automated disposable developer environment, setup of a new machine is fast and easy. This approach is also liberating - I can purchase a new computer (or wipe an existing one), run _bootstrap.sh_, and be up and running again in no time.
- **Know when and why settings change**. I not only know what tools and settings I'm using, but when and why I chose the tools and settings.
- **Learn new skills**. I learn skills, like shell scripting, that are useful and don't go out of date quickly. I wouldn't know shell as well if I didn't work on my developer environment. I learn these skills by tinkering a little bit at a time, in an unstructured way. It's time I might not otherwise be writing code.

### How

This dotfiles repository is meant to be installed by _[bootstrap.sh](bootstrap.sh)_.

_bootstrap.sh_ is a shell script to automate setup of a new macOS or Linux development machine. It is _idempotent_, meaning it can be run repeatedly on the same system. To set up a new machine, simply open a terminal and run the following command:

```sh
STRAP_GIT_EMAIL="you@example.com" STRAP_GIT_NAME="Your Name" STRAP_GITHUB_USER="username" \
  /usr/bin/env bash -c "$(curl -fsSL https://raw.githubusercontent.com/danilomartinelli/dotfiles/HEAD/bootstrap.sh)"
```

The following environment variables can be used to configure _bootstrap.sh_, and should be either set before with [`export`](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#export), or inline within the command to run the script:

- `STRAP_GIT_EMAIL`: email address to use for Git configuration. Will error and exit if not set.
- `STRAP_GIT_NAME`: name to use for Git configuration. Will error and exit if not set.
- `STRAP_GITHUB_USER`: username on GitHub or other remote from which dotfiles repo will be cloned. Defaults to my GitHub username, so you should set this if you're not me.
- `STRAP_DOTFILES_URL`: URL from which the dotfiles repo will be cloned. Defaults to `https://github.com/$STRAP_GITHUB_USER/dotfiles`, but any [Git-compatible URL](https://www.git-scm.com/docs/git-clone#_git_urls) can be used, so long as it is accessible at the time the script runs.
- `STRAP_DOTFILES_BRANCH`: Git branch to check out after cloning dotfiles repo. Defaults to `main`.

There are some additional variables for advanced usage. Consult the _[bootstrap.sh](bootstrap.sh)_ script to see all supported variables.

_bootstrap.sh_ will set up macOS and Homebrew, run scripts in the _scripts/_ directory, and install Homebrew packages and casks from the _[Brewfile](Brewfile)_. A Brewfile is a list of [Homebrew](https://brew.sh/) packages and casks (applications) that can be installed in a batch by [Homebrew Bundle](https://github.com/Homebrew/homebrew-bundle). The Brewfile can even be used to install Mac App Store apps with the `mas` CLI. Note that you must sign in to the App Store ahead of time for `mas` to work.

The following list is a brief summary of permissions related to _bootstrap.sh_.

- Initial setup of Homebrew itself does not require an admin user account, but does require `sudo`. See the [Homebrew installation docs](https://docs.brew.sh/Installation), [Homebrew/install#312](https://github.com/Homebrew/install/issues/312), and [Homebrew/install#315](https://github.com/Homebrew/install/pull/315/files).
- [After Homebrew setup, use of `sudo` with `brew` commands is discouraged](https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-bad).
- After Homebrew setup, commands such as `brew bundle install --global` should be run from the same user account used for setup. Attempts to run `brew` commands from another user account will result in errors, because directories that need to be updated are owned by the setup account. If access to the setup account is not routinely available, an alternative approach could be to change ownership of Homebrew directories to a group that includes the user account used for Homebrew setup as well as other users that need to run Homebrew commands.
- _bootstrap.sh_ can run with limited functionality on non-admin and non-`sudo` user accounts. A plausible use case could exist in which an admin runs `bootstrap.sh` to configure the system initially, then a non-admin runs `bootstrap.sh` to configure their own account. In this use case, the non-admin user should not need admin or `sudo` privileges, because all the pertinent setup (FileVault disk encryption, XCode developer tools, Homebrew, etc) is already complete.

Users with more complex needs for multi-environment dotfiles management might consider a tool like [`chezmoi`](https://www.chezmoi.io/).

## Hardware

- Apple Silicon [MacBook Pro](https://www.apple.com/macbook-pro/)
