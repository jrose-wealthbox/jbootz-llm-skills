# jbootz LLM skills

Personal, project-independent skills for coding agents. This repository is the
source of truth; installation creates symlinks rather than copies, so edits are
available to new agent sessions immediately.

## Supported agents

- Claude Code: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills`
- Codex CLI: `${CODEX_HOME:-$HOME/.codex}/skills`

Each skill is linked into each agent's native user-level skill directory. The
installer preserves unrelated skills already present there.

## Install

```sh
make install
```

You can also run `./bin/install` directly. The command is idempotent: existing
correct links are left unchanged. Files, directories, or links at conflicting
destinations are reported and never overwritten.

Run the installer again after adding or renaming a skill. Editing an existing
skill requires no reinstall; start a new agent session to pick up the change.

## Skills

Every direct child of `skills/` is one skill and must:

- Have a lowercase name containing only letters, digits, and hyphens.
- Contain a regular `SKILL.md` file with `name` and `description` frontmatter.
- Keep optional scripts, references, and assets inside its own directory.

Included skills:

- `jbootz-helloworld`: installation smoke test. In a new Claude Code or Codex
  session, ask:

> Use jbootz-helloworld.

The response should be exactly `Hello from jbootz-helloworld!`.

- `jbootz-pr-explainer`: publishes a terse, teammate-facing PR explainer as a
  secret GitHub Gist.

Secret Gists are unlisted, not access-controlled. Anyone with the URL can read
one; do not use this workflow for content that cannot be shared that way.

## Add another coding agent

Add an executable file to `install/adapters/`. Its only output must be the
absolute path of that agent's user-level skills directory. Installation and
conflict handling are shared by `bin/install`.

For example:

```sh
#!/bin/sh
printf '%s\n' "$HOME/.example-agent/skills"
```

## Test

```sh
make test
```

Tests use temporary configuration directories and do not touch real agent
installations.
