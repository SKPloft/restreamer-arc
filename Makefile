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

FFMPEG_FLAVOR ?= default
FFMPEG_TAG ?= $(FFMPEG_FLAVOR)
CORE_TAG ?= local
RESTREAMER_UI_TAG ?= local
BUNDLE_TAG ?= $(FFMPEG_FLAVOR)

RUN_NAME ?= restreamer-arc
CONFIG_DIR ?= $(CURDIR)/.local/config
DATA_DIR ?= $(CURDIR)/.local/data

# Map a logical ffmpeg flavor to the upstream Dockerfile naming used by ffmpeg-arc.
ifeq ($(FFMPEG_FLAVOR),default)
FFMPEG_DOCKERFILE := Dockerfile.alpine
else ifeq ($(FFMPEG_FLAVOR),rpi)
FFMPEG_DOCKERFILE := Dockerfile.alpine.rpi
else ifeq ($(FFMPEG_FLAVOR),cuda)
FFMPEG_DOCKERFILE := Dockerfile.ubuntu.cuda
else ifeq ($(FFMPEG_FLAVOR),vaapi)
FFMPEG_DOCKERFILE := Dockerfile.ubuntu.vaapi
else
$(error Unsupported FFMPEG_FLAVOR '$(FFMPEG_FLAVOR)'; use default, rpi, cuda, or vaapi)
endif

.PHONY: help submodules-add submodules-update check-submodules \
	build-ffmpeg build-core build-ui build \
	build-default build-rpi build-cuda build-vaapi \
	run print-images

help:
	@printf '%-18s %s\n' 'submodules-add' 'Add the three upstream forks as git submodules'
	@printf '%-18s %s\n' 'submodules-update' 'Init or refresh existing git submodules'
	@printf '%-18s %s\n' 'build' 'Build ffmpeg, core, restreamer-ui, then the bundle image'
	@printf '%-18s %s\n' 'build-default' 'Build the bundle with ffmpeg default flavor'
	@printf '%-18s %s\n' 'build-rpi' 'Build the bundle with ffmpeg rpi flavor'
	@printf '%-18s %s\n' 'build-cuda' 'Build the bundle with ffmpeg cuda flavor'
	@printf '%-18s %s\n' 'build-vaapi' 'Build the bundle with ffmpeg vaapi flavor'
	@printf '%-18s %s\n' 'run' 'Run the locally built bundle image'
	@printf '%-18s %s\n' 'print-images' 'Show the image tags used by the current configuration'
	@printf '\nUse FFMPEG_FLAVOR={default|rpi|cuda|vaapi} or override DOCKER_BUILD as needed.\n'

submodules-add:
	./scripts/add-submodules.sh

submodules-update:
	git submodule update --init --recursive

# Fail early with a clear message instead of letting docker build complain about missing contexts.
check-submodules:
	@test -f "$(FFMPEG_DIR)/$(FFMPEG_DOCKERFILE)" || { echo "Missing $(FFMPEG_DIR). Run ./scripts/add-submodules.sh first."; exit 1; }
	@test -f "$(CORE_DIR)/Dockerfile" || { echo "Missing $(CORE_DIR). Run ./scripts/add-submodules.sh first."; exit 1; }
	@test -f "$(RESTREAMER_UI_DIR)/Dockerfile" || { echo "Missing $(RESTREAMER_UI_DIR). Run ./scripts/add-submodules.sh first."; exit 1; }

build-ffmpeg: check-submodules
	$(DOCKER_BUILD) -f "$(FFMPEG_DIR)/$(FFMPEG_DOCKERFILE)" -t "$(FFMPEG_IMAGE):$(FFMPEG_TAG)" "$(FFMPEG_DIR)"

build-core: check-submodules
	$(DOCKER_BUILD) -f "$(CORE_DIR)/Dockerfile" -t "$(CORE_IMAGE):$(CORE_TAG)" "$(CORE_DIR)"

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
run:
	mkdir -p "$(CONFIG_DIR)" "$(DATA_DIR)"
	$(DOCKER) run --rm -it \
		--name "$(RUN_NAME)" \
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
