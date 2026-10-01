---
name: jbootz-gist-code-explainer
description: Use only when explicitly asked to publish a code or repository explainer (architecture, entities, execution flows, history) as a secret GitHub Gist; not for answering questions about code in chat.
---

# Gist Code Explainer

Explain code from repository evidence. Keep to the requested scope; a whole-repository request gets an architecture map, not a file-by-file dump. Explore read-only.

## Scope and Current Behavior

- Identify the repository, checkout, branch, and HEAD; say whether uncommitted changes are in scope.
- For a repository-wide request, summarize major components and entry points, then identify important entities and flows. Offer deeper traces instead of narrating every file.
- For a path, symbol, entity, or named flow, stay focused and follow relevant callers, dependencies, persistence, and external effects.
- Ground claims in source paths and line numbers. Verify persisted relationships against schema and model associations; distinguish direct code relationships from inferred ones.

## History and Pull Requests

- Inspect recent, relevant commits and diffs for the scoped paths or symbols; use blame to locate edits that need context.
- Find open or merged PRs touching the scoped code through commit links or changed paths when the Git host supports it. Include dates, commit SHAs, PR titles, and links; describe only changes supported by the diff or PR.
- Do not infer author intent from code or commit titles alone. Label other explanations as inference and do not claim an exhaustive PR search when results are limited.
- If Git metadata or remote access is unavailable, explain the current code and state which history could not be checked. PR and Linear access are not preconditions; publishing requires an authenticated `gh`.

In a sandboxed host, `gh` may lack network access or the user's token there. A sandboxed `gh` auth or network failure does not prove `gh` is unauthenticated: rerun it with the host's network or elevated permission before stopping.

## Explanation

Include only useful sections: architecture map, entity relationships, execution flows, and recent changes with related PRs. Cite current behavior to files and lines; cite history with commit dates and SHAs or PR links.

For diagrams, follow [jbootz-mermaid-diagrams](../jbootz-mermaid-diagrams/SKILL.md) for selection, rendering, and size limits. If the renderer reports a missing tool, stop and tell the user which tool is missing; never hand-draw the diagram or silently drop it.

## Publish

Use this Gist description and filename:

```text
{summary of what user asked to explain} Explainer VNNN
```

Replace filename-unsafe characters with `-`. Search all Gists owned by the authenticated user, not only the first page. Use `V001` unless a matching explainer exists; otherwise increment the highest version. Revisions create a new versioned Gist rather than editing an old one.

Secret Gists are unlisted, not private; include no secrets or copied proprietary code. Create with `gh gist create --filename <filename> --desc <description> -` (secret is the default). Return only its URL.
