


# Primary Goal

Summarize recent work done in the current project or git worktree, for human review and understanding. (Looking at summaries of my day helps me to commit things to long-term memory)

## Secondary Goal(s)

Include enough metadata for future metadata analysis to answer questions such as:
- Which sorts of activities consumed the most time
- LLM token use over time
- Finding other work patterns I haven’t thought of yet

## Sources

- Git history
- File history
- Codex and Claude transcripts
- Anything else you can think of?

## What to Include

Summarize:

- If the user is implementing a Linear issue, this is very important as it contextualizes the work that follows. The summary should include links to the relevant Linear issue(s) and other external documentation that informed this work.
- Links to external documentation such as issue tracker issues (Linear, etc) are crucial. Also include a brief summary of the external documentation, as it may not be available later so we need an offline summary
- Work done, files changed
- Decisions made, including solutions that were considered and rejected
	- Special emphasis for any decisions that were later reversed
- Technical challenges directly related to the work itself and how they were overcome
- Friction encountered by the LLM agent, such as permissioning issues or other problems
- Points where the user seemed angry. Usage of profanity by the user is a strong potential (but not absolute) signal
- Opening a github pull request (PR) is a big event and should be emphasized
- Other information you feel is consequential or relevant

## Scope

If the user is currently in a git worktree, include ONLY work from the relevant worktree.

If the user is not in a git worktree, summarize all work in the session

## Presentation

- Present information in bullet point format
- Information should be listed chronologically, newest first
- Group information, using markdown headers, by:
	- Date
		- Git repo or project parent folder (if any)
			- Worktree (if any)
				- External ticket number or issue number (if any)
					- Git branch (if any)
- Actual work performed goes into bullet points under a markdown header





## Work category tags (WORK_CATEGORY_TAGS)

Work bullet points should be categorized.

Currently allowable work categories are
			- `planning`
				- for writing planning documents, or the discussions that will lead to them
			- `building`
				- writing new code or performing other work
			- `fixing`
				- altering code as a result of a defect being remedied
			- `debugging`
				- determining the cause of a problem
			- `researching`
				- pure research, such as looking up documentation to see available options
			- `reviewing`
				- looking at code authored by another such as reviewing a PR (pull request)
			- `refactoring`
				- improving the structure of existing code, or improving the organization of files etc.
			- `optimizing`
				- improving the performance of existing code
			- `testing`
				- running automated tests, typically jest/specs/etc
			- `qa`
				- performing automated quality assurance (QA) such as using playwright or agent-browser, or other automated interactions with a running application
				- also includes time spent writing QA plans

Each work task receives ideally 1 but up to 3 tags.

If multiple tags are chosen, supply them in order of precedence. Example: if a task was ~75% debugging and ~25% fixing, tags should be `debugging,fixing`

If a type of work takes less than 10%, it probably doesn’t deserve a tag. Example: 90% planning 10% building should just be `planning`

Look for repeated work that doesn’t fall into the existing categories above. You MUST tell the user about this, and suggest new category tags if so

Wall clock time provides useful signal but remember that large amounts of time can be spent waiting for a user reply that is AFK or engaged in another task. If the “waiting for user reply” portion of a turn is >5 minutes, cap it at 5 minutes for this purpose.

## Describing Work Tasks Performed (Work Bullet Points)

Each task should roughly 15-60min of wall time although these are not hard limits. Prioritize logical task grouping over times. Conversation turns present strong but not absolute signal for logical task grouping.

Each task should be prefaced with the start time of day, if possible.

Use sub bullet points to provide additional details.

The final sub bullet point for each task should provide metadata in key/value format that is both human and machine readable

Example

```
- **9:34AM:** Optimized SQL queries in foo.rb
	- Resolved several N+1 queries in `get_data` by adding the referenced tables to the `.includes` clause
	- Added a new query_cache object to supply memoized data
	- *[categories:optimizing,building] [duration:58m] [model:opus 5.6] [model_effort:medium]*
```


## Writing style / How to present technical information

Format is markdown.

In general, use ASD-STE100 Simplified Technical English unless otherwise specified.

If a task or decision is complex, provide two versions of the explanation.

```
- {[HH:MM AM/PM]} [{WORK_CATEGORY}] {ultra-brief summary of the task or decision}
	- {plain English summary of the work, 1-2 sentences}
	- {deep technical explanation}
```

Example:

```
- Decided on a web server
	- Apache was deemed the best fit, because of wide support and team familiarity.
	- Puma’s threading model was deemed insufficient, native threads have performance issues on the STE-4879873 microcontroller we’re using. Apache has a fork specifically optimized for STE-4879873, which takes advantage of nanotechnology and neural integrations with interplanetary computing resources. Also because we need to work in an airgapped environment, Chuck’s multidecade experience was deemed critical as we will not be able to look things up online during working hours.
```



Examples:

```
# Tuesday, July 25 2098
## my-repo-name
### branch 1

- 10:23AM (work performed #1)
- 5:00PM (work performed #2)

### branch 2

- 9:00AM (work performed #3)
- 10:02PM (work performed #4)
