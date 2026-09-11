---
name: jbootz-crm-web-qa-checklist
description: Use when writing or revising browser QA plans for a local Wealthbox crm-web change, PR, or Linear issue, including agent-browser or Playwright QA; only in the crm-web repository.
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep
---

# Wealthbox QA Checklist

Source of truth for copy-paste-ready plans runnable by `jbootz-crm-web-qa`, `agent-browser`, or a human unfamiliar with CRM-web.

## Evidence order

Use these sources in order:

1. Linear acceptance criteria, if available;
2. PR description and current diff;
3. repository instructions and relevant docs;
4. existing QA patterns;
5. similar historical PRs, if useful.

Linear acceptance criteria are an independent product oracle; passing tests do not prove ticket compliance.

## Required `Prerequisites`

Every plan must name:

- the exact worktree-URL command;
- the health check, resolved Rails URL, and condition requiring `bin/wealthbox up`;
- dependency, feature-flag, and seed-data setup;
- the seeded account/user and `local-account-login` flow;
- required role, allowlist, or rollout state.

For local Ruby dependencies:

```bash
bin/wealthbox exec bundle check
```

If gems are missing:

```bash
bin/wealthbox exec bundle install
```

Never include bare `bundle`, `rails`, `rake`, `yarn`, `npm`, `npx`, or `docker compose`.

Do not prescribe `bin/wealthbox up` unconditionally. Inspect `bin/wealthbox status` and probe the resolved Rails `/healthcheck`; run `bin/wealthbox up` only when the probe fails, the URL is unavailable, or the request explicitly requires a restart/rebuild.

If a flag or seed command cannot be verified in the repository, mark the prerequisite blocked; never invent commands.

## Browser steps

Each step must state the exact page or visible label, action, expected and prohibited visible results, and tool (`agent-browser` or headless Playwright).

Example:

- Open the resolved URL, sign in through the seeded-user flow, and confirm the account indicator shows Bill Jones; then open `Morning Brief QA Generative View`, click `Help me plan the compliance filing`, and confirm the friendly result contains no `<artifact_action>`, internal IDs, or provider parameters.

After a navigation timeout, inspect the URL and accessibility snapshot before retrying.

## Terminal proof

For backend or persistence changes, include a `<details>` block with concrete read-only commands using:

```bash
bin/wealthbox runner
bin/wealthbox psql
```

## Plan shape

Use this structure, omitting irrelevant surfaces:

**Platforms**: Desktop web, Mobile web, Native/API as applicable

### Prerequisites

- [ ] Exact environment, dependency, flag, seed, and login setup

### Test 1: Primary user flow

- [ ] Exact navigation and interaction
- [ ] Visible expected result and prohibited-content assertion

### Test 2: Regression surface

- [ ] Existing regular AI chat behavior
- [ ] Existing agent or Generative View behavior

### Edge Cases

- [ ] Relevant malformed, legacy, privacy, or failure case

### Persisted/API Verification

- [ ] Exact read-only command, expected fields, and invariants

Include only scenarios relevant to the diff, but retain cross-surface coverage when shared serializers or message fields change.

## Quality gate

Before publishing, verify that:

- every checkbox is executable and flags/seeds are concrete;
- no credentials are embedded;
- browser proof and persisted-state proof are separate;
- tests/specs are not proposed as feature/system specs;
- expected behavior is plain language, limitations are explicit, and screenshots are requested only when useful.

## Execution handoff

This skill generates the plan; it does not execute setup or browser scenarios. For execution, load the plan and apply `jbootz-crm-web-qa` in `run` mode through the harness's normal skill mechanism. Treat skill names as instruction sources, not callable functions. If the mechanism is unavailable, return the complete plan for a separate executor rather than implying a silent handoff.
