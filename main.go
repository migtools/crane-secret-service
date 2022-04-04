package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	corev1 "k8s.io/api/core/v1"
)

const (
	authHeader       string = "Authorization"
	bearerSchema     string = "Bearer"
	apiServer        string = "https://kubernetes.default.svc"
	port             string = ":8443"
	secretRoute      string = "/api/v1/namespaces/:namespace/secrets"
	namedSecretRoute string = "/api/v1/namespaces/:namespace/secrets/:name"
)

func getToken(ctx *gin.Context) string {
	auth := ctx.Request.Header.Get(authHeader)
	if auth == "" {
		ctx.AbortWithError(http.StatusBadRequest, fmt.Errorf("No auth header provided"))
	}

	token := auth[len(bearerSchema):]
	return strings.TrimSpace(token)
}

func doProxy(ctx *gin.Context, body []byte) {
	var proxy *httputil.ReverseProxy

	baseURL, _ := url.Parse(apiServer)
	proxy = httputil.NewSingleHostReverseProxy(baseURL)
	if proxy == nil {
		ctx.AbortWithStatus(http.StatusBadGateway)
	}
	proxy.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	proxy.Director = func(req *http.Request) {
		// clone the headers
		req.Header = ctx.Request.Header.Clone()

		// reset content length
		contentLength := len(body)
		req.Body = ioutil.NopCloser(bytes.NewBuffer(body))
		req.Header.Set("Content-Length", strconv.Itoa(contentLength))
		req.ContentLength = int64(contentLength)

		req.Host = baseURL.Host
		req.URL.Scheme = baseURL.Scheme
		req.URL.Host = baseURL.Host
		req.URL.Path = ctx.Request.URL.Path
	}

	proxy.ServeHTTP(ctx.Writer, ctx.Request)
}

func secretHandler(ctx *gin.Context) {
	token := getToken(ctx)

	// If we aren't provided a Secret, then we should fail
	secret := corev1.Secret{}
	if err := ctx.BindJSON(&secret); err != nil {
		ctx.AbortWithError(http.StatusBadRequest, err)
	}
	secret.StringData = map[string]string{
		"url":   apiServer,
		"token": token,
	}
	secretJson, err := json.Marshal(secret)
	if err != nil {
		ctx.AbortWithError(http.StatusBadRequest, err)
	}

	doProxy(ctx, secretJson)
}

func secretPatchHandler(ctx *gin.Context) {
	token := getToken(ctx)

	secretJsonPatch, _ := json.Marshal(
		map[string]map[string]string{
			"stringData": {
				"url":   apiServer,
				"token": token,
			},
		},
	)

	doProxy(ctx, secretJsonPatch)
}

func main() {
	r := gin.Default()
	r.SetTrustedProxies(nil)

	// We will support POST|PUT|PATCH on secrets, this should allow the UI to
	// create and update secrets as necessary (ie. when tokens expire).
	r.POST(secretRoute, secretHandler)
	r.PUT(namedSecretRoute, secretHandler)
	r.PATCH(namedSecretRoute, secretPatchHandler)

	crt := os.Getenv("CRANE_SECRET_SERVICE_CRT")
	key := os.Getenv("CRANE_SECRET_SERVICE_KEY")
	if crt == "" || key == "" {
		log.Fatalf("Export CRANE_PROXY_CRT and CRANE_PROXY_KEY before running.")
	}

	r.RunTLS(port, crt, key)
}
