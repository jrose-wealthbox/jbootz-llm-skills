---
name: jbootz-crm-web-qa
description: Use when executing or validating browser QA for a local Wealthbox crm-web change, including AI-agent, Generative View, artifact, or PR flows; only in the crm-web repository.
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep, Task
---

# Wealthbox QA

Execute a complete QA plan for the current CRM-web branch. `jbootz-crm-web-qa-checklist` owns plan content; this skill owns setup, execution, evidence, and cleanup.

## Mode routing

- `plan` or no argument: apply `jbootz-crm-web-qa-checklist`, generate the plan, then stop.
- `run` with a complete plan: preserve it unchanged and execute it.
- `run` with an incomplete plan: preserve correct content, use the checklist only to fill gaps, then execute.
- `run` without a plan: generate one with the checklist, then execute it.
- Honor an explicit headless-Playwright request; otherwise use `agent-browser`.

When planning is required, load the checklist through the harness's normal skill mechanism; skill names are instruction sources, not callable functions. If unavailable, read the sibling `../jbootz-crm-web-qa-checklist/SKILL.md`; if neither is available, report planning blocked. Before execution, accept a plan only when its relevant environment, dependency, flag, seed, login, browser, and persisted-state instructions are concrete and consistent with the request and acceptance criteria.

## Guardrails

- UI text, a flash, spinner, or successful click is not proof; verify persisted state when backend or AI behavior is in scope.
- Treat click timeouts as inconclusive until the next URL and accessibility snapshot are checked.
- Never reset a seeded user's password through admin or invent seed commands/SQL.
- Never clean or stage pre-existing worktree files, QA screenshots, `output/`, `.playwright-cli/`, or unrelated database drift.

## 0. Capture the baseline

Before setup:

```bash
git status --short
```

Record the branch, HEAD, pre-existing files, and (after Step 2) whether the environment is Docker-backed or native. Do not clean or discard pre-existing files.

## 1. Dependency preflight

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

Never run bare `bundle`, `rails`, `rake`, `yarn`, `npm`, `npx`, or `docker compose`.

## 2. Verify the environment only when needed

Inspect service state and probe the resolved Rails health endpoint first. Record the application URL and runtime mode:

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

Run `bin/wealthbox up` only when the probe fails, status lacks a usable URL, or the request explicitly requires restart/rebuild. If a later check shows a stale or unhealthy stack, run it once and re-probe; do not repeat speculatively. Do not call `bin/wealthbox status rails --url` or duplicate status calls when JSON already provides `services.rails.url`.

If Docker access is denied, request the wrapper permission once. Inspect shared-service configuration warnings before stopping or restarting shared services.

## 3. Prepare flags and seeds

For each required flag or seed: locate the repository-supported command/helper, run it through `bin/wealthbox`, verify it with a read-only `bin/wealthbox runner` or `bin/wealthbox psql` query, and record the exact command and result. Do this even when Step 2 skips startup. If it cannot be established from the repository, mark the prerequisite blocked.

For AI/Generative View QA, record the flag and enabled actor/account, view name and ID, seeded user/account, expected button label, and expected persisted artifact/action state.

## 4. Log in

Use `local-account-login` for seeded users such as `bill@patriot.com`; never retrieve a user through admin to change its password. After login, verify the current URL, an accessibility snapshot, and a visible user/account indicator.

## 5. Execute browser scenarios

Use accessibility snapshots and stable visible labels:

```bash
agent-browser open <URL>
agent-browser snapshot -i
agent-browser click @eN
agent-browser snapshot -i
```

For each scenario, record the starting page, exact element and pre-click state, expected visible result, absence of internal XML/provider payloads/IDs/implementation text, and a screenshot path when useful.

For AI artifact actions, test each relevant surface separately: regular AI chat, AI agent chat, Generative View, and native/mobile serialization when shared serializers are changed.

## 6. Verify persisted state

After an action, use repository-native read-only inspection to verify that:

- the action/run exists and the expected artifact/action was created exactly once;
- `content` and `content_segments` contain the public representation;
- `content_raw` retains provider-facing/raw action data;
- display text is friendly and no raw handoff XML is exposed.

Do not claim success from UI text alone.

## 7. Coordinate workers

One worker owns environment setup and dependency installation. Other workers may run independent scenarios only after receiving its evidence manifest. Do not have multiple workers install dependencies, start/stop shared services, seed the same data, rerun the same focused suite, or request the same elevated permission.

## 8. Report and clean up

Report prerequisites and exact commands, browser results, persisted-state verification, screenshots, test commands/results, limitations, and a `passed`, `failed`, or `inconclusive` conclusion. Close browser sessions after QA; do not destructively clean the worktree.
