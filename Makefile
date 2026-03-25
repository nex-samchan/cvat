.PHONY: build build-cloud show-vars gcr-auth push

# basic vars
GCP_PROJECT ?= $(shell gcloud config get-value project)
GCP_REGION ?= $(shell gcloud config get-value compute/region)
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo "latest")
# basic build vars
PLATFORM ?= linux/amd64
IMAGE_PREFIX_UI ?= cvat-ui-custom
IMAGE_PREFIX_SERVER ?= cvat-server-custom
REMOTE_REPOSITORY ?= cvat-custom
include .env.release
# derived vars
IMAGE_NAME_UI ?= $(IMAGE_PREFIX_UI):git-$(GIT_SHA)
IMAGE_NAME_SERVER ?= $(IMAGE_PREFIX_SERVER):git-$(GIT_SHA)
REMOTE_REGISTRY ?= us-central1-docker.pkg.dev/$(GCP_PROJECT)
REMOTE_IMAGE_UI ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_NAME_UI)
REMOTE_IMAGE_SERVER ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_NAME_SERVER)
export


all: show-vars build-cloud push

show-vars:
	@echo "GIT_SHA: $(GIT_SHA)"
	@echo "GCP_PROJECT: $(GCP_PROJECT)"
	@echo "GCP_REGION: $(GCP_REGION)"
	@echo "IMAGE_NAME_UI: $(IMAGE_NAME_UI)"
	@echo "IMAGE_NAME_SERVER: $(IMAGE_NAME_SERVER)"
	@echo "REMOTE_IMAGE_UI: $(REMOTE_IMAGE_UI)"
	@echo "REMOTE_IMAGE_SERVER: $(REMOTE_IMAGE_SERVER)"

# Local build uses the native platform to avoid QEMU cross-compilation failures
# (openh264/FFmpeg C++ segfault under QEMU on Apple Silicon).
# Use 'make build-cloud' to produce linux/amd64 images via Google Cloud Build.
NATIVE_PLATFORM := $(shell docker info --format '{{.Architecture}}' 2>/dev/null | sed 's/x86_64/linux\/amd64/;s/aarch64/linux\/arm64/')

build:
	@echo "==> Building images for native platform ($(NATIVE_PLATFORM))..."
	docker buildx build \
		--builder multiarch \
		--platform $(NATIVE_PLATFORM) \
		--file Dockerfile.ui \
		--build-arg REACT_APP_IAM_TYPE=IAP \
		--load \
		--tag $(REMOTE_IMAGE_UI) \
		.
	docker buildx build \
		--builder multiarch \
		--platform $(NATIVE_PLATFORM) \
		--file Dockerfile \
		--load \
		--tag $(REMOTE_IMAGE_SERVER) \
		.
	@echo "==> Build complete ($(NATIVE_PLATFORM))."

# Production build via Google Cloud Build (runs natively on linux/amd64).
# Requires: gcloud auth login && gcloud auth configure-docker us-central1-docker.pkg.dev
build-cloud:
	@echo "==> Submitting Cloud Build for platform linux/amd64..."
	gcloud builds submit \
		--project $(GCP_PROJECT) \
		--config cloudbuild.yaml \
		--substitutions _IMAGE_UI=$(REMOTE_IMAGE_UI),_IMAGE_SERVER=$(REMOTE_IMAGE_SERVER) \
		.
	@echo "==> Cloud Build submitted."

push:
	@echo "==> Pushing image $(REMOTE_IMAGE_UI)..."
	docker push $(REMOTE_IMAGE_UI)
	@echo "==> Pushing image $(REMOTE_IMAGE_SERVER)..."
	docker push $(REMOTE_IMAGE_SERVER)
	@echo "==> Push complete."
