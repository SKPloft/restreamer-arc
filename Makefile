SHELL := /bin/bash

# Keep the superproject layout explicit so every build target uses the same paths.
SUBMODULE_ROOT ?= third_party
FFMPEG_DIR := $(SUBMODULE_ROOT)/ffmpeg
CORE_DIR := $(SUBMODULE_ROOT)/core
RESTREAMER_UI_DIR := $(SUBMODULE_ROOT)/restreamer-ui

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
FFMPEG_BUILD_DATE ?= 1970-01-01T00:00:00Z
FFMPEG_BUILD_COMMIT ?= unknown

FFMPEG_FLAVOR ?= default
FFMPEG_TAG ?= $(FFMPEG_FLAVOR)
CORE_TAG ?= local
RESTREAMER_UI_TAG ?= local
BUNDLE_TAG ?= $(FFMPEG_FLAVOR)

RUN_NAME ?= restreamer-arc
CONFIG_DIR ?= $(CURDIR)/.local/config
DATA_DIR ?= $(CURDIR)/.local/data

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

# Mirror the main-branch core workflow defaults for local builds.
CORE_GOLANG_IMAGE := golang:1.23-alpine3.20

.PHONY: help submodules-add submodules-update check-submodules \
	build-ffmpeg build-core build-ui build \
	build-default build-rpi build-cuda build-vaapi \
	generate-combo-catalog list-combos show-combo \
	run print-images

help:
	@printf '%-18s %s\n' 'submodules-add' 'Add the three upstream forks as git submodules'
	@printf '%-18s %s\n' 'submodules-update' 'Init or refresh existing git submodules'
	@printf '%-18s %s\n' 'build' 'Build ffmpeg, core, restreamer-ui, then the bundle image'
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
		-f "$(FFMPEG_DIR)/$(FFMPEG_DOCKERFILE)" \
		--build-arg "BUILD_IMAGE=$(FFMPEG_BUILD_IMAGE)" \
		--build-arg "BUILD_DATE=$(FFMPEG_BUILD_DATE)" \
		--build-arg "BUILD_COMMIT=$(FFMPEG_BUILD_COMMIT)" \
		--build-arg "FFMPEG_VERSION=$(FFMPEG_VERSION)" \
		$(FFMPEG_EXTRA_ARGS) \
		-t "$(FFMPEG_IMAGE):$(FFMPEG_TAG)" \
		"$(FFMPEG_DIR)"

# Keep core aligned with the base-image matrix used in core/.github/workflows/build_base.yaml.
build-core: check-submodules
	$(DOCKER_BUILD) \
		-f "$(CORE_DIR)/Dockerfile" \
		--build-arg BUILD_IMAGE="$(CORE_BUILD_IMAGE)" \
		--build-arg GOLANG_IMAGE="$(CORE_GOLANG_IMAGE)" \
		-t "$(CORE_IMAGE):$(CORE_TAG)" \
		"$(CORE_DIR)"

build-ui: check-submodules
	$(DOCKER_BUILD) -f "$(RESTREAMER_UI_DIR)/Dockerfile" -t "$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)" "$(RESTREAMER_UI_DIR)"

# The final bundle still assembles from three images so the root Dockerfile stays thin and predictable.
build: build-ffmpeg build-core build-ui
	$(DOCKER_BUILD) \
		--build-arg FFMPEG_IMAGE="$(FFMPEG_IMAGE):$(FFMPEG_TAG)" \
		--build-arg CORE_IMAGE="$(CORE_IMAGE):$(CORE_TAG)" \
		--build-arg RESTREAMER_UI_IMAGE="$(RESTREAMER_UI_IMAGE):$(RESTREAMER_UI_TAG)" \
		-t "$(BUNDLE_IMAGE):$(BUNDLE_TAG)" \
		.

build-default:
	$(MAKE) build FFMPEG_FLAVOR=default

build-rpi:
	$(MAKE) build FFMPEG_FLAVOR=rpi

build-cuda:
	$(MAKE) build FFMPEG_FLAVOR=cuda

build-vaapi:
	$(MAKE) build FFMPEG_FLAVOR=vaapi

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
