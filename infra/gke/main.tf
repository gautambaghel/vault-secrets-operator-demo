resource "google_service_account" "default" {
  account_id   = "gke-service-account-id"
  display_name = "GKE Service Account"
}

# create the GKE cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke-new"
  location = var.region
  
  node_locations = ["us-west1-a"]
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  cluster    = google_container_cluster.primary.name
  location   = var.region
  node_count = var.gke_num_nodes
  autoscaling {
      min_node_count = 1
      max_node_count = 2
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      env = var.project_id
    }
    
    # preemptible  = true
    machine_type = "n1-standard-1"
    service_account = google_service_account.default.email
    tags         = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}