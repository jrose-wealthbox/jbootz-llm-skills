---
name: jbootz-crm-web-qa-checklist
description: Generate Wealthbox QA plans from a diff, PR, Linear issue, and repository conventions. Use when writing QA steps, updating a PR QA plan, or preparing agent-browser/headless browser QA. Use only when working in `crm-web` repo.
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep
---

# Wealthbox QA Checklist

This skill is the source of truth for generating copy-paste-ready QA plans for the current CRM-web change. Plans must be suitable for execution by `jbootz-crm-web-qa`, `agent-browser`, or a human unfamiliar with CRM-web.

## Inputs

Use these sources in order:

1. the Linear acceptance criteria, if available;
2. the PR description and current PR diff;
3. repository instructions and relevant docs;
4. the existing QA checklist patterns;
5. similar historical PRs, if useful.

Treat the Linear acceptance criteria as an independent product oracle. Do not assume passing tests prove ticket compliance.

## Required preflight section

Every plan must include a concrete `Prerequisites` section containing:

- the exact command to resolve the worktree URL;
- the health-check command, resolved Rails application URL, and exact condition under which `bin/wealthbox up` is required;
- the dependency preflight;
- exact feature-flag setup;
- exact seed-data setup;
- the seeded account/user to use;
- login instructions through `local-account-login`;
- any required role, allowlist, or rollout state.

For local dependencies, use:

```bash
bin/wealthbox exec bundle check
```

If gems are missing:

```bash
bin/wealthbox exec bundle install
```

Never include bare bundle, rails, rake, yarn, npm, npx, or docker compose.

Do not instruct QA to run `bin/wealthbox up` unconditionally. First inspect `bin/wealthbox status` and probe the resolved Rails health endpoint. Run `bin/wealthbox up` only when the health probe fails, status cannot provide a usable URL, or the QA request explicitly requires a restart or rebuild.

If a feature flag or seed command cannot be verified from the repository, say so explicitly and mark the prerequisite as blocked. Do not invent commands.

## Browser-step requirements

Every browser step must identify:

- the exact page or visible label;
- the exact action;
- the expected visible result;
- the prohibited or unexpected result;
- the tool to use: agent-browser or headless Playwright.

Avoid vague steps such as:

- “Open the app.”
- “Verify it works.”
- “Click the button.”
- “Check the result.”

Prefer:

- “Open the resolved worktree URL, sign in through the seeded-user login flow, and confirm the account indicator shows Bill Jones.”
- “Open the seeded Morning Brief QA Generative View and click Help me plan the compliance filing.”
- “Confirm the resulting user-facing message contains the friendly intent and does not contain <artifact_action>, internal IDs, or provider parameters.”

If a browser action times out after navigation, instruct QA to inspect the URL and accessibility snapshot before retrying.

## Terminal verification

For backend or persistence changes, include a <details> block with concrete read-only commands using:

```bash
bin/wealthbox runner
bin/wealthbox psql
```

## Test structure

Use this structure:

**Platforms**: Desktop web, Mobile web, Native/API as applicable

### Prerequisites

- [ ] Exact environment and dependency setup
- [ ] Exact feature-flag and seed-data setup
- [ ] Exact login/account setup

### Test 1: Primary user flow

- [ ] Exact navigation and interaction
- [ ] Exact visible assertion
- [ ] Exact prohibited-content assertion

### Test 2: Regression surface

- [ ] Existing regular AI chat behavior
- [ ] Existing agent or Generative View behavior

### Edge Cases

- [ ] Relevant malformed, legacy, privacy, or failure case

### Persisted/API Verification

- [ ] Exact read-only command
- [ ] Expected field values and invariants

Only include scenarios relevant to the diff, but do not omit cross-surface coverage when shared serializers or message fields are changed.

## Final checklist quality gate

Before publishing the plan:

- every checkbox is executable;
- every feature flag and seed instruction is concrete;
- no credentials are embedded in the plan;
- browser proof and persisted-state proof are clearly separated;
- tests/specs are not proposed as feature/system specs;
- expected user-visible behavior is stated in plain language;
- limitations are explicit;
- screenshots are requested only where they materially help.

## Execution handoff

This skill produces the QA plan; it does not execute environment setup or browser scenarios. For execution, supply the completed plan while loading and applying `jbootz-crm-web-qa` in `run` mode through the harness's normal skill mechanism. Treat the skill name as an instruction source, not a callable function. If the harness cannot load it, return the complete plan for a separate executor rather than implying a silent skill-to-skill call.
