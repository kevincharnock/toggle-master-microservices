package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// initTracer configura o exportador OTLP/HTTP (para o OTel Collector gateway) e o
// propagador W3C TraceContext. O endpoint e o service.name vem das variaveis padrao
// OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME e OTEL_RESOURCE_ATTRIBUTES.
// Retorna a funcao de shutdown (faz o flush dos spans pendentes).
func initTracer() func(context.Context) error {
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT nao definido: tracing desativado")
		return func(context.Context) error { return nil }
	}

	exporter, err := otlptracehttp.New(context.Background())
	if err != nil {
		log.Printf("aviso: falha ao criar exportador OTLP, tracing desativado: %v", err)
		return func(context.Context) error { return nil }
	}

	res, err := resource.New(context.Background(),
		resource.WithFromEnv(), // service.name e atributos das variaveis OTEL_*
		resource.WithTelemetrySDK(),
	)
	if err != nil {
		log.Printf("aviso: falha ao montar resource OTel: %v", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))
	log.Println("OpenTelemetry tracing ativado")
	return tp.Shutdown
}

// notHealthCheck exclui /health do tracing: as probes do Kubernetes bateriam toda hora
// e diluiriam a taxa de erro calculada pelo spanmetrics.
func notHealthCheck(r *http.Request) bool {
	return r.URL.Path != "/health"
}
