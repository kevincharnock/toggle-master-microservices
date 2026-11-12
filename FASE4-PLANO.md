# Fase 4 - plano de execucao

Objetivo: chegar o mais rapido possivel a uma **demonstracao em video (ate 25 min)**
que evidencie TODOS os requisitos funcionando. A regra de avaliacao e explicita:
"qualquer requisito que nao for claramente demonstrado no video ou documentado no
relatorio sofre deducao direta de pontos". Nao basta configurar: precisa aparecer operando.

Trabalhamos em blocos A -> E, na ordem. Cada bloco tem um **critério de pronto**
verificavel por comando. Nao avance de bloco sem o critério atendido.
Ao terminar cada bloco: commit + push, e me avise em 2 linhas o que mudou.

---

## O que a Fase 4 exige (resumo do PDF oficial)

1. **Stack opensource no cluster, via GitOps (Helm charts no repositorio)**
   - Prometheus (metricas), Loki (logs centralizados dos conteineres), Grafana (visualizacao).
   - No minimo **1 dashboard customizado** no Grafana reunindo: uso de recursos do
     cluster + taxa de requisicoes dos microsservicos + painel de logs em tempo real.
2. **OTel Collector (OBRIGATORIO)** como peca central: os microsservicos mandam
   telemetria para ele, e ele roteia metricas -> Prometheus, logs -> Loki, traces -> APM.
3. **Instrumentacao + APM comercial** (New Relic, conta free)
   - Alterar codigo-fonte/Dockerfile dos servicos com bibliotecas OpenTelemetry.
   - **Distributed tracing**: uma requisicao no evaluation-service deve aparecer no APM
     mostrando o caminho entre servicos.
   - **Service Map** com os 5 microsservicos no painel do APM.
4. **Alerta + incidente + ChatOps + self-healing**
   - Alerta inteligente (ex.: taxa de 5xx do auth-service > 5%).
   - Incidente aberto automaticamente no **PagerDuty**.
   - Notificacao detalhada no **Discord**.
   - **Self-healing (obrigatorio)**: automacao que reage ao alerta e executa acao
     corretiva, ex. `kubectl rollout restart deployment/auth-service`.

### Entregaveis
- Codigo no repo: IaC/GitOps com a stack e o OTel Collector, apps instrumentadas,
  scripts de self-healing.
- Video de ate 25 min (roteiro no bloco E).
- Relatorio PDF: nome/RM/username, links do repo e do video, justificativa tecnica
  (arquitetura do OTel; por que New Relic e nao Datadog; por que PagerDuty e nao OpsGenie)
  e 4 prints obrigatorios: dashboard do Grafana, trace distribuido no APM,
  notificacao no ChatOps, log/execucao do self-healing.
  (OpsGenie esta em fim de vida - end-of-sale em 2025-06-04, shutdown em 2027-04-05.
  Essa e a justificativa para PagerDuty.)

---

## Decisoes de arquitetura ja tomadas (nao reabrir sem motivo)

- APM: **New Relic** (free tier 100 GB/mes). Endpoint OTLP `otlp.nr-data.net:4317`,
  header `api-key`.
- Incidentes: **PagerDuty** (Events API v2).
- ChatOps: **Discord** (webhook de canal).
- Stack: `kube-prometheus-stack` + `loki` (SingleBinary) + `opentelemetry-collector`
  (2 instancias: um **gateway** em Deployment e um **DaemonSet** para logs de todos os pods),
  todos instalados como **Applications do ArgoCD apontando para o repo Helm** -
  assim o requisito "Helm charts no repositorio GitOps" fica atendido.
- Namespace da observabilidade: `observability`. Apps ficam em `default`.
- Os servicos exportam OTLP para `http://otel-gateway.observability.svc:4318`.
- O gateway usa o connector `spanmetrics` para transformar traces em metricas
  (`traces_span_metrics_calls_total`). E dessas metricas que saem "taxa de requisicoes"
  e "taxa de 5xx" no Prometheus/Grafana, sem precisar instrumentar metricas a mao.

---

## BLOCO A - subir o ambiente + IRSA  (~1h30)

Ha dois patches prontos e testados (aplicam limpos sobre o commit `8d58abb`):
`patches/0001-feat-IRSA-*.patch` e `patches/0001-feat-stack-de-observabilidade-*.patch`.
Aplique com `git am patches/*.patch` e depois `git push`. Se preferir escrever os
arquivos do zero, o conteudo dos patches serve de referencia.

O que o patch de IRSA faz: cria `terraform/modules/workload-iam` com duas IAM Roles
(evaluation = `sqs:SendMessage`; analytics = receive/delete no SQS + `PutItem` no
DynamoDB), liga no `environments/dev/main.tf`, adiciona outputs e anota as
ServiceAccounts com `eks.amazonaws.com/role-arn`. Sem isso o analytics-service fica em
loop com "Unable to locate credentials" e o Service Map nao mostra os 5 servicos.
Tambem sobe `node_desired_size` para 3 (a stack de observabilidade precisa de memoria).

Passos:
1. `git am` dos dois patches, `git push`.
2. `cd terraform/environments/dev && terraform init && terraform apply` (~20 min).
3. `aws eks update-kubeconfig --name toggle-master-dev --region us-east-1`.
4. `terraform output` -> pegue endpoints de RDS, Redis, SQS e os 2 role ARNs.
5. Recrie os Secrets (valores vem do output; a senha do RDS esta no Secrets Manager):
   `auth-db-secret` (chaves `database_url` e `master_key`), `flag-db-secret` e
   `targeting-db-secret` (chave `database_url`). Formato:
   `postgresql://USUARIO:SENHA@ENDPOINT:5432/BANCO`.
6. Atualize `REDIS_URL` e `AWS_SQS_URL` nos ConfigMaps em `gitops/evaluation-service/`
   e `gitops/analytics-service/`. Commit + push.
7. ArgoCD: `helm repo add argo https://argoproj.github.io/argo-helm && helm repo update`,
   `helm install argocd argo/argo-cd -n argocd --create-namespace` (NAO interromper com
   Ctrl+C - ja aconteceu e deixou a release pela metade),
   `kubectl apply -f gitops/argocd/applicationset.yaml`.

**Critério de pronto**: `kubectl get applications -n argocd` com os 5 apps
Synced/Healthy; `kubectl get pods` com 10 pods Running; e
`kubectl logs deploy/analytics-service --tail=20` SEM "Unable to locate credentials".

---

## BLOCO B - Prometheus + Loki + Grafana + OTel Collector  (~1h30)

O patch de observabilidade cria `observability/argocd-apps/` com 5 Applications
(`kps`, `loki`, `otel-gateway`, `otel-logs`, `dashboards`) e o dashboard customizado
em `observability/dashboards/togglemaster-dashboard.yaml` (ConfigMap com label
`grafana_dashboard: "1"`, lido pelo sidecar do Grafana).

As versoes dos charts estao como `PIN_KPS`/`PIN_LOKI`/`PIN_OTEL`. Rode
`./scripts/pin-chart-versions.sh` (ele faz `helm search repo` e fixa a versao mais
recente de cada chart), confira o diff, commit + push.

Passos:
1. `kubectl create ns observability`
2. Secret com a chave do New Relic (eu te passo o valor; ele ja esta referenciado como
   `optional: true` no gateway, entao a stack sobe mesmo sem ele):
   `kubectl -n observability create secret generic newrelic-secret --from-literal=license-key='...'`
3. `kubectl apply -f observability/argocd-apps/`
4. `kubectl -n observability port-forward svc/kps-grafana 3000:80` (admin / toggle-admin)

**Critério de pronto**: os 5 Applications novos Synced/Healthy; Grafana abre; o dashboard
"ToggleMaster - Visao Geral" aparece com CPU/memoria preenchidos e o painel de logs ao
vivo mostrando linhas (via Loki). Os paineis de requisicoes ainda ficam vazios - eles
dependem do bloco C.

Se algum chart reclamar de valores invalidos (schema do chart mudou), ajuste pelo erro de
`kubectl describe application <nome> -n argocd`.

---

## BLOCO C - instrumentacao OpenTelemetry nos 5 servicos  (~3h)

Alvo: todo servico exporta traces (e logs) via OTLP para o gateway, com
`OTEL_SERVICE_NAME` proprio, de forma que o New Relic desenhe o Service Map com os 5
e mostre o trace distribuido de uma requisicao no evaluation-service.

### Python (flag, targeting, analytics) - caminho mais rapido: auto-instrumentacao
- `requirements.txt`: adicionar `opentelemetry-distro`, `opentelemetry-exporter-otlp`,
  `opentelemetry-instrumentation-flask`, `-requests`, `-psycopg2` (flag/targeting),
  `-botocore` (analytics), `-logging`.
- Dockerfile: trocar o entrypoint para rodar sob `opentelemetry-instrument gunicorn ...`.
- Nao precisa mexer no `app.py`.

### Go (auth, evaluation) - precisa de codigo
- Adicionar `go.opentelemetry.io/otel`, `otel/sdk`, `otel/exporters/otlp/otlptracehttp`,
  `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`.
- Criar `otel.go` em cada servico com um `initTracer()` (exportador OTLP + resource com
  service.name + propagador W3C TraceContext) chamado no inicio do `main()`.
- Servidor: envolver o `mux` com `otelhttp.NewHandler(mux, "...")`.
- Cliente HTTP (evaluation chama flag e targeting; flag/targeting chamam auth):
  usar `otelhttp.NewTransport(http.DefaultTransport)` no `http.Client` - isso propaga o
  contexto e e o que faz o trace ficar DISTRIBUIDO em vez de varios traces soltos.
- `evaluation-service` usa `aws-sdk-go` **v1** e `go-redis` **v8**: nao existe
  instrumentacao OTel oficial boa para essas versoes. Nao perca tempo - spans de HTTP
  bastam para o requisito. Se sobrar tempo, crie um span manual em volta da chamada SQS.
- Atencao: `go.mod` do auth esta em `go 1.25.0` e do evaluation em `go 1.26.0`.
  Mantenha a imagem do Dockerfile compativel com o `go.mod` de cada um.

### Variaveis de ambiente (nos deployments do `gitops/`)
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.observability.svc:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_SERVICE_NAME=<nome-do-servico>
OTEL_RESOURCE_ATTRIBUTES=service.namespace=togglemaster,deployment.environment=dev
```

### Fechamento do bloco
Push -> os 5 CIs rodam -> o bot atualiza as tags -> ArgoCD aplica. Depois gere trafego:
port-forward no evaluation-service e um laco de `curl` na rota de avaliacao.

**Critério de pronto**: no New Relic aparecem os 5 servicos; o Service Map liga
evaluation -> flag/targeting -> auth; um trace distribuido de uma requisicao no
evaluation mostra os spans dos servicos seguintes; e no Grafana os paineis "taxa de
requisicoes" e "taxa de erro" tem dados.

---

## BLOCO D - alerta + PagerDuty + Discord + self-healing  (~2h)

1. **Rota de caos** no auth-service: `GET /chaos?fail=on|off` que faz o `/health` e as
   rotas responderem 500 por N segundos. E o jeito controlado de produzir 5xx no video
   (o PDF aceita "injete erro no codigo").
2. **Alerta** no Grafana (Alerting -> Alert rule) sobre a metrica do spanmetrics:
   taxa de spans com erro do auth-service > 5% por 1 min. Deixe o `for` curto (1 min)
   para o video nao ficar parado esperando.
3. **Contact points** no Grafana: um webhook para o PagerDuty (Events API v2) e um
   webhook para o Discord. Dois contact points na mesma notification policy, para que
   um alerta gere incidente E mensagem.
4. **Self-healing**: um Deployment pequeno em Python (Flask) no namespace `observability`
   que expoe `POST /heal`, valida um token compartilhado e executa
   `kubectl rollout restart deployment/auth-service -n default`.
   - RBAC minimo: ServiceAccount proprio + Role com `get/list/patch` em `deployments`
     no namespace `default` (patch e o que o rollout restart usa). Nada de cluster-admin.
   - Terceiro contact point do Grafana aponta para esse endpoint.
   - O servico deve logar cada acionamento com data/hora e o alerta recebido - esse log
     e um dos 4 prints obrigatorios.
   - Tudo isso versionado em `observability/self-healing/` e aplicado pelo ArgoCD.

**Critério de pronto**: ligar o caos -> alerta vai para Firing no Grafana -> incidente
abre no PagerDuty -> mensagem chega no Discord -> o log do self-healing registra a acao
-> `kubectl get pods -w` mostra os pods do auth-service reiniciando.

---

## BLOCO E - gravacao e relatorio  (~2h)

Roteiro do video (ate 25 min; sugestao de tempo por bloco):
1. (2 min) Visao geral: console AWS com o EKS de pe, `terraform output`, ArgoCD com os
   10 Applications Synced/Healthy.
2. (5 min) Grafana: o dashboard customizado com recursos do cluster, taxa de requisicoes
   e logs ao vivo; uma busca no Loki; e a explicacao de como o OTel Collector roteia
   (mostrar `observability/argocd-apps/otel-gateway.yaml`: receivers -> pipelines ->
   exporters).
3. (5 min) New Relic: Service Map com os 5 servicos; um `curl` no evaluation-service e o
   trace distribuido correspondente aberto e detalhado.
4. (8 min) A prova real: liga o caos no auth-service -> alerta Firing -> incidente no
   PagerDuty -> mensagem no Discord -> log do self-healing -> pods reiniciando no terminal.
5. (2 min) Fechamento: codigo no repositorio (IaC, GitOps, instrumentacao, self-healing).

Antes de gravar, deixe abertos: terminal, Grafana, New Relic, PagerDuty, Discord e o
GitHub. Durante o bloco 4, mantenha `kubectl get pods -w` visivel.

Prints obrigatorios para o relatorio (tirar durante a gravacao, nao depois):
dashboard do Grafana, trace distribuido, notificacao no Discord, log do self-healing.

Depois do video: `terraform destroy` em `environments/dev` (NUNCA no bootstrap).

Dados do relatorio que ainda faltam: nome completo, RM e username do Kevin.
