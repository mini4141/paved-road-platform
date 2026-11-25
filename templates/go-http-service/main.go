// Command go-http-service is the Go golden-path service: /, /healthz, /work, /metrics,
// JSON logs, Prometheus metrics (with trace exemplars) and OpenTelemetry traces.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	serviceName = env("SERVICE_NAME", "go-http-service")
	logger      = slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", serviceName)

	requests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total", Help: "HTTP requests.",
	}, []string{"method", "path", "code"})
	latency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_request_duration_seconds", Help: "HTTP request latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5},
	}, []string{"method", "path"})
)

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(c int) { w.code = c; w.ResponseWriter.WriteHeader(c) }

// instrument records metrics, a span and a JSON access log line per request.
func instrument(path string, h http.HandlerFunc) http.Handler {
	tracer := otel.Tracer(serviceName)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		ctx, span := tracer.Start(ctx, r.Method+" "+path)
		defer span.End()
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		h(sw, r.WithContext(ctx))
		d := time.Since(start).Seconds()
		code := strconv.Itoa(sw.code)
		requests.WithLabelValues(r.Method, path, code).Inc()
		obs := latency.WithLabelValues(r.Method, path)
		if sc := trace.SpanContextFromContext(ctx); sc.IsSampled() {
			obs.(prometheus.ExemplarObserver).ObserveWithExemplar(d, prometheus.Labels{"trace_id": sc.TraceID().String()})
		} else {
			obs.Observe(d)
		}
		if path != "/healthz" {
			logger.InfoContext(ctx, "request", "method", r.Method, "path", path, "code", sw.code,
				"duration_ms", float64(time.Since(start).Microseconds())/1000,
				"trace_id", trace.SpanContextFromContext(ctx).TraceID().String())
		}
	})
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.Handle("GET /{$}", instrument("/", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"service": serviceName, "template": "go-http-service", "status": "ok"})
	}))
	mux.Handle("GET /healthz", instrument("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	}))
	mux.Handle("GET /work", instrument("/work", func(w http.ResponseWriter, r *http.Request) {
		ms, _ := strconv.Atoi(r.URL.Query().Get("ms"))
		busy(time.Duration(min(max(ms, 0), 5000)) * time.Millisecond)
		_, _ = w.Write([]byte("done"))
	}))
	mux.Handle("GET /metrics", promhttp.HandlerFor(prometheus.DefaultGatherer, promhttp.HandlerOpts{EnableOpenMetrics: true}))
	return mux
}

// busy burns CPU for d (used by load tests to trigger the HPA).
func busy(d time.Duration) {
	end := time.Now().Add(d)
	for x := 0; time.Now().Before(end); x++ {
		_ = x * x
	}
}

func initTracing(ctx context.Context) func(context.Context) error {
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		return func(context.Context) error { return nil }
	}
	exp, err := otlptracehttp.New(ctx)
	if err != nil {
		logger.Error("otel exporter", "err", err)
		return func(context.Context) error { return nil }
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp),
		sdktrace.WithResource(resource.NewSchemaless(semconv.ServiceName(serviceName))))
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})
	return tp.Shutdown
}

func main() {
	prometheus.MustRegister(requests, latency)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	shutdownTracing := initTracing(ctx)

	srv := &http.Server{Addr: env("ADDR", ":8080"), Handler: newMux(), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		logger.Info("listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			logger.Error("server", "err", err)
			os.Exit(1)
		}
	}()
	<-ctx.Done()
	sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
	_ = shutdownTracing(sctx)
}
