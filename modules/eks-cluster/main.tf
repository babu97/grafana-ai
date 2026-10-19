module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Whoever runs `terraform apply` becomes cluster admin (via an EKS access
  # entry, not the old aws-auth ConfigMap).
  enable_cluster_creator_admin_permissions = true

  # Skip the customer-managed KMS key: every destroy/rebuild would leave one
  # "pending deletion". EKS still envelope-encrypts Secrets with an AWS-owned key.
  create_kms_key    = false
  encryption_config = null

  # Managed add-ons. vpc-cni and the pod identity agent must exist BEFORE nodes
  # join, otherwise nodes come up NotReady (no pod networking).
  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }

  eks_managed_node_groups = {
    # ------------------------------------------------------------------------
    # System nodes: no taint, so everything that doesn't ask for a GPU lands here.
    # ------------------------------------------------------------------------
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.system_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_count
      max_size     = var.system_node_count + 1
      desired_size = var.system_node_count

      labels = { workload = "system" }

      # The default 20 GB fills up fast: the vllm-router image alone is ~5.5 GB
      # compressed, plus Prometheus, Grafana and k6 images. Kubelet starts
      # evicting pods at ~10% free, which is how we found this.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.system_disk_size_gb
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }

    # ------------------------------------------------------------------------
    # GPU node: AL2023 NVIDIA AMI ships the NVIDIA driver + container toolkit.
    # It does NOT advertise `nvidia.com/gpu` to Kubernetes on its own — the
    # NVIDIA device plugin (layer 3) does that.
    # ------------------------------------------------------------------------
    gpu = {
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = var.gpu_instance_types
      capacity_type  = var.gpu_capacity_type

      min_size     = 0
      max_size     = 2
      desired_size = var.gpu_node_count

      labels = {
        workload = "gpu"
        # The NVIDIA device plugin Helm chart only schedules onto nodes with
        # this label (normally set by Node Feature Discovery — we set it directly).
        "nvidia.com/gpu.present" = "true"
      }

      # Keep non-GPU pods off the expensive node. Pods that need the GPU
      # (vLLM, DCGM exporter, device plugin) carry a matching toleration.
      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.gpu_disk_size_gb
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      # Lets you open a shell on the node (`aws ssm start-session`) to run nvidia-smi.
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  tags = var.tags
}
