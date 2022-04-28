RUNTIME    ?= docker
IMAGE_ORG  ?= quay.io/konveyor
IMAGE_NAME ?= crane-secret-service
IMAGE_TAG  ?= $(shell git rev-parse --short HEAD)
IMAGE      ?= $(IMAGE_ORG)/$(IMAGE_NAME):$(IMAGE_TAG)

build-image: ## Build the crane-runner container image
	$(RUNTIME) build ${CONTAINER_BUILD_PARAMS} -t $(IMAGE) -f Dockerfile .

push-image: ## Push the crane-runner container image
	$(RUNTIME) push $(IMAGE)

build-push-image: build-image push-image ## Build and push crane-runner container image

openshift-e2e: ## Run the openshift-e2e test
	./hack/openshift-e2e.sh

help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ''

.PHONY: build-image push-image build-push-image manifests
