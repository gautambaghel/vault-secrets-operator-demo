output "region" {
  value       = var.region
  description = "GCloud Region"
}

output "project_id" {
  value       = var.project_id
  description = "GCloud Project ID"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "gar_repository" {
  value       = google_artifact_registry_repository.gar_repository
  description = "Google artifact registry repository"
}

output "service_account_email" {
  value = module.service-accounts_example_single_service_account.email
  description = "Service Account email with capacity to pull private images"
}