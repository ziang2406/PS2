#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then echo "usage: snapshot.sh before|after ITEM" >&2; exit 2; fi
phase=$1
item=$2
case "$phase" in before|after) ;; *) echo "phase must be 'before' or 'after'" >&2; exit 2;; esac
case "$item" in *[!A-Za-z0-9._-]*|'') echo "invalid item" >&2; exit 2;; esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel)
current_root=$(git rev-parse --show-toplevel)
[ "$repo_root" = "$current_root" ] || { echo "run from the TP skill's repository" >&2; exit 1; }
git -C "$repo_root" symbolic-ref -q HEAD >/dev/null || { echo "detached HEAD" >&2; exit 1; }
[ -z "$(git -C "$repo_root" diff --name-only --diff-filter=U)" ] || { echo "unresolved conflicts" >&2; exit 1; }
for ref in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    git -C "$repo_root" rev-parse -q --verify "$ref" >/dev/null && { echo "$ref exists" >&2; exit 1; }
done
git_dir=$(git -C "$repo_root" rev-parse --absolute-git-dir)
for dir in rebase-apply rebase-merge; do [ ! -d "$git_dir/$dir" ] || { echo "$dir exists" >&2; exit 1; }; done

git -C "$repo_root" add -A -- .
git -C "$repo_root" commit --allow-empty -m "TP $phase: $item" >&2
git -C "$repo_root" rev-parse HEAD

