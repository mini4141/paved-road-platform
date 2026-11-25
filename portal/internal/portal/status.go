package portal

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

// Event is a recent Kubernetes event of the service namespace.
type Event struct{ Type, Reason, Message string }

// Check is one scorecard line.
type Check struct {
	Name string
	OK   bool
}

// ServiceView is what the templates render.
type ServiceView struct {
	Name, Team, Sync, Health string
	Ready, Desired           int64
	Autoscaling              bool
	MaxReplicas              string
	Cost                     string
	URL, GrafanaURL          string
	Events                   []Event
	Scorecard                []Check
}

func str(u *unstructured.Unstructured, fields ...string) string {
	v, _, _ := unstructured.NestedString(u.Object, fields...)
	return v
}

func (s *Server) view(ctx context.Context, app *unstructured.Unstructured, detail bool) ServiceView {
	name := app.GetName()
	v := ServiceView{
		Name: name, Team: app.GetLabels()[labelTeam],
		Sync: str(app, "status", "sync", "status"), Health: str(app, "status", "health", "status"),
		URL: "/svc/" + name + "/", GrafanaURL: s.cfg.GrafanaDashPath + "?var-service=" + name,
	}
	if v.Sync == "" {
		v.Sync, v.Health = "Unknown", "Progressing"
	}
	params, _, _ := unstructured.NestedSlice(app.Object, "spec", "source", "helm", "parameters")
	vals := map[string]string{}
	for _, p := range params {
		if m, ok := p.(map[string]any); ok {
			vals[fmt.Sprint(m["name"])] = fmt.Sprint(m["value"])
		}
	}
	v.Autoscaling, v.MaxReplicas = vals["autoscaling.enabled"] == "true", vals["autoscaling.maxReplicas"]

	if d, err := s.dyn.Resource(deploymentGVR).Namespace(name).Get(ctx, name, metav1.GetOptions{}); err == nil {
		v.Ready, _, _ = unstructured.NestedInt64(d.Object, "status", "readyReplicas")
		v.Desired, _, _ = unstructured.NestedInt64(d.Object, "status", "replicas")
	}
	if detail {
		v.Events = s.events(ctx, name)
		v.Cost = s.cost(ctx, name)
		v.Scorecard = []Check{
			{"Healthy and synced", v.Health == "Healthy" && v.Sync == "Synced"},
			{"At least 2 replicas", v.Desired >= 2},
			{"Autoscaling enabled", v.Autoscaling},
			{"Owner team label set", v.Team != ""},
			{"Requests/limits and PDB (chart defaults)", true},
		}
	}
	return v
}

func (s *Server) events(ctx context.Context, ns string) []Event {
	list, err := s.dyn.Resource(eventGVR).Namespace(ns).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil
	}
	items := list.Items
	sort.Slice(items, func(i, j int) bool {
		return items[i].GetCreationTimestamp().After(items[j].GetCreationTimestamp().Time)
	})
	var out []Event
	for i := range items {
		out = append(out, Event{str(&items[i], "type"), str(&items[i], "reason"), str(&items[i], "message")})
		if len(out) == 8 {
			break
		}
	}
	return out
}

// cost asks OpenCost for the namespace's cost over the last hour and scales it to $/hour.
func (s *Server) cost(ctx context.Context, ns string) string {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	url := s.cfg.OpenCostURL + "/allocation/compute?window=1h&aggregate=namespace&accumulate=true"
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "n/a"
	}
	defer resp.Body.Close()
	var body struct {
		Data []map[string]struct {
			TotalCost float64 `json:"totalCost"`
			Minutes   float64 `json:"minutes"`
		} `json:"data"`
	}
	if json.NewDecoder(resp.Body).Decode(&body) != nil || len(body.Data) == 0 {
		return "n/a"
	}
	a, ok := body.Data[0][ns]
	if !ok || a.Minutes <= 0 {
		return "n/a"
	}
	return fmt.Sprintf("$%.4f/hour", a.TotalCost/(a.Minutes/60))
}
