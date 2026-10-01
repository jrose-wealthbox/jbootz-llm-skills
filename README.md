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

This repository pins Ruby 4.0.1 in `mise.toml`. On each computer, run
`mise trust` once for this repository and `mise install` after cloning or
changing the configured version. Make targets run inside that mise environment.

```sh
make install
```

You can also run `mise exec -- ./bin/install` directly. The command is
idempotent: existing correct links, managed instruction blocks, and rendered
agent definitions are left unchanged. Unmanaged files, directories, or links
at conflicting destinations are reported and never overwritten.

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

Run the installer again after adding, renaming, or deleting a skill. It removes
installed links that point into this repository's `skills/` directory but no
longer resolve, and leaves every other link alone. Editing an existing
skill requires no reinstall; start a new agent session to pick up the change.
Edit `global/global.md` or an agent's canonical source and run the installer
again to render the changes. Adding or renaming an agent also requires
reinstalling.

## Permission rules

User-level permission rules are maintained in `permissions/` and installed by
`bin/install`:

- Codex `.rules` files are symlinked into `${CODEX_HOME:-$HOME/.codex}/rules`.
  These remain user-level rules and apply across projects. The installer
  requires `codex execpolicy check` on `PATH` and uses it to parse each source
  before changing either host's configuration.
- Claude's `allow`, `ask`, and `deny` arrays come from
  `permissions/claude-code/rules.json` and synchronized into
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Other settings, including
  `permissions.defaultMode`, are preserved. Install state is recorded under
  `.jbootz-llm-skills/` in the Claude config directory so later installs can
  detect edits made outside this repository.

On a first install, an empty Claude permission list or one that already matches
the repo source is safe to adopt. Matching Codex rule files are migrated to
repo-backed symlinks; missing files are linked. If either host has different
existing rules, or Claude's rules change after installation, the installer
stops and identifies the config that needs reconciling. Add intentional rules
to the source in this repo and run the installer again; it does not overwrite
unrecognized rules.

## Skills

Every direct child of `skills/` is one skill and must:

- Have a lowercase name containing only letters, digits, and hyphens.
- Contain a regular `SKILL.md` file with `name` and `description` frontmatter.
- Keep optional scripts, references, and assets inside its own directory.

Included skills:

- `jbootz-adversarial-review`: verified PR or branch review that classifies
  each bug as introduced by the branch or already on its base, judges the PR
  against its Linear issue, and can weigh another reviewer's findings.
- `jbootz-claude-review`: from Codex only, runs Claude Code as an independent,
  read-only reviewer of a diff or plan.
- `jbootz-crm-web-qa`: executes a crm-web browser QA plan with `agent-browser`
  and verifies persisted state.
- `jbootz-crm-web-qa-checklist`: writes crm-web QA plans that a person new to
  the app, or a cheap agent, can follow.
- `jbootz-gist-code-explainer`: publishes a repository or code explainer as a
  secret GitHub Gist.
- `jbootz-gist-pr-explainer`: publishes a terse, teammate-facing PR explainer
  as a secret GitHub Gist.
- `jbootz-helloworld`: installation smoke test. In a new Claude Code or Codex
  session, ask:

> Use jbootz-helloworld.

The response should be exactly `Hello from jbootz-helloworld!`.

- `jbootz-human-readability`: proposes readability fixes with before/after
  snippets and edits only approved items.
- `jbootz-mermaid-diagrams`: writes Mermaid source and renders terminal text or
  SVG.
- `jbootz-pr-file-comments`: posts exactly one file-level comment per file in
  a GitHub PR and verifies the count.
- `jbootz-session-postmortem`: reviews recent Codex and Claude Code sessions
  for process improvements.

Secret Gists are unlisted, not access-controlled. Anyone with the URL can read
one; do not use the Gist explainers for content that cannot be shared that way.

### External tools

Some skills need command-line tools that this repository does not install.
They stop with an error naming the missing tool rather than falling back:

- `gh`, authenticated: the Gist explainers, `jbootz-pr-file-comments`, and
  `jbootz-adversarial-review`.
- `mermaid-ascii` (terminal rendering) and `mmdc` from Mermaid CLI (SVG):
  `jbootz-mermaid-diagrams` and the diagrams in both Gist explainers.
- `agent-browser` and `jq`: the crm-web QA skills.
- `claude`: `jbootz-claude-review`.

`make test` exercises the Mermaid renderer and fails if `mermaid-ascii` or
`mmdc` is missing.

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

## Validate skill metadata

```sh
make validate
```

This parses each skill's YAML frontmatter with Ruby's standard-library Psych.
It uses the Ruby runtime pinned in `mise.toml`; no Python or PyYAML
dependency is needed.
