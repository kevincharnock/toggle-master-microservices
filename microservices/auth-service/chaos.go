package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"sync/atomic"
	"time"
)

// Chaos engineering controlado (Fase 4): permite provocar 5xx de proposito para
// demonstrar alerta -> incidente -> self-healing.
//
//	GET /chaos?fail=on&seconds=300   liga (padrao 300s, maximo 600s)
//	GET /chaos?fail=off              desliga
//	GET /chaos                       mostra o estado
//
// Regras de seguranca:
//   - a rota exige a MASTER_KEY (mesmo middleware das rotas /admin);
//   - expira sozinha (a falha nunca fica ligada para sempre);
//   - /health continua respondendo 200, senao a liveness probe reiniciaria o pod
//     por conta propria e esconderia a acao do self-healing;
//   - o estado fica em memoria: um restart do pod (rollout restart) zera tudo,
//     que e exatamente a "correcao" que o self-healing aplica.
const (
	chaosDefaultSeconds = 300
	chaosMaxSeconds     = 600
)

// chaosUntil guarda o instante (unix nano) ate quando as rotas devem falhar. 0 = desligado.
var chaosUntil atomic.Int64

func chaosActive() bool {
	until := chaosUntil.Load()
	return until != 0 && time.Now().UnixNano() < until
}

// chaosHandler liga/desliga a injecao de falha.
func (a *App) chaosHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	switch r.URL.Query().Get("fail") {
	case "on":
		seconds := chaosDefaultSeconds
		if v := r.URL.Query().Get("seconds"); v != "" {
			n, err := strconv.Atoi(v)
			if err != nil || n <= 0 {
				http.Error(w, `{"error":"seconds invalido"}`, http.StatusBadRequest)
				return
			}
			seconds = min(n, chaosMaxSeconds)
		}
		chaosUntil.Store(time.Now().Add(time.Duration(seconds) * time.Second).UnixNano())
		log.Printf("CHAOS LIGADO: rotas vao responder 500 por %ds", seconds)
	case "off":
		chaosUntil.Store(0)
		log.Println("CHAOS DESLIGADO")
	case "":
		// apenas consulta o estado
	default:
		http.Error(w, `{"error":"use fail=on ou fail=off"}`, http.StatusBadRequest)
		return
	}

	remaining := 0
	if chaosActive() {
		remaining = int(time.Until(time.Unix(0, chaosUntil.Load())).Seconds())
	}
	if err := json.NewEncoder(w).Encode(map[string]any{
		"chaos":             chaosActive(),
		"remaining_seconds": remaining,
	}); err != nil {
		log.Printf("erro ao codificar resposta: %v", err)
	}
}

// chaosMiddleware responde 500 em todas as rotas enquanto o caos estiver ativo,
// exceto /health e /chaos.
func chaosMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health" && r.URL.Path != "/chaos" && chaosActive() {
			http.Error(w, "falha injetada (chaos)", http.StatusInternalServerError)
			return
		}
		next.ServeHTTP(w, r)
	})
}
