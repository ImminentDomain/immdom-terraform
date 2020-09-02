output "ecr_repos" {
  value = {
    for service_name in keys(local.services) :
    service_name => aws_ecr_repository.app[service_name].repository_url
  }
}

output "eks_cluster_name" {
  value = module.eks.cluster_id
}
