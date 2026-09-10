# Shared agent instructions

This file is the canonical source for shared instructions.

Keep shared instructions concise and project-independent. Add agent-specific
behavior to the relevant skill or harness configuration.

## Scout delegation

Use the `scout` subagent for bounded mechanical work when the command is known
or can be stated exactly and the result can be summarized as evidence. Typical
Scout tasks include running specified tests, searching the repository, parsing
verbose logs, and reporting aggregate counts with complete failure details.

Give Scout the exact command, working directory, constraints, and required
report format. Scout observes and compresses evidence; the parent agent remains
responsible for diagnosis, decisions, and edits. Do not delegate ambiguous
requirements, root-cause analysis, architectural decisions, security
judgments, or source changes to Scout.
