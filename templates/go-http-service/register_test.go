package main

import (
	"sync"

	"github.com/prometheus/client_golang/prometheus"
)

var once sync.Once

func prometheusOnce() { once.Do(func() { prometheus.MustRegister(requests, latency) }) }
