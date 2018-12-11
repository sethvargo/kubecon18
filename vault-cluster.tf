resource "google_service_account" "vault-server" {
  account_id   = "vault-server"
  display_name = "Vault Server"
  project      = "${google_project.project.project_id}"
}

resource "google_service_account_key" "vault" {
  service_account_id = "${google_service_account.vault-server.name}"
}

resource "google_project_iam_member" "vault-service-account" {
  count   = "${length(var.service_account_iam_roles)}"
  project = "${google_project.project.project_id}"
  role    = "${element(var.service_account_iam_roles, count.index)}"
  member  = "serviceAccount:${google_service_account.vault-server.email}"
}

resource "google_storage_bucket" "vault" {
  name          = "${google_project.project.project_id}-vault-storage"
  project       = "${google_project.project.project_id}"
  force_destroy = true
  storage_class = "MULTI_REGIONAL"

  versioning {
    enabled = false
  }

  depends_on = ["google_project_service.service"]
}

resource "google_storage_bucket_iam_member" "vault-server" {
  count  = "${length(var.storage_bucket_roles)}"
  bucket = "${google_storage_bucket.vault.name}"
  role   = "${element(var.storage_bucket_roles, count.index)}"
  member = "serviceAccount:${google_service_account.vault-server.email}"
}

resource "google_kms_key_ring" "vault" {
  name     = "vault"
  location = "${var.region}"
  project  = "${google_project.project.project_id}"

  depends_on = ["google_project_service.service"]
}

resource "google_kms_crypto_key" "vault-init" {
  name            = "vault-init"
  key_ring        = "${google_kms_key_ring.vault.id}"
  rotation_period = "604800s"
}

resource "google_kms_crypto_key_iam_member" "vault-init" {
  count         = "${length(var.kms_crypto_key_roles)}"
  crypto_key_id = "${google_kms_crypto_key.vault-init.id}"
  role          = "${element(var.kms_crypto_key_roles, count.index)}"
  member        = "serviceAccount:${google_service_account.vault-server.email}"
}

resource "google_container_cluster" "vault" {
  name    = "vault"
  project = "${google_project.project.project_id}"
  region  = "${var.region}"

  initial_node_count = "${var.num_nodes_per_zone}"

  min_master_version = "${data.google_container_engine_versions.versions.latest_master_version}"
  node_version       = "${data.google_container_engine_versions.versions.latest_node_version}"

  logging_service    = "${var.kubernetes_logging_service}"
  monitoring_service = "${var.kubernetes_monitoring_service}"

  # Disable legacy ACLs. The default is false, but explicitly marking it false
  # here as well.
  enable_legacy_abac = false

  node_config {
    machine_type    = "${var.instance_type}"
    service_account = "${google_service_account.vault-server.email}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels {
      service = "vault"
    }

    tags = ["vault"]

    # Protect node metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }
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
    "google_kms_crypto_key_iam_member.vault-init",
    "google_storage_bucket_iam_member.vault-server",
    "google_project_iam_member.vault-service-account",
  ]
}

resource "null_resource" "get-vault-cluster-credentials" {
  depends_on = [
    "google_container_cluster.vault",

    # Race condition, also do this last so it's active
    "null_resource.get-apps-cluster-credentials",
  ]

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials '${google_container_cluster.vault.name}' --region='${google_container_cluster.vault.region}' --project='${google_container_cluster.vault.project}'"
  }
}

resource "google_compute_address" "vault" {
  name    = "vault-lb"
  region  = "${var.region}"
  project = "${google_project.project.project_id}"

  depends_on = ["google_project_service.service"]
}

data "template_file" "vault-yaml" {
  template = "${file("${path.module}/templates/vault.yaml")}"

  vars {
    load_balancer_ip     = "${google_compute_address.vault.address}"
    num_vault_pods       = "${var.num_vault_pods}"
    vault_container      = "${var.vault_container}"
    vault_init_container = "${var.vault_init_container}"

    project = "${google_kms_key_ring.vault.project}"

    kms_region     = "${google_kms_key_ring.vault.location}"
    kms_key_ring   = "${google_kms_key_ring.vault.name}"
    kms_crypto_key = "${google_kms_crypto_key.vault-init.name}"

    gcs_bucket_name = "${google_storage_bucket.vault.name}"
  }
}

resource "filesystem_file_writer" "vault-yaml" {
  path     = "${path.module}/vault.yaml"
  contents = "${data.template_file.vault-yaml.rendered}"
}

resource "filesystem_file_writer" "vault-env" {
  path = "${path.module}/vault.env"

  contents = <<EOF
export VAULT_ADDR="https://${google_compute_address.vault.address}"
export VAULT_CAPATH="${pathexpand("${path.module}/tls/ca.crt")}"

# Not specific for Vault, but specific for this demo
export GOOGLE_CLOUD_PROJECT="${google_project.project.project_id}"
export GOOGLE_CLOUD_REGION="${var.region}"
EOF
}

output "address" {
  value = "${google_compute_address.vault.address}"
}

output "project" {
  value = "${google_project.project.project_id}"
}

output "region" {
  value = "${var.region}"
}
