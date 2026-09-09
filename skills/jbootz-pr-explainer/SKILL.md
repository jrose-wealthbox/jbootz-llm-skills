---
name: jbootz-pr-explainer
description: Publish a terse teammate-facing GitHub Gist explaining a supplied pull request.
---

# PR Explainer

Create a Markdown explainer for professional Rails and TypeScript developers.
Be extremely terse and plain. They can view the diff; explain intent and flow,
not every edit.

## Preconditions

Stop with a concise explanation if no PR was supplied, `gh` is unavailable or
unauthenticated, the PR is inaccessible, or its Linear issue number and title
cannot be established. Never guess identifiers.

## Evidence

Pin the PR URL, number, and exact HEAD commit. Inspect its description, diff,
changed files, commits, reviews, and relevant discussion. Read the Linear issue
and linked issues with available tools. Use relevant conversation context.

Recheck HEAD before publishing; if it changed, refresh the explainer. State
only supported conclusions. Do not infer rejected approaches or deferral
reasons from missing code.

## Document

Omit optional sections when empty. Account for every changed file in the tour;
put files outside runtime flow under `Supporting Changes`.

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

Use `Points of Interest` only for genuinely surprising complexity: substantial
iteration, external-invariant workarounds, intentional best-practice
exceptions, reviewer disagreement or feedback-driven changes, or edits outside
the feature's expected area.

## Publish

Use this Gist description:

```text
{linear issue number} / PR #{pr number} Explainer VNNN ({linear issue title})
```

Gists are flat, so use a hyphen instead of the slash in the filename:

```text
{linear issue number} - PR #{pr number} Explainer VNNN ({linear issue title}).md
```

Replace filename-unsafe title characters with `-`. Search all Gists owned by
the authenticated user, not only the default first page. Use `V001` unless a
matching issue/PR explainer exists; otherwise increment the highest version.
Revisions create a new versioned Gist rather than editing an old one.

Treat secret Gists as unlisted, not private. Include no secrets or copied
proprietary code. Create the Gist with `gh gist create --filename <filename>
--desc <description> -`; secret is the default. Return only its URL.
