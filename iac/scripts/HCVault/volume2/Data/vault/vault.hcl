api_addr                = "https://0.0.0.0:8200"
cluster_addr            = "https://0.0.0.0:8201"
cluster_name            = "learn-vault-cluster"
disable_mlock           = true
ui                      = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/config_file/vault-cert.pem"
  tls_key_file  = "/config_file/vault-key.pem"
}

storage "file" {
  path = "/data"
}
