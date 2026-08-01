#!/usr/bin/env bash
# freshness.sh — per-binary source-mtime staleness gate, shared by every
# run-exp-*.sh campaign runner.
#
# Why not a whole-repo scan: the original check_fresh() (still duplicated
# in older scripts) compared *any* source file in the whole repo against
# *each* binary individually. In a multi-binary repo (vxedge: vxedge +
# vxedged; vxota: vxota + vxota-probe) that's a false positive whenever one
# binary's source changes but a sibling binary that doesn't depend on it
# hasn't been touched — cargo correctly leaves the sibling un-relinked, but
# the whole-repo scan flags it anyway. Hit twice running exp-003
# (vxperiments/TASKS.md has the story). This version walks each crate's
# *actual* local path dependencies (parsed straight from its Cargo.toml —
# single source of truth, no drift risk) instead of guessing.
#
# Usage:
#   source "$(dirname "$0")/lib/freshness.sh"
#   check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
#   #                repo_dir     binary     crate_dir (produces $binary)   extra dirs...

# Print $1's directory and, recursively, every local `path = "..."` Cargo
# dependency it declares (relative to $1). One directory per line; a crate
# with no Cargo.toml (e.g. an extra dir passed in verbatim) is still emitted
# once, unexpanded.
_freshness_crate_dirs() {
  local dir="$1"
  echo "$dir"
  local toml="$dir/Cargo.toml"
  [[ -f "$toml" ]] || return 0
  local rel dep_dir
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    dep_dir=$(cd "$dir" 2>/dev/null && cd "$rel" 2>/dev/null && pwd) || continue
    _freshness_crate_dirs "$dep_dir"
  done < <(grep -oE 'path[[:space:]]*=[[:space:]]*"[^"]+"' "$toml" 2>/dev/null \
             | sed -E 's/.*"(.*)"/\1/')
}

# $1=repo_dir $2=binary_path $3=crate_dir (the crate that produces $2)
# $4.. = extra directories to include verbatim (e.g. proto/, for crates
# whose build.rs reads it outside of any Cargo.toml path dependency).
check_fresh_bin() {
  local repo_dir="$1" binary="$2" crate_dir="$3"
  shift 3
  local extra_dirs=("$@")

  [[ -x "$binary" ]] || { echo "error: missing $binary — cargo build each repo first" >&2; exit 1; }

  local dirs newer=""
  dirs=$( { _freshness_crate_dirs "$crate_dir"; printf '%s\n' "${extra_dirs[@]}"; } | sort -u)
  local d hit
  while IFS= read -r d; do
    [[ -z "$d" || ! -d "$d" ]] && continue
    hit=$(find "$d" \( -name '*.rs' -o -name 'Cargo.toml' -o -name '*.proto' \) \
            -not -path '*/target/*' -newer "$binary" -print -quit 2>/dev/null)
    if [[ -n "$hit" ]]; then
      newer="$hit"
      break
    fi
  done <<<"$dirs"

  # Deliberately NOT checking Cargo.lock's mtime here: cargo rewrites/
  # normalizes it on most invocations regardless of whether anything
  # relevant changed, which would make this fire on nearly every build --
  # false positives, not a safety margin. A transitive dependency bump with
  # no local Cargo.toml edit anywhere in the crate's own dependency tree is
  # the only case this misses, and it's rare enough not to be worth it.

  if [[ -n "$newer" ]]; then
    echo "error: $binary is older than source file $newer — rebuild (as your user, not root):" >&2
    echo "       cd $repo_dir && cargo build --workspace && touch $binary" >&2
    echo "       (touch after a successful build attests cargo's freshness — cargo does" >&2
    echo "        not relink unchanged binaries, so mtime alone can look stale)" >&2
    exit 1
  fi
}
