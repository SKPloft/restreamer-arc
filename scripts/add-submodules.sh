#!/usr/bin/env bash

set -euo pipefail

# Resolve from the repository root so the script works no matter where it is called from.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"
mkdir -p third_party

add_submodule() {
  local url="$1"
  local path="$2"

  # Skip paths that are already registered, but refuse to overwrite a plain directory.
  if git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' | grep -Fx "${path}" >/dev/null; then
    echo "submodule already declared: ${path}"
    return 0
  fi

  if [ -e "${path}" ]; then
    echo "path already exists and is not a declared submodule: ${path}" >&2
    return 1
  fi

  git submodule add "${url}" "${path}"
}

# Pin the three component repositories under a stable layout consumed by the Makefile.
add_submodule "https://github.com/SKPloft/ffmpeg-arc.git" "third_party/ffmpeg"
add_submodule "https://github.com/SKPloft/core-arc.git" "third_party/core"
add_submodule "https://github.com/SKPloft/restreamer-ui-arc.git" "third_party/restreamer-ui"

# Pull nested submodules too, so a fresh clone can build immediately.
git submodule update --init --recursive
