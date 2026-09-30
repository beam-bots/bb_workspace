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
| `bb-check` | Shorthand for `bb-each --mix -- mix check --no-retry`. Pass any mix task as an alternative. Under `BB_VERSION=local` it also drops each repo's cached PLT hash, since dialyxir can't tell a path dep's source has moved. |
| `bb-deps-local` | `mix deps.get` everywhere with `BB_VERSION=local` so packages resolve `bb` from the sibling checkout. |

`bb-sync` rewrites a managed block in `.gitignore` between `# >>> bb-sync managed`
markers — anything you put outside those markers is preserved.

### One writer at a time

`bb-sync`, `bb-each`, `bb-check` and `bb-deps-local` all write to the same
checkouts, so they take a workspace-wide lock (`bin/bb-lock.sh`, a `.bb-lock`
directory in the workspace root). A second one waits for the first instead of
racing it, naming the script, pid and start time it is queued behind:

```
==> waiting for bb-each mix check --no-retry (pid 4213 on jeb) since 2026-08-17 16:22:58 — ^C to give up
```

^C during the wait is safe — nothing has been touched yet, and the holder keeps
its lock. The read-only scripts — `bb-status`, `bb-unreleased` — don't lock and
can be run at any time.

The lock is released on exit, `INT` and `TERM`. A lock left behind by a
`kill -9` is detected and reclaimed rather than waited on, provided the pid was
recorded on the same host — a lock taken inside the devcontainer can't be
verified from the host (or vice versa) and has to be removed by hand.

### Skipping repos

`bb-sync` has a `SKIP_REPOS` array near the top for repos that should never be
cloned (currently `bb_rpc` and `bb_workspace` itself). Edit it there.

The `local_name_for` function maps a GitHub repo name to a different on-disk
directory name. `.github` is cloned as `_github` so it doesn't clash with this
workspace's own (potential) `.github` CI directory.

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

## Working across the ecosystem

The workspace clones one framework package (`bb`) plus a constellation of
satellites. Knowing how they fit together saves re-deriving it from source.

### Package roles

| Category | Packages | Role |
|---|---|---|
| Core framework | `bb` | The Spark DSL, runtime, supervision, component behaviours, messaging, safety. Everything else is a satellite. |
| Kinematics | `bb_ik_dls`, `bb_ik_fabrik` | Interchangeable `BB.IK.Solver` implementations. |
| Estimators | `bb_estimator_ahrs` | `BB.Estimator` implementations (Madgwick/Mahony/Complementary). |
| Controllers | `bb_pid_controller` | `BB.Controller` implementations. |
| Sensors | `bb_sensor_ina219`, `bb_sensor_bmi323` | `BB.Sensor` drivers (I²C/SPI via `wafer`). |
| Servos | `bb_servo_feetech`, `bb_servo_pca9685`, `bb_servo_pigpio`, `bb_servo_robotis` | A `BB.Controller` bus manager + `BB.Actuator`s (+ optional `BB.Bridge`). |
| Orchestration | `bb_reactor`, `bb_jido` | Reactor (saga) commands and Jido agents over BB commands. |
| Policies | `bb_policy` | Learned (neural-network) behaviours mapping observations to actions, via ONNX. |
| Persistence | `bb_parameter_store_cubdb` | A `BB.Parameter.Store` backed by CubDB. Ships its own DSL section. |
| Board support | `bb_nsk` | Nerves Starter Kit and its Balance Bot add-on, plus the workshop deck in `slides/`. |
| Surfaces | `bb_liveview`, `bb_kino`, `bb_mcp` | UIs / tooling over a running robot. |
| Examples | `bb_example_so101`, `bb_example_wx200`, `bb_so101`, `bb_examples` | Whole-robot configurations. |
| Vendored libs | `feetech` | Non-BB hardware protocol libraries. |

### The extension model

A robot is a module that does `use BB` — a Spark DSL (`BB.Dsl`). Most satellites
integrate the same way: they supply a *module implementing a `bb` behaviour*,
which the user wires into an existing DSL slot as `Module` or `{Module,
keyword_opts}` (the schema type is consistently `{:or, [{:behaviour, BB.X},
{:tuple, [{:behaviour, BB.X}, :keyword_list]}]}`). Treat that as the norm.

It is not the boundary, though. Spark supports extension composition, and
`bb_parameter_store_cubdb` already ships its own — `BB.Parameter.Store.CubDB.Dsl`
adds a section and a transformer, and the user opts in with `use BB, extensions:
[BB.Parameter.Store.CubDB.Dsl]`. Reach for an extension when a satellite needs
configuration of its own rather than a slot to be dropped into.

The behaviours, each defined in `bb/lib/bb/<name>.ex`: `BB.Sensor`,
`BB.Actuator`, `BB.Controller`, `BB.Estimator`, `BB.Command`, `BB.Bridge`,
`BB.IK.Solver`, `BB.Motion.Tracker`, `BB.Parameter`, `BB.Parameter.Store`,
`BB.Message`.

Two integration shapes:

- **Callback module + framework wrapper GenServer** — `BB.Sensor`,
  `BB.Actuator`, `BB.Controller`, `BB.Estimator`. You write a plain module
  (`use BB.X`; define `init/1` + GenServer-style callbacks + an
  `options_schema` via `Spark.Options`). `bb` wraps it in `BB.<X>.Server`,
  validates options, injects `:bb => %{robot, path}`, and registers it in the
  robot's `Registry` under a `{:via, …}` tuple keyed by its unique DSL name.
  You never write a `child_spec` — `BB.Process.child_spec/6` builds it.
- **Pure-function behaviour** — `BB.IK.Solver` (`solve/5`), `BB.Motion.Tracker`.
  Stateless; invoked per-call (e.g. `BB.Motion.move_to(Robot, link, target,
  solver: BB.IK.DLS)`), not supervised, not DSL-declared. Solver options are an
  untyped keyword list with no schema or validation — defaults are convention
  only, and two solvers already disagree (DLS `max_iterations: 100` vs FABRIK
  `50`).

### Standing vs one-shot

The recurring pair for "run an algorithm against a robot":

- **`BB.Controller`** — long-lived, supervised, robot-level. Usually runs a
  periodic loop (see `bb_pid_controller` and `bb_servo_feetech`'s controller).
  Optional `disarm/1` registers it with `BB.Safety`. **Gotcha:** controllers
  default to
  `simulation: :omit` (`bb/lib/bb/dsl.ex`), so a DSL-declared controller does
  *not* start under simulation unless set to `:mock`/`:start`.
- **`BB.Command`** — short-lived GenServer; `handle_command/3` + `result/1`;
  returns a result and exits. Composable as a `bb_reactor` `command` step
  (`apply(robot, command_name, [goal])`) and as a `bb_jido` action.

Periodic components use **`BB.Loop`** (`bb/lib/bb/loop.ex`) — a struct you embed
in your own state rather than a behaviour or a process, giving a non-drifting
tick, a measured `dt`, and health accounting when the loop falls behind. Clock it
`{:rate, hertz}` to schedule its own ticks, or `:external` to step on message
arrival, which is usually the better choice for a loop fed by a sensor. Every
periodic satellite now uses it; the handful of remaining hand-rolled
`Process.send_after(self(), :tick, ms)` loops predate it and should move across
as they're touched. `robot_opts/0` is an app-bootstrap helper that
`mix bb.add_robot` writes into the host `Application` (carrying `:simulation`),
*not* a component attach point. Core ships actuator command message types
(`BB.Message.Actuator.Command.{Position,Velocity,Effort,Hold,Stop,Trajectory}`).

### What a satellite package looks like

Satellites are near-clones of a shared skeleton. A new one should match:

- **`mix.exs`**: module `BB.<Name>.MixProject`; `{:bb, bb_dep("~> 0.31")}` with
  the standard `bb_dep/1` `BB_VERSION` switch; `elixir: "~> 1.19"`;
  `consolidate_protocols: Mix.env() == :prod`; `elixirc_paths` incl.
  `test/support`; `dialyzer: [plt_add_apps: [:mix]]`. Pin `bb` to whatever
  `bb/mix.exs` currently says rather than to the number written here — a few
  satellites lag a minor version or two and should be bumped as they're touched.
- **Dev/test deps** (`runtime: false`): `credo`, `dialyxir`, `ex_check`,
  `ex_doc`, `git_ops`, `igniter`; `mimic` (`only: :test`) where mocking is
  needed. No `stream_data` — there is no property testing in the ecosystem. No
  `mix_audit` either: its advisory database is a git checkout that drifts out of
  date, and `mix hex.audit` now reports CVEs straight from hex.pm.
- **Quality gate**: `mix check --no-retry` (ex_check); `.check.exs` adds
  `credo --strict` + `hex.audit` + `reuse lint` (+ Spark tools only if the
  package ships a DSL).
- **REUSE/SPDX**: every source file carries an SPDX header (`#`-style for code,
  HTML-comment for `.md`; `Apache-2.0`; year `2026`); binaries/locks/json get a
  `<file>.license` sidecar; `LICENSES/` holds the texts. CI runs `reuse lint`.
  When creating a file, its `SPDX-FileCopyrightText` credits **the user you are
  working for** (name from `git config user.name`, current year) — not the agent
  and not the repo's original author; never copy an existing file's copyright
  line onto a new one. `bb_estimator_ahrs` is mixed-licence (MIT algorithm code,
  Apache-2.0 wrappers), so match the neighbouring files rather than assuming
  `Apache-2.0`.
- **Releases**: conventional commits + `git_ops` auto-bump the version in
  `mix.exs`/README and generate `CHANGELOG.md`; CI publishes to Hex via the
  shared `beam-bots/.github` reusable workflow on push to `main`.
- **Layout**: `lib/<namespace>/`, a `Mix.Tasks.<app>.install` igniter task,
  `test/` mirroring `lib/` with `test/support/`, `AGENTS.md` (+ `CLAUDE.md`
  symlink), `assets/logo.png` (+ `.license`).
- **Errors**: structured `BB.Error` types (Splode); each must
  `defimpl BB.Error.Severity`.

Per-package detail lives in each repo's `AGENTS.md`; the framework's own
conventions (message naming, error classes, DSL) are in `bb/AGENTS.md`.

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
