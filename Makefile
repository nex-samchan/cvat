.PHONY: build show-vars gcr-auth push

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
REMOTE_IMAGE_UI ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_PREFIX_UI)
REMOTE_IMAGE_SERVER ?= $(REMOTE_REGISTRY)/$(REMOTE_REPOSITORY)/$(IMAGE_PREFIX_SERVER)


all: show-vars build push

show-vars:
	@echo "GIT_SHA: $(GIT_SHA)"
	@echo "GCP_PROJECT: $(GCP_PROJECT)"
	@echo "GCP_REGION: $(GCP_REGION)"
	@echo "IMAGE_NAME_UI: $(IMAGE_NAME_UI)"
	@echo "IMAGE_NAME_SERVER: $(IMAGE_NAME_SERVER)"
	@echo "REMOTE_IMAGE_UI: $(REMOTE_IMAGE_UI)"
	@echo "REMOTE_IMAGE_SERVER: $(REMOTE_IMAGE_SERVER)"

build:
	@echo "==> Building image $(REMOTE_IMAGE_UI)..."
	REACT_APP_IAM_TYPE=IAP docker build --platform $(PLATFORM) -f Dockerfile.ui -t $(REMOTE_IMAGE_UI) .
	@echo "==> Building image $(REMOTE_IMAGE_SERVER)..."
	docker build --platform $(PLATFORM) -f Dockerfile -t $(REMOTE_IMAGE_SERVER) .
	@echo "==> Build complete."

push:
	@echo "==> Pushing image $(REMOTE_IMAGE_UI)..."
	docker push $(REMOTE_IMAGE_UI)
	@echo "==> Pushing image $(REMOTE_IMAGE_SERVER)..."
	docker push $(REMOTE_IMAGE_SERVER)
	@echo "==> Push complete."