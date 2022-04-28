#!/usr/bin/env bash

set -ex

NAME="${NAME:-secret-service-test-secret}"
NAMESPACE=$(oc project -q)
CRANE_SECRET_SERVICE="${CRANE_SECRET_SERVICE:-quay.io/konveyor/crane-secret-service:latest}"

# Use kustomize to edit the deployment configuration for testing
kustomize version || (curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash)
pushd config/default &&  kustomize edit set image quay.io/konveyor/crane-secret-service=${CRANE_SECRET_SERVICE} && popd
pushd config/dev && kustomize edit remove resource namespace.yaml && kustomize edit set namespace ${NAMESPACE} && popd

# Use kustomize to deploy secret-service, wait for it to be ready
kustomize build config/dev | oc apply -f -
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
