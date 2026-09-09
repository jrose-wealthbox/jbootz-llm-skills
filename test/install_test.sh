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
  cp -R "$repo_root/bin" "$repo_root/install" "$repo_root/skills" "$fixture/"
  fixture=$(CDPATH='' cd -- "$fixture" && pwd -P)
}

assert_link_to() {
  link=$1
  expected=$2

  [ -L "$link" ] || fail "expected symlink: $link"
  actual=$(readlink "$link")
  [ "$actual" = "$expected" ] || fail "$link points to $actual, expected $expected"
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

second_output=$(CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install")
case "$second_output" in
  *'claude-code: unchanged'*'codex: unchanged'*) ;;
  *) fail "second install was not idempotent" ;;
esac

fixture="$test_root/conflict-repo"
copy_fixture "$fixture"
claude_root="$test_root/conflict-claude"
codex_root="$test_root/conflict-codex"
mkdir -p "$claude_root/skills"
printf 'keep me\n' > "$claude_root/skills/jbootz-helloworld"

if CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >"$test_root/conflict-output" 2>&1; then
  fail "install succeeded despite a destination conflict"
fi

[ "$(cat "$claude_root/skills/jbootz-helloworld")" = 'keep me' ] || fail "conflict was overwritten"
assert_link_to "$codex_root/skills/jbootz-helloworld" "$fixture/skills/jbootz-helloworld"

fixture="$test_root/invalid-repo"
copy_fixture "$fixture"
mkdir -p "$fixture/skills/Bad_Name"
printf '%s\n' '---' 'name: Bad_Name' 'description: invalid test skill' '---' > "$fixture/skills/Bad_Name/SKILL.md"
claude_root="$test_root/invalid-claude"
codex_root="$test_root/invalid-codex"

if CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >"$test_root/invalid-output" 2>&1; then
  fail "install accepted an invalid skill name"
fi

[ ! -e "$claude_root" ] || fail "validation failure created a Claude directory"
[ ! -e "$codex_root" ] || fail "validation failure created a Codex directory"

fixture="$test_root/empty-repo"
copy_fixture "$fixture"
rm -rf "$fixture/skills"
mkdir -p "$fixture/skills"
claude_root="$test_root/empty-claude"
codex_root="$test_root/empty-codex"
CLAUDE_CONFIG_DIR="$claude_root" CODEX_HOME="$codex_root" "$fixture/bin/install" >/dev/null
[ -d "$claude_root/skills" ] || fail "empty install did not create Claude skill directory"
[ -d "$codex_root/skills" ] || fail "empty install did not create Codex skill directory"

printf 'PASS: installer behavior\n'
