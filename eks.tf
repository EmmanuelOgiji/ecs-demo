# Create simple EKS Cluster
resource "null_resource" "create_eksctl_cluster" {
  provisioner "local-exec" {
    command = "bash -c eksctl create cluster"
    environment = {
      AWS_ACCESS_KEY_ID     = var.access_key
      AWS_SECRET_ACCESS_KEY = var.secret_key
      AWS_REGION            = var.region
    }
  }
}