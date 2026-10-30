---
name: jbootz-crm-web-workflow
description: Use before implementing scoped work in the local Wealthbox crm-web repository when a Docker/dependency preflight or fresh ticket and scope gate is needed; preserve the checkout and personal configuration.
allowed-tools: Read, Bash, Glob, Grep
---

# CRM-web workflow gates

STOP if not currently in the `crm-web` repo.

Use this skill for first slice of CRM-web work:

1. Establish whether current checkout and local runtime are ready.
2. Establish whether requested work is still relevant and bounded.
3. Stop with one actionable blocker when either decision cannot be made.

The workflow audit in docs/crm-web-session-workflow-audit.md is historical evidence. It can explain why these gates exist, but it is not current repository, ticket, PR, or service truth. Read current repository instructions and inspect current branch before relying on any example from that document.

## Boundaries

- Work in the checkout the user placed in scope. A main worktree is valid; do not create or switch worktrees automatically.
- Capture git status --short --branch, the branch, HEAD, and existing worktree changes before any setup. Treat those changes as baseline and preserve them.
- Use repository commands through bin/wealthbox. Never run host bundle, rails, rake, yarn, npm, npx, or Docker Compose commands.
- Do not stage, clean, reset, restore, checkout, amend, commit, push, edit local agent configuration, or run the installer as part of these gates.
- Do not start, stop, or rebuild shared services from a read-only preflight. Report the exact repository command that would unblock the environment instead.
- Do not perform browser QA, GitHub/Linear writes, implementation, or publication here. After both gates are ready, hand off to the relevant implementation or jbootz-crm-web-qa workflow.

## Mode routing

- preflight or no argument: run the environment and dependency preflight below.
- gate CHECKPOINT.json: validate the freshness and scope checkpoint below.
- If the request combines both, run preflight first and do not call the gate ready until current ticket/PR evidence is also captured.

## Preflight

Run one bounded pass and report PREFLIGHT: READY or PREFLIGHT: BLOCKED. Do not retry a failed check speculatively, and report the first actionable blocker rather than hiding it behind later failures.

### 1. Capture checkout and repository guidance

From the CRM-web root, record:

```bash
pwd
git status --short --branch
git branch --show-current
git rev-parse HEAD
git worktree list --porcelain
```

Locate and read the applicable AGENTS.md/CLAUDE.md, then inspect the current command and skill surfaces relevant to the request. At minimum, check bin/wealthbox, bin/\_status, bin/\_pkg_cache, and .agents/skills/; do not assume a command mentioned by the historical audit still exists.

### 2. Inspect services and the Rails URL

Use the wrapper once:

```bash
status_json="$(bin/wealthbox status)"
```

Use jq to verify that the core services required by the requested work are running. For ordinary server-side work, that normally includes rails, db, redis, and opensearch. Resolve the Rails application and health URLs from .services.rails.url and .services.rails.localhost; never guess a port or domain.

Probe resolved Rails health endpoint with curl using the endpoint documented by current repository workflow (currently /healthcheck in the existing CRM-web QA path). If status cannot run, a required service is down, or health fails, return one blocker with the observed detail and the next repository-supported command, usually:

```text
PREFLIGHT: BLOCKED
check: service status | Rails health
reason: <one concrete failure>
next: bin/wealthbox up -d --wait
```

Running bin/wealthbox up -d --wait is a setup action, not part of this read-only gate; only run it when the user has asked for setup or the owning QA/implementation workflow authorizes it. If Docker access is denied, treat that as an environment permission blocker and do not retry the same wrapped command.

### 3. Check dependencies through the wrapper

Run the repository-supported checks that the requested work needs:

```bash
bin/wealthbox exec bundle check
bin/wealthbox exec yarn install --immutable
```

The Yarn command is an immutable lockfile/dependency verification used by the current repository cache workflow. It must not result in a lockfile change. If a check reports missing dependencies or needs network/install work, report that as the blocker and give the exact wrapper command required by the repository instructions; do not substitute a host package manager or blindly retry.

A successful result should include the mode, Rails URL, health result, required service result, and Ruby/JavaScript dependency result. Keep the output concise and reproducible.

## Freshness and scope gate

Do not implement until a current checkpoint exists with exactly these decision fields (arrays may be empty where shown):

```json
{
  "ticket_status": "relevant",
  "base_sha": "<current base commit>",
  "head_sha": "<current HEAD>",
  "related_prs": [],
  "acceptance_criteria": ["<current criterion>", "<current criterion>"],
  "expected_files": ["app/...", "spec/..."],
  "scope_budget": 2,
  "out_of_scope": ["<explicit exclusion>"]
}
```

Validate the checkpoint against live sources and the current checkout:

- ticket_status must be one of relevant, already_addressed, superseded, or ambiguous. Continue only for relevant. Stop immediately for the other three; in particular, do not reproduce or edit work when the exact invariant is already addressed.
- base_sha and head_sha must resolve to commits, base_sha must be an ancestor of head_sha, and head_sha must equal the current git rev-parse HEAD. If the branch moved, refresh the checkpoint instead of proceeding.
- Read acceptance criteria from the current ticket/PR or other current source. The historical audit cannot establish relevance, related PRs, or acceptance criteria.
- expected_files must be unique, repository-relative paths without ..; its count must be no greater than scope_budget. State out_of_scope before implementation.
- Compare git diff --name-only <base_sha>...<head_sha> with expected_files when a committed range exists. Any committed file outside the declaration, or any intended expansion beyond the budget, blocks implementation.
- Compare the checkpoint with the baseline git status captured before setup. Pre-existing uncommitted files are not silently added to scope and are never cleaned or restored.

Report SCOPE GATE: READY with the ticket status, exact base/head, criteria count, expected files, budget, and exclusions. Otherwise report SCOPE GATE: BLOCKED with one reason and the next action: refresh current ticket/PR evidence, update the checkpoint, or reduce the proposed scope.

Once both outputs are ready, preserve the evidence manifest for the implementation and QA handoff. This skill does not authorize changes outside the declared files or any mutation of the personal installer/configuration.
