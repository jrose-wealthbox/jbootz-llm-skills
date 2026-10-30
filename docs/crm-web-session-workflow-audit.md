# CRM-web Codex Session Workflow Audit

Status: findings and recommendations so far; no workflow changes have been implemented by this audit.

## Executive summary

The main productivity constraint is not a lack of agent capacity. It is friction at the boundaries between:

1. local environment setup and permission policy;
2. parallel agents and duplicated work;
3. stale ticket/branch context and a fast-moving repository;
4. review evidence and publication mechanics; and
5. browser QA, persisted-state proof, and long-running monitoring.

At 50 hours per week, these are worth treating as an internal productivity system rather than as isolated inconveniences. The best improvements are a small number of durable lifecycle commands or personal skills, not a large collection of narrowly overlapping skills.

## Scope and method

I inspected the accessible active and archived Codex JSONL session records whose initial working directory contained `crm-web`.

- Date range: 2026-06-29 through 2026-09-11
- CRM-web rollout nodes: 815
- Top-level user sessions: 209
- Child rollouts: 606
- Guardian/auto-classifier sessions: 113
- Final classifier assessments: 1,309
- Top-level task-like user messages: 1,169

For user behavior, I counted root-session messages so that subagent transcript repetition did not look like additional user requests. For authorization and environment behavior, I used child-session records and distinct root-session coverage.

### Recency weighting

Because CRM-web evolves quickly, conclusions use an exponential 21-day half-life:

- a session on the audit date has weight `1.0`;
- a session 21 days old has weight `0.5`;
- a session 42 days old has weight `0.25`.

Raw counts are retained for auditability. The recommendations are driven primarily by the last 7–21 days.

The classifier data is especially recent: 179 assessments occurred in the last 7 days and 919 in the last 14 days. Explicit Linear-authentication complaints occurred through September 3 but not in the newest explicit-auth sample, so that problem may be improving.

### Caveats

- Guardian transcripts replay earlier history. Approval-request-record counts can therefore overcount what a human saw. Final classifier assessments and distinct root sessions are more reliable.
- The logs do not provide reliable wall-clock cost per action, so this report identifies likely savings rather than claiming exact hours recovered.
- Parsed error signatures can also be replayed in child/guardian transcripts; distinct root-session coverage is the stronger environment signal.
- The `superset-10x` skill's prescribed read-only audit could not run because its `audit.sh` and the `superset` CLI were unavailable in this environment. This report does not claim anything about the current live Superset automation/task inventory.

## Highest-confidence findings

### 1. Environment and permission friction is still current

Distinct root sessions containing parsed error signatures:

| Failure signature | All sessions | Last 14 days | Last 7 days |
|---|---:|---:|---:|
| OrbStack Docker socket denial | 85 | 27 | 12 |
| GitHub API connectivity error | 58 | 22 | 10 |
| `Operation not permitted` | 46 | 16 | 7 |
| MCP startup/handshake failure | 18 | 11 | 4 |

The Docker problem is not a test failure. It is a host-access/setup boundary. Repeated sandbox retries consume agent turns without producing useful evidence.

The single explicit classifier denial was a QA runner command that disabled all matching `custom_field_value.update` triggers and then enabled one named trigger. The denial was an appropriate safety boundary because the command could affect unrelated agents. The productive fix is a narrowly scoped, idempotent QA fixture/helper—not a broader authorization rule.

### 2. The auto-classifier is invoked heavily for low-risk operational work

There were 1,309 final classifier assessments. Of these:

- 1,246 requested escalated execution;
- 1,308 were allowed;
- 1 was denied;
- 1,043 were classified low risk;
- 1,193 carried high user-authorization confidence.

The assessed actions were concentrated in:

- 703 browser-QA actions;
- 390 `bin/wealthbox` wrapper actions;
- 84 GitHub CLI actions;
- 39 Git actions.

In the newest 7-day window, the distribution shifted toward wrapper/test activity: 114 `bin/wealthbox` assessments versus 33 browser-QA assessments.

This suggests a narrow local permission matrix and fewer compound/wrapped shell command shapes could remove a substantial amount of machine-visible friction without weakening safeguards around mutations.

### 3. Parallelism is being used, but the fan-out often becomes overhead

Examples of large recent or high-cost roots:

- AIE-2319: 26 child rollouts, split evenly between guardians and subagents;
- AIE-2157: 22 child rollouts;
- AIE-2283: 16 child rollouts and 49 task-like user messages;
- AIE-2255: 31 child rollouts and 461 final classifier assessment records;
- AIE-2065: 10 child rollouts and 274 final classifier assessment records.

The AIE-2255 history explicitly contains repeated QA attempts, a request to stop all subagents, a request to use a single Luna worker, and a correction from one browser tool to another. This is a strong example of parallel execution increasing coordination cost.

The useful distinction is not “parallel versus sequential.” It is “independent work versus duplicated setup, tests, browser sessions, and review.”

### 4. You repeatedly restate a mature review and publication contract

Recency-weighted user-message patterns:

| Pattern | Raw messages / root sessions | Weighted message score |
|---|---:|---:|
| Commit and push | 78 / 49 | 31.7 |
| Rebase or resolve conflicts | 62 / 36 | 21.8 |
| Evaluate another agent's review | 28 / 22 | 20.9 |
| Stop or interrupt work | 34 / 26 | 19.1 |
| Exact-head/base review instructions | 29 / 23 | 15.8 |
| Do not use superpowers/skill | 25 / 22 | 14.7 |

The repeated review requirements are consistent and specific:

- pin the published base and head and use a three-dot diff;
- distinguish branch regressions from inherited defects;
- classify normal-user versus crafted/console reachability;
- use Linear acceptance criteria as an independent product oracle;
- keep source/test proof separate from browser and persisted-state proof;
- evaluate another review without automatically repeating a full review.

These instructions are sufficiently stable to become a reusable review protocol.

### 5. The repository's speed makes stale plans unusually expensive

Recent sessions include:

- AIE-2065: a second attempt after an approximately 1,500-line first attempt was judged over-scoped;
- AIE-2281: an older activation/target persistence approach was superseded by a leaner `pause_reason` design;
- AIE-2319: an adapter change initially appeared related to a lifecycle issue, but finalization and current-turn invariants required separate investigation.

The recurring failure mode is not simply “the agent made a bad plan.” It is that a previously reasonable plan becomes wrong as master, related PRs, and Linear comments move.

### 6. Long-running work creates repeated monitoring and interruption loops

There were 213 aborted-turn events across the corpus. In the last 14 days, 37 root sessions were associated with 61 aborted events. The logs also contain repeated `sleep`, “continue,” “where are we?”, and “monitor the CI” interactions.

This is a good candidate for bounded monitoring that polls until a terminal state and reports once, rather than making the user supervise each interval.

## Concrete recommended changes

### Priority 1: one `crm-web preflight` workflow

Create a local personal skill or command that checks, in one pass:

- Docker host access and `bin/wealthbox` readiness;
- Rails health and the resolved worktree URL;
- port-block ownership and collisions;
- Ruby and JavaScript dependency state;
- browser automation socket/session availability;
- GitHub connectivity/authentication;
- Linear connector readiness.

It should return `READY` or one actionable `BLOCKED` result with the next command. It should not retry Docker or network operations blindly.

The permission policy should be split by risk:

- preapprove narrow read-only status, dependency-check, focused-test, browser-snapshot, and GitHub-read commands;
- retain confirmation for git publication, Linear writes, flag/seed mutations, trigger changes, resets, and destructive service operations.

Use direct, stable command shapes instead of wrapping safe commands in arbitrary `bash`, `env`, or multi-command shells when possible.

### Priority 2: a freshness/scope gate before implementation

Before any implementation fan-out, require a short machine-readable checkpoint containing:

```text
ticket_status: relevant | already_addressed | superseded | ambiguous
base_sha:
head_sha:
related_prs:
acceptance_criteria:
expected_files:
scope_budget:
out_of_scope:
```

The agent should stop when the issue is already addressed or when the proposed solution exceeds the scope budget. This is especially important for fast-moving Agent work.

### Priority 3: cap and stage agent fan-out

Default lifecycle:

1. one implementer or investigator;
2. one adversarial reviewer when the change warrants it;
3. one QA worker after the environment and dependency manifest are proven.

Additional workers should require genuinely independent surfaces. One worker should own setup and dependency installation; other workers should consume its evidence manifest and never repeat setup, seeding, shared-service restarts, or identical focused tests.

### Priority 4: an exact-head review and handoff skill

Package the repeated review contract into one skill with a required handoff artifact. Each finding should include:

```text
severity:
introduced_by_branch: yes | no | uncertain
normal_user_reachable: yes | crafted_only | console_only | no
base_behavior:
head_behavior:
evidence:
recommendation:
```

The skill should refuse to call a finding a regression until the parent/base behavior is checked.

### Priority 5: a safe publication workflow

Create a personal `crm-web publish` workflow that verifies branch, HEAD, upstream, destination ref, divergence, intended staged paths, and remote SHA. It should use explicit push destinations and exact `--force-with-lease` values when rewriting history.

It should also assert that unrelated `db/structure.sql`, generated files, and pre-existing worktree changes are not accidentally staged.

### Priority 6: a batched file-level PR comment workflow

The PR #23577 sequence shows a concrete avoidable loop: comments were initially line-anchored, then removed and recreated as file-level comments, then prefixed in a separate pass.

A dedicated workflow should:

- enumerate changed application files;
- exclude tests when requested;
- preview the exact file-level payloads;
- submit the batch after one confirmation;
- verify subject type, file, body prefix, and resulting comment count.

This should be a single workflow rather than many per-comment authorization prompts.

### Priority 7: bounded CI/QA monitoring

Add a monitor mode that records the target PR/run, polls at a bounded interval, exits on success/failure/cancellation, and emits one concise report. It should distinguish:

- application/test failure;
- dependency/setup failure;
- Docker/host permission failure;
- CI infrastructure failure;
- inconclusive browser evidence.

### Priority 8: narrow QA fixtures instead of broad runtime mutation

Provide named, reversible QA setup helpers for flags, users, triggers, and seeded data. They should modify only the requested fixture and report the before/after state. This preserves the classifier's useful safety boundary while eliminating risky one-off `update_all` commands.

## Improvements already present in the personal QA skills

The current uncommitted versions of `jbootz-crm-web-qa` and `jbootz-crm-web-qa-checklist` already incorporate several findings from this audit:

- conditional `bin/wealthbox up -d --wait` instead of unconditional startup;
- dependency preflight through the repository wrapper;
- explicit browser readiness waits and re-snapshotting;
- separate persisted-state verification;
- one worker owning environment setup;
- a rule against duplicate elevated setup/test work.

Those should be treated as existing work to preserve and validate, not duplicated as new skills.

## Suggested implementation order

For a 50-hour workweek, I would implement these in this order:

1. `crm-web preflight` plus narrow local permission rules;
2. freshness/scope gate plus exact-head review handoff;
3. safe publication workflow;
4. capped staged fan-out;
5. batched PR comments and bounded CI/QA monitoring;
6. optional Linear/EOD automation after the connector is reliable.

The first three address the largest recent environment, review, and publication costs. The fan-out change is likely to reduce both agent spend and human supervision. The QA skill updates already underway provide a good foundation for the later steps.
