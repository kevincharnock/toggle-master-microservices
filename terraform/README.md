# Terraform - ToggleMaster (Fase 3)

## Estrutura

```
terraform/
├── bootstrap/            # roda UMA VEZ: cria o bucket S3 do state
├── environments/dev/     # montagem do ambiente (so chama modulos)
└── modules/
    ├── network/          # VPC, subnets, IGW, NAT, route tables
    └── eks/              # cluster + node groups
```

Ainda faltam os modulos: `database` (3x RDS + Redis + DynamoDB), `messaging` (SQS),
`ecr` (5 repositorios) e `argocd`.

## Ordem de execucao (primeira vez)

```bash
# 1. Criar o bucket do state
cd terraform/bootstrap
terraform init
terraform apply
# anote o output state_bucket_name

# 2. Colar o nome do bucket em environments/dev/backend.tf
#    (substituir BUCKET_AQUI)

# 3. Subir o ambiente
cd ../environments/dev
terraform init
terraform plan      # SEMPRE leia o plan antes do apply
terraform apply     # ~15-20 min por causa do EKS

# 4. Conectar o kubectl
aws eks update-kubeconfig --region us-east-1 --name toggle-master-dev
kubectl get nodes   # deve listar 2 nos Ready
```

## Destruir (faca isso TODO fim de dia)

```bash
cd terraform/environments/dev
terraform destroy
```

Depois confira no console AWS se sobrou algum **Elastic IP** ou **volume EBS**
orfao - eles continuam sendo cobrados.

## Custo estimado rodando 24/7

| Recurso | Aprox. |
|---|---|
| EKS control plane | US$ 73/mes |
| 2x t3.medium | US$ 60/mes |
| NAT Gateway (1) | US$ 33/mes |
| **Total desta etapa** | **~US$ 166/mes** |

Mas a cobranca e por hora. Usando 40h no total, da ~US$ 9.
Crie um **AWS Budget** com alerta em US$ 10 antes do primeiro apply.
