# ============================================================================
# MODULO: EKS
#
# Aqui EU USO o modulo oficial da comunidade (terraform-aws-modules/eks/aws),
# ao contrario da rede. Motivo: um cluster EKS escrito na mao sao ~40 recursos
# (cluster, node group, 4 roles IAM, security groups, launch template, addons,
# OIDC provider...). Nao ha ganho pedagogico em reescrever isso; ha ganho em
# entender o que voce esta configurando.
#
# ATENCAO A VERSAO: a serie 21.x mudou bastante em relacao a 20.x e 19.x.
# Tutorial do YouTube de 2024 vai quebrar aqui. As duas mudancas que mais
# confundem:
#   - o parametro de versao do k8s agora e `kubernetes_version` (era `cluster_version`)
#   - autenticacao agora e por "access entries" (o ConfigMap aws-auth morreu)
# ============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Endpoint publico = voce consegue rodar kubectl da sua maquina e o GitHub
  # Actions consegue alcancar o cluster. Em producao voce restringiria
  # `endpoint_public_access_cidrs` a IPs conhecidos.
  endpoint_public_access  = true
  endpoint_private_access = true

  # Voce (quem roda o terraform apply) vira admin do cluster automaticamente.
  # Sem isso, voce cria o cluster e nao consegue rodar kubectl nele.
  enable_cluster_creator_admin_permissions = true

  # Addons essenciais. O EKS nao vem com rede nem DNS funcionando por padrao.
  addons = {
    coredns                = {} # DNS interno do cluster
    kube-proxy             = {} # roteamento de Services
    vpc-cni                = {} # rede dos pods (da IP da VPC para cada pod)
    eks-pod-identity-agent = {} # permite pods assumirem roles IAM
  }

  eks_managed_node_groups = {
    default = {
      # ON_DEMAND e mais caro que SPOT, mas SPOT pode ser encerrado pela AWS
      # no meio da sua gravacao. Para o video, prefira ON_DEMAND.
      capacity_type = var.capacity_type

      instance_types = var.instance_types

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      # 5 microsservicos + ArgoCD (que sozinho sobe ~7 pods) precisam de
      # folga. t3.medium suporta ate 17 pods por no.
      disk_size = 30

      labels = {
        role = "general"
      }
    }
  }

  tags = var.tags
}
