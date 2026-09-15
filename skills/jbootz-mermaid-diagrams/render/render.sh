#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  render.sh text  FILE
  render.sh ascii FILE
  render.sh svg   FILE [OUTPUT_BASE]
  render.sh both  FILE [OUTPUT_BASE]

Modes:
  text    Render Unicode terminal output.
  ascii   Render strict ASCII terminal output.
  svg     Render SVG using Mermaid CLI.
  both    Render Unicode terminal output and SVG.

Examples:
  render.sh text docs/architecture.mmd
  render.sh ascii docs/architecture.mmd
  render.sh svg docs/architecture.mmd
  render.sh svg docs/architecture.mmd docs/generated/architecture
  render.sh both docs/architecture.mmd

When OUTPUT_BASE is omitted, SVG output is written to a unique directory under
TMPDIR (or /tmp).
EOF
  exit 2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 127
  fi
}

[[ $# -ge 2 ]] || usage

mode="$1"
src="$2"
output_base="${3:-}"

if [[ ! -f "$src" ]]; then
  echo "error: Mermaid source file not found: $src" >&2
  exit 1
fi

render_text() {
  require_command mermaid-ascii
  mermaid-ascii --file "$src"
}

render_ascii() {
  require_command mermaid-ascii
  mermaid-ascii --file "$src" --ascii
}

default_output_base() {
  local source_name="${src##*/}"
  local diagram_name="${source_name%.*}"
  local temp_dir

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/jbootz-mermaid.XXXXXX")"
  printf '%s/%s' "$temp_dir" "$diagram_name"
}

render_svg() {
  require_command mmdc

  local selected_output_base="$output_base"
  local output
  local output_dir

  if [[ -z "$selected_output_base" ]]; then
    selected_output_base="$(default_output_base)"
  fi

  output="${selected_output_base}.svg"

  output_dir="$(dirname -- "$output")"

  if [[ "$output_dir" != "." ]]; then
    mkdir -p "$output_dir"
  fi

  mmdc \
    --input "$src" \
    --output "$output"

  printf 'SVG: %s\n' "$output"
}

render_both() {
  local text_exit_code=0

  if render_text; then
    :
  else
    text_exit_code=$?
  fi

  render_svg

  if [[ "$text_exit_code" -ne 0 ]]; then
    printf 'warning: terminal renderer does not support this diagram; SVG was generated\n' >&2
  fi
}

case "$mode" in
  text)
    [[ $# -eq 2 ]] || usage
    render_text
    ;;

  ascii)
    [[ $# -eq 2 ]] || usage
    render_ascii
    ;;

  svg)
    [[ $# -le 3 ]] || usage
    render_svg
    ;;

  both)
    [[ $# -le 3 ]] || usage
    render_both
    ;;

  *)
    echo "error: unknown mode: $mode" >&2
    usage
    ;;
esac
