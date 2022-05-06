Crane Secret Service
====================

A simple service to proxy requests from the
[crane-ui-plugin](https://github.com/konveyor/crane-ui-plugin)
creating Secrets to the API Server. Requests from the plugin include the user's
token and this service adds the token (and the internal
`https://kubernetes.default.svc`) to the Secret before being sent along to the
API Server.

## Developer Installation

```shell
kubectl kustomize github.com/konveyor/crane-secret-service/config/dev | kubectl apply -f -
```

## Basic Usage

Get the URL for the secret-service

* Get the route to the service: `oc get route -n openshift-migration-toolkit secret-service -o go-template='{{ .spec.host }}'`
* Service is also reachable inside the cluster at `https://secret-service.openshift-migration-toolkit.svc.cluster.local:8443`

Example request:

```bash
curl -k \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"example"}}' \
  https://secret-service-openshift-migration-toolkit.apps-crc.testing/api/v1/namespaces/openshift-migration-toolkit/secrets
```
