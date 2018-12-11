resource "google_container_cluster" "apps-cluster" {
  name    = "apps-cluster"
  project = "${google_project.project.project_id}"
  region  = "${var.region}"

  initial_node_count = "${var.num_nodes_per_zone}"

  min_master_version = "${data.google_container_engine_versions.versions.latest_master_version}"
  node_version       = "${data.google_container_engine_versions.versions.latest_node_version}"

  logging_service    = "${var.kubernetes_logging_service}"
  monitoring_service = "${var.kubernetes_monitoring_service}"

  node_config {
    machine_type = "${var.instance_type}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels {
      service = "apps-cluster"
    }

    tags = ["apps-cluster"]
  }

  addons_config {
    # Disable the Kubernetes dashboard, which is often an attack vector. The
    # cluster can still be managed via the GKE UI.
    kubernetes_dashboard {
      disabled = true
    }

    # Enable network policy configurations (like Calico).
    network_policy_config {
      disabled = false
    }
  }

  # Disable basic authentication and cert-based authentication.
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable network policy configurations (like Calico) - for some reason this
  # has to be in here twice.
  network_policy {
    enabled = true
  }

  # Set the maintenance window.
  maintenance_policy {
    daily_maintenance_window {
      start_time = "${var.daily_maintenance_window}"
    }
  }

  depends_on = [
    "google_project_service.service",
  ]
}

resource "null_resource" "get-apps-cluster-credentials" {
  depends_on = [
    "google_container_cluster.apps-cluster",
  ]

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials '${google_container_cluster.apps-cluster.name}' --region='${google_container_cluster.apps-cluster.region}' --project='${google_container_cluster.apps-cluster.project}'"
  }
}
