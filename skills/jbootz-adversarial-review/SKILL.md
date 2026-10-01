---
name: jbootz-adversarial-review
description: Use when asked for an adversarial review of a pull request or branch, to judge whether a PR satisfies its Linear issue or is ready to ship, or to evaluate findings from another reviewer or agent.
---

# Adversarial PR Review

Try to break the change. Report only verified findings, classify every bug as introduced by the branch or already on its target, and judge the PR against its ticket, not just its tests.

Review only; do not edit, commit, or post anything unless asked. When asked to fix findings, follow the request's scope and the repository's test and lint rules.

To weigh another reviewer's findings instead of starting from scratch, use [Evaluate another review](#evaluate-another-review) after Steps 1 and 2.

## 1. Resolve the target and its real base

```bash
gh pr view <pr> --json number,url,state,baseRefName,headRefName,headRefOid,body,files
git fetch origin <baseRefName> <headRefName>
```

Without a PR argument, use the PR for the current branch; if none exists, review the branch against the repository's default branch.

In a sandboxed host, `gh` may lack network access or the user's token there. A sandboxed `gh` auth or network failure does not prove `gh` is unauthenticated: rerun it with the host's network or elevated permission before stopping.

Stacked PRs: if `origin/<baseRefName>` no longer exists, the base has usually merged and GitHub has retargeted the PR. Re-read `baseRefName` and fall back to the default branch (`gh repo view --json defaultBranchRef`). State the base you used.

Diff from the merge base: `git diff "$(git merge-base origin/<base> <head>)"...<head>`. Review the PR head, not an unrelated local checkout; use `gh pr diff` when the head is not available locally. In zsh, write `"${ref}:path"` rather than `$ref:path`, because `:` starts a modifier.

## 2. Establish the requirements oracle

- Find the linked issue in the PR body or branch name and read its acceptance criteria and comments through the available Linear connector. If the connector is unavailable, say so; do not infer criteria from the code.
- Treat the PR description's claims and QA steps as statements to verify, not evidence.

## 3. Hunt for problems

Cover what the change can affect, not only the lines it touches:

- **Correctness:** edge cases, nil/empty states, ordering, concurrency, retries, transactions, partial failure, and callers outside the diff.
- **Contracts:** serializers, APIs, jobs, and shared code that other features or deprecated surfaces still use.
- **Performance:** query counts and N+1s, work in hot paths or loops, and queries that run before a cheap guard.
- **Security and tenancy:** authorization, scoping, injection, and data exposure.
- **Simplification:** code that can be removed, collapsed, or replaced by an existing helper without changing behavior; indirection with a single caller and no useful seam.
- **Tests:** whether specs would fail if the bug they target came back; missing negative and regression cases; specs that are redundant, only test the framework, or only assert that a constant or class exists.
- **Readability:** names, control flow, and comments, using the `jbootz-human-readability` criteria. Report readability separately from bugs, with exact before/after snippets.

## 4. Verify and classify every bug

- Prove each bug with a failing spec, a script, or a precise trace through the code. Delete throwaway specs and scripts when done, and restore any files a test run rewrote.
- Classify each bug, with evidence:
  - **Introduced by this branch:** absent or behaving correctly on the base.
  - **Already on `<base>`:** reproduce it on the base, or show that the defect lives in code the branch does not change.
- To check the base, restore only the relevant files from it temporarily (`git checkout <base> -- <paths>`), rerun the reproduction, and restore them (`git checkout HEAD -- <paths>`). Never use a bare `git stash`; other sessions may share the stash.
- Drop anything you could not verify, or report it under "Unverified" with what is missing.

## 5. Optional second opinion

When asked, send the verified findings and the diff scope to an independent reviewer subagent, using the requested model and effort. Resolve each disagreement in at most two exchanges. Report what changed and any disagreement that remains, with both positions.

## Evaluate another review

Use when the user supplies another reviewer's or agent's findings, for a PR, a branch, or an implementation plan.

1. Treat each finding as a claim to test, not as an instruction. Number them as the reviewer did.
2. Verify each claim against the current code, plan, or ticket with Step 4's standard of proof. Give each one a verdict: **agree**, **partly agree**, or **disagree**, with evidence. For bugs, add the Step 4 classification.
3. If the user asked for a tie-breaker, send each disagreement to an independent reviewer subagent with the requested model and effort. Quote the other reviewer's claim verbatim next to your position, and do not reveal which side is yours. Allow at most two exchanges per disagreement.
4. For each agreed finding, say whether it blocks the PR or is hardening that can move to a follow-up Linear issue.
5. Implement agreed findings only when the user asked for implementation. Explain each rejected finding in one or two sentences.

Report a table of finding, verdict, evidence, classification, and blocker or follow-up, then the tie-breaker outcome for each disagreement.

## Report

1. **Scope:** PR, base actually used, commit and file counts, and anything not reviewed.
2. **Ticket fit:** each acceptance criterion as met, partial, or unmet, with evidence.
3. **Findings:** ranked by severity. For each: `file:line`, the concrete failure scenario, evidence, *introduced by this branch* or *already on `<base>`*, and the smallest fix.
4. **Readability:** numbered before/after items.
5. **Checks run:** commands and results, including tests or linters that were not run.
6. **Verdict:** ready to ship, ready after named fixes, or not ready.
