#!/usr/bin/env bash

# Build the release images from the pinned submodules and write the bill of materials.
#
# Run through `make release FFMPEG_FLAVOR=<flavor>` so FFMPEG_VERSION and DOCKER come from the
# Makefile. The build only starts after the checked-out sources are proven to be the pinned ones,
# and every image is tagged by the component commit it was built from.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

GIT="${GIT:-git}"
DOCKER="${DOCKER:-docker}"
MAKE="${MAKE:-make}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-restreamer-arc}"
FFMPEG_VERSION="${FFMPEG_VERSION:-}"
RELEASE_DIR="${RELEASE_DIR:-${ROOT_DIR}/releases}"
flavor="${1:-${FFMPEG_FLAVOR:-}}"

fail() { echo "release: $*" >&2; exit 1; }

case "${flavor}" in
  default | rpi | vaapi | cuda) ;;
  *) fail "pass a supported flavor: make release FFMPEG_FLAVOR=default|rpi|vaapi|cuda" ;;
esac

[ -n "${FFMPEG_VERSION}" ] || fail "FFMPEG_VERSION is empty; run this through make release"

root_revision="$("${GIT}" rev-parse --verify HEAD)"
root_repository="$("${GIT}" remote get-url origin)"

dirty="$("${GIT}" status --porcelain --untracked-files=no)"
[ -z "${dirty}" ] || fail "the superproject has tracked changes:
${dirty}"

components=(ffmpeg core restreamer-ui)
declare -A component_revision component_repository component_short

for name in "${components[@]}"; do
  path="third_party/${name}"

  if ! revision="$("${GIT}" -C "${path}" rev-parse --verify HEAD 2>/dev/null)"; then
    fail "${path} is not a git checkout; run git submodule update --init --recursive"
  fi

  gitlink="$("${GIT}" ls-tree HEAD "${path}" | awk '{print $3}')"
  [ "${revision}" = "${gitlink}" ] ||
    fail "${path} HEAD ${revision} is not the superproject gitlink ${gitlink:-<none>}"

  component_dirty="$("${GIT}" -C "${path}" status --porcelain --untracked-files=no)"
  [ -z "${component_dirty}" ] || fail "${path} has tracked changes:
${component_dirty}"

  if ! "${GIT}" -C "${path}" branch -r --contains "${revision}" | grep -q .; then
    fail "${path} commit ${revision} is not on any remote branch; push it before releasing"
  fi

  component_revision["${name}"]="${revision}"
  component_repository["${name}"]="$("${GIT}" -C "${path}" remote get-url origin)"
  component_short["${name}"]="${revision:0:12}"
done

ffmpeg_short="${component_short[ffmpeg]}"
core_short="${component_short[core]}"
ui_short="${component_short[restreamer-ui]}"
root_short="${root_revision:0:12}"

ffmpeg_tag="${flavor}-ff${ffmpeg_short}"
core_tag="${flavor}-core${core_short}"
ui_tag="ui${ui_short}"
bundle_tag="${flavor}-ui${ui_short}-core${core_short}-ff${ffmpeg_short}-r${root_short}"

# The FFmpeg stamp comes from the verified commit. Passing it on the command line of every make
# invocation below keeps an inherited environment or MAKEFLAGS value from claiming another source.
ffmpeg_build_commit="${component_revision[ffmpeg]}"
ffmpeg_build_date="$("${GIT}" -C third_party/ffmpeg show -s --format=%cI "${ffmpeg_build_commit}")"
[ -n "${ffmpeg_build_date}" ] || fail "could not read the commit date of ${ffmpeg_build_commit}"

# Base images and toolchains come from the Makefile flavor matrix; read them instead of
# duplicating the matrix here.
build_inputs="$(${MAKE} --no-print-directory build-inputs \
  FFMPEG_FLAVOR="${flavor}" \
  FFMPEG_BUILD_COMMIT="${ffmpeg_build_commit}" \
  FFMPEG_BUILD_DATE="${ffmpeg_build_date}")" ||
  fail "could not read the build inputs from make"

build_input() {
  printf '%s\n' "${build_inputs}" | awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
}

ui_dockerfile_arg() {
  awk -F= -v key="ARG $1" '$1 == key { print $2; exit }' third_party/restreamer-ui/Dockerfile
}

ffmpeg_image="${IMAGE_REPOSITORY}-ffmpeg:${ffmpeg_tag}"
core_image="${IMAGE_REPOSITORY}-core:${core_tag}"
ui_image="${IMAGE_REPOSITORY}-restreamer-ui:${ui_tag}"
bundle_image="${IMAGE_REPOSITORY}:${bundle_tag}"

# Docker reads the build contexts, so every context is materialised from the verified commit.
# Untracked files, ignored files and a private .env in the working copies stay out of the images.
contexts="${RELEASE_DIR}/.contexts.$$"
cleanup_contexts() { rm -rf "${contexts}"; }
trap cleanup_contexts EXIT INT TERM
mkdir -p "${contexts}/root"

"${GIT}" archive --format=tar "${root_revision}" | tar -x -C "${contexts}/root"

for name in ffmpeg restreamer-ui; do
  mkdir -p "${contexts}/${name}"
  "${GIT}" -C "third_party/${name}" archive --format=tar "${component_revision[${name}]}" |
    tar -x -C "${contexts}/${name}"
done

# The core Makefile stamps app.Commit only when .git is a directory, so its context is a local
# clone of the pinned commit. A clone also holds tracked files only. The declared submodule
# branch names the local branch, so app.Branch matches it; without that line the context stays
# detached and core would report HEAD.
mkdir -p "${contexts}/core"
"${GIT}" clone --quiet --local third_party/core "${contexts}/core"
core_branch="$("${GIT}" config -f .gitmodules --get submodule.third_party/core.branch || true)"
if [ -n "${core_branch}" ]; then
  "${GIT}" -C "${contexts}/core" checkout --quiet -B "${core_branch}" "${component_revision[core]}"
else
  "${GIT}" -C "${contexts}/core" checkout --quiet --detach "${component_revision[core]}"
fi

[ "$("${GIT}" -C "${contexts}/core" rev-parse HEAD)" = "${component_revision[core]}" ] ||
  fail "the core build context does not point at ${component_revision[core]}"
[ -d "${contexts}/core/.git" ] ||
  fail "the core build context has no .git directory, so app.Commit would be stamped unknown"
[ -z "$("${GIT}" -C "${contexts}/core" status --porcelain)" ] ||
  fail "the core build context is not clean"
if [ -n "${core_branch}" ]; then
  [ "$("${GIT}" -C "${contexts}/core" rev-parse --abbrev-ref HEAD)" = "${core_branch}" ] ||
    fail "the core build context is not on branch ${core_branch}"
fi

echo "release: flavor ${flavor}"
echo "release: root ${root_revision}"
for name in "${components[@]}"; do
  echo "release: ${name} ${component_revision[${name}]}"
done
echo "release: bundle tag ${bundle_image}"

"${MAKE}" --no-print-directory build \
  FFMPEG_FLAVOR="${flavor}" \
  FFMPEG_TAG="${ffmpeg_tag}" \
  FFMPEG_BUILD_COMMIT="${ffmpeg_build_commit}" \
  FFMPEG_BUILD_DATE="${ffmpeg_build_date}" \
  CORE_TAG="${core_tag}" \
  RESTREAMER_UI_TAG="${ui_tag}" \
  BUNDLE_TAG="${bundle_tag}" \
  FFMPEG_BUILD_CONTEXT="${contexts}/ffmpeg" \
  CORE_BUILD_CONTEXT="${contexts}/core" \
  RESTREAMER_UI_BUILD_CONTEXT="${contexts}/restreamer-ui" \
  ROOT_BUILD_CONTEXT="${contexts}/root"

image_id() {
  "${DOCKER}" image inspect -f '{{.Id}}' "$1"
}

registry_digests() {
  "${DOCKER}" image inspect -f '{{json .RepoDigests}}' "$1"
}

platform() {
  "${DOCKER}" image inspect -f '{{.Os}}/{{.Architecture}}' "$1"
}

# The local image ID of a pull-on-demand build image, or null when it was never pulled.
image_id_or_null() {
  local id
  if id="$("${DOCKER}" image inspect -f '{{.Id}}' "$1" 2>/dev/null)" && [ -n "${id}" ]; then
    json_string "${id}"
  else
    printf 'null'
  fi
}

json_string() {
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# A manifest without the built images would be a claim the build never produced.
for image in "${ffmpeg_image}" "${core_image}" "${ui_image}" "${bundle_image}"; do
  "${DOCKER}" image inspect -f '{{.Id}}' "${image}" >/dev/null 2>&1 ||
    fail "image ${image} is missing after the build"
done

json_component() {
  local name="$1" image="$2"
  cat <<EOF
    $(json_string "${name}"): {
      "path": $(json_string "third_party/${name}"),
      "repository": $(json_string "${component_repository[${name}]}"),
      "revision": $(json_string "${component_revision[${name}]}"),
      "image": $(json_string "${image}"),
      "image_id": $(json_string "$(image_id "${image}")"),
      "platform": $(json_string "$(platform "${image}")"),
      "registry_digests": $(registry_digests "${image}")
    }
EOF
}

mkdir -p "${RELEASE_DIR}"
manifest="${RELEASE_DIR}/restreamer-arc-${flavor}-${root_short}.json"
suffix=1
while [ -e "${manifest}" ]; do
  manifest="${RELEASE_DIR}/restreamer-arc-${flavor}-${root_short}-${suffix}.json"
  suffix=$((suffix + 1))
done

{
  cat <<EOF
{
  "schema": 1,
  "generated_at": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "flavor": $(json_string "${flavor}"),
  "ffmpeg_version": $(json_string "${FFMPEG_VERSION}"),
  "root": {
    "repository": $(json_string "${root_repository}"),
    "revision": $(json_string "${root_revision}")
  },
  "build_contexts": {
    "root": "git archive",
    "ffmpeg": "git archive",
    "core": "git clone --local at the verified commit",
    "restreamer-ui": "git archive"
  },
  "build_inputs": {
    "ffmpeg": {
      "dockerfile": $(json_string "$(build_input FFMPEG_DOCKERFILE)"),
      "build_image": $(json_string "$(build_input FFMPEG_BUILD_IMAGE)"),
      "build_image_id": $(image_id_or_null "$(build_input FFMPEG_BUILD_IMAGE)"),
      "extra_args": $(json_string "$(build_input FFMPEG_EXTRA_ARGS)"),
      "build_commit": $(json_string "$(build_input FFMPEG_BUILD_COMMIT)"),
      "build_date": $(json_string "$(build_input FFMPEG_BUILD_DATE)"),
      "version": $(json_string "$(build_input FFMPEG_VERSION)")
    },
    "core": {
      "build_image": $(json_string "$(build_input CORE_BUILD_IMAGE)"),
      "build_image_id": $(image_id_or_null "$(build_input CORE_BUILD_IMAGE)"),
      "golang_image": $(json_string "$(build_input CORE_GOLANG_IMAGE)"),
      "golang_image_id": $(image_id_or_null "$(build_input CORE_GOLANG_IMAGE)")
    },
    "restreamer-ui": {
      "node_image": $(json_string "$(ui_dockerfile_arg NODE_IMAGE)"),
      "node_image_id": $(image_id_or_null "$(ui_dockerfile_arg NODE_IMAGE)"),
      "caddy_image": $(json_string "$(ui_dockerfile_arg CADDY_IMAGE)"),
      "caddy_image_id": $(image_id_or_null "$(ui_dockerfile_arg CADDY_IMAGE)")
    }
  },
  "components": {
EOF
  json_component ffmpeg "${ffmpeg_image}"
  printf ',\n'
  json_component core "${core_image}"
  printf ',\n'
  json_component restreamer-ui "${ui_image}"
  cat <<EOF

  },
  "bundle": {
    "image": $(json_string "${bundle_image}"),
    "image_id": $(json_string "$(image_id "${bundle_image}")"),
    "registry_digests": $(registry_digests "${bundle_image}"),
    "labels": $("${DOCKER}" image inspect -f '{{json .Config.Labels}}' "${bundle_image}")
  },
  "checks": [
    "submodule HEAD equals the superproject gitlink",
    "tracked trees are clean in the superproject and every submodule",
    "component commits are on remote branches",
    "Docker build contexts are materialised from the verified commits, not the working copies",
    "component image revisions equal the pinned revisions"
  ],
  "notes": "image_id is the local image config digest; registry_digests stays empty until the image is pushed, so the two are never interchangeable"
}
EOF
} >"${manifest}"

echo "release: manifest written to ${manifest}"
