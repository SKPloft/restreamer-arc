#!/usr/bin/env bash

# Refuse to assemble a bundle from component images that were built from another revision.
# Usage: verify-component-images.sh <image> <expected-revision> [...]

set -euo pipefail

DOCKER="${DOCKER:-docker}"

if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
  echo "usage: $0 <image> <expected-revision> [<image> <expected-revision> ...]" >&2
  exit 2
fi

status=0

while [ "$#" -gt 0 ]; do
  image="$1"
  expected="$2"
  shift 2

  if ! actual="$("${DOCKER}" image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${image}" 2>/dev/null)"; then
    echo "missing component image ${image}; build it with the matching make build-* target" >&2
    status=1
    continue
  fi

  if [ -z "${actual}" ]; then
    echo "component image ${image} has no org.opencontainers.image.revision label; rebuild it with the matching make build-* target" >&2
    status=1
    continue
  fi

  if [ "${actual}" != "${expected}" ]; then
    echo "component image ${image} records revision '${actual}', the pinned revision is '${expected}'" >&2
    status=1
  fi
done

exit "${status}"
