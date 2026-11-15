#!/usr/bin/env python3
"""Self-healing (Runbook Automation) do ToggleMaster - Fase 4.

Recebe o webhook do Grafana Alerting (contact point "self-healing") e, quando o
alerta esta FIRING, executa a acao corretiva:

    kubectl rollout restart deployment/auth-service -n default

O "rollout restart" nada mais e do que um PATCH no Deployment que grava a anotacao
kubectl.kubernetes.io/restartedAt no template dos pods. Fazemos esse mesmo PATCH
direto na API do Kubernetes (so biblioteca padrao: sem pip, sem binario kubectl).

Seguranca:
  - POST /heal exige "Authorization: Bearer <HEAL_TOKEN>" (token compartilhado com o Grafana);
  - so reinicia Deployments da lista ALLOWED_DEPLOYMENTS, no namespace TARGET_NAMESPACE;
  - o RBAC do pod permite apenas get/patch no Deployment auth-service;
  - COOLDOWN_SECONDS evita reiniciar em loop quando o Grafana reenvia a notificacao.

Cada acionamento e logado com data/hora e o alerta recebido (evidencia para o relatorio).
"""
import hmac
import json
import logging
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HEAL_TOKEN = os.environ.get("HEAL_TOKEN", "")
TARGET_NS = os.environ.get("TARGET_NAMESPACE", "default")
DEFAULT_TARGET = os.environ.get("TARGET_DEPLOYMENT", "auth-service")
ALLOWED = {d.strip() for d in os.environ.get("ALLOWED_DEPLOYMENTS", DEFAULT_TARGET).split(",") if d.strip()}
COOLDOWN = int(os.environ.get("COOLDOWN_SECONDS", "120"))
PORT = int(os.environ.get("PORT", "8080"))
K8S_API = os.environ.get("K8S_API", "https://kubernetes.default.svc")
SA_DIR = os.environ.get("SA_DIR", "/var/run/secrets/kubernetes.io/serviceaccount")

logging.Formatter.converter = time.gmtime
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)sZ [self-healing] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    stream=sys.stdout,
)
log = logging.getLogger("heal")

_lock = threading.Lock()
_last_restart = {}  # deployment -> time.monotonic() do ultimo restart


def rollout_restart(namespace, deployment):
    """Equivalente a `kubectl rollout restart deployment/<deployment> -n <namespace>`."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = json.dumps({"spec": {"template": {"metadata": {"annotations": {
        "kubectl.kubernetes.io/restartedAt": now}}}}}).encode()

    with open(os.path.join(SA_DIR, "token"), encoding="utf-8") as f:
        sa_token = f.read().strip()
    ca = os.path.join(SA_DIR, "ca.crt")
    ctx = ssl.create_default_context(cafile=ca) if os.path.exists(ca) else None

    req = urllib.request.Request(
        f"{K8S_API}/apis/apps/v1/namespaces/{namespace}/deployments/{deployment}",
        data=body,
        method="PATCH",
        headers={
            "Authorization": f"Bearer {sa_token}",
            "Content-Type": "application/strategic-merge-patch+json",
        },
    )
    with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:  # nosec B310 - URL fixa da API do cluster
        return resp.status


def describe_alert(alert):
    labels = alert.get("labels", {})
    notes = alert.get("annotations", {})
    return (f"alertname={labels.get('alertname', '?')} service={labels.get('service', '?')} "
            f"severity={labels.get('severity', '?')} startsAt={alert.get('startsAt', '?')} "
            f"summary={notes.get('summary', '')!r}")


def handle_alert(payload):
    """Processa o payload do Grafana. Retorna (http_status, dict_resposta)."""
    status = payload.get("status", "")
    alerts = payload.get("alerts", []) or []
    for alert in alerts:
        log.info("ALERTA RECEBIDO status=%s %s", alert.get("status", status), describe_alert(alert))

    if status != "firing":
        log.info("IGNORADO: payload com status=%r (so age em firing)", status)
        return 200, {"action": "none", "reason": f"status={status}"}

    target = DEFAULT_TARGET
    for alert in alerts:
        wanted = alert.get("labels", {}).get("heal_deployment")
        if wanted:
            target = wanted
            break
    if target not in ALLOWED:
        log.warning("RECUSADO: deployment %r fora da lista permitida %s", target, sorted(ALLOWED))
        return 400, {"action": "none", "reason": "deployment nao permitido"}

    with _lock:
        elapsed = time.monotonic() - _last_restart.get(target, -COOLDOWN - 1)
        if elapsed < COOLDOWN:
            log.info("COOLDOWN: %s ja foi reiniciado ha %.0fs (minimo %ss) - nenhuma acao", target, elapsed, COOLDOWN)
            return 200, {"action": "none", "reason": "cooldown"}
        _last_restart[target] = time.monotonic()

    log.info("ACAO: kubectl rollout restart deployment/%s -n %s", target, TARGET_NS)
    try:
        code = rollout_restart(TARGET_NS, target)
    except (urllib.error.URLError, OSError) as exc:
        with _lock:
            _last_restart.pop(target, None)  # permite nova tentativa no proximo envio
        log.error("FALHA ao reiniciar deployment/%s: %s", target, exc)
        return 502, {"action": "restart", "error": str(exc)}
    log.info("SUCESSO: deployment/%s restarted (HTTP %s da API do Kubernetes)", target, code)
    return 200, {"action": "rollout restart", "deployment": target, "namespace": TARGET_NS}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/heal":
            self._send(404, {"error": "not found"})
            return
        supplied = self.headers.get("Authorization", "").removeprefix("Bearer ")
        if not hmac.compare_digest(supplied.encode(), HEAL_TOKEN.encode()):
            log.warning("NEGADO: token invalido vindo de %s", self.client_address[0])
            self._send(401, {"error": "unauthorized"})
            return
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 1_000_000)
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"error": "json invalido"})
            return
        code, resp = handle_alert(payload)
        self._send(code, resp)

    def log_message(self, fmt, *args):  # silencia o log por requisicao (probes)
        pass


if __name__ == "__main__":
    if not HEAL_TOKEN:
        sys.exit("HEAL_TOKEN nao definido: recuso subir sem autenticacao")
    log.info("pronto na porta %s | alvo=%s/%s | permitidos=%s | cooldown=%ss",
             PORT, TARGET_NS, DEFAULT_TARGET, sorted(ALLOWED), COOLDOWN)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()  # nosec B104 - bind necessario no container
