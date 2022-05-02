#!/usr/bin/env bash

set -ex

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
NAME="${NAME:-secret-service-test-secret}"
NAMESPACE=$(oc project -q)
CRANE_SECRET_SERVICE="${CRANE_SECRET_SERVICE:-quay.io/konveyor/crane-secret-service:latest}"
KUSTOMIZE="${PROJECT_ROOT}/kustomize"

# Use kustomize to edit the deployment configuration for testing
if [ ! -f "${KUSTOMIZE}" ]; then
	curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" ${KUSTOMIZE} | bash
fi
pushd config/default &&  ${KUSTOMIZE} edit set image quay.io/konveyor/crane-secret-service=${CRANE_SECRET_SERVICE} && popd
pushd config/dev && ${KUSTOMIZE} edit remove resource namespace.yaml && ${KUSTOMIZE} edit set namespace ${NAMESPACE} && popd

# Use kustomize to deploy secret-service, wait for it to be ready
${KUSTOMIZE} build config/dev | oc apply -f -
exit 0
oc wait --for=condition=ready pod --selector=app=crane,service=secret-service --timeout=180s

# Get the route to the service
oc get route -n ${NAMESPACE} secret-service >/dev/null 2>&1 || ( echo "Deploy crane-secret-service before running"; exit 1 )
host=$(oc get route -n ${NAMESPACE} secret-service -o go-template='{{ .spec.host }}')

# Create a secret
curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/json" \
	-X POST \
	-d '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"'${NAME}'"}}' \
	https://${host}/api/v1/namespaces/${NAMESPACE}/secrets
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${NAMESPACE} secrets/${NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch when POSTing secret"; exit 1 )

# Replace a secret
curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/json" \
	-X PUT \
	-d '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"'${NAME}'"}}' \
	https://${host}/api/v1/namespaces/${NAMESPACE}/secrets/${NAME}
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${NAMESPACE} secrets/${NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch when PUTing secret"; exit 1 )

# Patch secret
curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/strategic-merge-patch+json" \
	-X PATCH \
	https://${host}/api/v1/namespaces/${NAMESPACE}/secrets/${NAME}
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${NAMESPACE} secrets/${NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch when PATCHing secret"; exit 1 )
