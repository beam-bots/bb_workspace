# bb_workspace

A self-contained workspace for working across the [beam-bots](https://github.com/beam-bots)
ecosystem. Clones every active `beam-bots/*` repository into itself, keeps them
out of source control via `.gitignore`, and ships scripts that make the
cross-repo workflows ergonomic.

## Layout

```
bb_workspace/
├── .devcontainer/      VS Code devcontainer (Elixir + asdf, based on team-alembic template)
├── bin/                Cross-repo helper scripts (added to $PATH in the devcontainer)
├── prompts/            Reusable prompts for Claude Code / agents
├── .tool-versions      Erlang/Elixir versions used by the devcontainer
└── <repo>/             Each beam-bots repo, cloned by `bin/bb-sync` and gitignored
```

## Scripts

All scripts are in `bin/`. They expect to be run from the workspace root (or
anywhere — they resolve their own paths).

| Script | What it does |
|---|---|
| `bb-sync` | Discover `beam-bots/*` repos via the GitHub API, clone any missing, fast-forward existing ones, regenerate `.gitignore`. |
| `bb-sync --fresh` | Same as above, but also switch each clean repo back to its default branch ready for new work. Refuses repos with uncommitted/untracked changes, or feature branches that have unpushed commits. |
| `bb-status` | One-line `git status` summary across every cloned repo (branch, ahead/behind, dirty marker). |
| `bb-unreleased` | List non-chore commits on each repo's default branch above its latest tag — i.e. user-visible changes waiting for a release. `--all` shows every repo, `--quiet` prints just the names, `--types` overrides which conventional-commit types count as chore. |
| `bb-each` | Run an arbitrary command in every repo. `--mix` limits to Elixir repos; `--filter 'bb_*'` for globs; `--parallel` to fan out. |
| `bb-check` | Shorthand for `bb-each --mix -- mix check --no-retry`. Pass any mix task as an alternative. |
| `bb-deps-local` | `mix deps.get` everywhere with `BB_VERSION=local` so packages resolve `bb` from the sibling checkout. |

`bb-sync` rewrites a managed block in `.gitignore` between `# >>> bb-sync managed`
markers — anything you put outside those markers is preserved.

### Skipping repos

`bb-sync` has a `SKIP_REPOS` array near the top for repos that should never be
cloned (currently `.github` and `bb_workspace` itself). Edit it there.

## Devcontainer

`.devcontainer/devcontainer.json` is based on the
[`elixir-asdf` template from team-alembic](https://github.com/team-alembic/devcontainer-templates)
with the workspace-specific bits inlined (no template features registry needed)
plus:

- `bin/` is prepended to `$PATH`, so the scripts above are always available.
- The host `~/.ssh` is mounted read-only so `bb-sync` can clone via SSH.
- `i2c-tools`, `inotify-tools`, and `direnv` are added on top of the standard
  Erlang/OTP build deps, since several packages here drive real hardware.

`onCreateCommand` runs `.devcontainer/setup.sh`, which installs asdf plugins
from `.tool-versions` and bootstraps Hex/Rebar.

## BB_VERSION

Packages in this workspace use the `BB_VERSION` env var to switch between
hex.pm, the local `../bb` checkout, and the `bb` `main` branch. See the parent
`CLAUDE.md` for the helper function. `bb-deps-local` is a thin wrapper that
runs `mix deps.get` with `BB_VERSION=local` everywhere.

## Prompts

`prompts/` holds reusable prompts that operate across the ecosystem — e.g.
`progress-post.md` for drafting the periodic progress blog post. Feed one to
Claude Code like:

```sh
claude < prompts/progress-post.md
```

## Adding a new helper script

1. Drop the script in `bin/` with a `#!/usr/bin/env bash` shebang.
2. `chmod +x` it.
3. Keep it portable: the workspace runs on macOS (default bash 3.2) as well as
   the Debian devcontainer. Avoid `mapfile`, `readarray`, and `[[ -v ]]`.
