# bb_workspace

A self-bootstrapping workspace for the [beam-bots](https://github.com/beam-bots)
ecosystem. Clone this repo into a fresh directory, run one script, and you
end up with every active `beam-bots/*` project checked out as a sibling
directory inside it — ignored by git but reachable from a single shell.

## Quick start

```sh
git clone git@github.com:beam-bots/bb_workspace.git
cd bb_workspace
bin/bb-sync          # clones every beam-bots repo, updates .gitignore
bin/bb-status        # shows branch / ahead-behind / dirty for each repo
```

Requires `gh` (authenticated) and `git` on the host. The included
[`.devcontainer`](./.devcontainer/devcontainer.json) (based on
[team-alembic/devcontainer-templates](https://github.com/team-alembic/devcontainer-templates))
provides Elixir, Erlang, `gh`, Node, and Claude Code preinstalled.

## What you get

| Script | Purpose |
|---|---|
| `bin/bb-sync` | Clone any missing `beam-bots/*` repo here, fast-forward existing ones, rewrite the managed `.gitignore` block. |
| `bin/bb-status` | One-line `git status` per repo. |
| `bin/bb-each` | Run a command in every repo (`--mix` to limit to Elixir, `--filter`, `--parallel`). |
| `bin/bb-check` | `mix check --no-retry` everywhere; pass any mix task as args to override. |
| `bin/bb-deps-local` | `mix deps.get` with `BB_VERSION=local` so packages resolve `bb` from the sibling checkout. |

See [`AGENTS.md`](./AGENTS.md) for the full layout and conventions.

## Prompts

Reusable prompts live in [`prompts/`](./prompts) — drop new ones in as they
prove useful across the ecosystem.
