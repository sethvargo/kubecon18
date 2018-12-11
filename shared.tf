provider "google" {
  region  = "${var.region}"
  project = "${var.project}"
}

resource "random_id" "random" {
  prefix      = "${var.project_prefix}"
  byte_length = "8"
}

resource "google_project" "project" {
  name            = "${random_id.random.hex}"
  project_id      = "${random_id.random.hex}"
  org_id          = "${var.org_id}"
  billing_account = "${var.billing_account}"
}

resource "google_project_service" "service" {
  count   = "${length(var.project_services)}"
  project = "${google_project.project.project_id}"
  service = "${element(var.project_services, count.index)}"

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

data "google_container_engine_versions" "versions" {
  project = "${google_project.project.project_id}"
  region  = "${var.region}"
}
