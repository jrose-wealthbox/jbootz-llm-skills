---
name: jbootz-crm-web-qa
description: Route Wealthbox crm-web QA planning through jbootz-crm-web-qa-checklist and execute complete plans using agent-browser, with explicit dependency, runtime, feature-flag, seed-data, login, and persisted-state verification. Use for local CRM-web QA, AI-agent QA, Generative Views, artifact actions, and PR validation. Use ONLY when working in `crm-web` repo.
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep, Task
---

# Wealthbox QA

Consume and execute a complete QA plan for the current CRM-web branch. `jbootz-crm-web-qa-checklist` is the source of truth for generating or repairing that plan.

## Mode routing

- `plan` or no argument: apply `jbootz-crm-web-qa-checklist` to generate the plan, then stop without executing it.
- `run` with an existing complete plan: preserve the plan unchanged and execute it.
- `run` with an incomplete plan: preserve its correct content, apply `jbootz-crm-web-qa-checklist` only to fill the gaps, then execute it.
- `run` without a plan: apply `jbootz-crm-web-qa-checklist` first, then execute the resulting plan.
- If the user explicitly requests headless Playwright, use the repository Playwright workflow for that request. Otherwise, use `agent-browser` for browser interaction.

## Planning source and handoff

The checklist skill owns plan decisions. This skill owns execution: dependencies, runtime, setup, login, browser mechanics, persisted-state inspection, evidence, worker coordination, and cleanup.

When planning is required, load and apply the checklist through the current harness's normal skill mechanism; treat the skill name as an instruction source, not a callable function. If that mechanism is unavailable, read the sibling `../jbootz-crm-web-qa-checklist/SKILL.md` and apply it. If neither is possible, report that plan generation is blocked rather than recreating its rules here.

Before execution, confirm the plan has concrete environment, dependency, feature-flag, seed-data, login, browser, and persisted-state instructions relevant to the change and does not conflict with the user request or acceptance criteria. A plan satisfying that check is complete and must not be regenerated.

## Core principles

- Browser output is not the sole source of truth.
- A flash message, spinner, or successful click is insufficient proof.
- Verify persisted backend state for backend or AI behavior.
- Treat a click timeout as inconclusive until the next URL and accessibility snapshot are checked.
- Never reset a seeded user’s password through admin.
- Never invent seed commands or SQL.
- Never stage QA screenshots, `output/`, `.playwright-cli/`, or unrelated database drift.

## Step 0: Capture the baseline

Before starting:

```bash
git status --short
```

Record:

- current branch;
- current commit;
- pre-existing worktree files;
- whether the environment is Docker-backed or native (recorded during Step 2).

Do not clean or discard pre-existing files.

## Step 1: Dependency preflight

For Ruby/container work:

```bash
bin/wealthbox exec bundle check
```

If the output specifically reports missing gems:

```bash
bin/wealthbox exec bundle install
bin/wealthbox exec bundle check
```

For JavaScript work, use Yarn through the wrapper only. If a command reports missing packages, run the repository-approved Yarn install through bin/wealthbox exec, then retry the original command.

Do not run bare bundle, rails, rake, yarn, npm, npx, or docker compose.

## Step 2: Start and verify the environment only when necessary

First inspect the current service state and probe the resolved Rails health endpoint. Record the application URL and runtime mode from this status result. `bin/wealthbox up` is intentionally conditional because it can rebuild or wait on the full local stack.

```bash
status_json="$(bin/wealthbox status 2>/dev/null || true)"
rails_health_url="$(jq -r '.services.rails.localhost // .services.rails.url // empty' <<<"$status_json")"
rails_app_url="$(jq -r '.services.rails.url // .services.rails.localhost // empty' <<<"$status_json")"

if [ -n "$rails_health_url" ] && curl --fail --silent --show-error --max-time 5 \
  "$rails_health_url/healthcheck" >/dev/null 2>&1; then
  echo "Rails is already healthy at $rails_health_url; skipping bin/wealthbox up."
else
  bin/wealthbox up
  status_json="$(bin/wealthbox status)"
  rails_app_url="$(jq -r '.services.rails.url // .services.rails.localhost // empty' <<<"$status_json")"
fi

echo "QA application URL: $rails_app_url"
```

Run `bin/wealthbox up` only when the health probe fails, the status command cannot produce a usable URL, or the QA request explicitly requires a restart/rebuild. If a later browser or dependency check shows the running stack is stale or unhealthy, run `bin/wealthbox up` once and re-probe; do not repeat it speculatively.

Do not run `bin/wealthbox status rails --url` or duplicate status calls when the JSON status already provides `services.rails.url`.

If the QA task changes feature-flag configuration or seed data, perform that setup explicitly even when startup is skipped, then verify the resulting state with a read-only runner or psql query.

If Docker access is denied, request the required wrapper permission once. Do not repeatedly retry the same sandbox-blocked command.

If shared-service configuration differs from the worktree, inspect the warning before stopping or restarting shared services.

## Step 3: Prepare feature flags and seed data

For every required feature flag or seed:

1. Locate the existing repository-supported command or seed helper.
2. Run it through bin/wealthbox.
3. Verify the resulting state with a read-only bin/wealthbox runner or bin/wealthbox psql query.
4. Record the exact command and verification result in the QA evidence.

For AI/Generative View QA, explicitly record:

- the feature flag name and enabled actor/account;
- the seeded view name and ID;
- the seeded user/account;
- the expected button label;
- the expected persisted artifact/action state.

If the exact command cannot be established from the repository, mark the prerequisite blocked instead of fabricating a command.

## Step 4: Log in

Use the local-account-login skill for seeded users such as bill@patriot.com.

Do not retrieve the user through admin and change their password.

After login, verify the destination with:

- the current URL;
- an accessibility snapshot;
- a visible user/account indicator.

## Step 5: Execute browser scenarios

Use accessibility snapshots and stable visible labels:

```bash
agent-browser open <URL>
agent-browser snapshot -i
agent-browser click @eN
agent-browser snapshot -i
```

For each scenario, record:

1. starting page;
2. exact element clicked;
3. visible state immediately before the click;
4. expected visible result;
5. absence of internal XML, provider payloads, IDs, or implementation-only text;
6. screenshot path when visual evidence is useful.

For AI artifact actions, test the relevant surfaces separately:

- regular AI chat;
- AI agent chat;
- Generative View;
- native/mobile serialization when the diff touches shared serializers.

## Step 6: Verify persisted state

After an action, use repository-native read-only inspection to verify:

- the action or run was persisted;
- the user-facing display text is friendly;
- content and content_segments contain the public representation;
- content_raw retains provider-facing/raw action data;
- no raw internal handoff XML is exposed;
- the expected artifact/action was created exactly once.

Do not claim success from UI text alone.

## Step 7: Parallelization

At most one worker owns environment setup and dependency installation.

Other workers may execute independent scenarios only after receiving the setup owner’s evidence manifest.

Do not have multiple workers independently:

- install dependencies;
- start or stop shared services;
- seed the same data;
- rerun the same focused suite;
- request the same elevated permission.

## Step 8: Report

Report:

- prerequisites and exact commands;
- browser scenarios and results;
- persisted-state verification;
- screenshots;
- test commands and results;
- known limitations;
- whether the result is passed, failed, or inconclusive.

Close browser sessions after QA. Do not destructively clean the worktree.
