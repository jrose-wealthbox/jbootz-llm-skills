# Shared agent instructions

Canonical source for shared instructions.

Keep it concise and project-independent. Agent-specific
behavior goes in relevant skill or harness config.

When the user explicitly requests one-shot execution or opts out of optional workflow skills, skip those steps and act within the stated scope; retain required safety and validation checks.

## Required tools

Check for tools required by the requested workflow before investing in it. If a required tool or access is unavailable, stop that workflow, tell the user what is missing and how it affects the result, and wait before using a materially slower or less effective workaround. Continue with a fallback when the user has authorized it.

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
