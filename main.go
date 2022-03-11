package main

import (
	"bytes"
	"encoding/json"
	"crypto/tls"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"

	"github.com/gin-gonic/gin"
	corev1 "k8s.io/api/core/v1"
)

const (
	bearerSchema string = "Bearer"
	apiServer    string = "https://kubernetes.default.svc"
	port         string = ":8443"
)

func main() {
	r := gin.Default()
	r.SetTrustedProxies(nil)

	// We want POST to /api/v1/namespace/:namespace/secrets
	r.POST("*secretsPath", func(ctx *gin.Context) {
		var proxy *httputil.ReverseProxy

		// Get the token to put in the Secret
		authHeader := ctx.Request.Header.Get("Authorization")
		if authHeader == "" {
			ctx.AbortWithError(http.StatusBadRequest, fmt.Errorf("No auth header provided"))
			return
		}
		token := authHeader[len(bearerSchema):]

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
			contentLength := len(secretJson)
			req.Body = ioutil.NopCloser(bytes.NewBuffer(secretJson))
			req.Header.Set("Content-Length", strconv.Itoa(contentLength))
			req.ContentLength = int64(contentLength)

			secretPath, _ := ctx.Params.Get("secretsPath")
			req.Host = baseURL.Host
			req.URL.Scheme = baseURL.Scheme
			req.URL.Host = baseURL.Host
			req.URL.Path = secretPath
		}

		proxy.ServeHTTP(ctx.Writer, ctx.Request)
	})

	crt := os.Getenv("CRANE_SECRET_SERVICE_CRT")
	key := os.Getenv("CRANE_SECRET_SERVICE_KEY")
	if crt == "" || key == "" {
		log.Fatalf("Export CRANE_PROXY_CRT and CRANE_PROXY_KEY before running.")
	}

	r.RunTLS(port, crt, key)
}
