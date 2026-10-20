#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then echo "usage: verify_log_append_only.sh BASELINE_COMMIT" >&2; exit 2; fi
baseline=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir" rev-parse --show-toplevel)
[ "$root" = "$(git rev-parse --show-toplevel)" ] || { echo "run from the TP repository" >&2; exit 1; }
git -C "$root" cat-file -e "$baseline^{commit}"
git -C "$root" merge-base --is-ancestor "$baseline" HEAD || { echo "baseline is not an ancestor" >&2; exit 1; }

old=$(mktemp "${TMPDIR:-/tmp}/tp-old-log.XXXXXX")
trap 'rm -f "$old"' EXIT HUP INT TERM
if git -C "$root" cat-file -e "$baseline:AI_INTERACTIONS.md" 2>/dev/null; then
    git -C "$root" show "$baseline:AI_INTERACTIONS.md" >"$old"
else
    : >"$old"
fi
log="$root/AI_INTERACTIONS.md"
[ -f "$log" ] || { echo "AI_INTERACTIONS.md is missing" >&2; exit 1; }
old_size=$(wc -c <"$old" | tr -d ' ')
new_size=$(wc -c <"$log" | tr -d ' ')
[ "$new_size" -gt "$old_size" ] || { echo "AI_INTERACTIONS.md did not grow" >&2; exit 1; }
if [ "$old_size" -gt 0 ]; then
    head -c "$old_size" "$log" | cmp -s "$old" - || { echo "existing log content changed" >&2; exit 1; }
fi
echo "AI_INTERACTIONS.md is append-only relative to $baseline"
