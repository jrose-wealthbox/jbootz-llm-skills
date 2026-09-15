---
name: jbootz-high-end-sausage-factory
description:
---

The user should supply the name of a file containing ideas for a feature, or a link to a Linear issue. If none was supplied, STOP and ask the user what we're supposed to plan and execute.

## Launch

Launch three subagents: "Planner", "Reviewer", "Worker"

- "Planner" and "Reviewer": Sol/Opus by default or Astra/Fable if the user requests.
- "Worker": Luna or Terra (high effort)

## Plan

- Have "Planner" use Superpowers to write a design doc. Pass it all of the necessary context such as a link to the Linear ticket or idea document.
- Have "Reviewer" perform an adversarial review of the design doc
- Have "Planner" revise the design doc (if necessary) based on the feedback from "Reviewer"
- Have "Planner" use Superpowers to create a detailed implementation plan
- Have "Planner" revise the implementation doc (if necessary) based on the feedback from "Reviewer"
- Have "Worker" execute the implementation plan. After each step, commit and push.
