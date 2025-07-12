# Project 3: EKS Cluster Deployment Challenge

## Overview
Transform traditional infrastructure into a modern Amazon EKS deployment using Terraform and Helm. Deploy a production-ready 3-tier application with AWS Secrets Manager integration, demonstrating enterprise-grade Kubernetes orchestration and Infrastructure as Code practices.

## Application Architecture

### Frontend Tier (React.js)
- **Technology**: React 18.x with modern hooks and routing
- **Features**: 
  - User authentication with JWT tokens
  - Real-time dashboard with statistics
  - User registration and login flows
  - Post creation and management
  - Responsive design with professional UI
- **Container**: Multi-stage Docker build with Nginx proxy
- **Networking**: ClusterIP service with ingress routing
- **Scaling**: Horizontal Pod Autoscaler (2-5 replicas)

### Backend Tier (Node.js/Express)
- **Technology**: Node.js with Express.js framework
- **Features**:
  - RESTful API with comprehensive endpoints
  - JWT authentication with bcrypt password hashing
  - PostgreSQL integration with connection pooling
  - Rate limiting and security middleware (Helmet, CORS)
  - Health checks and graceful shutdown
  - Comprehensive error handling
- **Endpoints**:
  - `POST /api/register` - User registration
  - `POST /api/login` - User authentication
  - `GET /api/users` - List users (protected)
  - `POST /api/posts` - Create posts (protected)
  - `GET /api/posts` - List all posts
  - `GET /api/dashboard` - Dashboard statistics
  - `GET /health` - Health check endpoint
  - `GET /version` - Application version info
- **Scaling**: Horizontal Pod Autoscaler (3-10 replicas)

### Database Tier (PostgreSQL)
- **Technology**: PostgreSQL 15 with persistent storage
- **Schema**: Users and posts tables with relationships
- **Security**: Credentials managed via AWS Secrets Manager
- **Storage**: Persistent Volume Claims with EBS volumes
- **High Availability**: Single instance with persistent storage

## Infrastructure Components

### Amazon EKS Cluster
- **Cluster Name**: eks-nebulance
- **Region**: eu-central-1 (Frankfurt)
- **Kubernetes Version**: 1.28+
- **Node Groups**: Auto-scaling t3.medium instances (2-10 nodes)
- **Networking**: IPv4 with private endpoint access
- **Add-ons**: CoreDNS, kube-proxy, VPC CNI, AWS Load Balancer Controller

### VPC and Networking
- **CIDR Block**: 10.0.0.0/16
- **Public Subnets**: 3 subnets for load balancers across AZs
- **Private Subnets**: 3 subnets for worker nodes across AZs
- **Internet Gateway**: Public subnet internet access
- **NAT Gateways**: Private subnet outbound connectivity
- **Security Groups**: Minimal required access patterns

## Prerequisites

### Required Tools
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip && sudo mv terraform /usr/local/bin/
```

### AWS Configuration
```bash
# Configure AWS CLI with your credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (eu-central-1), Output format (json)

# Verify AWS access
aws sts get-caller-identity
```

## Deployment Steps

### Step 1: Build and Push Docker Images

#### Build Application Images
```bash
# Build backend image
cd application/backend/
docker build -t your-registry/nebulance-app:backend-1.0.0 .
docker push your-registry/nebulance-app:backend-1.0.0

# Build frontend image
cd ../frontend/
docker build -t your-registry/nebulance-app:frontend-1.0.0 .
docker push your-registry/nebulance-app:frontend-1.0.0
```

### Step 2: Deploy Infrastructure with Terraform

```bash
cd ../../terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the EKS cluster (takes 15-20 minutes)
terraform apply

# Configure kubectl for the new cluster
aws eks update-kubeconfig --region eu-central-1 --name eks-nebulance
```

### Step 3: Create AWS Secrets

Generate secure secrets and store them in AWS Secrets Manager:

```bash
# Generate cryptographically secure secrets
JWT_SECRET=$(openssl rand -base64 32)
API_KEY=$(openssl rand -hex 16)
DB_PASSWORD=$(openssl rand -base64 20)

# Create database secrets
aws secretsmanager create-secret \
  --name "eks-app/database" \
  --description "Database credentials for EKS application" \
  --secret-string "{
    \"POSTGRES_USER\":\"appuser\",
    \"POSTGRES_PASSWORD\":\"$DB_PASSWORD\",
    \"POSTGRES_DB\":\"appdb\"
  }" \
  --region eu-central-1

# Create application secrets
aws secretsmanager create-secret \
  --name "eks-app/application" \
  --description "Application secrets for EKS application" \
  --secret-string "{
    \"JWT_SECRET\":\"$JWT_SECRET\",
    \"API_KEY\":\"$API_KEY\",
    \"NODE_ENV\":\"production\"
  }" \
  --region eu-central-1

# Verify secrets were created
aws secretsmanager list-secrets --region eu-central-1
```

### Step 4: Install AWS Load Balancer Controller

```bash
# Download IAM policy for AWS Load Balancer Controller
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create IAM role and service account
eksctl create iamserviceaccount \
  --cluster=eks-nebulance \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Add EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-nebulance \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Step 5: Install External Secrets Operator

```bash
# Add External Secrets Operator Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true

# Verify installation
kubectl get pods -n external-secrets-system
kubectl get crd | grep external-secrets
```

### Step 6: Update Helm Chart Configuration

Before deploying, update the Helm chart values:

```bash
cd ../helm-charts/

# Edit values.yaml to match your Docker registry
vim values.yaml
```

Update these sections in `values.yaml`:
```yaml
frontend:
  image:
    repository: your-registry/nebulance-app  # Replace with your registry
    tag: "frontend-1.0.0"

backend:
  image:
    repository: your-registry/nebulance-app  # Replace with your registry
    tag: "backend-1.0.0"

# Services configured as LoadBalancer for direct external access
frontend:
  service:
    type: LoadBalancer  # Exposes frontend on AWS Network Load Balancer

backend:
  service:
    type: LoadBalancer  # Exposes backend API on AWS Network Load Balancer
```

### Step 7: Setup CI/CD Pipeline (Optional)

Configure CircleCI pipeline for automated image building:

```bash
# Set up CircleCI environment variables in your project settings:
# - DOCKER_LOGIN: Your Docker Hub username
# - DOCKER_PASSWORD: Your Docker Hub password
```

The included `.circleci/config.yml` provides:
- Automated testing for both frontend and backend
- Docker image building and pushing
- Automatic updating of Helm values.yaml with new image tags

**Note**: CircleCI only builds and pushes images. Manual deployment via Helm is required:
```bash
# Deploy application after CircleCI builds new images
helm upgrade --install nebulance-app helm-charts/ \
  --namespace production \
  --create-namespace
```

### Step 8: Deploy Application with Helm

```bash
# Install the application stack
helm install nebulance-app helm-charts/ \
  --namespace production \
  --create-namespace \
  --timeout 10m

# Verify deployment
kubectl get pods -n production
kubectl get secrets -n production
kubectl get services -n production

# Check External Secrets sync
kubectl get externalsecrets -n production
kubectl describe externalsecret database-secret -n production
```

## Verification and Testing

### Check Application Status
```bash
# Verify all pods are running
kubectl get pods -n production

# Check services and LoadBalancer URLs
kubectl get services -n production

# Get LoadBalancer external URLs
kubectl get services -n production -o wide

# View application logs
kubectl logs -f deployment/backend -n production
kubectl logs -f deployment/frontend -n production
```

### Test Application Functionality
```bash
# Get the frontend LoadBalancer URL
FRONTEND_URL=$(kubectl get service frontend -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Frontend URL: http://$FRONTEND_URL"

# Get the backend LoadBalancer URL  
BACKEND_URL=$(kubectl get service backend -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Backend API URL: http://$BACKEND_URL:3000"

# Test health endpoint
curl http://$BACKEND_URL:3000/health

# Test version endpoint
curl http://$BACKEND_URL:3000/version

# Access frontend application
echo "Open browser to: http://$FRONTEND_URL"
```

## File Structure
```
project-3-terraform-aws/
├── README.md
├── requirements.md
├── application/
│   ├── frontend/          # React application
│   │   ├── src/
│   │   │   ├── components/
│   │   │   │   ├── Login.js
│   │   │   │   ├── Register.js
│   │   │   │   └── Dashboard.js
│   │   │   ├── App.js
│   │   │   ├── App.css
│   │   │   └── index.js
│   │   ├── public/
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── nginx.conf
│   └── backend/           # Node.js API
│       ├── server.js
│       ├── package.json
│       └── Dockerfile
├── terraform/             # Terraform infrastructure
│   ├── main.tf
│   ├── eks.tf
│   ├── vpc.tf
│   ├── variables.tf
│   └── outputs.tf
├── .circleci/             # CircleCI configuration
│   └── config.yml
└── helm-charts/           # Helm charts
    ├── Chart.yaml
    ├── values.yaml
    └── templates/         # 12 Kubernetes manifests (LoadBalancer services)
```

## Troubleshooting

### Common Issues

**EKS Cluster Creation Fails**
```bash
# Check IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name your-username

# Check VPC limits
aws ec2 describe-account-attributes --attribute-names supported-platforms
```

**Pods Fail to Start**
```bash
# Check pod status and logs
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production

# Check secrets synchronization
kubectl get externalsecrets -n production
kubectl describe externalsecret database-secret -n production
```

**External Secrets Not Syncing**
```bash
# Check External Secrets Operator logs
kubectl logs -f deployment/external-secrets -n external-secrets-system

# Verify IRSA configuration
kubectl describe serviceaccount external-secrets-sa -n production
```

**Application Not Accessible**
```bash
# Check LoadBalancer services status
kubectl get services -n production
kubectl describe service frontend -n production
kubectl describe service backend -n production

# Check if security groups allow external traffic
aws ec2 describe-security-groups --filters "Name=group-name,Values=*eks*"
```

## Success Criteria

### Infrastructure ✅
- EKS cluster operational and accessible via kubectl
- External Secrets Operator pulling secrets from AWS Secrets Manager
- Proper IAM roles and IRSA configuration
- Security groups configured for LoadBalancer access

### Application ✅
- All three tiers (frontend, backend, database) deployed and running
- External access via Network Load Balancers (frontend on port 80, backend on port 3000)
- User registration and authentication working
- Database persistence across pod restarts
- Secrets properly injected from AWS Secrets Manager