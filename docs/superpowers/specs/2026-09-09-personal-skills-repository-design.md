# Personal LLM Skills Repository Design

## Purpose

This repository is the source of truth for personal, project-independent LLM
skills. A one-time installation command exposes those skills to every Claude
Code and Codex CLI session on the local machine. Editing a linked skill in this
repository must require no reinstall or copy step.

The initial implementation supports Claude Code and Codex CLI while keeping the
installation mechanism easy to extend to additional coding agents.

## Repository Layout

```text
jbootz-llm-skills/
|-- skills/
|   `-- <skill-name>/
|       |-- SKILL.md
|       |-- scripts/       # optional
|       |-- references/    # optional
|       `-- assets/        # optional
|-- install/
|   `-- adapters/
|       |-- claude-code
|       `-- codex
|-- bin/
|   `-- install
|-- Makefile
`-- README.md
```

Each direct child of `skills/` is one skill and must contain `SKILL.md`. Skills
use the common Agent Skills layout directly; the repository does not maintain
agent-specific copies or transform skill content.

## Installation Architecture

`make install` is the documented entrypoint and delegates to `bin/install`.
Calling `bin/install` directly provides the same behavior without requiring
Make.

The installer discovers executable adapter files in `install/adapters/`. Each
adapter has one responsibility: report the user-level skill directory for its
agent. Initially:

- `claude-code` targets `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills`.
- `codex` targets `${CODEX_HOME:-$HOME/.codex}/skills`.

The installer enumerates direct children of the repository's `skills/`
directory and creates one directory symlink per skill in every enabled adapter
destination:

```text
~/.claude/skills/<skill-name> -> <repository>/skills/<skill-name>
~/.codex/skills/<skill-name>  -> <repository>/skills/<skill-name>
```

Per-skill links are intentional. The installer must coexist with skills placed
in those global directories by users, plugins, or the agents themselves. It
must never replace an entire global skills directory.

Adding support for another agent consists of adding one adapter that returns
its user-level skills directory. Skill discovery, validation, conflict
handling, and link creation remain centralized in `bin/install`.

## Installer Behavior

The installer resolves its own location so it works regardless of the caller's
current directory and regardless of where the repository was cloned.

For every skill and target directory, it follows these rules:

1. If the destination does not exist, create the symlink.
2. If the destination is already a symlink to the expected source, report it as
   unchanged.
3. If the destination is a stale or differently targeted symlink, report a
   conflict and leave it untouched.
4. If the destination is a file or directory, report a conflict and leave it
   untouched.

The command processes all skills and adapters so that one conflict does not
hide other conflicts. It exits nonzero if validation fails or any conflict is
found. It must not remove, overwrite, or migrate existing entries implicitly.

Before creating links, the installer validates that:

- `skills/` exists.
- Every direct, non-hidden child of `skills/` is a directory.
- Every skill directory contains a regular `SKILL.md` file.
- Every adapter is executable and returns one non-empty absolute directory.
- Skill names contain only lowercase letters, digits, and hyphens.

An empty `skills/` directory is valid. This lets the repository installation
mechanism be established before the first personal skill is created.

## Immediate-Update Semantics

Because both agent installations point directly at each repository skill
directory, edits to any existing skill are visible the next time an agent
session discovers or loads it. There is no generated output to refresh.

Adding a new skill requires rerunning `make install` once to create that skill's
links. Removing or renaming a skill may leave broken links in agent directories;
cleanup is deliberately manual in the first version to avoid deleting anything
the installer cannot prove it owns.

## Documentation

The README will explain:

- The repository's purpose and supported agents.
- The skill directory contract.
- How to run `make install` or `bin/install`.
- The non-destructive conflict behavior.
- That edits are immediate but new skills require rerunning installation.
- How to add an adapter for another coding agent.

## Verification

Installer behavior will be tested against temporary home and configuration
directories rather than the developer's real global skill directories. Tests
will cover:

- An empty repository skill set.
- Creating links for multiple skills and adapters.
- Re-running installation without changes.
- Respecting `CLAUDE_CONFIG_DIR` and `CODEX_HOME` overrides.
- Rejecting invalid skill layouts and names.
- Reporting all conflicting files, directories, and symlinks without changing
  them.
- Running from a working directory outside the repository.

The final implementation will also run a read-only check against the actual
machine layout before the user chooses whether to execute the real one-time
installation.

## Scope Boundaries

This first version does not:

- Create any personal skills.
- Replace or consolidate existing agent-managed skill directories.
- Automatically remove stale links.
- Publish the repository or alter shell startup files.
- Add agent-specific skill variants.
