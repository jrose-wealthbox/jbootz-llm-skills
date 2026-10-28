# Shared agent instructions

Canonical source for shared instructions.

Keep concise and project-independent. Agent-specific
behavior goes in relevant skill or harness config.

When user explicitly requests one-shot execution or opts out of optional workflow skills, skip those steps and act within the stated scope; retain required safety and validation checks.

## Required tools

Check for tools required by the requested workflow before investing in it. If a required tool or access is unavailable, stop that workflow, tell the user what is missing and how it affects the result, and wait before using a materially slower or less effective workaround. Continue with a fallback when the user has authorized it.

Use `jq` or `Read` to parse JSON, not `python -c`, unless python is truly needed for complex parsing `jq` can't handle.

## Git writes in restricted sandboxes

When the harness declares `.git` read-only and supports escalation, request
escalation on the first authorized Git write (such as staging or committing)
rather than trying known-blocked write first. Keep local commits and remote
pushes in separate commands. Before a push, identify the remote and destination
branch and verify that the user's authorization covers that destination. All
actions remain subject to harness's approval checks.

## Code Style

- Always include units in identifier names. Standard SI base unit abbreviations and prefixes (m, km, kg, s, etc) are okay.
  - BAD: `READ_SIZE`, `LENGTH`
  - GOOD: `READ_SIZE_BYTES`, `LENGTH_M`
- Prioritize human readability
- Ensure identifier names are descriptive and convey intent (and contents, if applicable)
  - If changing existing code update identifier names to reflect intent/contents if needed

## Session length

After a feature is committed and pushed, if the conversation has been compacted, suggest starting a fresh session with a short handoff (what shipped, what is next, where lessons were recorded) instead of continuing: later turns otherwise carry every earlier feature's context.

## Jbootz.SCOUT delegation

Use the `Jbootz.SCOUT` subagent for bounded mechanical work when the command is known or can be stated exactly and the result can be summarized as evidence. Examples: running specified tests, searching the repository, parsing verbose logs, and reporting aggregate counts with complete failure details.

Give `Jbootz.SCOUT` the exact command, working directory, constraints, and required report format. Jbootz.SCOUT observes and compresses evidence; the parent agent remains responsible for diagnosis, decisions, and edits. Do not delegate ambiguous requirements, root-cause analysis, architectural decisions, security judgments, code-quality validation, correctness validation, or source changes to Jbootz.SCOUT unless the user specifically asks.

## Bounded reads

- Budget the combined output of parallel calls against the enclosing tool response limit, leaving room for wrappers and summaries. Several individually bounded reads can still overflow one response; split the batch when needed.
- Start with filenames and counts (`rg --files`, `git diff --name-only`, or a JSON projection), then read the relevant content. Use line ranges such as `sed -n '120,180p' file` or JSON slices with a total count; page through the rest when complete coverage is required. Do not combine a full PR body, file list, and source dump in one result.
- Filter tool discovery by the required capability and return matching names with short descriptions; do not print the full inventory.
- Filter large output with `rg`, `jq`, or bounded `sed` before returning it. For semantic compression, give `Jbootz.SCOUT` one bounded read; request counts, relevant evidence, and complete failures. Avoid duplicate parent reads.
- Treat truncation as incomplete evidence. Identify the missing files, fields, or ranges and read only those in smaller chunks, or delegate their extraction. Do not repeat the oversized read, raise the output limit, or treat an unread remainder as reviewed.

## Browser Automation

Use headless `agent-browser` for web automation. `agent-browser --help` for all commands.

Core workflow:

1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes

## When Working in crm-web

- When local QA reports pending development migrations, run `bin/wealthbox exec bundle exec rails db:migrate`, then resume QA. A webserver restart does not apply migrations; do not hand this step back to the user.
- Before initializing tenant-scoped models in runner, console, or QA seed scripts, establish the actor with `Current.set_user(user) { ... }` at the script entry point. `TenantManager` checks context during initialization; the scoped helper restores the previous context. Do not move context setup into commands or services. The implementation is `app/lib/current.rb`; see `docs/current-context-guidelines.md`.
- When writing STI type discriminants whose allowlist names base classes, use `resource.class.base_class.name`. For example, comment resource types accept `Contact`, while `Person` and `Household` are Contact subclasses. Apply this normalization only when the allowlist requires the base class.

## Skills

Use these skills only when the user or another skill explicitly requests this skill.

"- foo*" means it applies to all skills beginning with "foo"

- anthropic*
- chrome-devtools*
- chrome*
- find-skills
- frontend-design:frontend-design
- hookify*
- jbootz*
- superpowers:using-superpowers
- superset*
- wealthbox:adr
- wealthbox:cleanup-code
- wealthbox:diagnose-and-fix-error
- wealthbox:docs
- wealthbox:dogfood
- wealthbox:fix-honeybadger
- wealthbox:generate-meme
- wealthbox:generate-production-investigation
- wealthbox:hb-monitor
- wealthbox:headless-component-designer
- wealthbox:issue-to-draft-pr
- wealthbox:learnings
- wealthbox:lgtm
- wealthbox:linear-project-automation
- wealthbox:open-pr
- wealthbox:open-spike-pr
- wealthbox:pr-quiz
- wealthbox:pr-stack-nav
- wealthbox:pr-stack-nav
- wealthbox:qa-checklist
- wealthbox:query-database
- wealthbox:request-log-search
- wealthbox:request-log-search
- wealthbox:request-skill
- wealthbox:request-skill
- wealthbox:screenshot
- wealthbox:search-wealthbox-docs
- wealthbox:split-pr
- wealthbox:take-webpage-screenshot
- wealthbox:video-assembly
- wealthbox:video-walkthrough
