package portal

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

// GVRs used by the portal.
var (
	applicationGVR = schema.GroupVersionResource{Group: "argoproj.io", Version: "v1alpha1", Resource: "applications"}
	deploymentGVR  = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}
	eventGVR       = schema.GroupVersionResource{Version: "v1", Resource: "events"}
)

const (
	labelManaged = "paved-road/managed"
	labelTeam    = "paved-road/team"
)

// templateImages maps a golden-path template to its image repository name.
var templateImages = map[string]string{
	"go-http":   "go-http-service",
	"node-http": "node-http-service",
}

var (
	nameRe   = regexp.MustCompile(`^[a-z][a-z0-9-]{1,30}[a-z0-9]$`)
	reserved = map[string]bool{
		"argocd": true, "default": true, "kube-system": true, "kube-public": true, "traefik": true,
		"monitoring": true, "observability": true, "kyverno": true, "opencost": true, "paved-road": true,
		"portal": true, "kube-node-lease": true, "local-path-storage": true, "metrics-server": true,
	}
)

// ServiceRequest is the input of the create form.
type ServiceRequest struct {
	Name        string
	Template    string
	Team        string
	Replicas    int
	Autoscaling bool
	MaxReplicas int
}

// Validate checks the name and template only (happy-path scope).
func (r ServiceRequest) Validate() error {
	if !nameRe.MatchString(r.Name) || reserved[r.Name] || strings.HasPrefix(r.Name, "addon-") {
		return fmt.Errorf("invalid service name %q: use 3-32 lowercase letters, digits or '-'", r.Name)
	}
	if _, ok := templateImages[r.Template]; !ok {
		return fmt.Errorf("unknown template %q", r.Template)
	}
	return nil
}

func (c Config) image(tmpl string) string {
	repo := templateImages[tmpl]
	if c.ImageRegistry != "" {
		repo = c.ImageRegistry + "/" + repo
	}
	return repo
}

// BuildApplication renders the ArgoCD Application that deploys charts/golden-service
// for the request, with the user's values inlined as Helm parameters.
func (c Config) BuildApplication(r ServiceRequest) *unstructured.Unstructured {
	minReplicas := max(r.Replicas, 1)
	maxReplicas := max(r.MaxReplicas, minReplicas)
	params := []any{
		param("nameOverride", r.Name),
		param("team", r.Team),
		param("image.repository", c.image(r.Template)),
		param("image.tag", c.ImageTag),
		param("replicas", strconv.Itoa(minReplicas)),
		param("autoscaling.enabled", strconv.FormatBool(r.Autoscaling)),
		param("autoscaling.minReplicas", strconv.Itoa(minReplicas)),
		param("autoscaling.maxReplicas", strconv.Itoa(maxReplicas)),
	}
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "argoproj.io/v1alpha1",
		"kind":       "Application",
		"metadata": map[string]any{
			"name":       r.Name,
			"namespace":  c.ArgoNamespace,
			"labels":     map[string]any{labelManaged: "true", labelTeam: r.Team},
			"finalizers": []any{"resources-finalizer.argocd.argoproj.io"},
		},
		"spec": map[string]any{
			"project": "default",
			"source": map[string]any{
				"repoURL":        c.RepoURL,
				"targetRevision": c.Revision,
				"path":           "charts/golden-service",
				"helm":           map[string]any{"parameters": params},
			},
			"destination": map[string]any{"server": "https://kubernetes.default.svc", "namespace": r.Name},
			"syncPolicy": map[string]any{
				"automated":   map[string]any{"prune": true, "selfHeal": true},
				"syncOptions": []any{"CreateNamespace=true"},
				"managedNamespaceMetadata": map[string]any{
					"labels": map[string]any{labelManaged: "true", labelTeam: r.Team},
				},
			},
		},
	}}
}

func param(name, value string) map[string]any {
	return map[string]any{"name": name, "value": value}
}
