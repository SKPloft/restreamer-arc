SHELL := /bin/bash

# Keep the superproject layout explicit so every build target uses the same paths.
SUBMODULE_ROOT ?= third_party
FFMPEG_DIR := $(SUBMODULE_ROOT)/ffmpeg
CORE_DIR := $(SUBMODULE_ROOT)/core
RESTREAMER_UI_DIR := $(SUBMODULE_ROOT)/restreamer-ui

# Every image records the commit it was built from, so a mutable tag can never hide a stale or
# foreign component. The helpers read the submodule working copies that `check-submodules` proves.
GIT ?= git
git_revision = $(shell $(GIT) -C $(1) rev-parse --verify HEAD 2>/dev/null)
git_source = $(shell $(GIT) -C $(1) remote get-url origin 2>/dev/null)
git_short = $(shell printf '%s' '$(1)' | cut -c1-12)
oci_labels = --label "org.opencontainers.image.revision=$(1)" --label "org.opencontainers.image.source=$(2)"

# DOCKER_BUILD can be overridden with "docker buildx build --load" when multi-platform tooling is needed.
DOCKER ?= docker
DOCKER_BUILD ?= $(DOCKER) build

IMAGE_REPOSITORY ?= restreamer-arc
FFMPEG_IMAGE ?= $(IMAGE_REPOSITORY)-ffmpeg
CORE_IMAGE ?= $(IMAGE_REPOSITORY)-core
RESTREAMER_UI_IMAGE ?= $(IMAGE_REPOSITORY)-restreamer-ui
BUNDLE_IMAGE ?= $(IMAGE_REPOSITORY)

RUBY ?= ruby
COMBO_CATALOG_SCRIPT := scripts/generate_combo_catalog.rb
COMBO_CATALOG := combinations/catalog.json

# third_party/ffmpeg is pinned to the 8.0 branch, which keeps its versions in Build.sh and in the
# base build workflows instead of separate env files.
FFMPEG_VERSION ?= 8.0.1
FFMPEG_BUILD_COMMIT ?= $(call git_revision,$(FFMPEG_DIR))
FFMPEG_BUILD_DATE ?= $(shell $(GIT) -C $(FFMPEG_DIR) show -s --format=%cI HEAD 2>/dev/null)

FFMPEG_FLAVOR ?= default
FFMPEG_TAG ?= $(FFMPEG_FLAVOR)
CORE_TAG ?= local
RESTREAMER_UI_TAG ?= local
BUNDLE_TAG ?= $(FFMPEG_FLAVOR)

# Docker build contexts default to the working copies. `make release` overrides them with git
# archives of the verified commits so untracked and ignored files never enter a release image.
FFMPEG_BUILD_CONTEXT ?= $(FFMPEG_DIR)
CORE_BUILD_CONTEXT ?= $(CORE_DIR)
RESTREAMER_UI_BUILD_CONTEXT ?= $(RESTREAMER_UI_DIR)
ROOT_BUILD_CONTEXT ?= .

RUN_NAME ?= restreamer-arc
CONFIG_DIR ?= $(CURDIR)/.local/config
DATA_DIR ?= $(CURDIR)/.local/data
RELEASE_DIR ?= $(CURDIR)/releases

# Map a logical ffmpeg flavor to the Dockerfile naming and base images used by ffmpeg-arc.
ifeq ($(FFMPEG_FLAVOR),default)
FFMPEG_DOCKERFILE := Dockerfile.alpine
FFMPEG_OS_NAME := alpine
FFMPEG_OS_VERSION := 3.23
FFMPEG_BUILD_IMAGE := alpine:3.23
FFMPEG_EXTRA_ARGS :=
CORE_BUILD_IMAGE := alpine:3.23
else ifeq ($(FFMPEG_FLAVOR),rpi)
FFMPEG_DOCKERFILE := Dockerfile.alpine.rpi
FFMPEG_OS_NAME := alpine
FFMPEG_OS_VERSION := 3.23
FFMPEG_BUILD_IMAGE := alpine:3.23
FFMPEG_EXTRA_ARGS :=
CORE_BUILD_IMAGE := alpine:3.23
else ifeq ($(FFMPEG_FLAVOR),vaapi)
FFMPEG_DOCKERFILE := Dockerfile.ubuntu.vaapi
FFMPEG_OS_NAME := ubuntu
FFMPEG_OS_VERSION := 24.04
FFMPEG_BUILD_IMAGE := ubuntu:24.04
FFMPEG_EXTRA_ARGS := --build-arg "DEPLOY_IMAGE=ubuntu:24.04"
CORE_BUILD_IMAGE := ubuntu:24.04
else ifeq ($(FFMPEG_FLAVOR),cuda)
FFMPEG_DOCKERFILE := Dockerfile.ubuntu.cuda13
FFMPEG_OS_NAME := ubuntu
FFMPEG_OS_VERSION := 24.04
FFMPEG_CUDA_VERSION := 13.1.0
FFMPEG_BUILD_IMAGE := nvidia/cuda:13.1.0-devel-ubuntu24.04
FFMPEG_EXTRA_ARGS := --build-arg "DEPLOY_IMAGE=nvidia/cuda:13.1.0-runtime-ubuntu24.04" --build-arg "FFNVCODEC_VERSION=13.0.19.0"
CORE_BUILD_IMAGE := ubuntu:24.04
else
$(error Unsupported FFMPEG_FLAVOR '$(FFMPEG_FLAVOR)'; use default, rpi, cuda, or vaapi)
endif

# Mirror the dev-line core workflow defaults for local builds. The module only requires go 1.25,
# while the dev matrix builds with 1.27, so the image has to keep up with that matrix.
CORE_GOLANG_IMAGE := golang:1.27-alpine3.23

.PHONY: help submodules-add submodules-update check-submodules \
	build-ffmpeg build-core build-ui build \
	build-default build-rpi build-cuda build-vaapi \
	generate-combo-catalog list-combos show-combo \
	check-component-images build-inputs release \
	run print-images

help:
	@printf '%-18s %s\n' 'submodules-add' 'Add the three upstream forks as git submodules'
	@printf '%-18s %s\n' 'submodules-update' 'Init or refresh existing git submodules'
	@printf '%-18s %s\n' 'build' 'Build ffmpeg, core, restreamer-ui, then the bundle image'
	@printf '%-18s %s\n' 'release' 'Build pinned release images with SHA tags and a manifest under releases/'
	@printf '%-18s %s\n' 'build-default' 'Build the bundle with ffmpeg default flavor'
	@printf '%-18s %s\n' 'build-rpi' 'Build the bundle with ffmpeg rpi flavor'
	@printf '%-18s %s\n' 'build-cuda' 'Build the bundle with ffmpeg cuda flavor'
	@printf '%-18s %s\n' 'build-vaapi' 'Build the bundle with ffmpeg vaapi flavor'
	@printf '%-18s %s\n' 'list-combos' 'List upstream-supported bundle combos with local drift status'
	@printf '%-18s %s\n' 'show-combo' 'Show details for one combo (set COMBO=<channel/flavor>)'
	@printf '%-18s %s\n' 'run' 'Run the locally built bundle image'
	@printf '%-18s %s\n' 'print-images' 'Show the image tags used by the current configuration'
	@printf '\nUse FFMPEG_FLAVOR={default|rpi|cuda|vaapi}, COMBO=<channel/flavor>, or override DOCKER_BUILD as needed.\n'

submodules-add:
	./scripts/add-submodules.sh

submodules-update:
	git submodule update --init --recursive

# Fail early with a clear message instead of letting docker build complain about missing contexts.
check-submodules:
	@test -f "$(FFMPEG_DIR)/$(FFMPEG_DOCKERFILE)" || { echo "Missing $(FFMPEG_DIR)/$(FFMPEG_DOCKERFILE). Run ./scripts/add-submodules.sh first."; exit 1; }
	@test -f "$(CORE_DIR)/Dockerfile" || { echo "Missing $(CORE_DIR). Run ./scripts/add-submodules.sh first."; exit 1; }
	@test -f "$(RESTREAMER_UI_DIR)/Dockerfile" || { echo "Missing $(RESTREAMER_UI_DIR). Run ./scripts/add-submodules.sh first."; exit 1; }
	@$(GIT) -C "$(FFMPEG_DIR)" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "$(FFMPEG_DIR) is not a git checkout. Run git submodule update --init --recursive."; exit 1; }
	@$(GIT) -C "$(CORE_DIR)" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "$(CORE_DIR) is not a git checkout. Run git submodule update --init --recursive."; exit 1; }
	@$(GIT) -C "$(RESTREAMER_UI_DIR)" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "$(RESTREAMER_UI_DIR) is not a git checkout. Run git submodule update --init --recursive."; exit 1; }

$(COMBO_CATALOG): $(COMBO_CATALOG_SCRIPT) \
		.github/workflows/build_bundle.yaml \
		.github/workflows/build_bundle_dev.yaml \
		Makefile \
		third_party/core/app/version.go \
		third_party/restreamer-ui/package.json \
		third_party/ffmpeg/Build.sh
	$(RUBY) $(COMBO_CATALOG_SCRIPT) generate $(COMBO_CATALOG)

generate-combo-catalog: $(COMBO_CATALOG)

list-combos: $(COMBO_CATALOG)
	@$(RUBY) $(COMBO_CATALOG_SCRIPT) list $(COMBO_CATALOG)

show-combo: $(COMBO_CATALOG)
	@test -n "$(COMBO)" || { echo "Set COMBO=<channel/flavor>, for example COMBO=main/default"; exit 1; }
	@$(RUBY) $(COMBO_CATALOG_SCRIPT) show "$(COMBO)" $(COMBO_CATALOG)

# The flavor mapping above carries the same versions and base images that ffmpeg-arc passes in its workflows.
build-ffmpeg: check-submodules
	$(DOCKER_BUILD) \
		-f "$(FFMPEG_BUILD_CONTEXT)/$(FFMPEG_DOCKERFILE)" \
		--build-arg "BUILD_IMAGE=$(FFMPEG_BUILD_IMAGE)" \
		--build-arg "BUILD_DATE=$(FFMPEG_BUILD_DATE)" \
		--build-arg "BUILD_COMMIT=$(FFMPEG_BUILD_COMMIT)" \
		--build-arg "FFMPEG_VERSION=$(FFMPEG_VERSION)" \
		$(FFMPEG_EXTRA_ARGS) \
		$(call oci_labels,$(call git_revision,$(FFMPEG_DIR)),$(call git_source,$(FFMPEG_DIR))) \
		-t "$(FFMPEG_IMAGE):$(FFMPEG_TAG)" \
		"$(FFMPEG_BUILD_CONTEXT)"

# Keep core aligned with the base-image matrix used in core/.github/workflows/build_base.yaml.
build-core: check-submodules
	$(DOCKER_BUILD) \
		-f "$(CORE_BUILD_CONTEXT)/Dockerfile" \
		--build-arg BUILD_IMAGE="$(CORE_BUILD_IMAGE)" \
		--build-arg GOLANG_IMAGE="$(CORE_GOLANG_IMAGE)" \
		$(call oci_labels,$(call git_revision,$(CORE_DIR)),$(call git_source,$(CORE_DIR))) \
		-t "$(CORE_IMAGE):$(CORE_TAG)" \
		"$(CORE_BUILD_CONTEXT)"

build-ui: check-submodules
	$(DOCKER_BUILD) \
		-f "$(RESTREAMER_UI_BUILD_CONTEXT)/Dockerfile" \
		$(call oci_labels,$(call git_revision,$(RESTREAMER_UI_DIR)),$(call git_source,$(RESTREAMER_UI_DIR))) \
		-t "$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)" \
		"$(RESTREAMER_UI_BUILD_CONTEXT)"

# Refuse to assemble a bundle from component images that were built from another revision.
check-component-images: check-submodules
	@DOCKER="$(DOCKER)" ./scripts/verify-component-images.sh \
		"$(FFMPEG_IMAGE):$(FFMPEG_TAG)" "$(call git_revision,$(FFMPEG_DIR))" \
		"$(CORE_IMAGE):$(CORE_TAG)" "$(call git_revision,$(CORE_DIR))" \
		"$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)" "$(call git_revision,$(RESTREAMER_UI_DIR))"

# The build inputs that the flavor matrix resolves, one KEY=VALUE per line. `make release` writes
# them into the manifest so the base images are recorded next to the commits.
build-inputs: check-submodules
	@printf 'FFMPEG_DOCKERFILE=%s\n' "$(FFMPEG_DOCKERFILE)"
	@printf 'FFMPEG_BUILD_IMAGE=%s\n' "$(FFMPEG_BUILD_IMAGE)"
	@printf 'FFMPEG_EXTRA_ARGS=%s\n' "$(FFMPEG_EXTRA_ARGS)"
	@printf 'FFMPEG_BUILD_COMMIT=%s\n' "$(FFMPEG_BUILD_COMMIT)"
	@printf 'FFMPEG_BUILD_DATE=%s\n' "$(FFMPEG_BUILD_DATE)"
	@printf 'FFMPEG_VERSION=%s\n' "$(FFMPEG_VERSION)"
	@printf 'CORE_BUILD_IMAGE=%s\n' "$(CORE_BUILD_IMAGE)"
	@printf 'CORE_GOLANG_IMAGE=%s\n' "$(CORE_GOLANG_IMAGE)"

# The final bundle still assembles from three images so the root Dockerfile stays thin and predictable.
build: build-ffmpeg build-core build-ui
	@$(MAKE) --no-print-directory check-component-images
	$(DOCKER_BUILD) \
		-f "$(ROOT_BUILD_CONTEXT)/Dockerfile" \
		--build-arg FFMPEG_IMAGE="$(FFMPEG_IMAGE):$(FFMPEG_TAG)" \
		--build-arg CORE_IMAGE="$(CORE_IMAGE):$(CORE_TAG)" \
		--build-arg RESTREAMER_UI_IMAGE="$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)" \
		$(call oci_labels,$(call git_revision,.),$(call git_source,.)) \
		--label "io.skploft.restreamer.components=ffmpeg:$(call git_revision,$(FFMPEG_DIR)),core:$(call git_revision,$(CORE_DIR)),restreamer-ui:$(call git_revision,$(RESTREAMER_UI_DIR))" \
		-t "$(BUNDLE_IMAGE):$(BUNDLE_TAG)" \
		"$(ROOT_BUILD_CONTEXT)"

build-default:
	$(MAKE) build FFMPEG_FLAVOR=default

build-rpi:
	$(MAKE) build FFMPEG_FLAVOR=rpi

build-cuda:
	$(MAKE) build FFMPEG_FLAVOR=cuda

build-vaapi:
	$(MAKE) build FFMPEG_FLAVOR=vaapi

# Release builds prove the pins match the checked-out sources, tag every image by component SHA
# and write the bill of materials under releases/. Local `make build` stays as it is.
release: check-submodules
	@DOCKER="$(DOCKER)" FFMPEG_VERSION="$(FFMPEG_VERSION)" RELEASE_DIR="$(RELEASE_DIR)" ./scripts/build-release.sh "$(FFMPEG_FLAVOR)"

# Keep runtime state under the repo by default so local smoke tests are easy to clean up.
# The DRM device is required for the hardware AV1 coders (av1_vaapi, av1_qsv).
run: check-submodules
	mkdir -p "$(CONFIG_DIR)" "$(DATA_DIR)"
	$(DOCKER) run --rm -it \
		--name "$(RUN_NAME)" \
		--device /dev/dri:/dev/dri \
		-v "$(CONFIG_DIR):/core/config" \
		-v "$(DATA_DIR):/core/data" \
		-p 8080:8080 \
		-p 8181:8181 \
		-p 1935:1935 \
		-p 1936:1936 \
		-p 6000:6000/udp \
		"$(BUNDLE_IMAGE):$(BUNDLE_TAG)"

print-images:
	@printf '%-22s %s\n' 'FFMPEG_IMAGE' "$(FFMPEG_IMAGE):$(FFMPEG_TAG)"
	@printf '%-22s %s\n' 'CORE_IMAGE' "$(CORE_IMAGE):$(CORE_TAG)"
	@printf '%-22s %s\n' 'RESTREAMER_UI_IMAGE' "$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)"
	@printf '%-22s %s\n' 'BUNDLE_IMAGE' "$(BUNDLE_IMAGE):$(BUNDLE_TAG)"
