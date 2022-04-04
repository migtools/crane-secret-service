#!/usr/bin/env bash

set -ex

SECRET_NAME="${SECRET_NAME:-functional-test}"
SECRET_NAMESPACE="${SECRET_NAMESPACE:-test-namespace}"

# This script assumes:
# 1. OpenShift cluster is current context (use `kubectl config current-context`)
# 2. Crane Secret Service is already installed and accessible via route
oc get route -n openshift-migration secret-service >/dev/null 2>&1 || ( echo "Deploy crane-secret-service before running"; exit 1 )
host=$(oc get route -n openshift-migration secret-service -o go-template='{{ .spec.host }}')

curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/json" \
	-X POST \
	-d '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"'${SECRET_NAME}'"}}' \
	https://${host}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${SECRET_NAMESPACE} secrets/${SECRET_NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch"; exit 1 )

curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/json" \
	-X PUT \
	-d '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"'${SECRET_NAME}'"}}' \
	https://${host}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets/${SECRET_NAME}
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${SECRET_NAMESPACE} secrets/${SECRET_NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch"; exit 1 )

curl -k --fail \
	-H "Authorization: Bearer $(oc whoami -t)" \
	-H "Content-Type: application/strategic-merge-patch+json" \
	-X PATCH \
	https://${host}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets/${SECRET_NAME}
# Verify token saved correctly
[ "$(oc whoami -t)" == "$(oc get --namespace ${SECRET_NAMESPACE} secrets/${SECRET_NAME} --template={{.data.token}} | base64 -d)" ] || ( echo "Token mismatch"; exit 1 )

oc delete --namespace ${SECRET_NAMESPACE} secrets/${SECRET_NAME}
