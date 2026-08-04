<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Plan: Proposal 0022 — Multi-DoF Joints

**Started:** 2026-08-04
**Proposal:** `proposals/accepted/0022-multi-dof-joints.md`
**Branch (all repos):** `multi-dof-joints`

## Decisions taken

| Question | Decision |
|---|---|
| Scope of first branch | All five pieces together, one coordinated branch per repo |
| Proposal Open Q3 — 2D transform name | `BB.Math.Transform2D` |
| Proposal Open Q4 — `parent_joint/2` root case | `{:error, %NoParentJoint{}}` |
| Proposal Open Q1 — how much of `defn.ex` changes | More than `chain_tensors/3`: the kernel takes per-joint motion matrices. See "Kernel refactor" below |
| Proposal Open Q2 — floating Jacobian frame | Joint-local (body) frame, because `grad` at `δ = 0` produces it with no special-casing |
| `Twist2D` / `Wrench2D` module placement | `BB.Message.Geometry.*`, matching their 3D siblings (their 3D counterparts are message payloads, not `BB.Math` values) |
| `child_joints/2` (not in the proposal) | Converts to a result tuple too — it calls both converted lookups, and returning `[]` for a missing link preserves the conflation the change removes |
| `BB.Robot.Runtime.positions/1` (not in the proposal) | Renamed to `configurations/1`, applying the proposal's own "position is the wrong word for a 4x4" argument one layer up. `velocities/1` keeps its name |
| In-plane basis for a tilted `:planar` normal | Derived from the least-aligned cardinal axis; `{0,0,1}` reduces to `u == x̂`, `v == ŷ`. **Open:** whether the DSL should let a user name the in-plane reference direction |

## Measured surface

**First pass was wrong and much too high.** Raw `git grep` substring counts
include docs, prose mentions, and several matches per expression, so they
overstate the work by roughly 3x. Real call sites, counted as
`\b(name)\(` in `bb`:

| Symbol group | `lib` sites | `test` sites |
|---|---|---|
| `get_link` / `get_joint` / `parent_joint` / `path_to` / `actuator_path` / `depth_of` / `child_joints` | 36 (17 of them the definitions and docs in `robot.ex`) | 29 |
| State accessors (`get_all_positions` etc.) | 17 | 22 |

Actual work done for pieces 3 and 4 in `bb`: **6 lib files** and **6 test
files**, plus 2 documentation files. Not the 96 `get_link` hits the substring
count suggested.

### Satellite surface — measured 2026-08-04

Counted as real call sites (`\b(name)\(`) in `lib/` and `test/`, not substrings.
**214 sites across 15 repos**, and the shape matters more than the total: two
repos carry the genuine work and thirteen are mechanical.

| Repo | Lookups + state | Solver + motion | `JointState` | Total |
|---|---|---|---|---|
| `bb_ik_fabrik` | 16 | 47 | 0 | **63** |
| `bb_ik_dls` | 6 | 46 | 0 | **52** |
| `bb_pid_controller` | 0 | 0 | 19 | 19 |
| `bb_jido` | 1 | 0 | 12 | 13 |
| `bb_kino` | 0 | 0 | 13 | 13 |
| `bb_reactor` | 0 | 0 | 12 | 12 |
| `bb_example_so101` | 2 | 8 | 0 | 10 |
| `bb_liveview` | 0 | 0 | 6 | 6 |
| `bb_servo_feetech` | 0 | 0 | 6 | 6 |
| `bb_servo_pca9685` | 2 | 0 | 3 | 5 |
| `bb_example_wx200` | 0 | 5 | 0 | 5 |
| `bb_mcp` | 3 | 0 | 1 | 4 |
| `bb_servo_robotis` | 0 | 0 | 4 | 4 |
| `bb_policy` | 1 | 0 | 0 | 1 |
| `bb_servo_pigpio` | 0 | 0 | 1 | 1 |

The `JointState` columns are almost entirely type specs and docs — those consumers
only ever see single-DoF joints, so their runtime behaviour is unchanged. The real
work is the two solvers.

## Kernel refactor — resolves Open Questions 1 and 2

The proposal's Option C says multi-DoF joints expand "to the vectorised scalar
form *only* inside `chain_tensors/3`". Taken literally that is wrong, and it
reintroduces exactly what Option B was rejected for.

`Defn.fk_chain/6` derives each joint's motion matrix from a *scalar* via
`build_motions/4` (Rodrigues about `axes[i]`, or translation along it). To feed it
six scalars for a floating joint you must decompose the stored rotation into three
angles about three axes — an Euler decomposition. That is lossy, non-unique, and
gimbal-locked, which is the Option B objection resurfacing at the kernel boundary.

So the kernel changes:

**Forward kinematics.** `build_motions` stops being the only source of motion
matrices. The chain passes `{n_joints, 4, 4}` motion matrices directly; single-DoF
joints compute theirs from `q` as now, a floating joint supplies its stored
`Transform` verbatim, and a planar joint supplies `Transform2D.to_transform/2` of
its configuration. FK is then bit-exact for multi-DoF joints — no decomposition
anywhere.

**Jacobian.** `position_jacobian` differentiates via `grad` over the positions
vector, so multi-DoF columns need a differentiable parameterisation.

**Spiked and confirmed 2026-08-04.** The first attempt used `M_stored · exp(δ)`
with a proper `se(3)` exponential, and it failed: `b = (1 - cos θ)/θ²` is a
literal `0/0` at `δ = 0`, so three of six gradient components came back `:nan`.
Regularising the denominator would work but is unnecessary, because **δ is only
ever evaluated at zero**. So the parameterisation is *first order*:

    Motion_j = ScalarMotion_j(q_j) · Stored_j · (I + hat(δ_j))

- At `δ = 0` the factor is **exactly** the identity — bit-exact, no `sin`/`cos`,
  so FK for a multi-DoF joint is the stored transform verbatim.
- `exp(δ) = I + hat(δ) + O(δ²)`, so the *derivative at zero* is identical to the
  exponential's. Higher-order terms are irrelevant because they are never
  evaluated.
- No gimbal lock: δ never leaves zero, so an Euler chart's singularities are
  never visited.
- No `while` and no integer tensor indexing, which is what `Defn`'s two existing
  `grad` warnings are about — so neither pitfall is triggered.

Verified against finite differences of the **true** rigid motion (real
`Transform.from_axis_angle` / `translation` perturbations, not of the
linearisation): max error `2.1e-10`, i.e. finite-difference truncation noise.

This also settles Open Question 2: the columns are derivatives with respect to
perturbations in the **joint's local frame**, expressed in the base frame. If
`bb_ik_dls` wants base-frame perturbations instead, that is a rotation applied
afterwards, not a change of parameterisation.

The unified form means single-DoF joints need no special case: their `Stored_j`
is the identity and their `δ_j` is zero, so `Motion_j` reduces to exactly what it
is today. A multi-DoF joint carries `is_revolute = is_prismatic = 0`, so its
`ScalarMotion_j` is the identity and `Motion_j` reduces to `Stored_j`.

**`link_transforms/7` needs the same treatment.** The proposal's file list misses
it. It is used by `all_link_transforms/2`, carries one scalar per *link* (that
link's parent joint), and has the identical single-DoF assumption.

The concatenated parameter vector is `[q for each single-DoF joint..., δ for each
multi-DoF joint...]` in chain order, which is what makes Jacobian width the sum of
DoF along the chain.

## Work breakdown

Order is dependency order. Everything lands on one branch per repo.

### 1. `bb` — 2D value types
- [ ] `BB.Math.Transform2D` — `x`, `y`, `theta` plain floats; `new/3`,
      `identity/0`, `compose/2`, `inverse/1`, `to_transform/2`
- [ ] `BB.Message.Geometry.Twist2D` — `vx`, `vy`, `omega`
- [ ] `BB.Message.Geometry.Wrench2D` — `fx`, `fy`, `tau`
- [ ] Tests, including `Transform2D`/`Transform` agreement via `to_transform/2`

### 2. `bb` — error types
- [ ] `BB.Error.Kinematics.UnknownJoint` — `[:joint, :robot]`
- [ ] `BB.Error.Kinematics.UnknownActuator` — `[:actuator, :robot]`
- [ ] `BB.Error.Kinematics.NoParentJoint` — `[:link]`
- [ ] `BB.Error.Kinematics.NotAnAncestor` — `[:source_link, :target_link, :common_ancestor]`
- [ ] `BB.Error.Kinematics.UnknownLink` — `:target_link` → `:link`, add `:role`
- [ ] `BB.Error.Severity` impls for all new types

### 3. `bb` — topology and introspection
- [ ] `BB.Robot.root_link/1`
- [ ] `BB.Robot.Topology.path_between/3` + `BB.Robot.path_between/3`, ancestor-only
- [ ] nil → result tuples: `get_link/2`, `get_joint/2`, `parent_joint/2`,
      `path_to/2`, `actuator_path/2`, `Topology.path_to/2`, `Topology.depth_of/2`
- [ ] `child_joints/2` — currently swallows a missing link into `[]`; decide
      whether it converts too (not in the proposal's table)
- [ ] Fix all in-repo callers (96 `get_link` hits in `bb` alone)

### 4. `bb` — state
- [ ] Multi-DoF configuration storage in ETS: raw `Nx.to_binary/1` bytes for
      floating, tuple for planar, bare float for single-DoF
- [ ] Rename: `get_all_configurations/1`, `set_configurations/2`,
      `get_chain_configurations/2`, `get_configuration/2`, `set_configuration/3`
- [ ] Delete the old names — no shims
- [ ] `set_configuration/3` shape validation against joint type →
      `BB.Error.Invalid.JointConfig` with `:expected` populated
- [ ] Velocity accessors follow the same rename/retype

### 5. `bb` — kinematics — **done**
- [x] `compute_joint_transform/3` handles `:planar` and `:floating`
- [x] `chain_tensors/3` supplies `stored` motion matrices and zero `deltas`
- [x] `Defn.fk_chain/8` takes `stored` and `deltas`
- [x] `Defn.position_jacobian/8` + new `position_jacobian_deltas/8`
- [x] `Defn.orientation_jacobian/8` + new `orientation_jacobian_deltas/8`,
      sharing one chain walk via `orientation_frames/8`
- [x] `Defn.link_transforms/9` — same treatment
- [x] `assemble_columns/5` replaces `select_columns/3`: per-DoF columns, with
      multi-DoF blocks projected through `dof_basis/1`
- [x] `BB.Robot.Joint.dof/1`
- [x] `BB.Robot.Kinematics.jacobian_columns/2` so a solver can map a column back
      to its joint and degree of freedom
- [x] `BB.Math.Transform2D.plane_basis/1` made public — the Jacobian's planar
      columns must use the same basis `to_transform/2` lifts through, and the two
      disagreeing would be a silently wrong derivative

**Also changed, not in the proposal:** naming a joint the robot does not have in
`joint_names` used to yield one zero column, silently swallowing a typo. It
cannot survive per-DoF columns anyway — there is no way to know how wide a
nonexistent joint should be — so it now raises `UnknownJoint`, matching
`forward_kinematics/3`'s existing behaviour for an unknown link.

**`Enum.map/2` cannot be called inside `defn`**, so the three coordinate grads
are written out rather than mapped, as the original code did.

### 6. `bb` — messages — **done**
- [x] `JointState` carries type-appropriate values in all three of `positions`,
      `velocities` and `efforts`
- [x] Schema types widen from `{:list, :float}` to new `BB.Message.Option`
      custom types — `configurations_type/0`, `velocities_type/0`,
      `efforts_type/0`

**Resolves the plan's open question on validation.** Widening to an untyped list
would have lost the only thing rejecting garbage. The custom types check each
element is one of the three shapes that joint type admits, and name the offending
index — which matters because the lists run parallel to `names`, so "element 4 is
wrong" is the difference between finding the bad joint and eyeballing a list of
transforms. What a message *cannot* check is whether a value matches a
*particular* joint's type: that needs the robot, which the message does not carry.
`BB.Robot.State.set_configuration/3` is what enforces that.

### 7. `bb` — motion + solver behaviour
- [ ] `BB.IK.Solver.solve/6` with `source_link`; `solve/5` removed
- [ ] `BB.Motion.move_to/4`, `move_to_multi/4`, `solve_only*` require
      `:source_link` with no default
- [ ] Update ~34 `BB.Motion` references in `bb` including doc examples

### 8. `bb` — DSL — **done**
- [x] Reject `axis` on `:floating`; require it on `:planar`
- [x] Joint entity docs for both `axis` and `type`

**Not a new verifier.** Two discoveries redirected this. Spark *verifier* errors
surface as warnings rather than raising for modules defined at runtime inside a
test, so `assert_raise` cannot catch them. And `BB.Dsl.TopologyTransformer`
already owns axis-vs-joint-type validation — it has the fixed-joint axis rule and
a `limit`-required-per-type rule, which is the exact precedent. So both rules went
there: no new module, no duplicated topology walk.

**Fixed a pre-existing bug found on the way.** The fixed-joint axis rule built its
error with `module:` where `message:` was meant — a duplicate key, so the later
one won and the diagnostic printed as `nil`. Now covered by a test asserting the
message reads.

**Deviation raised and reversed.** Requiring `axis` on `:planar` contradicts an
existing test named "planar joint with optional axis compiles", and `Kinematics`
already reads `joint.axis || {0.0, 0.0, 1.0}` so an omitted axis already meant the
horizontal plane. Raised it; the decision was to require it as the proposal
specifies. The existing fixture and test were updated.

### 9. Satellites — solvers done

**`bb_ik_dls` — done.** `solve/6`, chain from `path_between/3`, and the real work:
`apply_update/4` zips the delta against `jacobian_columns/2` rather than
`joint_names`, groups per-DoF deltas by joint, and applies a multi-DoF joint's
components as one rigid motion composed on the right — the same side the kernel
places the perturbation. Limit clamping skips multi-DoF joints. Tests prove
*convergence*: a 2m target with a 0.5m arm on a planar base, and a 3D target
through a floating base.

**`bb_ik_fabrik` — done.** Refuses `:planar`/`:floating` chains with a new
`BB.Error.Kinematics.FABRIK.UnsupportedJoint` naming the joint, its degrees of
freedom, and both remedies. The same robot it refuses root-to-tip, it solves when
scoped below the base — which is the whole argument for `source_link`.

**Two pre-existing bugs fixed, one filed.**

- Both trackers' `get_current_positions/1` indexed `robot.joints` with a *link*
  name, so both always returned `%{}` and `last_positions` was permanently empty.
  Both were reimplementing `get_all_configurations/1`; both deleted.
- `clamp_to_joint/2`'s `nil` clause became unreachable once `get_joint/2` returned
  a result tuple. Dialyzer caught it; removed rather than suppressed.
- **Filed as `bb_ik_fabrik` issue 85:** `solve/6` hardcodes `reached: true`
  whenever the internal loop converges, never comparing the residual it then
  computes against the tolerance. Reproduces on `main` with an all-revolute robot
  at 923x the requested tolerance. Predates this work entirely; not fixed here.

### 9b. Remaining satellites
- [ ] `bb_ik_dls` — `solve/6`, `path_between/3`, apply deltas via configuration
      API, solve chains containing multi-DoF joints, `:source_link` in
      `BB.IK.DLS.Motion`
- [ ] `bb_ik_fabrik` — `solve/6`, `path_between/3`, error clearly on a multi-DoF
      joint in the chain, `:source_link` in `BB.IK.FABRIK.Motion`
- [ ] `JointState` consumers: `bb_jido`, `bb_kino`, `bb_liveview`, `bb_mcp`,
      `bb_pid_controller`, `bb_reactor`, `bb_servo_feetech`, `bb_servo_pca9685`,
      `bb_servo_pigpio`, `bb_servo_robotis`
- [ ] `bb_policy`, `bb_example_so101`, `bb_example_wx200`, `bb_examples` — state
      API rename and `:source_link`

### 10. Verification
- [ ] FK against independently derived poses — hand-computed, plus one
      non-trivial chain cross-checked against a known-good external
      implementation. Not a round-trip through our own code
- [ ] Jacobian against finite differences of FK
- [ ] Composition-order tests where floating and revolute do not commute
- [ ] `:planar` with a non-Z surface normal
- [ ] Bit-exact ETS round-trip for a floating configuration
- [ ] Regression: fixed-base arm kinematics numerically unchanged
- [x] `mix check --no-retry` green in `bb`, `bb_ik_dls`, `bb_ik_fabrik`
- [ ] `BB_VERSION=local ./bin/bb-check` across the workspace

**Per-repo `mix check` is not a substitute for `bb-check`, and treating it as one
was a gap.** Running `mix test` in the mechanically-swept repos left dialyzer,
credo and `reuse lint` unrun in all of them, and left the repos that needed *no*
source change entirely unverified — which are precisely the ones where a
`JointState` pattern match or a `[float]` spec could break without anything in the
diff pointing at it. `bb-check` is also the only thing that drops the stale
`.plt.hash` files, without which dialyxir silently checks against a PLT predating
the newest `bb` exports.

## Risks

1. **`grad` through the new parameterisation.** `Defn` already carries two
   comments about `grad` misbehaving — it "misroutes through a `while` that
   dynamically gathers `mats[i]`", and "mishandles range/integer tensor
   indexing". Injecting `exp(δ)` risks tripping the same edges. Mitigation: the
   finite-difference check is the oracle, and `chain_product` is already unrolled
   at trace time for this reason.

2. **Nothing compiles until most of it does.** One branch across 15 repos with
   `BB_VERSION=local` means the workspace is red for the duration. Mitigation:
   land `bb` internally consistent first, then sweep satellites; keep `bb`'s own
   `mix check` green at each commit.

3. **`JointState` value types are unvalidated in practice.** Widening the schema
   from `{:list, :float}` loses the only thing currently rejecting garbage. The
   list is heterogeneous by joint type, so validating it properly needs the
   robot's joint types, which the message does not carry. Open — see below.

4. **Nested message payloads.** `BB.Message.Geometry.Twist` is itself a
   `use BB.Message` payload type; embedding it inside `JointState` nests one
   payload in another. It works, but it is a new pattern in this codebase.

5. **`bb_ik_fabrik` has no meaningful multi-DoF behaviour.** It can only refuse.
   Its 48 `get_link` hits still all have to change for the result-tuple sweep,
   so it pays full migration cost for no new capability.

6. ~~**`set_configuration/3` now rejects fixed joints.**~~ **Resolved — was a
   defect, now fixed.** Rejecting fixed joints outright broke read-modify-write:
   `get_all_configurations/1` includes fixed joints as `0.0`, and handing that
   map straight back to `set_configurations/2` failed on any robot with a fixed
   joint. A fixed joint's configuration space is a single point, so that point is
   assignable: `0.0` is accepted, anything else — a nonzero angle, a `Transform`
   — is still rejected. Forward kinematics ignores the value regardless, since
   both motion masks are zero. Covered by round-trip tests over all three
   fixture robots, which is the test that should have existed first.

7. **Underestimated blast radius.** Now corrected downward — see "Measured
   surface". Pieces 3 and 4 came to 6 lib files in `bb`, not the ~100 call sites
   first reported. Pieces 6 and 9 are still unmeasured and are the remaining
   bulk; neither is required by multi-DoF joints.

## Unknowns to resolve during implementation

- **`JointState` validation.** Widened lists admit anything. Options: a custom
  Spark.Options type accepting `float | Transform | Transform2D` per position and
  the matching velocity/effort types; or accept that the message is unvalidated
  and rely on producers. Needs a decision before piece 6.
- **Whether `child_joints/2` converts.** Not in the proposal. It currently
  returns `[]` for a missing link, conflating "no children" with "no such link".
- **Whether `Transform2D` needs `from_transform/2`.** The proposal only specifies
  `to_transform/2`. Projecting a 3D transform back into a plane is lossy and may
  not be wanted at all.
- **Base-frame vs local-frame Jacobian columns for DLS.** Local falls out of the
  parameterisation; whether DLS needs them rotated into the base frame is
  determined by making DLS converge. `jacobian_columns/2` gives DLS the
  `{joint, dof}` per column, which is what it needs to apply a delta at all.

- **`:planar` in-plane reference direction.** `Transform2D.plane_basis/1` derives
  the in-plane axes from the least-aligned cardinal axis, so a tilted normal gets
  a deterministic but arbitrary `x` direction. If the DSL should let a user name
  it, that is a joint-entity addition and wants deciding before anyone builds a
  tilted-plane robot.
