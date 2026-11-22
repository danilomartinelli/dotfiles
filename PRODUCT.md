# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Static HTML/CSS with no build step, kept in an underscore-prefixed directory so
topic discovery ignores it.

Decided, not yet built: a GitHub Actions workflow publishes the page to GitHub
Pages at `danilomartinelli.github.io/dotfiles`. Neither the workflow nor the
Pages site exists yet.

## Users

Curious developers who found the repository through GitHub, a search, or a
link. They want to understand the approach and take ideas for their own setup.
They are not expected to install it as is.

## Product Purpose

The repository is the source of truth for Danilo Martinelli's personal macOS
environment: Homebrew software, Mise-managed runtimes, macOS defaults, Zsh
startup, public shell commands, application configuration, and idempotent topic
installers. One bootstrap configures a new Mac; the `dot` command keeps an
existing machine in sync with the declarations.

The public page succeeds when a visiting developer understands how the system
works and leaves for the repository with something worth borrowing.

## Positioning

- Declarative and tested: `Brewfile`, `mise/config.toml`, and tab-separated
  catalogs are the single source for what the machine holds, checked by
  isolated fixture tests and by CI on macOS.
- Used in real life: Danilo has been a developer for 12 years and has recorded
  and evolved this setup for 4 years. It is a working environment, not a
  demonstration.

## Operating Context

- These are personal dotfiles, not a universal macOS installer. Applying them
  installs software, changes macOS preferences, and links configuration into
  the home directory.
- `README.md` is the complete reference for installation, operation, and
  commands. The page introduces the system; it does not replace the README.

## Capabilities and Constraints

- The software catalog is rendered from declarations by
  `_scripts/render-software-catalog`, which reads them only through
  `_scripts/declared_software.py`. A catalog shown on the page comes from the
  same declarations and must not be maintained by hand.
- Visible top-level directories are topics unless `_scripts/topic-catalog`
  classifies them as reserved; hidden and underscore-prefixed names are
  excluded from discovery.
- `tests/documentation_test.sh` enforces documentation contracts. A generated
  page region falls under the same rule: it fails the check while out of date.
- Repository artifacts, including page copy, are written in English.
- No credential, account identifier, or machine-private state appears in
  tracked files, and the page is a tracked file.

## Brand Commitments

- Name: `dotfiles`, by Danilo Martinelli (`danilomartinelli` on GitHub).
- Repository description: "@danilomartinelli does dotfiles".
- `https://witek.com.br` is Danilo's own brand and the repository's homepage
  link. The page may link to it as authorship; it does not inherit that site's
  visual identity.
- No logo or visual identity exists yet.

## Evidence on Hand

- `README.md`: installation, update lifecycle, software catalog tables, public
  commands, architecture, validation.
- `docs/adr/`: nine architecture decision records.
- `GLOSSARY.md`: the domain vocabulary.
- `Brewfile` and `mise/config.toml`: every declared tool with its catalog
  description as a trailing comment.
- `tests/` and `.github/workflows/ci.yml`: the fixture suites and the macOS CI
  run, with a live status badge.
- Absent, and not to be invented: screenshots of the machine, testimonials,
  usage numbers, and benchmarks.

## Product Principles

- One declaration, written once: a name, a version, or a description lives
  where the software is declared, and everything else is rendered from it.
- A source diff does not prove that configuration was applied; the page
  describes the source, not a particular machine's state.
- Show the reasoning: decisions are recorded, and the page points to them
  rather than restating them.
- Honest scope: the page says plainly that this is one person's setup.

## Accessibility & Inclusion

The public page meets WCAG 2.2 AA.
