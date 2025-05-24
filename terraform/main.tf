// vpc
resource "google_compute_network" "vpc_network" {
  name         = "vpc-network-docs-site"
  project      = var.project_id
  routing_mode = "REGIONAL"
  auto_create_subnetworks = false
}

// subnet - private
resource "google_compute_subnetwork" "subnet" {
  name                     = "subnet-internal-docs-site"
  network                  = google_compute_network.vpc_network.id
  project                  = var.project_id
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  private_ip_google_access = true

  // production - add log config block
}

// subnet - load balancing reserved
resource "google_compute_subnetwork" "lb_subnet" {
  name          = "lb-subnet-docs-site"
  network       = google_compute_network.vpc_network.id
  project       = var.project_id
  ip_cidr_range = var.lb_subnet_cidr
  region        = var.region
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

// VPC access connector
resource "google_vpc_access_connector" "connector" {
  name          = "conn-int-docs-site"
  region        = var.region
  project       = var.project_id
  ip_cidr_range = var.vpc_access_connector_cidr
  network       = google_compute_network.vpc_network.id
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3
}

// firewall
resource "google_compute_firewall" "allow_internal_cloudrun" {
  name      = "allow-internal-lb-cloudrun"
  network   = google_compute_network.vpc_network.id
  project   = var.project_id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = [var.private_subnet_cidr]
}

// Service accounts for Cloud Run services
resource "google_service_account" "oauth2_proxy_sa" {
  account_id   = "sa-cloudrun-oauth2-proxy"
  display_name = "oauth2-proxy-service-account"
  project      = var.project_id
}

// grant secret accessor role to sa

data "google_secret_manager_secret" "oauth2_proxy_client_secret" {
  secret_id = "oauth2-proxy-client-secret"
  project   = var.project_id
}

data "google_secret_manager_secret" "oauth2_proxy_cookie_secret" {
  secret_id = "oauth2-proxy-cookie-secret"
  project   = var.project_id
}

resource "google_secret_manager_secret_iam_member" "oauth2_proxy_client_secret_access" {
  secret_id = data.google_secret_manager_secret.oauth2_proxy_client_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.oauth2_proxy_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "oauth2_proxy_cookie_secret_access" {
  secret_id = data.google_secret_manager_secret.oauth2_proxy_cookie_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.oauth2_proxy_sa.email}"
}

// Cloud Run Service (oauth2)
resource "google_cloud_run_service" "oauth2_proxy" {
  name     = "oauth2-proxy-docs-site"
  project  = var.project_id
  location = var.region

  metadata {
    annotations = {
      "run.googleapis.com/ingress"              = "internal-and-cloud-load-balancing"
      "run.googleapis.com/invoker-iam-disabled" = "true"
      "run.googleapis.com/default-url-disabled" = "true"

    }
  }

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"        = "0"
        "autoscaling.knative.dev/maxScale"        = "2"
        "run.googleapis.com/startup-cpu-boost"    = "true"
      }
    }
    spec {
      service_account_name = google_service_account.oauth2_proxy_sa.email
      containers {
        // Must be created before terraform apply
        image = "${var.region}-docker.pkg.dev/${var.project_id}/test-containers/oauth2-proxy:latest"

        ports {
          container_port = 8080
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        startup_probe {
          initial_delay_seconds = 5
          period_seconds        = 10
          timeout_seconds       = 5
          http_get {
            path = "/ready"
            port = "8080"
          }
        }

        liveness_probe {
          initial_delay_seconds = 30
          period_seconds        = 600
          timeout_seconds       = 5
          http_get {
            path = "/ping"
            port = "8080"
          }
        }

        env {
          name  = "OAUTH2_PROXY_PROVIDER"
          value = "oidc"
        }
        env {
          name  = "OAUTH2_PROXY_OIDC_ISSUER_URL"
          value = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"
        }
        env {
          name  = "OAUTH2_PROXY_EMAIL_DOMAINS"
          value = var.oauth_allowed_email_domains
        }
        env {
          name  = "OAUTH2_PROXY_CLIENT_ID"
          value = var.oauth2_client_id
        }
        env {
          name = "OAUTH2_PROXY_CLIENT_SECRET"
          value_from {
            secret_key_ref {
              // Must be created before terraform apply
              name = "oauth2-proxy-client-secret"
              key  = "latest"
            }
          }
        }
        env {
          name = "OAUTH2_PROXY_COOKIE_SECRET"
          value_from {
            secret_key_ref {
              // Must be created before terraform apply
              name = "oauth2-proxy-cookie-secret"
              key  = "latest"
            }
          }
        }
        env {
          name  = "OAUTH2_PROXY_COOKIE_DOMAIN"
          value = var.domain_name
        }
        env {
          name  = "OAUTH2_PROXY_COOKIE_SAMESITE"
          value = "strict"
        }
        env {
          name  = "OAUTH2_PROXY_UPSTREAMS"
          value = "http://10.8.0.3:8080"
        }
        env {
          name  = "OAUTH2_PROXY_HTTP_ADDRESS"
          value = "0.0.0.0:8080"
        }
        env {
          name  = "OAUTH2_PROXY_REDIRECT_URL"
          value = "https://${var.domain_name}/oauth2/callback"
        }
        env {
          name  = "OAUTH2_PROXY_FOOTER"
          value = "-"
        }
        env {
          name  = "OAUTH2_PROXY_TLS_MIN_VERSION"
          value = "TLS1.3"
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// Regional Serverless NEG for OAuth2 Proxy
resource "google_compute_region_network_endpoint_group" "oauth2_proxy_neg" {
  name                  = "oauth2-proxy-neg-docs-site"
  project               = var.project_id
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.oauth2_proxy.name
  }
}

// Backend Group for Oauth2 proxy
resource "google_compute_backend_service" "oauth2_proxy_backend" {
  name                  = "oauth2-proxy-backend-docs-site"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.oauth2_proxy_security_policy.id
  protocol = "HTTPS"
  connection_draining_timeout_sec = 0
  backend {
    group = google_compute_region_network_endpoint_group.oauth2_proxy_neg.id
  }

  log_config {
    enable = true
  }
}

// Cloud run service (gcs-proxy)

// SSL certificate
resource "google_compute_managed_ssl_certificate" "this" {
  name    = "gcp-usr-docs-tst"
  project = var.project_id

  lifecycle {
    prevent_destroy = true
    create_before_destroy = true
  }

  managed {
    domains = [var.domain_name]
  }
}

// load balancer (external https)
resource "google_compute_global_address" "lb_ip" {
  name         = "ext-lb-ip-${var.project_id}"
  project      = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_url_map" "gcp-usr-docs-ext-https-proxy" {
  name = "gcp-usr-docs-ext"
  project = var.project_id
  default_service = google_compute_backend_service.oauth2_proxy_backend.id
}

resource "google_compute_ssl_policy" "tls12_min" {
  name            = "require-tls12"
  project         = var.project_id
  min_tls_version = "TLS_1_2"
  profile         = "MODERN"
}

resource "google_compute_target_https_proxy" "lb_ext" {
  project = var.project_id
  name    = "gcp-usr-docs-ext-https-proxy-target"
  url_map = google_compute_url_map.gcp-usr-docs-ext-https-proxy.self_link

  ssl_certificates = [
    google_compute_managed_ssl_certificate.this.self_link
  ]

  ssl_policy           = google_compute_ssl_policy.tls12_min.id
}

resource "google_compute_global_forwarding_rule" "lb_rule" {
  name                  = "ext-lb-rule"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  ip_address            = google_compute_global_address.lb_ip.address
  network_tier          = "PREMIUM"
  target                = google_compute_target_https_proxy.lb_ext.self_link
}

// GCS PROXY SERVICE //

resource "google_service_account" "gcs_proxy_sa" {
  account_id   = "sa-cloudrun-gcs-proxy"
  display_name = "gcs-proxy-service-account"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "gcs_proxy_bucket_access" {
  bucket = var.gcs_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gcs_proxy_sa.email}"
}

resource "google_cloud_run_service" "gcs_proxy" {
  name = "gcs-proxy-docs-site"
  project = var.project_id
  location = var.region
  metadata {
    annotations = {
      "run.googleapis.com/ingress"              = "internal"
      "run.googleapis.com/default-url-disabled" = "true"
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"        = "0"
        "autoscaling.knative.dev/maxScale"        = "2"
        "run.googleapis.com/startup-cpu-boost"    = "true"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.id
      }
    }
    spec {
      service_account_name = google_service_account.gcs_proxy_sa.email

      containers {
        // Must be created before terraform apply
        image = "${var.region}-docker.pkg.dev/${var.project_id}/test-containers/gcs-proxy:latest"

        ports {
          container_port = 8080
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        startup_probe {
          initial_delay_seconds = 5
          period_seconds        = 10
          timeout_seconds       = 5
          http_get {
            path = "/healthcheck"
            port = "8080"
          }
        }

        liveness_probe {
          initial_delay_seconds = 30
          period_seconds        = 600
          timeout_seconds       = 5
          http_get {
            path = "/healthcheck"
            port = "8080"
          }
        }

        env {
          name = "BUCKET_NAME"
          value = var.gcs_bucket_name
        }

        env {
          name = "LOG_LEVEL"
          value = "debug"
        }
      }
    }
  }
}

// Regional Serverless NEG for GCS Proxy
resource "google_compute_region_network_endpoint_group" "gcs_proxy_neg_internal" {
  name                  = "gcs-proxy-neg-docs-site"
  project               = var.project_id
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.gcs_proxy.name
  }
}

// Regional Backend Service for GCS Proxy
resource "google_compute_region_backend_service" "gcs_proxy_backend_regional" {
  name                  = "gcs-proxy-backend-docs-site"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "HTTPS"
  connection_draining_timeout_sec = 0
  backend {
    group = google_compute_region_network_endpoint_group.gcs_proxy_neg_internal.id
  }
  log_config {
    enable = true
  }
}

// Internal Load Balancer for GCS Proxy
resource "google_compute_region_url_map" "gcs_proxy_url_map" {
  name    = "gcs-proxy-url-map-docs-site"
  project = var.project_id
  region  = var.region
  default_service = google_compute_region_backend_service.gcs_proxy_backend_regional.id
}

// Forwarding rule for GCS Proxy
resource "google_compute_region_target_http_proxy" "gcs_proxy_http_lb" {
  name    = "gcs-proxy-forwarding-rule-docs-site"
  project = var.project_id
  region  = var.region
  url_map = google_compute_region_url_map.gcs_proxy_url_map.id
}

resource "google_compute_forwarding_rule" "gcs_proxy_forwarding_rule" {
  name                  = "gcs-proxy-forwarding-rule-docs-site"
  project               = var.project_id
  region                = var.region
  subnetwork           = google_compute_subnetwork.subnet.id
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "8080"
  target                = google_compute_region_target_http_proxy.gcs_proxy_http_lb.id
  network_tier          = "PREMIUM"
  ip_address            = "10.8.0.3"
}