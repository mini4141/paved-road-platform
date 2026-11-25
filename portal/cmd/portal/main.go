// Command portal runs the self-service developer portal.
package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/paved-road/portal/internal/portal"
)

func restConfig() (*rest.Config, error) {
	if cfg, err := rest.InClusterConfig(); err == nil {
		return cfg, nil
	}
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		clientcmd.NewDefaultClientConfigLoadingRules(), &clientcmd.ConfigOverrides{}).ClientConfig()
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", "portal")
	rc, err := restConfig()
	if err != nil {
		log.Error("kubernetes config", "err", err)
		os.Exit(1)
	}
	dyn, err := dynamic.NewForConfig(rc)
	if err != nil {
		log.Error("dynamic client", "err", err)
		os.Exit(1)
	}
	srv, err := portal.New(dyn, portal.ConfigFromEnv(), log)
	if err != nil {
		log.Error("portal", "err", err)
		os.Exit(1)
	}
	addr := os.Getenv("PORTAL_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	log.Info("listening", "addr", addr)
	hs := &http.Server{Addr: addr, Handler: srv.Handler(), ReadHeaderTimeout: 5 * time.Second}
	if err := hs.ListenAndServe(); err != nil {
		log.Error("server", "err", err)
		os.Exit(1)
	}
}
