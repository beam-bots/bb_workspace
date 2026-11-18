<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Starting a new Beam Bots package

What a new package in this ecosystem needs before it can be released, and why
each piece is there. The summary lives in `AGENTS.md` under *What a satellite
package looks like*; this is the long form, written down after two packages
were built outside the skeleton and had to be brought back into it.

**Copy from a neighbour rather than from here.** `bb_sensor_ina219` is the
smallest complete example and the best thing to clone. Several files below are
byte-identical across all 22 repos, and where they are, say so and copy them —
do not retype them.

## Before you start: should this be a package at all?

A new satellite is justified when it supplies an implementation of a `bb`
behaviour that `bb` itself should not carry: a hardware driver, an algorithm
with its own dependencies, a UI, a board support package.

It is *not* justified when what you actually have is a gap in `bb`. The test
is whether the thing you are about to build would make sense in three other
packages. If it would, it belongs in `bb`, and building it here means every
other package eventually grows its own slightly different copy. See *Look for
the precedent before inventing one* in `AGENTS.md`.

## Naming

- Repository and Hex package: `bb_<thing>`, lower snake case —
  `bb_sensor_ina219`, `bb_servo_feetech`, `bb_ik_dls`, `bb_camera_v4l`. The
  prefix after `bb_` groups by role, so a second V4L-ish camera driver would
  be `bb_camera_<something>`.
- Elixir namespace: `BB.<Role>.<Thing>` — `BB.Sensor.INA219`,
  `BB.Camera.V4L`. Not `BBCamera`, and not a top-level name of your own.
- Mix project module: `BB.<Role>.<Thing>.MixProject`.

## The files

Everything below is required unless marked optional. ✓ marks files that are
byte-identical across the ecosystem and should be copied verbatim.

| Path | | |
|---|---|---|
| `mix.exs` | | See below |
| `.check.exs` | ✓ | The quality gate's configuration |
| `.formatter.exs` | | Per-package; include any DSL locals |
| `.github/workflows/ci.yml` | ✓ | Calls the shared reusable workflow |
| `.github/dependabot.yml` | ✓ | Weekly mix + actions updates |
| `renovate.json` + `.license` | ✓ | Two lines; extends the org preset |
| `config/config.exs` | | `git_ops` config; only `repository_url` differs |
| `CHANGELOG.md` | | The starter, with the `<!-- changelog -->` marker |
| `README.md` | | See *The README header* below |
| `AGENTS.md` + `CLAUDE.md` symlink | | `ln -s AGENTS.md CLAUDE.md` |
| `usage-rules.md` | | See *usage-rules.md* below |
| `LICENSES/Apache-2.0.txt` | ✓ | |
| `LICENSES/LicenseRef-Beam-Bots-Logo.txt` | ✓ | Needed by the logo |
| `assets/logo.png` + `.license` | ✓ | The organisation's logo, not yours |
| `documentation/` | | Optional; tutorials and how-tos for ex_doc |
| `test/support/` | | Test robots and doubles |

### `mix.exs`

```elixir
defmodule BB.Sensor.Thing.MixProject do
  use Mix.Project

  @moduledoc """
  One sentence. This is the Hex description, so write it for a stranger.
  """

  @version "0.1.0"

  def project do
    [
      aliases: aliases(),
      app: :bb_sensor_thing,
      consolidate_protocols: Mix.env() == :prod,
      deps: deps(),
      description: @moduledoc,
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end
```

- `dialyzer: [plt_add_apps: [:mix]]`.
- `elixirc_paths/1` adds `test/support` in `:dev` and `:test`.
- `package/0`: `files:` listing `lib`, `.formatter.exs`, `mix.exs`, `README*`,
  `CHANGELOG*`, `LICENSE*`, `usage-rules.md` (plus `priv` if you ship any);
  `maintainers`; `licenses: ["Apache-2.0"]`; `links` with Source and Sponsor.
  Note that `documentation/` is deliberately *not* shipped in the tarball —
  hexdocs is built separately by CI.
- `docs/0`: `main: "readme"`, `logo: "assets/logo.png"`, extras globbing
  `documentation/**/*.{md,livemd,cheatmd}`, `source_ref: "main"`.

### Depending on `bb`, and on siblings

Never a bare path dependency. The `BB_VERSION` switch is what lets the
workspace build every package against local checkouts while Hex and CI build
against releases:

```elixir
defp bb_dep(default, package \\ :bb) do
  case System.get_env("BB_VERSION") do
    nil -> default
    "local" -> [path: "../#{package}", override: true]
    "main" -> [git: "https://github.com/beam-bots/#{package}.git", override: true]
    version -> "~> #{version}"
  end
end

defp deps do
  [
    {:bb, bb_dep("~> 0.33")},
    {:bb_camera, bb_dep("~> 0.1", :bb_camera)},
    ...
  ]
end
```

Take the one-argument form if you depend only on `bb`; take the two-argument
form the moment you depend on a sibling. Two consequences worth knowing:

- **CI sets no `BB_VERSION`**, so it resolves from Hex. A package that depends
  on an unpublished sibling cannot have a green build until that sibling is
  published. Publish in dependency order.
- A numeric `BB_VERSION` applies the same constraint to *every* package, which
  is wrong for siblings at different versions. Only unset, `local` and `main`
  are sound once you have sibling dependencies.

### Dev and test dependencies

`runtime: false`, `only: [:dev, :test]`: `credo`, `dialyxir`, `ex_check`,
`ex_doc`, `git_ops`, `igniter`. `mimic` (`only: :test`) where you need mocking,
`usage_rules` (`only: [:dev]`).

Not `stream_data` — there is no property testing here. Not `mix_audit` — its
advisory database is a git checkout that drifts, and `mix hex.audit` reports
CVEs from hex.pm instead.

### The README header

Every package opens the same way, below the SPDX comment: the logo, the title,
then six badges in this order — CI, licence, Hex version, Hexdocs, REUSE
status, Ask DeepWiki. Only the repository name varies.

```markdown
<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# bb_sensor_thing

[![CI](https://github.com/beam-bots/bb_sensor_thing/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_sensor_thing/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Hex version badge](https://img.shields.io/hexpm/v/bb_sensor_thing.svg)](https://hex.pm/packages/bb_sensor_thing)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/bb_sensor_thing)
[![REUSE status](https://api.reuse.software/badge/github.com/beam-bots/bb_sensor_thing)](https://api.reuse.software/info/github.com/beam-bots/bb_sensor_thing)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/beam-bots/bb_sensor_thing)
```

Below that, there is no house structure — packages range from two sections to
eleven. Write what the package needs.

### `usage-rules.md`

Consumed by coding agents through `mix usage_rules.sync <file> <pkg>:all`, so
it is read by something that will act on it without asking. The house shape:

1. An opening paragraph saying what the package is, pointing at `bb`'s own
   rules, and scoping this file to what is specific here.
2. **Core principles** — numbered, the invariants somebody will otherwise
   violate.
3. **Wiring it in** — a DSL snippet showing the component declared in a robot.
4. **Options** — a table, or the sections the options group into.
5. **Anti-patterns** — the mistakes, each with the consequence.
6. **Further reading** — hexdocs, and the modules worth reading.

The test of a good one is whether it says things the README does not. A
restatement of the README is worse than nothing, because it is one more file
to keep true. Write down the gotchas, the invariants and the calling shapes.

### `AGENTS.md`

Package-specific guidance: the architecture, the things that are easy to get
wrong, the design decisions worth not re-litigating, and the testing notes.
`CLAUDE.md` is a symlink to it (`ln -s AGENTS.md CLAUDE.md`) — note that
editing tools may need to be pointed at `AGENTS.md` directly.

Record *why* a decision was made, especially where it looks wrong from
outside. A decision with its reasoning attached does not get reverted by the
next person through.

## Licensing

Every file carries an SPDX header — `#` comments for code, an HTML comment for
Markdown, a `<file>.license` sidecar for anything that cannot hold a comment
(binaries, lockfiles, JSON). `reuse lint` runs in `mix check` and in CI, and
fails the build on a missing one.

A new file credits **the person the work is for**, from `git config user.name`
and the current year — not the agent that wrote it, and not whoever wrote the
file it was copied from. Never copy an existing file's copyright line onto a
new file.

`bb_estimator_ahrs` is mixed-licence (MIT algorithm code, Apache-2.0
wrappers), so match the neighbouring files rather than assuming.

## Testing

Event-driven, never timed. No `Process.sleep/1`, no test double that takes
300ms, no `refute_receive` standing in for "it didn't happen". The full rules
are in `AGENTS.md` under *Tests are event-driven, never timed* — read them
before writing the first test, because retrofitting is painful.

Two habits worth building in from the start:

- **Give periodic code an external clock.** A component clocked
  `{:rate, hertz}` in production should accept `:external` so tests step it
  deliberately. `BB.Camera.Synthetic` and `BB.Camera.Hub` both do this.
- **Test the second time through.** Every correctness bug found in the camera
  review appeared only on a *second* pass through a lifecycle — a second
  capture session, a restarted dependency, a refused change. First-pass tests
  pass and prove less than they look like they prove.

## The quality gate

`mix check --no-retry` is the gate — never the individual tools. It runs
compile, test, format, `credo --strict`, dialyzer, `reuse lint` and
`hex.audit`. Add the Spark tools to `.check.exs` only if the package ships a
DSL.

In the workspace, run it with `BB_VERSION=local`. `bb-check` does this across
every package at once.

## Releasing

1. Conventional commits throughout — `git_ops` reads them.
2. `mix git_ops.release` bumps the version in `mix.exs` and the README,
   writes `CHANGELOG.md` and tags `vX.Y.Z`.
3. Push the tag. The shared workflow publishes to Hex on a `v*` tag and
   deploys docs from the default branch.

`HEX_API_KEY` has to be reachable by the repository. The `beam-bots/.github`
repository holds the reusable workflow, the renovate preset and the ruleset
sync, so a new repository needs to exist in that organisation to inherit them.

## Adding it to the workspace

`bin/bb-sync` discovers `beam-bots/*` through the GitHub API, so a package is
picked up automatically once the repository exists. Add a row to the package
roles table in `AGENTS.md` so the next person knows what it is for.
