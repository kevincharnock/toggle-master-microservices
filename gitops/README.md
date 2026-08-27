# GitOps - manifestos Kubernetes

## Estrutura

```
gitops/
├── auth-service/
│   ├── deployment.yaml        ← a linha da imagem e reescrita pelo CI
│   ├── service.yaml
│   └── secret.yaml.example    ← template, nao comite valores reais
├── flag-service/              (mesma estrutura)
├── targeting-service/         (mesma estrutura)
├── evaluation-service/        (usa Redis + SQS, ConfigMap em vez de Secret)
├── analytics-service/         (usa DynamoDB, ConfigMap)
└── argocd/
    └── applicationset.yaml    ← registra os 5 apps no ArgoCD
```

**Uma pasta = uma Application do ArgoCD.** O ArgoCD aplica TODOS os YAMLs
que encontrar dentro da pasta.

## A linha que muda

```yaml
containers:
  - name: auth-service
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/toggle-master/auth-service:placeholder
                                                                                    ↑
                                                        o CI troca isto pela tag do commit
```

Fluxo completo:

```
push na main
   → CI: build, lint, SCA, SAST, docker build, scan
   → CI: push da imagem no ECR com tag 20260812-a1b2c3d
   → CI: yq reescreve a linha acima em gitops/auth-service/deployment.yaml
   → CI: git commit -m "chore(auth): bump image [skip ci]"
   → CI TERMINA (nunca roda kubectl)
   → ArgoCD ve o commit e aplica no cluster sozinho
```

## Antes de aplicar - 3 ajustes obrigatorios

**1. repoURL** em `argocd/applicationset.yaml`:
```yaml
repoURL: https://github.com/kevincharnock/toggle-master-microservices.git
```

**2. Secrets dos bancos** (auth, flag, targeting). Depois do terraform apply:
```bash
# pega o endpoint
terraform output postgres_endpoints

# pega a senha (o Terraform gerou e guardou no Secrets Manager)
aws secretsmanager get-secret-value \
  --secret-id toggle-master-dev/auth/postgres \
  --query SecretString --output text

# cria o secret no cluster
kubectl create secret generic auth-db-secret \
  --from-literal=host=SEU_ENDPOINT \
  --from-literal=port=5432 \
  --from-literal=username=toggleadmin \
  --from-literal=password=SUA_SENHA
```
Repita para flag e targeting.

**3. ConfigMaps** de evaluation e analytics: troque os `PREENCHER-COM-...`
pelos valores de `terraform output redis_endpoint` e `terraform output sqs_queue_url`.

## Instalar o ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace

# senha inicial do admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# acessar a UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080  (usuario: admin)
```

Depois:
```bash
kubectl apply -f gitops/argocd/applicationset.yaml
kubectl get applications -n argocd   # devem aparecer as 5
```

## Demo do selfHeal para o video

Vale 30 segundos e impressiona:

```bash
kubectl scale deployment auth-service --replicas=5
kubectl get pods -w
```

O ArgoCD detecta o desvio e volta para 2 replicas sozinho, em segundos.
E a prova visual de que ninguem consegue mais mudar o cluster por fora do Git.
