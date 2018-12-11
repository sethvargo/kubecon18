resource "tls_private_key" "vault-ca" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_self_signed_cert" "vault-ca" {
  key_algorithm   = "${tls_private_key.vault-ca.algorithm}"
  private_key_pem = "${tls_private_key.vault-ca.private_key_pem}"

  subject {
    common_name  = "vault-ca.local"
    organization = "HashiCorp Vault"
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "filesystem_file_writer" "ca-crt" {
  path     = "${path.module}/tls/ca.crt"
  contents = "${tls_self_signed_cert.vault-ca.cert_pem}"
  mode     = "0600"
}

resource "tls_private_key" "vault" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "filesystem_file_writer" "vault-key" {
  path     = "${path.module}/tls/vault.key"
  contents = "${tls_private_key.vault.private_key_pem}"
  mode     = "0600"
}

resource "tls_cert_request" "vault" {
  key_algorithm   = "${tls_private_key.vault.algorithm}"
  private_key_pem = "${tls_private_key.vault.private_key_pem}"

  dns_names = [
    "vault",
    "vault.local",
    "vault.default.svc.cluster.local",
    "localhost",
  ]

  ip_addresses = [
    "127.0.0.1",
    "${google_compute_address.vault.address}",
  ]

  subject {
    common_name  = "vault.local"
    organization = "HashiCorp Vault"
  }
}

resource "tls_locally_signed_cert" "vault" {
  cert_request_pem = "${tls_cert_request.vault.cert_request_pem}"

  ca_key_algorithm   = "${tls_private_key.vault-ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.vault-ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.vault-ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "cert_signing",
    "client_auth",
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "filesystem_file_writer" "vault-crt" {
  path     = "${path.module}/tls/vault.crt"
  contents = "${tls_locally_signed_cert.vault.cert_pem}${tls_self_signed_cert.vault-ca.cert_pem}"
  mode     = "0600"
}
