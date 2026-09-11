---
name: jbootz-pr-explainer
description: Use when a pull request needs a terse teammate-facing explainer based on GitHub and Linear evidence.
---

# PR Explainer

Write a terse, plain Markdown explainer for Rails and TypeScript developers. Explain intent and flow, not every diff edit.

## Preconditions

Stop with a concise explanation if no PR was supplied, `gh` is unavailable or unauthenticated, the PR is inaccessible, or its Linear issue number and title cannot be established. Never guess identifiers.

## Evidence

Pin the PR URL, number, and exact HEAD commit. Inspect its description, diff, changed files, commits, reviews, and relevant discussion; read the Linear issue and linked issues with available tools; use relevant conversation context.

Recheck HEAD before publishing and refresh the explainer if it changed. State only supported conclusions; do not infer rejected approaches or deferral reasons from missing code.

## Document

Omit empty optional sections. Account for every changed file; put files outside runtime flow under `Supporting Changes`.

```markdown
## Relevant Links

- PR: <PR URL>
- Created: <YYYY-MM-DD HH:MM TZ>
- HEAD: <full commit SHA linked to GitHub>

## Extra small TL;DR

<One sentence: problem and solution.>

## Problem

<One sentence combining the Linear issue with confirmed implementation context.>

## User Impact

<One sentence describing concrete bug impact or feature benefit.>

## Rejected Solutions

- <One terse sentence naming the approach. One terse sentence explaining its rejection.>

## Points of Interest

- <Why this is complex or surprising.> `<file>:<line>` ([diff](<PR file-diff URL>)).

## Execution Flow Tour

### <Flow name; include headings only when multiple flows exist>

- `<file>`: <One sentence explaining its change and role in this flow.>

### Supporting Changes

- `<file>`: <One sentence explaining the supporting change.>

## Follow-up / Spin-off Linear Issues

- [<ID>: <title>](<URL>) — <One-sentence summary.> <Confirmed reason for deferral, if known.>
```

Use `Points of Interest` only for genuinely surprising complexity: substantial iteration, external-invariant workarounds, intentional best-practice exceptions, reviewer disagreement or feedback-driven changes, or edits outside the expected feature area.

## Publish

Use this Gist description:

```text
{linear issue number} / PR #{pr number} Explainer VNNN ({linear issue title})
```

Gists are flat, so use a hyphen in the filename:

```text
{linear issue number} - PR #{pr number} Explainer VNNN ({linear issue title}).md
```

Replace filename-unsafe title characters with `-`. Search all Gists owned by the authenticated user, not only the first page. Use `V001` unless a matching issue/PR explainer exists; otherwise increment the highest version. Revisions create a new versioned Gist rather than editing an old one.

Secret Gists are unlisted, not private; include no secrets or copied proprietary code. Create with `gh gist create --filename <filename> --desc <description> -` (secret is the default). Return only its URL.
