# LLM Agent Skills Primer

This repository is a personal, cross-agent collection of reusable skills for
Codex CLI and Claude Code CLI. The same `SKILL.md` source can be installed into
both tools, while invocation syntax and packaging details remain host-specific.

## The mental model

The terms overlap, but they describe different layers:

| Concept | What it means |
| --- | --- |
| CLI / host | The runtime that owns the conversation, permissions, tools, and sessions |
| Project instructions | Always-on repository guidance |
| Skill | Reusable instructions, knowledge, or workflow |
| Tool | A callable capability such as shell, file editing, web search, or an API |
| MCP | A standard way to connect external tools and context |
| Agent / subagent | An independent reasoning loop, often with an isolated context |
| Plugin | A package that distributes skills, agents, hooks, and tools together |
| Hook | Automation triggered by a lifecycle event |

A useful analogy is:

- A skill is a recipe.
- A tool is an appliance the agent can operate.
- An agent is a cook with its own context and permissions.
- A plugin is a box containing recipes, appliances, and automation.
- The CLI is the kitchen where everything runs.

## Cross-platform comparison

| Concept | Codex CLI | Claude Code CLI |
| --- | --- | --- |
| Project instructions | `AGENTS.md` | `CLAUDE.md` |
| Skill format | `SKILL.md` with `name` and `description` | `SKILL.md` with `name` and `description` |
| Explicit skill invocation | Type `$skill-name` or use `/skills` in the TUI | Type `/skill-name` |
| Automatic skill invocation | Yes, based on the skill description | Yes, based on the skill description |
| MCP configuration | Usually `config.toml`; inspect with `/mcp` | Commonly `.mcp.json`; inspect with `/mcp` |
| Custom agents | `.codex/agents/*.toml` or `~/.codex/agents/*.toml` | `.claude/agents/*.md` or `~/.claude/agents/*.md` |
| Agent controls | Ask Codex to use subagents; inspect with `/agent` | Manage with `/agents`; Claude can invoke agents automatically |
| Plugin management | Codex plugin marketplaces and plugin packages | `/plugin marketplace ...` and `/plugin install ...` |
| Scripted execution | `codex exec "..."` | `claude -p "..."` |

The shared portability boundary is the skill content. Plugin manifests,
configuration files, custom-agent formats, and command syntax should be treated
as host-specific.

Official references:

- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Codex CLI command reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
- [Claude Code skills](https://code.claude.com/docs/en/slash-commands)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)

## Skills

A skill is a directory containing a `SKILL.md` file and optional supporting
files:

~~~text
my-skill/
├── SKILL.md
├── scripts/
├── references/
└── assets/
~~~

The portable core looks like this:

~~~yaml
---
name: my-skill
description: Explain when this skill should be used.
---
~~~

The Markdown body contains the instructions the agent follows. Supporting
scripts, references, and assets should live inside the skill directory so the
skill remains self-contained.

Both Codex and Claude Code can select skills automatically when a task matches
the description. They also support explicit invocation, which is preferable
when you specifically want a skill to run.

### Codex invocation

Inside the Codex interactive composer, use either:

~~~text
$my-skill
~~~

or:

~~~text
/skills
~~~

and select the skill from the picker.

The `$my-skill` form belongs in the Codex prompt composer. It is not a shell
command.

### Claude Code invocation

Inside Claude Code, use:

~~~text
/my-skill
~~~

Claude Code also treats files in `.claude/commands/` as skills-style slash
commands for compatibility, although `skills/<name>/SKILL.md` is the preferred
form for new work.

### Keep skills portable

For a skill intended to work in both hosts:

- Use the shared `name` and `description` frontmatter.
- Put the main workflow in ordinary Markdown.
- Keep scripts and references inside the skill directory.
- Avoid relying on host-specific interpolation or frontmatter unless the skill
  is explicitly platform-specific.
- Clearly document external dependencies such as `gh`, Python, Node, or an MCP
  server.

This repository's current skills follow that portable pattern.

The repository can also install custom agents. Their behavior has one canonical
source even though Codex requires TOML and Claude Code requires Markdown:

~~~text
agents/<agent-name>/agent.yml
agents/<agent-name>/instructions.md
~~~

The included `scout` agent is a deliberately narrow, low-cost worker for
running specified tests, searching files, parsing verbose output, and returning
compressed evidence. It should not diagnose failures or edit source files; the
parent agent owns those decisions.

## Project instructions

Project instruction files are background context, not workflows that you invoke.
Use them for rules that should apply to nearly every task, such as:

- preferred package manager
- test and lint commands
- repository architecture
- coding conventions
- permission or safety expectations
- files that should not be edited

Codex reads `AGENTS.md` files. Claude Code reads `CLAUDE.md` files. The names
are different, so a repository supporting both tools may maintain both files or
use a shared source plus thin host-specific adapters.

This repository uses a managed shared source instead of replacing either host's
global file:

~~~text
global/global.md                         canonical source
    ├── $CODEX_HOME/AGENTS.md             managed Codex block
    └── $CLAUDE_CONFIG_DIR/CLAUDE.md      managed Claude Code block

agents/scout/agent.yml                   shared metadata and host settings
agents/scout/instructions.md             shared Scout behavior
    ├── $CODEX_HOME/agents/scout.toml    rendered Codex agent
    └── $CLAUDE_CONFIG_DIR/agents/scout.md rendered Claude agent
~~~

`make install` creates each file when absent, appends a marked block when the
file already exists without one, and replaces only that block on later runs.
Everything outside the markers remains user-owned. Malformed or duplicated
markers cause the installer to stop for that host rather than guessing how to
rewrite the file. The block is copied into both files because Claude Code's
`@path` imports are not a documented cross-host mechanism.

References:

- [Codex `AGENTS.md`](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude Code configuration files](https://code.claude.com/docs/en/claude-directory)

## Tools and MCP

A tool is an actual capability the agent can call. Examples include:

- reading a file
- editing a file
- running a shell command
- searching the web
- querying GitHub
- controlling a browser
- calling an external API

MCP, the Model Context Protocol, is a standard way to provide external tools
and context to an agent. An MCP server might expose tools for GitHub, Linear,
databases, browsers, or internal services.

A skill usually explains how and when to use a tool; it does not necessarily
create the tool itself:

~~~text
MCP server: provides GitHub operations
Skill: explains your preferred pull-request workflow
Agent: decides when to call the GitHub tools
~~~

Tool calls are usually selected by the model in response to the task. You do
not normally invoke an MCP tool by typing its tool name as a slash command.

Codex stores MCP configuration in `config.toml` and supports project-scoped
configuration in trusted repositories. Claude Code commonly uses `.mcp.json`.

References:

- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)

## Agents and subagents

The CLI itself is already an agent: it reasons, calls tools, and works toward a
goal.

A subagent is a separate agent loop with its own context. Use one when you want:

- a large codebase exploration isolated from the main conversation
- several independent reviews in parallel
- a specialized worker with different permissions or model settings
- a summary returned instead of every intermediate detail

### Codex agents

Codex supports built-in and custom agents. Custom agents are configured with
TOML files under:

~~~text
~/.codex/agents/
.codex/agents/
~~~

They define fields such as `name`, `description`, and
`developer_instructions`, and can also configure model, sandbox, MCP, and skill
settings.

In an interactive session, ask Codex directly:

~~~text
Review this branch with separate read-only agents for security, tests, and maintainability.
~~~

Use `/agent` to inspect or switch between running agent threads.

See [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).

### Claude Code agents

Claude Code custom agents are Markdown files under:

~~~text
~/.claude/agents/
.claude/agents/
~~~

They can define a specialized prompt, tools, model, permissions, skills to
preload, maximum turns, background behavior, and worktree isolation.

Use `/agents` to manage them, or ask Claude Code to delegate work to a named
specialist.

See [Claude Code subagents](https://code.claude.com/docs/en/subagents).

A skill and a subagent can work together: a subagent can preload a skill, or a
skill can request isolated execution when the host supports it.

## Plugins

A plugin is primarily a packaging and distribution mechanism. It groups several
capabilities so someone can install them as one unit.

A plugin might contain:

~~~text
skills/
agents/
hooks/
MCP configuration
scripts/
~~~

Plugins are useful when you want versioning, discovery, multiple skills,
specialized agents, hooks, or MCP servers bundled together.

### Codex plugins

Codex plugins can use a root `plugin.json`, a `skills/` directory, MCP
configuration, and optional lifecycle hooks. Codex supports marketplaces for
discovering and distributing plugins.

Typical marketplace management includes:

~~~text
codex plugin marketplace add owner/repo
codex plugin marketplace list
~~~

After installation, bundled skills are still used through Codex's skill
mechanism, such as `$skill-name` or `/skills`.

See [Codex plugin packaging](https://developers.openai.com/plugins/build/plugins).

### Claude Code plugins

Claude Code plugins commonly use:

~~~text
.claude-plugin/plugin.json
skills/
agents/
hooks/
.mcp.json
~~~

Typical installation commands are:

~~~text
claude plugin marketplace add owner/repo
claude plugin install my-plugin@my-marketplace
~~~

Plugin skills are namespaced by the plugin name:

~~~text
/my-plugin:skill-name
~~~

See [Claude Code plugins](https://code.claude.com/docs/en/plugins) and the
[plugin reference](https://code.claude.com/docs/en/plugins-reference).

The important distinction is:

- `SKILL.md` is reusable content.
- A plugin manifest describes a distributable package.
- Plugin installation enables the package.
- Skill invocation runs one workflow from that package.

The plugin layer is more host-specific than the skill layer. A portable skill
can usually be shared directly; a portable plugin may still need host-specific
manifests or marketplace metadata.

## Hooks

A hook is automation triggered by an event rather than selected as a normal
workflow. Examples include:

- run a formatter after a file edit
- validate a command before execution
- notify you when a long task finishes
- run a security check when a session stops

Use a hook when timing matters and the action should happen whenever a matching
event occurs. Use a skill when the user or model should deliberately load a
workflow and apply it to a task.

Hooks can be distributed through plugins, but their event names and
configuration formats are host-specific.

## CLI invocation cheat sheet

### Codex

Start an interactive session:

~~~sh
codex
~~~

Start with an initial prompt:

~~~sh
codex "explain this repository"
~~~

Run a scripted or CI-style task:

~~~sh
codex exec "summarize the failing tests"
~~~

Emit machine-readable JSONL events:

~~~sh
codex exec --json "review the repository structure"
~~~

### Claude Code

Start an interactive session:

~~~sh
claude
~~~

Start with an initial prompt:

~~~sh
claude "explain this repository"
~~~

Run a one-off query and exit:

~~~sh
claude -p "summarize the failing tests"
~~~

Pipe content into a one-off query:

~~~sh
cat logs.txt | claude -p "explain the likely cause"
~~~

The key scripting difference is that Codex uses `codex exec`, while Claude
Code uses `claude -p`.

References:

- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)

## Choosing the right option

| Need | Use |
| --- | --- |
| A rule that applies to almost every task | Project instructions: `AGENTS.md` or `CLAUDE.md` |
| A repeated checklist, procedure, or body of knowledge | Skill |
| Access to GitHub, Linear, a database, or another external service | MCP tool |
| Separate context or parallel workers | Agent / subagent |
| Event-triggered automation | Hook |
| Several skills, agents, hooks, and tools distributed together | Plugin |
| A CI or shell pipeline integration | Non-interactive CLI mode |

Do not turn every skill into an agent. Most reusable workflows should remain
skills. Add an agent when context isolation, specialization, or parallel work
materially improves the task.

## How this repository fits

The repository currently focuses on standalone skills:

~~~text
skills/<skill-name>/SKILL.md
~~~

Its installer creates symlinks into the native user-level skill directories for
Claude Code and Codex, manages the shared global instruction block described
above, and preserves unrelated installed skills. Run:

~~~sh
make install
~~~

Then start a new agent session if the host does not detect the new skill,
agent, or instruction change immediately. Skill edits do not require
reinstalling because they are symlinked. Agent and `global/global.md` edits do,
because the installer renders or copies them into native configuration files.

The existing skills illustrate two useful categories:

- `jbootz-helloworld` is a tiny installation smoke test.
- `jbootz-pr-explainer` is a real workflow with external dependencies such as
  the `gh` CLI, GitHub access, and Linear context.

That is a sensible progression for a personal collection: begin with
standalone, portable skills; add scripts and references as workflows mature;
introduce MCP when an external service needs a reusable tool interface; and
package related capabilities as a plugin when distribution becomes important.

### Codex path detail

The current Codex adapter targets:

~~~text
$CODEX_HOME/skills
~~~

and defaults to:

~~~text
$HOME/.codex/skills
~~~

Current Codex documentation also describes `$HOME/.agents/skills` as a primary
user-level skill location and explicitly supports symlinked skill folders. The
repository may therefore be relying on compatibility behavior in the Codex
versions it supports. Validate the target path against the versions you intend
to support before changing the adapter.

## Further reading

- [Repository README](../README.md)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex plugins](https://developers.openai.com/plugins/build/plugins)
- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Claude Code skills](https://code.claude.com/docs/en/slash-commands)
- [Claude Code plugins](https://code.claude.com/docs/en/plugins)
- [Claude Code subagents](https://code.claude.com/docs/en/subagents)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
