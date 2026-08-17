This is the Beam Bots project. Its core library is in the `bb` subfolder, the ecosystem support packages are in the `bb_*` subfolders, and the website is in `website`. All of these live on GitHub in the `beam-bots` organisation. Dependabot and Renovate both raise dependency PRs across the org.

Your job is to sweep those PRs: refresh the workspace, merge everything that is genuinely green, and report on whatever you could not merge. Work autonomously — this prompt is meant to run unattended on a schedule, so never stop to ask a question. If something needs a human decision, leave the PR alone and say so in the report.

## The sweep

1. **Refresh the workspace.** Run `bb-sync` from the workspace root. Don't pass `--fresh` — an unattended run has no business moving branches around. `bb-sync` leaves dirty repos and feature branches alone by design; that's fine, merges happen on the remote regardless.

2. **Enumerate the open PRs from GitHub**, not from the local clone directories. Some org repos are never cloned, and some CI consumers aren't in the org at all:

   ```sh
   gh search prs --owner beam-bots --state open --author app/dependabot --limit 100 \
     --json repository,number,title --jq '.[] | "\(.repository.name)#\(.number) \(.title)"'
   gh search prs --owner beam-bots --state open --author app/renovate --limit 100 \
     --json repository,number,title --jq '.[] | "\(.repository.name)#\(.number) \(.title)"'
   ```

3. **Drop the ones that are out of scope.** Skip `bb_rpc` entirely — it's an archived spike, its PRs are locked, and approving one returns `422 lock prevents review`. Renovate keeps opening PRs against it anyway. Skip anything not authored by `dependabot[bot]` or `renovate[bot]`.

4. **Check each remaining PR** for mergeability and CI:

   ```sh
   gh pr view "$num" -R "beam-bots/$repo" --json mergeable,mergeStateStatus,statusCheckRollup \
     --jq '"m=\(.mergeable) s=\(.mergeStateStatus) bad=" + ([.statusCheckRollup[]?
       | select(.conclusion != "SUCCESS" and .conclusion != "NEUTRAL" and .conclusion != "SKIPPED")
       | "\(.name // .context):\(.conclusion // "RUNNING")"] | join(",")
       | if . == "" then "GREEN" else . end)'
   ```

   A check with an empty `conclusion` is still running, not failing. `mergeStateStatus` is almost always `BLOCKED` and `reviewDecision` almost always `REVIEW_REQUIRED` before you approve — neither is a reason to skip a PR.

5. **Merge the green ones.** Approve first, then merge over the REST API:

   ```sh
   gh pr review "$num" -R "beam-bots/$repo" --approve
   gh api --method PUT "repos/beam-bots/$repo/pulls/$num/merge" \
     -f merge_method=squash -f commit_title="$title (#$num)" -f commit_message=""
   ```

   Always squash, and always set `commit_title` to `<PR title> (#N)` so the default branch keeps its conventional-commit history — `git_ops` reads those commits to work out release versions.

6. **Wait for anything still building.** Poll until the checks settle rather than declaring a PR unmergeable, then merge whatever went green. CI across this org runs for tens of minutes, and `bb`'s subproject matrix is slower still.

7. **Re-enumerate before you finish.** Both bots roll a wave out repo by repo, so the queue is often not empty just because it looked empty a few minutes ago. Merging anything in `beam-bots/.github` guarantees a fresh wave — see below.

8. **Re-run `bb-sync`** so the local clones match, and report.

## Things that will trip you up

- **`gh pr merge` will refuse to merge PRs that are perfectly mergeable.** It reads GitHub's cached `mergeStateStatus`, which stays at `BLOCKED` for several minutes after you approve, and fails with "the base branch policy prohibits the merge". The REST call in step 5 succeeds immediately. Don't go digging through the rulesets when this happens.

- **The repos use rulesets, not classic branch protection**, so `repos/<repo>/branches/main/protection` returns 404. Read `gh api repos/beam-bots/<repo>/rules/branches/main` instead. The usual shape is one required approval plus one required check (`CI / canary`), with `OrganizationAdmin` as an always-bypass actor — which is why approving as James and then merging over REST works.

- **Some red checks are not failures.** `bb` runs downstream canaries for third-party consumers (`bb_mcuhub`, `bb_tui` in the "Test Third-Party" workflow) that are `continue-on-error`. A red job there with a green workflow conclusion does not block the merge. Before you treat one as a regression, compare it against the same job on `main`:

  ```sh
  gh run list -R beam-bots/bb --workflow "Test Third-Party" --branch main --limit 1 --json databaseId
  gh run view <id> -R beam-bots/bb --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
  ```

  If it's already failing on `main`, it's pre-existing and not yours to fix.

- **Several PRs in one repo will conflict with each other.** They each touch `mix.lock`, so the first merge makes the rest dirty. Merge them one at a time and expect `405 Pull Request has merge conflicts` on the later ones. Renovate is configured with `rebaseWhen: behind-base-branch`, so it rebases its own conflicted PRs on the next run and you can leave them. Dependabot needs a nudge: `gh pr comment <n> -R beam-bots/<repo> --body "@dependabot rebase"`. Either way the rebase takes a while — note it in the report and pick it up next run rather than waiting.

- **Merging `beam-bots/.github` starts a whole new wave.** Renovate pins the shared workflows by digest, so every commit on `.github` produces an "update beam-bots/.github digest to `<sha>`" PR in all ~20 consumer repos. If a `.github` PR is in the queue, merge it *first* so the resulting wave lands within the same run; merge it last and you've guaranteed another ~20 PRs after you've finished. Expect the follow-up wave either way, and don't mistake it for something having gone wrong.

## Guardrails

- **Only merge bot-authored dependency PRs.** James's own PRs are out of scope for this sweep, always. He can't approve them with his own token anyway, and merging one would bypass the review requirement entirely — on changes that are often breaking (`improvement!:`). Leave them and list them in the report.
- **Never merge a PR with a failing required check**, and never merge one whose checks you couldn't assess. Report it instead.
- **Never close, reopen, or reconfigure a PR**, and never edit a bot's branch. If a PR looks wrong, say so in the report.
- **Don't touch local working state** — no committing, no pushing, no switching branches, no discarding changes in the clones.
- Green means green regardless of semver: a major bump with passing CI gets merged like anything else. That's the current practice, so flag majors prominently in the report rather than holding them back.

## Report

Finish with a short written report covering:

- what was merged, grouped by repo
- what was skipped and why (conflicts awaiting a rebase, red checks, still building, out of scope)
- any check failure that looked like a real regression rather than a known-flaky canary
- whether a new wave is expected, and roughly how large
- anything about the workspace that needs a human: repos left on feature branches, unpushed commits, dirty trees

Keep it factual and brief. No praise, no filler.

## Scheduling notes

Both bots are on weekly schedules, and Renovate's `github-actions` updates are pinned to a "before 4am" UTC window by the shared config in `beam-bots/.github`. A run shortly after 4am UTC catches a whole wave rather than half of one. A second run some hours later mops up the `.github` digest follow-on and any rebases that were still in flight.
