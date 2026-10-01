---
name: jbootz-pr-file-comments
description: Use when asked to add a file-level comment to each changed, added, renamed, or deleted file in a GitHub pull request, such as explaining why each file changed or was removed.
---

# PR File Comments

Post exactly one file-level review comment per target file in a GitHub pull request, then prove the count. A partial or duplicated set is a failed run.

## Scope

- Default targets: every file in the PR, including removed and renamed files. Honor an explicit subset or exclusion.
- Comment purpose comes from the request, for example the rationale for each change or deletion. Follow any example comment the user links; read it with `gh api` first.
- Post as the authenticated `gh` user. Never edit or delete anyone else's comments.

## 1. Resolve the PR and its files

```bash
gh pr view <pr> --json number,url,headRefOid,baseRefName
gh api repos/<owner>/<repo>/pulls/<number>/files --paginate \
  --jq '.[] | {filename, status, previous_filename}'
gh api user --jq .login
```

`gh pr view --json files` omits file status; use the `pulls/<number>/files` endpoint so removed and renamed files are not missed.

## 2. Find existing file-level comments

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate \
  --jq '.[] | select(.subject_type == "file") | {path, user: .user.login, id}'
```

A target is done when it already has one comment from the authenticated user. Report targets with two or more of that user's comments as duplicates. Delete duplicates only with explicit approval; deletion is visible to everyone on the PR.

## 3. Draft one body per remaining file

- Ground each body in that file's diff, commit messages, and the conversation. Never write generic filler that would fit any file.
- Removed files: say why the file was deleted and where its behavior or coverage now lives, if anywhere.
- Renamed files: name the previous path.
- Match the tone and length of the user's example comment when one exists.
- If the user asked to review drafts first, show path → body and wait for approval.

## 4. Post in one command

Write one JSON object per line to a temporary file. Build every line with `jq -nc --arg ...` so quotes and newlines in bodies stay valid. Never name a shell variable `path`: in zsh it is tied to `$PATH`, and assigning it breaks every later command.

```bash
jq -nc --arg path "$file_path" --arg body "$body" --arg sha "$head_sha" \
  '{path: $path, body: $body, commit_id: $sha, subject_type: "file"}' >> "$payload_file"
```

Then post every line in a single shell invocation, which needs one approval, and keep going past individual failures:

```bash
failed=0
while IFS= read -r payload; do
  printf '%s' "$payload" | gh api --method POST \
    repos/<owner>/<repo>/pulls/<number>/comments --input - >/dev/null \
    || { failed=$((failed + 1)); printf 'FAILED %s\n' "$(jq -r .path <<<"$payload")"; }
done < "$payload_file"
echo "failed=$failed"
```

The batched reviews endpoint does not document file-level comments; post them individually through `pulls/<number>/comments` with `subject_type: "file"`.

## 5. Verify the exact count

Re-fetch the comments and count the authenticated user's file-level comments per target path:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate \
  --jq '[.[] | select(.subject_type == "file" and .user.login == "<login>") | .path]
        | group_by(.) | map({path: .[0], count: length})'
```

Every target must have a count of exactly 1. Retry missing paths once. Report any path that still fails, with the API error.

## Report

State the PR, the number of targets, how many were posted, already present, failed, and duplicated, and list every non-1 count by path. Never report success without the Step 5 count.
