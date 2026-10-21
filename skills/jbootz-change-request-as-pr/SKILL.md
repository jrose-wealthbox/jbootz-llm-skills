---
name: jbootz-change-request-as-pr
description: Use when asked to implement a review's findings or suggested changes for another pull request as a separate PR, with one commit per change and a description that links each change to its commit.
---

# Change Request as PR

Turn a review of someone else's PR into a stacked PR. The PR has one commit per suggested change, and its description maps each change to its commit, severity, problem and fix.

## Rules

- **The commits MUST be on a branch other than the one that was reviewed.** Never commit to, push to, rebase or force-push the reviewed branch. If the current branch is the reviewed branch, create a new branch from its head before you edit anything.
- Open the PR against the reviewed branch, not the repository's default branch, so the diff contains only the suggested changes.
- Make one commit per suggested change. If one change also fixes another item, make one commit and say in the description which items it addresses. Do not make empty commits.
- Implement only the items the user selects. If the user says "all", implement every finding and readability item. Report items you could not implement, and why, under "Not in this PR".
- Do not use the repository's PR template. Use the [description format](#description-format) below. All other repository rules still apply, for example writing style, test commands and lint commands.

## 1. Collect the change list

- Use the review in the conversation. If there is none, ask for it, or run `jbootz-adversarial-review` when the user asks for a review first.
- Number the items as the review did: findings first, then readability items.
- Record each item's severity from the review. Use `Readability` for readability items, and the review's own label for process items.
- Before you edit, check each item against the current code. The reviewed branch may have changed since the review.

## 2. Set up the branch

```bash
gh pr view <pr> --json number,url,baseRefName,headRefName,headRefOid
git fetch origin <headRefName>
git switch -c <new-branch> origin/<headRefName>   # unless the user already made one
```

- Use the user's branch name if they give one.
- Confirm that the branch is not `<headRefName>`.
- Run the focused tests for the affected area once before you change anything. If they fail, fix the environment or report the failure before you continue. Otherwise you cannot tell a new failure from an old one.

## 3. Implement, one commit per item

For each item, in order:

1. Make the smallest change that fixes the item. Add or update a test that would fail without the change.
2. Run the focused tests and linters for the files you changed.
3. Stage files by path. Never stage files you did not change for this item, including stray changes that were already in the worktree.
4. Commit. Use the repository's commit message style, and name the change, not the review item.
5. Record the commit's short SHA next to the item.

## 4. Verify the whole branch

- Run the focused tests for every affected area and the linters for every changed file.
- Run `git diff --stat origin/<headRefName>...HEAD` and confirm that each changed file belongs to an item.
- Report any check you did not run.

## 5. Push and open the PR

```bash
git push -u origin <new-branch>
gh pr create --base <headRefName> --head <new-branch> --title "<title>" --body-file <body.md>
```

- Write `<body.md>` in your scratchpad, not in the repository.
- Request reviewers only when the user names them.
- If `gh pr create` or `gh pr edit` fails because the token is missing a scope, such as `read:org`, use the REST API instead:

  ```bash
  gh api -X PATCH repos/<owner>/<repo>/pulls/<number> -F body=@<body.md>
  gh api -X POST repos/<owner>/<repo>/pulls/<number>/requested_reviewers -f 'reviewers[]=<login>'
  ```

- After you publish, read the PR body back and confirm that every item has its commit link.

## Description format

Commit links use the full URL: `https://github.com/<owner>/<repo>/commit/<sha>`.

Each item's "Problem" section keeps the review's wording as closely as possible, including the "Where", "What happens" and "Why it happened" bullets. The "Change" section says what the commit does. Leave out the review's suggested fix, because "Change" replaces it.

```markdown
These changes come from the review of #<reviewed PR>. Each item is one commit. Line numbers in the "Problem" sections refer to the base branch, `<headRefName>`.

## 1. <Commit subject or short change name>

SEVERITY: <Medium | Low | Readability | ...>
Commit: https://github.com/<owner>/<repo>/commit/<sha>
Addresses: Finding 1, and readability items 1 and 4.

**Problem:** <one-line summary from the review>
- **Where:** `<file>:<lines>`.
- **What happens:** <the review's trace>
- **Why it happened:** <if the review said why>

**Change:**
- <what the commit does>
- <the test that covers it>

## 2. ...

## Not in this PR

<Each item you did not implement, and why.>

## Known limit

<Any limit you found and did not fix, if there is one.>

## Checks

- <Each test and lint command, with its result.>
- <Each check that was not run.>
```

Leave out "Not in this PR" and "Known limit" when they have no content.

## Report to the user

- The PR link, base branch and reviewers.
- A table of commit, change and the review items it addresses.
- Items you did not implement, and why.
- Behavior changes the reviewer should know about.
- The check results, and any check you did not run.
- Stray worktree changes that you left out of the commits.
