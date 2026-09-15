---
name: jbootz-mermaid-diagrams
description: Use when creating or rendering Mermaid architecture, flowchart, ER, sequence, state, or class diagrams as terminal text or SVG.
---

# Mermaid diagrams

Use Mermaid as canonical source format.

## Renderer

Entry point: `<skill-dir>/scripts/render.sh`. Resolve its absolute path from
this `SKILL.md` directory; do not assume caller's cwd is skill directory. Input
paths are relative to caller's cwd.

```text
render.sh text FILE                 # Unicode terminal preview
render.sh ascii FILE                # ASCII-only preview
render.sh svg FILE [OUTPUT_BASE]    # SVG
render.sh both FILE [OUTPUT_BASE]   # text + SVG
```

Without `OUTPUT_BASE`, SVG output goes to a unique directory under
`${TMPDIR:-/tmp}`. An explicit output base wins; e.g.:

```text
render.sh both docs/architecture.mmd docs/architecture
# writes docs/architecture.svg
```

## Workflow

1. Unless user requests repository artifacts, create a unique temp directory
   under `${TMPDIR:-/tmp}` and write source there (for example, `diagram.mmd`).
2. Keep `.mmd` source as canonical editable artifact for current task. For
   requested repository artifacts, preserve it at requested path.
3. Render with this skill's script; do not manually draw ASCII.
4. Prefer `text`; use `ascii` only when user specifically requests no Unicode.
5. Use `svg` for graphical output and `both` when terminal + SVG are useful.

## Output and compatibility

Temporary sources/default SVGs stay under `${TMPDIR:-/tmp}`; explicit repository
artifacts normally include both `diagram.mmd` and `diagram.svg`. SVG is
compatibility authority; terminal preview may support fewer Mermaid features.

`both` still attempts SVG if terminal rendering fails. If SVG succeeds, keep it
and warn about terminal incompatibility. Preserve valid source/SVG; do not
change diagram meaning merely to satisfy terminal limitations. Prefer broadly
supported syntax when equivalent.

## Diagram guidance

- `flowchart`: architecture, control flow, pipelines, dependencies.
- `sequenceDiagram`: interactions over time.
- `erDiagram`: database entities/relationships.
- `stateDiagram-v2`: state machines/lifecycles.
- `classDiagram`: object/type relationships.

For architecture diagrams, show clear boundaries, label non-obvious edges,
keep diagrams readable, and split large diagrams when needed.

## Validation

After creating/modifying source, render SVG to verify syntax:

```text
<skill-dir>/scripts/render.sh svg path/to/diagram.mmd
```

Use `both` when terminal presentation matters.
