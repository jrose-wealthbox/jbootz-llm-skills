# jbootz LLM skills and agents

Personal, project-independent skills and shared instructions for coding agents.
This repository is the source of truth; installation creates skill symlinks,
managed instruction blocks, and rendered native agent definitions without
replacing unrelated agent configuration.

## Supported agents

- Claude Code: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills`
- Codex CLI: `${CODEX_HOME:-$HOME/.codex}/skills`

Each skill is linked into each agent's native user-level skill directory. The
installer preserves unrelated skills already present there. Shared instructions
come from `global/global.md` and are managed in:

- Claude Code: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md`
- Codex CLI: `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`

Custom agents are installed alongside those skills:

- Claude Code: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents`
- Codex CLI: `${CODEX_HOME:-$HOME/.codex}/agents`

## Install

```sh
make install
```

You can also run `./bin/install` directly. The command is idempotent: existing
correct links, managed instruction blocks, and rendered agent definitions are
left unchanged. Unmanaged files, directories, or links at conflicting
destinations are reported and never overwritten.

The installer wraps the contents of `global/global.md` in a marked block. If a
target instruction file does not exist, it creates the file. If the file exists
without the block, it appends the block. On later installs, it replaces only the
block so user-authored content outside it remains untouched. Duplicated,
incomplete, or out-of-order markers are treated as an error and are not
modified.

The managed markers are:

```text
<!-- BEGIN jbootz-llm-skills global instructions -->
<!-- END jbootz-llm-skills global instructions -->
```

The content is copied into both host files instead of using an import directive:
Claude Code supports `@path` imports, but Codex's official instruction-file
documentation does not define an equivalent portable import syntax.

Run the installer again after adding or renaming a skill. Editing an existing
skill requires no reinstall; start a new agent session to pick up the change.
Edit `global/global.md` or an agent's canonical source and run the installer
again to render the changes. Adding or renaming an agent also requires
reinstalling.

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

## Agents

Every direct child of `agents/` is one named agent with shared metadata,
instructions, and host-specific settings:

```text
agents/<agent-name>/agent.yml        # metadata and host settings
agents/<agent-name>/instructions.md  # shared behavior
```

Each manifest enables at least one supported host. During installation,
`bin/render-agent` validates the canonical source and renders the host's native
format into its user-level `agents/` directory. Managed files are updated
atomically; unrelated files and symlinks remain untouched. Legacy symlinks
created by older versions of this repository are migrated to physical files.

The included `scout` agent is deliberately narrow. It uses Codex's
`gpt-5.6-luna` model at medium reasoning effort to run bounded mechanical
checks, parse noisy output, and return compressed evidence. It is instructed
not to diagnose failures or edit source files; the parent agent owns those
decisions. The Claude Code definition uses its low-cost `haiku` model as the
closest host-native equivalent.

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
