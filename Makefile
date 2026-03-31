.PHONY: build show-vars push all

# basic vars
GCP_PROJECT ?= $(shell gcloud config get-value project)
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo "latest")
PLATFORM ?= linux/amd64
IMAGE_PREFIX_UI ?= cvat-ui-custom
IMAGE_PREFIX_SERVER ?= cvat-server-custom
REMOTE_REPOSITORY ?= cvat-custom
include .env.release
# derived vars
REMOTE_REGISTRY ?= us-central1-docker.pkg.dev/$(GCP_PROJECT)
REMOTE_IMAGE_UI ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_PREFIX_UI):git-$(GIT_SHA)
REMOTE_IMAGE_SERVER ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_PREFIX_SERVER):git-$(GIT_SHA)

all: build push

show-vars:
	@echo "GIT_SHA:              $(GIT_SHA)"
	@echo "PLATFORM:             $(PLATFORM)"
	@echo "REMOTE_IMAGE_UI:      $(REMOTE_IMAGE_UI)"
	@echo "REMOTE_IMAGE_SERVER:  $(REMOTE_IMAGE_SERVER)"

build:
	@echo "==> Building UI image ($(PLATFORM))..."
	docker buildx build \
		--platform $(PLATFORM) \
		--file Dockerfile.ui \
		--build-arg REACT_APP_IAM_TYPE=IAP \
		--load \
		--tag $(REMOTE_IMAGE_UI) \
		.
	@echo "==> Building server image ($(PLATFORM))..."
	docker buildx build \
		--platform $(PLATFORM) \
		--file Dockerfile \
		--load \
		--tag $(REMOTE_IMAGE_SERVER) \
		.
	@echo "==> Build complete."

push:
	docker push $(REMOTE_IMAGE_UI)
	docker push $(REMOTE_IMAGE_SERVER)
	@echo "==> Push complete."
