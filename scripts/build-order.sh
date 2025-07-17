#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

declare -A built
declare -A visiting
declare -A provides
declare -A pkgdirs

# Step 1: Map all local package names to their directory
for d in */; do
  [[ -f "$d/PKGBUILD" ]] || continue
  dir="${d%/}"

  eval "$(bash -c "
    set -e
    pkgname=()
    provides=()
    source \"$d/PKGBUILD\" &>/dev/null || exit 0
    for p in \${pkgname[@]}; do echo provides[\"\$p\"]=\"$dir\"; done
    for p in \${provides[@]:-}; do echo provides[\"\$p\"]=\"$dir\"; done
  ")"

  pkgdirs["$dir"]=1
done

resolve_deps() {
  local dir=$1

  [[ -n "${built[$dir]:-}" ]] && return
  [[ -n "${visiting[$dir]:-}" ]] && {
    echo "❌ Circular dependency detected at $dir" >&2
    exit 1
  }

  visiting["$dir"]=1

  mapfile -t all_deps < <(bash -c "
    depends=()
    makedepends=()
    source \"$dir/PKGBUILD\" &>/dev/null || exit 0
    printf '%s\n' \${depends[@]:-} \${makedepends[@]:-}
  ")

  for dep in "${all_deps[@]:-}"; do
    provider="${provides[$dep]:-}"
    if [[ -n "$provider" ]]; then
      resolve_deps "$provider"
    fi
  done

  echo "$dir"
  built["$dir"]=1
  unset visiting["$dir"]
}

# Step 2: Emit build order
for dir in "${!pkgdirs[@]}"; do
  resolve_deps "$dir"
done

