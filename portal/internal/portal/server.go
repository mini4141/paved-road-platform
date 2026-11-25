package portal

import (
	"embed"
	"html/template"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/dynamic"
)

//go:embed all:web
var webFS embed.FS

// Server serves the portal pages.
type Server struct {
	dyn  dynamic.Interface
	cfg  Config
	tmpl *template.Template
	log  *slog.Logger
}

// New builds a Server around a dynamic Kubernetes client.
func New(dyn dynamic.Interface, cfg Config, log *slog.Logger) (*Server, error) {
	t, err := template.ParseFS(webFS, "web/templates/*.html")
	if err != nil {
		return nil, err
	}
	return &Server{dyn: dyn, cfg: cfg, tmpl: t, log: log}, nil
}

// Handler returns the routed, logged HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	static, _ := fs.Sub(webFS, "web/static")
	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServerFS(static)))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("ok")) })
	mux.HandleFunc("GET /{$}", s.catalog)
	mux.HandleFunc("GET /services", s.catalog)
	mux.HandleFunc("GET /services/new", s.newForm)
	mux.HandleFunc("POST /services", s.create)
	mux.HandleFunc("GET /services/{name}", s.detail)
	mux.HandleFunc("GET /services/{name}/status", s.status)
	mux.HandleFunc("DELETE /services/{name}", s.remove)
	mux.HandleFunc("POST /alerts", s.alerts)
	return s.logging(mux)
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(c int) { w.code = c; w.ResponseWriter.WriteHeader(c) }

func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		next.ServeHTTP(sw, r)
		if r.URL.Path != "/healthz" {
			s.log.Info("request", "method", r.Method, "path", r.URL.Path, "code", sw.code,
				"duration_ms", time.Since(start).Milliseconds())
		}
	})
}

func (s *Server) render(w http.ResponseWriter, name string, data any) {
	if err := s.tmpl.ExecuteTemplate(w, name, data); err != nil {
		s.log.Error("render", "template", name, "err", err)
		http.Error(w, "render error", http.StatusInternalServerError)
	}
}

func (s *Server) catalog(w http.ResponseWriter, r *http.Request) {
	list, err := s.dyn.Resource(applicationGVR).Namespace(s.cfg.ArgoNamespace).
		List(r.Context(), metav1.ListOptions{LabelSelector: labelManaged + "=true"})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	var views []ServiceView
	for i := range list.Items {
		views = append(views, s.view(r.Context(), &list.Items[i], false))
	}
	sort.Slice(views, func(i, j int) bool { return views[i].Name < views[j].Name })
	s.render(w, "catalog.html", map[string]any{"Services": views})
}

func (s *Server) newForm(w http.ResponseWriter, _ *http.Request) {
	s.render(w, "new.html", map[string]any{"Error": ""})
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	replicas, _ := strconv.Atoi(r.FormValue("replicas"))
	maxReplicas, _ := strconv.Atoi(r.FormValue("max_replicas"))
	req := ServiceRequest{
		Name: r.FormValue("name"), Template: r.FormValue("template"), Team: r.FormValue("team"),
		Replicas: replicas, Autoscaling: r.FormValue("autoscaling") == "on", MaxReplicas: maxReplicas,
	}
	if req.Team == "" {
		req.Team = "platform"
	}
	if err := req.Validate(); err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		s.render(w, "new.html", map[string]any{"Error": err.Error()})
		return
	}
	if _, err := s.dyn.Resource(applicationGVR).Namespace(s.cfg.ArgoNamespace).
		Create(r.Context(), s.cfg.BuildApplication(req), metav1.CreateOptions{}); err != nil {
		w.WriteHeader(http.StatusConflict)
		s.render(w, "new.html", map[string]any{"Error": err.Error()})
		return
	}
	s.log.Info("service created", "name", req.Name, "template", req.Template, "team", req.Team)
	http.Redirect(w, r, "/services/"+req.Name, http.StatusSeeOther)
}

func (s *Server) get(w http.ResponseWriter, r *http.Request, detail bool) (ServiceView, bool) {
	app, err := s.dyn.Resource(applicationGVR).Namespace(s.cfg.ArgoNamespace).
		Get(r.Context(), r.PathValue("name"), metav1.GetOptions{})
	if err != nil {
		http.Error(w, "service not found", http.StatusNotFound)
		return ServiceView{}, false
	}
	return s.view(r.Context(), app, detail), true
}

func (s *Server) detail(w http.ResponseWriter, r *http.Request) {
	if v, ok := s.get(w, r, true); ok {
		s.render(w, "detail.html", v)
	}
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	if v, ok := s.get(w, r, true); ok {
		s.render(w, "status.html", v)
	}
}

func (s *Server) remove(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if err := s.dyn.Resource(applicationGVR).Namespace(s.cfg.ArgoNamespace).
		Delete(r.Context(), name, metav1.DeleteOptions{}); err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	s.log.Info("service deleted", "name", name)
	w.Header().Set("HX-Redirect", "/")
	w.WriteHeader(http.StatusNoContent)
}

// alerts is the Alertmanager webhook receiver: it logs the payload so firing alerts are visible in Loki.
func (s *Server) alerts(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	s.log.Warn("alertmanager webhook", "payload", string(body))
	w.WriteHeader(http.StatusAccepted)
}
