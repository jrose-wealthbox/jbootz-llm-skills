# CRM-web workflow skill handoff

## Purpose

The first workflow slice is intentionally outside the CRM-web repository. It lives in the personal skills repository and teaches the agent to establish:

1. whether the current CRM-web checkout and runtime are ready;
2. whether the current ticket/PR is still relevant; and
3. whether the intended change is bounded before implementation begins.

The source document `docs/crm-web-session-workflow-audit.md` is historical evidence only. Current repository instructions, ticket/PR state, acceptance criteria, and service status are authoritative.

## Current state

### Personal skills repository

- Path: `/Users/john/code/jbootz-llm-skills`
- Branch: `codex/aie-2359-crm-web-workflow`
- Latest commit before this handoff: `38ef1e9` (`Add CRM-web workflow gate skill`)
- Pull request: [jbootz-llm-skills#1](https://github.com/jrose-wealthbox/jbootz-llm-skills/pull/1)
- Intended tracked files:
  - `skills/jbootz-crm-web-workflow/SKILL.md`
  - this handoff document
- Preserve, do not stage: `docs/crm-web-session-workflow-audit.md` (pre-existing untracked historical document)
- Installer and local agent configuration were not changed.

### CRM-web repository

- Path: `/Users/john/code/crm-web`
- Branch: `jrose/skillz-overhaul`
- HEAD: `692ad8c6c7291a3cde9dc9cd309acb7a69ce39e6`
- At the last check, the worktree was clean and HEAD matched `origin/master`.
- No CRM-web files were added, modified, staged, committed, or pushed for this work.

### Linear test issue

- [AIE-2359](https://linear.app/wealthbox-crm/issue/AIE-2359/test-validate-jbootz-crm-web-workflow-gates)
- Project: Agent MVP
- Team: Agentic AI
- It is a disposable validation issue, not a CRM-web product request.
- The issue contains five acceptance criteria for the preflight, freshness/scope fields, rejection conditions, preservation rules, and personal-skill-only implementation scope.
- The PR and validation evidence were added to the issue as a comment.

## Validation already completed

### Personal skill source

Run from `/Users/john/code/jbootz-llm-skills`:

```bash
mise exec -- make test
```

Result: `PASS: installer behavior`.

Ruby 4.0.1/Psych frontmatter validation also passed for `skills/jbootz-crm-web-workflow/SKILL.md`.

The bundled Python validator was not usable because the active Python environment lacks the `yaml` module. No Python dependency was installed.

### CRM-web preflight

Run from `/Users/john/code/crm-web` with host Docker access:

- `bin/wealthbox status`: Docker mode; `rails`, `db`, `redis`, and `opensearch` running.
- Rails health: passed at the wrapper-resolved `http://localhost:3000/healthcheck`.
- `bin/wealthbox exec bundle check): passed.
- `bin/wealthbox exec yarn install --immutable`: exited 0 with existing peer-dependency warnings.
- The wrapper warned that another worktree has different shared Compose configuration; no services were restarted.
- The restricted sandbox could not access OrbStack's Docker socket. The same checks passed after approved host access.

### CRM-web scope exercise

A live checkpoint based on AIE-2359 reached `SCOPE GATE: READY`:

- `ticket_status: relevant`
- `base_sha = head_sha = 692ad8c6c7291a3cde9dc9cd309acb7a69ce39e6`
- five acceptance criteria
- zero CRM-web expected files and zero scope budget
- zero committed CRM-web diff
- current HEAD and ancestry checks passed

This deliberately exercised the positive, zero-CRM-file path. The scope gate is currently prose in the skill, not an executable helper.

## Next session: test from a CRM-web worktree

1. Start the new session with `cwd=/Users/john/.superset/worktrees/crm-web/<name>` or another dedicated CRM-web worktree. A worktree is now preferred for isolation, but the skill must not create or switch one automatically.
2. Capture the branch, HEAD, `git status --short --branch`, and pre-existing changes before setup.
3. Invoke `jbootz-crm-web-workflow` in preflight mode. Use the current worktree's `bin/wealthbox status` URLs and run server-side commands only through `bin/wealthbox`.
4. Invoke the freshness/scope gate using a current ticket/PR checkpoint. For a real CRM-web change, `expected_files` should contain only the intended CRM-web paths and `scope_budget` should be nonzero. Do not list the personal skill file as a CRM-web path.
5. Use AIE-2359 only as a controlled workflow test. For meaningful implementation coverage, use a real current ticket with real acceptance criteria and a current base/head range.
6. If testing a change, preserve unrelated worktree files and verify persisted/runtime behavior separately from the gate evidence.
7. Keep the personal skill source, installer, and local agent configuration outside the CRM-web change set.

## Important guardrails

- Treat stale or ambiguous ticket state as a blocker; do not reproduce or edit an exact invariant that is already addressed.
- Do not infer current truth from the historical audit.
- Do not stage with `git add -A`; stage intended paths explicitly.
- Do not clean, reset, restore, or overwrite pre-existing worktree changes.
- Do not run bare `bundle`, `rails`, `rake`, `yarn`, `npm`, `npx`, or Docker Compose commands in CRM-web.
- The skill does not authorize browser QA, GitHub/Linear writes, implementation, publication, or personal configuration changes.

## Links

- [Personal skill PR](https://github.com/jrose-wealthbox/jbootz-llm-skills/pull/1)
- [Linear test issue AIE-2359](https://linear.app/wealthbox-crm/issue/AIE-2359/test-validate-jbootz-crm-web-workflow-gates)
