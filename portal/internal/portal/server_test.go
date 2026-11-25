package portal

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	dynfake "k8s.io/client-go/dynamic/fake"
)

func newTestServer(t *testing.T, objs ...runtime.Object) (*Server, *dynfake.FakeDynamicClient) {
	t.Helper()
	listKinds := map[schema.GroupVersionResource]string{
		applicationGVR: "ApplicationList", deploymentGVR: "DeploymentList", eventGVR: "EventList",
	}
	dyn := dynfake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), listKinds, objs...)
	cfg := Config{RepoURL: "https://example.test/repo.git", Revision: "main", ArgoNamespace: "argocd",
		ImageTag: "0.1.0", OpenCostURL: "http://127.0.0.1:1", GrafanaDashPath: "/grafana/d/x/y"}
	s, err := New(dyn, cfg, slog.New(slog.NewJSONHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	return s, dyn
}

func do(s *Server, method, target string, form url.Values) *httptest.ResponseRecorder {
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req := httptest.NewRequest(method, target, body)
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, req)
	return rec
}

func TestCreateServiceBuildsApplication(t *testing.T) {
	s, dyn := newTestServer(t)
	rec := do(s, http.MethodPost, "/services", url.Values{
		"name": {"orders-api"}, "template": {"go-http"}, "team": {"payments"},
		"replicas": {"2"}, "autoscaling": {"on"}, "max_replicas": {"5"},
	})
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/services/orders-api" {
		t.Fatalf("unexpected response %d %s", rec.Code, rec.Header().Get("Location"))
	}
	app, err := dyn.Resource(applicationGVR).Namespace("argocd").Get(context.Background(), "orders-api", metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if app.GetLabels()[labelManaged] != "true" || app.GetLabels()[labelTeam] != "payments" {
		t.Errorf("labels: %v", app.GetLabels())
	}
	if path, _, _ := unstructured.NestedString(app.Object, "spec", "source", "path"); path != "charts/golden-service" {
		t.Errorf("path = %q", path)
	}
	params, _, _ := unstructured.NestedSlice(app.Object, "spec", "source", "helm", "parameters")
	got := map[string]string{}
	for _, p := range params {
		m := p.(map[string]any)
		got[m["name"].(string)] = m["value"].(string)
	}
	want := map[string]string{"nameOverride": "orders-api", "image.repository": "go-http-service",
		"autoscaling.enabled": "true", "autoscaling.maxReplicas": "5", "replicas": "2", "team": "payments"}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("param %s = %q, want %q", k, got[k], v)
		}
	}
}

func TestCreateServiceRejectsBadName(t *testing.T) {
	s, _ := newTestServer(t)
	rec := do(s, http.MethodPost, "/services", url.Values{"name": {"Bad_Name"}, "template": {"go-http"}})
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("code = %d", rec.Code)
	}
}

func appObject(name string) *unstructured.Unstructured {
	app := Config{ArgoNamespace: "argocd", ImageTag: "0.1.0"}.BuildApplication(
		ServiceRequest{Name: name, Template: "go-http", Team: "payments", Replicas: 2, Autoscaling: true, MaxReplicas: 5})
	_ = unstructured.SetNestedField(app.Object, "Synced", "status", "sync", "status")
	_ = unstructured.SetNestedField(app.Object, "Healthy", "status", "health", "status")
	return app
}

func TestCatalogListsServices(t *testing.T) {
	s, _ := newTestServer(t, appObject("orders-api"))
	rec := do(s, http.MethodGet, "/", nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "orders-api") || !strings.Contains(rec.Body.String(), "Healthy") {
		t.Fatalf("catalog: %d %s", rec.Code, rec.Body.String())
	}
}

func TestNewFormAndHealthz(t *testing.T) {
	s, _ := newTestServer(t)
	if rec := do(s, http.MethodGet, "/services/new", nil); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Create service") {
		t.Fatalf("form: %d", rec.Code)
	}
	if rec := do(s, http.MethodGet, "/healthz", nil); rec.Code != http.StatusOK {
		t.Fatalf("healthz: %d", rec.Code)
	}
}

func TestDetailAndStatusPartial(t *testing.T) {
	s, _ := newTestServer(t, appObject("orders-api"))
	if rec := do(s, http.MethodGet, "/services/orders-api", nil); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "hx-trigger=\"every 3s\"") {
		t.Fatalf("detail: %d", rec.Code)
	}
	rec := do(s, http.MethodGet, "/services/orders-api/status", nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Healthy") {
		t.Fatalf("status: %d %s", rec.Code, rec.Body.String())
	}
}

func TestDeleteService(t *testing.T) {
	s, dyn := newTestServer(t, appObject("orders-api"))
	rec := do(s, http.MethodDelete, "/services/orders-api", nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete: %d", rec.Code)
	}
	if _, err := dyn.Resource(applicationGVR).Namespace("argocd").Get(context.Background(), "orders-api", metav1.GetOptions{}); err == nil {
		t.Fatal("application still exists")
	}
}
