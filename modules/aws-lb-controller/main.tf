# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
#
# Watches Kubernetes Ingress objects (and LoadBalancer Services) and creates
# real AWS load balancers for them. Without it, an Ingress does nothing.
#
# It calls the AWS API (create ALB, target groups, security groups...), so it
# needs an IAM role. EKS Pod Identity hands that role to the controller's
# ServiceAccount — no access keys anywhere:
#
#   IAM role (policy: manage ELBs)  <-- pod identity association -->
#   ServiceAccount kube-system/aws-load-balancer-controller  <-- controller pod
# -----------------------------------------------------------------------------
locals {
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
}

module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name = "${var.cluster_name}-aws-lb-controller"

  # The module ships AWS's official controller IAM policy.
  attach_aws_lb_controller_policy = true

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      namespace       = local.namespace
      service_account = local.service_account
    }
  }

  tags = var.tags
}

resource "helm_release" "controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = local.namespace

  values = [yamlencode({
    clusterName = var.cluster_name
    region      = var.region
    vpcId       = var.vpc_id

    serviceAccount = {
      create = true
      name   = local.service_account
    }

    # Run on the CPU nodes; 1 replica is plenty for a demo.
    replicaCount = 1
    nodeSelector = { workload = "system" }

    # Tag every ALB/target group/SG it creates, so the budget sees them.
    defaultTags = var.tags

    # Don't silently turn future LoadBalancer Services into NLBs — we only
    # want load balancers we explicitly ask for via Ingress.
    enableServiceMutatorWebhook = false
  })]

  # The role must be associated before the pod starts, or it comes up
  # without AWS credentials.
  depends_on = [module.pod_identity]
}
