HUB            ?= quay.io/sail-dev
TAG            ?= latest
ARCH           ?= amd64
PLATFORMS      ?= linux/amd64,linux/arm64
CONTAINER_CLI  ?= podman
BUILDER        ?= ossm-multiarch

IMAGE = $(HUB)/ossm-ai-local:$(TAG)

# podman buildx create does not support --driver docker-container,
# it uses its own driver automatically.
ifeq ($(CONTAINER_CLI),podman)
  BUILDX_CREATE_FLAGS =
else
  BUILDX_CREATE_FLAGS = --driver docker-container
endif

.PHONY: build push all multiarch buildx-setup help

## Build the image for a single arch (default: amd64)
build:
	$(CONTAINER_CLI) build \
		--platform linux/$(ARCH) \
		-f Dockerfile.local \
		-t $(IMAGE) \
		..

## Push the image
push:
	$(CONTAINER_CLI) push $(IMAGE)

## Build and push
all: build push

# ── Multi-arch (requires push to registry) ───────────────────────────────────
# docker: uses buildx. podman: uses native --manifest + manifest push.

ifeq ($(CONTAINER_CLI),podman)

## Build and push as multi-arch manifest using podman (build each arch separately)
multiarch:
	$(CONTAINER_CLI) build --platform linux/amd64 -f Dockerfile.local -t $(IMAGE)-amd64 ..
	$(CONTAINER_CLI) build --platform linux/arm64 -f Dockerfile.local -t $(IMAGE)-arm64 ..
	$(CONTAINER_CLI) push $(IMAGE)-amd64
	$(CONTAINER_CLI) push $(IMAGE)-arm64
	$(CONTAINER_CLI) manifest rm $(IMAGE) 2>/dev/null || true
	$(CONTAINER_CLI) rmi $(IMAGE) 2>/dev/null || true
	$(CONTAINER_CLI) manifest create $(IMAGE) $(IMAGE)-amd64 $(IMAGE)-arm64
	$(CONTAINER_CLI) manifest push --all $(IMAGE)

else

## Create the docker buildx builder (run once, idempotent)
buildx-setup:
	$(CONTAINER_CLI) buildx inspect $(BUILDER) > /dev/null 2>&1 || \
		$(CONTAINER_CLI) buildx create --name $(BUILDER) --driver docker-container --bootstrap
	$(CONTAINER_CLI) buildx use $(BUILDER)

## Build and push as multi-arch manifest using docker buildx
multiarch: buildx-setup
	$(CONTAINER_CLI) buildx build \
		--platform $(PLATFORMS) \
		-f Dockerfile.local \
		-t $(IMAGE) \
		--push \
		..

endif

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@echo "Usage:"
	@echo ""
	@echo "  make build       Build for a single arch (default: amd64)"
	@echo "  make push        Push the image"
	@echo "  make all         Build and push"
	@echo "  make multiarch   Build and push multi-arch manifest (amd64 + arm64)"
	@echo "  make buildx-setup  Create the buildx builder (run once)"
	@echo ""
	@echo "Variables:"
	@echo "  CONTAINER_CLI  docker or podman       (default: $(CONTAINER_CLI))"
	@echo "  HUB            Registry + org         (default: $(HUB))"
	@echo "  TAG            Image tag              (default: $(TAG))"
	@echo "  ARCH           Single-arch target     (default: $(ARCH))  options: amd64, arm64"
	@echo "  PLATFORMS      Multi-arch target list (default: $(PLATFORMS))"
	@echo ""
	@echo "Examples:"
	@echo "  make all        HUB=quay.io/myorg TAG=v1.0.0"
	@echo "  make all        HUB=quay.io/myorg TAG=v1.0.0 CONTAINER_CLI=podman"
	@echo "  make multiarch  HUB=quay.io/myorg TAG=v1.0.0 CONTAINER_CLI=podman"
