# Shared agent instructions

Canonical source for shared instructions.

Keep it concise and project-independent. Agent-specific
behavior goes in relevant skill or harness config.

## Jbootz.SCOUT delegation

Use the `Jbootz.SCOUT` subagent for bounded mechanical work when the command is known or can be stated exactly and the result can be summarized as evidence. Examples: running specified tests, searching the repository, parsing verbose logs, and reporting aggregate counts with complete failure details.

Give `Jbootz.SCOUT` the exact command, working directory, constraints, and required report format. Jbootz.SCOUT observes and compresses evidence; the parent agent remains responsible for diagnosis, decisions, and edits. Do not delegate ambiguous requirements, root-cause analysis, architectural decisions, security judgments, code-quality validation, correctness validation, or source changes to Jbootz.SCOUT unless the user specifically asks.

## Browser Automation

Use `agent-browser` for web automation. `agent-browser --help` for all commands.

Core workflow:

1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes
