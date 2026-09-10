#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/jbootz-skills-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

copy_fixture() {
  fixture=$1
  mkdir -p "$fixture"
  cp -R "$repo_root/agents" "$repo_root/bin" "$repo_root/global" "$repo_root/install" "$repo_root/skills" "$fixture/"
  fixture=$(CDPATH='' cd -- "$fixture" && pwd -P)
}

assert_link_to() {
  link=$1
  expected=$2

  [ -L "$link" ] || fail "expected symlink: $link"
  actual=$(readlink "$link")
  [ "$actual" = "$expected" ] || fail "$link points to $actual, expected $expected"
}

assert_contains() {
  file=$1
  expected=$2

  rg -F --quiet -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_regular_file() {
  file=$1

  [ -f "$file" ] || fail "expected regular file: $file"
  [ ! -L "$file" ] || fail "expected physical file, found symlink: $file"
}

fixture="$test_root/basic-repo"
copy_fixture "$fixture"
claude_root="$test_root/basic-claude"
codex_root="$test_root/basic-codex"

first_output=$(CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install")
case "$first_output" in
  *'claude-code: linked'*'codex: linked'*) ;;
  *) fail "first install did not report links" ;;
esac

for skill in "$fixture/skills"/*; do
  name=${skill##*/}
  assert_link_to "$claude_root/skills/$name" "$skill"
  assert_link_to "$codex_root/skills/$name" "$skill"
done

assert_regular_file "$claude_root/agents/scout.md"
assert_regular_file "$codex_root/agents/scout.toml"
"$fixture/bin/render-agent" "$fixture/agents/scout" claude-code > "$test_root/expected-scout.md"
"$fixture/bin/render-agent" "$fixture/agents/scout" codex > "$test_root/expected-scout.toml"
cmp -s "$claude_root/agents/scout.md" "$test_root/expected-scout.md" || fail "Claude agent was not rendered from canonical source"
cmp -s "$codex_root/agents/scout.toml" "$test_root/expected-scout.toml" || fail "Codex agent was not rendered from canonical source"

for global_file in "$claude_root/CLAUDE.md" "$codex_root/AGENTS.md"; do
  [ -f "$global_file" ] || fail "missing managed global instructions: $global_file"
  assert_contains "$global_file" '<!-- BEGIN jbootz-llm-skills global instructions -->'
  assert_contains "$global_file" 'Canonical source for shared instructions.'
  assert_contains "$global_file" '<!-- END jbootz-llm-skills global instructions -->'
done

{
  printf '%s\n' 'user Claude instructions before'
  cat "$claude_root/CLAUDE.md"
  printf '%s\n' 'user Claude instructions after'
} > "$test_root/claude-global-with-user-content"
mv "$test_root/claude-global-with-user-content" "$claude_root/CLAUDE.md"

{
  printf '%s\n' 'user Codex instructions before'
  cat "$codex_root/AGENTS.md"
  printf '%s\n' 'user Codex instructions after'
} > "$test_root/codex-global-with-user-content"
mv "$test_root/codex-global-with-user-content" "$codex_root/AGENTS.md"

cp "$claude_root/CLAUDE.md" "$test_root/claude-global-before-second-install"
cp "$codex_root/AGENTS.md" "$test_root/codex-global-before-second-install"

second_output=$(CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install")
case "$second_output" in
  *'claude-code: unchanged'*'codex: unchanged'*) ;;
  *) fail "second install was not idempotent" ;;
esac

cmp -s "$claude_root/CLAUDE.md" "$test_root/claude-global-before-second-install" || fail "second install changed Claude global instructions"
cmp -s "$codex_root/AGENTS.md" "$test_root/codex-global-before-second-install" || fail "second install changed Codex global instructions"

printf '%s\n' 'Updated canonical instructions.' > "$fixture/global/global.md"
CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >/dev/null
assert_contains "$claude_root/CLAUDE.md" 'Updated canonical instructions.'
assert_contains "$codex_root/AGENTS.md" 'Updated canonical instructions.'
assert_contains "$claude_root/CLAUDE.md" 'user Claude instructions before'
assert_contains "$claude_root/CLAUDE.md" 'user Claude instructions after'
assert_contains "$codex_root/AGENTS.md" 'user Codex instructions before'
assert_contains "$codex_root/AGENTS.md" 'user Codex instructions after'
if rg -F --quiet -- 'Canonical source for shared instructions.' "$claude_root/CLAUDE.md"; then
  fail "Claude global instructions were not replaced"
fi
[ "$(rg -F --count 'Updated canonical instructions.' "$claude_root/CLAUDE.md")" = '1' ] || fail "Claude global instructions were duplicated"

printf '\nUpdated agent instructions.\n' >> "$fixture/agents/scout/instructions.md"
CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >/dev/null
assert_contains "$claude_root/agents/scout.md" 'Updated agent instructions.'
assert_contains "$codex_root/agents/scout.toml" 'Updated agent instructions.'
assert_regular_file "$codex_root/agents/scout.toml"

fixture="$test_root/conflict-repo"
copy_fixture "$fixture"
claude_root="$test_root/conflict-claude"
codex_root="$test_root/conflict-codex"
mkdir -p "$claude_root/skills"
mkdir -p "$codex_root"
printf 'keep me\n' > "$claude_root/skills/jbootz-helloworld"
mkdir -p "$claude_root/agents"
printf 'keep this agent\n' > "$claude_root/agents/scout.md"
printf '%s\n' 'user Claude instructions' > "$claude_root/CLAUDE.md"
printf '%s\n' 'user Codex instructions' > "$codex_root/AGENTS.md"

if CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >"$test_root/conflict-output" 2>&1; then
  fail "install succeeded despite a destination conflict"
fi

[ "$(cat "$claude_root/skills/jbootz-helloworld")" = 'keep me' ] || fail "conflict was overwritten"
[ "$(cat "$claude_root/agents/scout.md")" = 'keep this agent' ] || fail "agent conflict was overwritten"
assert_contains "$claude_root/CLAUDE.md" 'user Claude instructions'
assert_contains "$codex_root/AGENTS.md" 'user Codex instructions'
assert_link_to "$codex_root/skills/jbootz-helloworld" "$fixture/skills/jbootz-helloworld"
assert_regular_file "$codex_root/agents/scout.toml"
assert_contains "$codex_root/agents/scout.toml" 'Generated by jbootz-llm-skills for scout'

fixture="$test_root/legacy-repo"
copy_fixture "$fixture"
claude_root="$test_root/legacy-claude"
codex_root="$test_root/legacy-codex"
mkdir -p "$claude_root/agents" "$codex_root/agents"
ln -s "$fixture/agents/scout/claude-code.md" "$claude_root/agents/scout.md"
ln -s "$fixture/agents/scout/codex.toml" "$codex_root/agents/scout.toml"
legacy_output=$(CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install")
case "$legacy_output" in
  *'claude-code: migrated'*'codex: migrated'*) ;;
  *) fail "legacy agent links were not reported as migrated" ;;
esac
assert_regular_file "$claude_root/agents/scout.md"
assert_regular_file "$codex_root/agents/scout.toml"

fixture="$test_root/malformed-repo"
copy_fixture "$fixture"
claude_root="$test_root/malformed-claude"
codex_root="$test_root/malformed-codex"
mkdir -p "$claude_root"
printf '%s\n' '<!-- BEGIN jbootz-llm-skills global instructions -->' '<!-- BEGIN jbootz-llm-skills global instructions -->' > "$claude_root/CLAUDE.md"
cp "$claude_root/CLAUDE.md" "$test_root/malformed-claude-before"

if CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >"$test_root/malformed-output" 2>&1; then
  fail "install accepted duplicated managed markers"
fi

cmp -s "$claude_root/CLAUDE.md" "$test_root/malformed-claude-before" || fail "malformed Claude file was modified"

fixture="$test_root/invalid-repo"
copy_fixture "$fixture"
mkdir -p "$fixture/skills/Bad_Name"
printf '%s\n' '---' 'name: Bad_Name' 'description: invalid test skill' '---' > "$fixture/skills/Bad_Name/SKILL.md"
mkdir -p "$fixture/agents/Bad_Name"
printf '%s\n' 'name: bad' > "$fixture/agents/Bad_Name/agent.yml"
claude_root="$test_root/invalid-claude"
codex_root="$test_root/invalid-codex"

if CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >"$test_root/invalid-output" 2>&1; then
  fail "install accepted an invalid skill name"
fi

[ ! -e "$claude_root" ] || fail "validation failure created a Claude directory"
[ ! -e "$codex_root" ] || fail "validation failure created a Codex directory"

fixture="$test_root/empty-repo"
copy_fixture "$fixture"
rm -rf "$fixture/agents" "$fixture/skills"
mkdir -p "$fixture/agents" "$fixture/skills"
claude_root="$test_root/empty-claude"
codex_root="$test_root/empty-codex"
CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >/dev/null
[ -d "$claude_root/skills" ] || fail "empty install did not create Claude skill directory"
[ -d "$codex_root/skills" ] || fail "empty install did not create Codex skill directory"
[ -d "$claude_root/agents" ] || fail "empty install did not create Claude agent directory"
[ -d "$codex_root/agents" ] || fail "empty install did not create Codex agent directory"

printf 'PASS: installer behavior\n'
