---
name: jbootz-human-readability
description: Use when asked to review or improve code readability.
---

# Human Readability Review

Find evidence-backed readability improvements that make code safer to change. Ignore style preferences, guide conformity, and metric reduction alone.

## Scope

- Named paths define scope.
- Repository-wide: inspect maintained source and relevant config; skip generated, vendored, build, and dependency output unless requested.
- Default: review the current branch diff from its merge base, plus staged, unstaged, and relevant untracked files. State base and scope; clarify ambiguity.

## What to look for

- Control flow: nested or compound conditions, repeated negation, complex trailing `if`/`unless`. Consider guard clauses for rejected states, multiline logic, or a domain-named predicate when clearer.
- Names that are vague, misleading, or hide a value's role, unit, or meaning.
- Business rules, exceptions, workarounds, or ordering constraints with unclear purpose. Search nearby code/docs; never guess rationale.
- Missing, stale, or narrating comments. Prefer clearer code; comment only to explain supported rationale, invariants, or constraints.
- Long or multi-purpose methods, mixed abstraction levels, and dense chains. Extract named steps only when they clarify flow. Inline a one-caller helper only if clearer and no useful name, reuse, or test seam is lost.
- Repeated or domain-significant numbers that need constants; leave self-explanatory values alone.
- Predicates whose in-repo callers all negate them. Check callers and contract; consider a domain-named inverse (e.g. `ineligible?` for `!eligible?`) and account for external or dynamic calls.
- Rails: check custom validation names for clear intent and complex parameterized scopes for named class-method alternatives. Treat guides as prompts, not rules.
- Ruby methods/blocks near configured RuboCop complexity or length limits (e.g. `Metrics/AbcSize`, `Metrics/BlockLength`): read effective config and report concrete readability pressure, never score reduction alone.

## Findings and approval

Number actionable candidates. For each, give location, issue and reason, exact before/after snippets, and assumptions or behavior risks. If rationale is unknown, ask; do not guess.

Edit only after the user sees every before/after and explicitly approves item numbers or all. Change only approved items; re-propose material deviations.

## Approved edits and checks

Preserve behavior, public interfaces, and useful test seams. After all approved edits, run focused tests and linters; group coupled changes and distinguish new failures from existing ones.

If tests fail, show the code/failure and get approval before fixing. If a linter fails, show the code and exact failure; ask whether to adjust code or add a narrow inline directive. Never silently suppress rules or expand scope.
