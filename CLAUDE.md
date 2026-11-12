# ToggleMaster - contexto permanente do projeto

Projeto academico (POSTECH Tech Challenge). Trabalho SOLO: Kevin.
Monorepo com 5 microsservicos + IaC + CI/CD + GitOps + observabilidade.
Fases 1, 2 e 3 estao CONCLUIDAS e entregues. Estamos executando a **Fase 4**
(observabilidade, OpenTelemetry, APM, alertas e self-healing).
O plano detalhado da entrega esta em `FASE4-PLANO.md` - leia esse arquivo antes de agir.

O idioma de trabalho e portugues do Brasil. Comentarios de codigo e commits em portugues,
sem acentos em comentarios de YAML/Terraform (ja e o padrao do repo).

---

## REGRAS DE OURO (quebrar qualquer uma destas ja causou prejuizo real neste projeto)

1. **Trabalhe sempre na branch `main`.** Nao crie branch, nao use stash, nao use
   `git reset --hard` sem me avisar antes. Ja perdemos trabalho assim duas vezes.
2. **Commit + push a cada passo que funciona.** Nunca acumule varias etapas sem push.
   O ArgoCD le do GitHub: sem push, nada acontece no cluster.
3. **NUNCA rode `terraform destroy` em `terraform/bootstrap/`.** Esse state contem o
   bucket S3 `toggle-master-tfstate-6e7f6e06` que guarda o state de tudo o resto.
   `destroy` e permitido APENAS em `terraform/environments/dev/`.
4. **Segredos nunca entram no git.** Chaves de API (New Relic, PagerDuty, Discord) e
   senhas de banco vao para Kubernetes Secrets criados a mao via `kubectl`, ou para
   GitHub Secrets. Se precisar de um valor secreto, PERGUNTE - nao invente, nao gere
   placeholder parecido com chave real (o GitHub Push Protection bloqueia o push).
5. **Nao edite YAML de varios documentos com `yq`.** Ele insere blocos `spec:`/`template:`
   invalidos em documentos ServiceAccount/ConfigMap e quebra o sync do ArgoCD.
   Use Edit/Write ou Python. Depois de qualquer edicao em `gitops/`, rode
   `git diff` e confira o resultado antes do commit.
6. **O custo e real:** ~US$7/dia com o cluster ligado. Se eu disser que vou parar por
   horas, sugira `terraform destroy` em `environments/dev`.
7. Antes de dar algo por funcionando, **valide com comando** (`kubectl get`, `curl`,
   `terraform plan`). Nao afirme que esta pronto sem evidencia na tela.

---

## Estado atual da infraestrutura

- **AWS**: conta `604218333422`, regiao `us-east-1`. Hoje NAO ha nada rodando
  (dev foi destruido). O bucket de state do bootstrap continua existindo.
- Para subir tudo: `cd terraform/environments/dev && terraform init && terraform apply`
  (~20 min). Depois: `aws eks update-kubeconfig --name toggle-master-dev --region us-east-1`.
- **Cluster**: EKS `toggle-master-dev`, Kubernetes 1.33, nodes `t3.medium`.
- Apos cada `apply` novo, os endpoints de RDS/Redis/SQS MUDAM. E preciso recriar os
  Secrets e atualizar os ConfigMaps em `gitops/` com os novos valores.

## Os 5 microsservicos

| Servico | Linguagem | Porta | Depende de |
|---|---|---|---|
| auth-service | Go (net/http + pgx) | 8001 | RDS `auth` |
| flag-service | Python (Flask + psycopg2) | 8002 | RDS `flagdb`, auth-service |
| targeting-service | Python (Flask + psycopg2) | 8003 | RDS `targeting`, auth-service |
| evaluation-service | Go (net/http, go-redis v8, aws-sdk-go v1) | 8004 | Redis, flag, targeting, SQS |
| analytics-service | Python (Flask + boto3) | 8005 | SQS (consome), DynamoDB |

Todos escutam em `0.0.0.0:<porta>` e expoem `/health`. Imagens no ECR
`604218333422.dkr.ecr.us-east-1.amazonaws.com/toggle-master/<servico>`, tags IMMUTABLE.

### Variaveis de ambiente que cada servico realmente le
Errar isso causa CrashLoopBackOff - ja aconteceu.
- auth: `DATABASE_URL`, `MASTER_KEY`, `PORT`
- flag / targeting: `DATABASE_URL`, `AUTH_SERVICE_URL`, `PORT`
- evaluation: `REDIS_URL`, `FLAG_SERVICE_URL`, `TARGETING_SERVICE_URL`, `AWS_SQS_URL`, `AWS_REGION`, `PORT`
- analytics: `AWS_SQS_URL`, `AWS_DYNAMODB_TABLE`, `AWS_REGION`, `PORT`

O banco do flag-service chama `flagdb` (e nao `flag`: "flag" e palavra reservada no RDS).

## Estrutura do repositorio

```
terraform/
  bootstrap/              # bucket S3 do state (NAO DESTRUIR)
  environments/dev/       # montagem: chama os modulos
  modules/{network,eks,database,messaging,ecr,github-oidc,workload-iam}
.github/workflows/        # 5 CIs + reusable-ci-go.yml + reusable-ci-python.yml
gitops/<servico>/         # deployment.yaml + service.yaml (ArgoCD le daqui)
gitops/argocd/applicationset.yaml
observability/            # Fase 4: Applications dos Helm charts + dashboards
microservices/<servico>/
```

## Como o CI/CD funciona (Fase 3, ja validado)

1. Push em `main` com mudanca em `microservices/<svc>/**` dispara o CI daquele servico
   (path filtering). O CI chama o workflow reutilizavel da linguagem.
2. Etapas: lint -> SAST (gosec/bandit) -> SCA (Trivy) -> build -> scan da imagem (Trivy)
   -> push no ECR -> **o bot edita a tag da imagem em `gitops/<svc>/deployment.yaml`**
   e comita com `[skip ci]` (evita loop).
3. O ArgoCD ve o commit e aplica no cluster. **O CI nunca fala com o cluster.**
4. Autenticacao na AWS por OIDC, sem access key.

### Detalhes de CI que custaram horas - nao mexer sem motivo
- `aquasecurity/trivy-action@v0.36.0` (tags migraram para prefixo `v`).
- `golangci/golangci-lint-action@v7` com `version: v2.10.1` (v1 nao suporta Go 1.26).
- `docker/setup-buildx-action@v3` e obrigatorio ANTES do build (senao
  `cache-to: type=gha` falha com "Cache export is not supported for the docker driver").
- Dockerfiles: Python usa `python:3.11-slim-bookworm` (alpine/perl-base tinha CVE
  CRITICAL); evaluation usa `golang:1.26-alpine` (go.mod exige 1.26).
- A trust policy do OIDC usa o formato novo e imutavel do claim `sub`:
  `repo:kevincharnock@48034956/toggle-master-microservices@1329891103:*`.
  Se der `Not authorized to perform sts:AssumeRoleWithWebIdentity`, o problema e aqui.
- "Re-run job" no GitHub reaproveita o snapshot antigo do workflow: para testar
  mudanca em workflow, gere um evento novo (commit).

## Terraform - pontos que nao podem se perder

- `modules/eks`: o node group precisa de `ami_type = "AL2023_x86_64_STANDARD"` (AL2 foi
  descontinuada -> nodes `Unhealthy`) e o addon `vpc-cni` precisa de
  `before_compute = true` (senao `cni plugin not initialized`). Isso ja foi perdido
  num git cleanup e teve de ser refeito.
- `single_nat_gateway = true` em dev. Mudar triplica a conta do NAT.
- O backend S3 usa `use_lockfile` (sem tabela DynamoDB de lock).

## Comandos uteis

```bash
terraform -chdir=terraform/environments/dev output
kubectl get pods -A
kubectl get applications -n argocd
kubectl logs deploy/<svc> --tail=50
argocd app list                      # se o CLI estiver logado
```
