FROM registry.ci.openshift.org/openshift/release:golang-1.17 as builder
ENV GOFLAGS "-mod=mod"
WORKDIR /go/src/github.com/konveyor/crane
COPY . .
RUN go build -o /crane-secret-service main.go

FROM registry.access.redhat.com/ubi8-minimal
WORKDIR /
COPY --from=builder /crane-secret-service .
ENTRYPOINT ["/crane-secret-service"]
