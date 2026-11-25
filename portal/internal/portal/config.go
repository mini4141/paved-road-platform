// Package portal implements the self-service portal: it creates ArgoCD Application
// objects for golden-path services and reports their status.
package portal

import "os"

// Config is read from environment variables (see .env.example).
type Config struct {
	RepoURL         string
	Revision        string
	ArgoNamespace   string
	ImageRegistry   string
	ImageTag        string
	OpenCostURL     string
	GrafanaDashPath string
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// ConfigFromEnv builds the configuration with local-friendly defaults.
func ConfigFromEnv() Config {
	return Config{
		RepoURL:         env("GIT_REPO_URL", "https://github.com/mini4141/paved-road-platform.git"),
		Revision:        env("GIT_REVISION", "main"),
		ArgoNamespace:   env("ARGOCD_NAMESPACE", "argocd"),
		ImageRegistry:   os.Getenv("IMAGE_REGISTRY"),
		ImageTag:        env("IMAGE_TAG", "0.1.0"),
		OpenCostURL:     env("OPENCOST_URL", "http://opencost.opencost.svc:9003"),
		GrafanaDashPath: env("GRAFANA_DASH_PATH", "/grafana/d/golden-signals/service-golden-signals"),
	}
}
