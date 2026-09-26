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

## Execution Flow Tour (Before This Branch)

### <Flow name; include headings only when multiple flows exist>

- `<file>`: <One concise sentence explaining its role in this flow. If this step in the flow was changed by the current branch, state the problem or reason.>

## Execution Flow Tour (After This PR)

### <Flow name; include headings only when multiple flows exist>

- `<file>`: <One sentence explaining its change and role in this flow.>

### Supporting Changes

- `<file>`: <One sentence explaining the supporting change.>

## Mermaid Diagram

<Optional: include a fenced `text` block containing a rendered Mermaid diagram when it materially clarifies relationships or a nontrivial flow.>

## Follow-up / Spin-off Linear Issues

- [<ID>: <title>](URL) — <One-sentence summary.> <Confirmed reason for deferral, if known.>
```

Use `Points of Interest` only for genuinely surprising complexity: substantial iteration, external-invariant workarounds, intentional best-practice exceptions, reviewer disagreement or feedback-driven changes, or edits outside the expected feature area.

Use a Mermaid diagram only when it materially clarifies branch-specific
information. Good fits include an ERD of relevant entities and their
relationships before or after the branch's changes, or a nontrivial execution
flow with meaningful branching. For linear or nearly linear flows, prefer
bullets; flowcharts are more useful when they show real branching. Skip diagrams
that repeat the prose.

Keep each rendered ASCII diagram within 150 characters (columns) wide and 800
lines (rows) tall. If a diagram would exceed either limit, consider splitting
it into readable diagrams; use bullets when splitting would add little clarity.

When useful, load [jbootz-mermaid-diagrams](../jbootz-mermaid-diagrams/SKILL.md)
and follow its workflow: create Mermaid source in a unique temporary directory,
resolve the absolute path to that skill's `scripts/render.sh`, and run
`<renderer-path> ascii <file.mmd>`. Put only readable, faithfully rendered
ASCII output in a fenced `text` block; do not hand-draw the diagram or include
the `.mmd` source unless requested. If ASCII mode cannot represent the diagram
clearly within the size limits, omit it and retain the prose.

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
