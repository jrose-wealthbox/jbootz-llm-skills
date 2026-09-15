#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd -P)
renderer="$repo_root/skills/jbootz-mermaid-diagrams/scripts/render.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/jbootz-mermaid-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -x "$renderer" ] || fail "renderer is not executable: $renderer"

cat > "$test_root/diagram.mmd" <<'EOF'
flowchart LR
  A[Start] --> B[End]
EOF

(
  cd "$test_root"
  "$renderer" text diagram.mmd > text.out
  "$renderer" ascii diagram.mmd > ascii.out
)

rg -F --quiet -- 'Start' "$test_root/text.out" || fail "text mode omitted diagram content"
rg -F --quiet -- 'Start' "$test_root/ascii.out" || fail "ascii mode omitted diagram content"

"$renderer" svg "$test_root/diagram.mmd" "$test_root/output/diagram" > "$test_root/svg.out"
[ -s "$test_root/output/diagram.svg" ] || fail "svg mode did not create an SVG"

mkdir -p "$test_root/tmp-output"
TMPDIR="$test_root/tmp-output" "$renderer" svg "$test_root/diagram.mmd" > "$test_root/default-svg.out"
default_svg=$(tail -n 1 "$test_root/default-svg.out" | sed 's/^SVG: //')
case "$default_svg" in
  "$test_root/tmp-output"/jbootz-mermaid.*/diagram.svg) ;;
  *) fail "default SVG output was not placed under TMPDIR: $default_svg" ;;
esac
[ -s "$default_svg" ] || fail "default SVG output was not created"
[ ! -e "$test_root/diagram.svg" ] || fail "default SVG output cluttered the source directory"

"$renderer" both "$test_root/diagram.mmd" "$test_root/output/both" > "$test_root/both.out"
[ -s "$test_root/output/both.svg" ] || fail "both mode did not create an SVG"
rg -F --quiet -- 'SVG:' "$test_root/both.out" || fail "both mode did not report the SVG"

cat > "$test_root/state.mmd" <<'EOF'
stateDiagram-v2
  [*] --> Active
EOF

if "$renderer" both "$test_root/state.mmd" "$test_root/output/state" > "$test_root/state.out" 2> "$test_root/state.err"; then
  :
else
  fail "both mode failed when terminal rendering did not support a valid diagram"
fi
[ -s "$test_root/output/state.svg" ] || fail "both mode dropped the SVG after terminal rendering failed"
rg -F --quiet -- 'terminal renderer does not support' "$test_root/state.err" \
  || fail "both mode did not report terminal renderer incompatibility"

printf '%s\n' 'PASS: Mermaid renderer behavior'
