output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_registry" {
  description = "Registry host plus prefix, used as the image registry for the portal and golden services."
  value       = "${split("/", module.ecr.repository_urls["portal"])[0]}/${var.cluster_name}"
}
