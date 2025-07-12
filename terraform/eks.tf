# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Encryption key
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name = "eks-nebulance-nodes"

      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 10
      desired_size = 3

      ami_type                   = "AL2_x86_64"
      capacity_type             = "ON_DEMAND"
      disk_size                  = 50
      force_update_version       = false
      use_custom_launch_template = false

      update_config = {
        max_unavailable_percentage = 33
      }

      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }

      taints = {}

      tags = {
        Name = "eks-nebulance-node-group"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.external_secrets.arn
      username = "external-secrets"
      groups   = ["system:masters"]
    },
  ]

  tags = {
    Name = "eks-nebulance"
  }
}

# IAM role for External Secrets Operator
resource "aws_iam_role" "external_secrets" {
  name = "eks-nebulance-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:external-secrets:external-secrets"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com"
          }
        }
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
      }
    ]
  })

  tags = {
    Name = "eks-nebulance-external-secrets"
  }
}

# IAM policy for External Secrets Operator to access Secrets Manager
resource "aws_iam_policy" "external_secrets" {
  name        = "eks-nebulance-external-secrets-policy"
  description = "IAM policy for External Secrets Operator"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:eks-app/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  policy_arn = aws_iam_policy.external_secrets.arn
  role       = aws_iam_role.external_secrets.name
}

# IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "eks-nebulance-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com"
          }
        }
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
      }
    ]
  })

  tags = {
    Name = "eks-nebulance-aws-load-balancer-controller"
  }
}

# Download and attach AWS Load Balancer Controller IAM policy
data "http" "aws_load_balancer_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "eks-nebulance-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.aws_load_balancer_controller_policy.response_body
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# Security group for additional EKS access
resource "aws_security_group" "additional" {
  name_prefix = "eks-nebulance-additional"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }

  tags = {
    Name = "eks-nebulance-additional"
  }
}

# Install AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\.amazonaws\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller.arn
  }

  depends_on = [
    module.eks.eks_managed_node_groups,
    aws_iam_role_policy_attachment.aws_load_balancer_controller
  ]
}