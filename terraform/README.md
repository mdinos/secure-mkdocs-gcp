# Infrastructure for MkDocs with OAuth2 Proxy

## High level architecture

1. DNS A record point to a HTTPS load balancer (global application).
1. HTTPS Load balancer forwards traffic to an OAuth2 Proxy
1. OAuth2 Proxy authenticates users via Entra ID Application
1. OAuth2 Proxy forwards traffic to an internal load balancer (HTTP regional)
1. Internal LB forwards traffic to a simple GCS proxy service (in `../gcs-proxy`)
1. GCS proxy service serves static files from a GCS bucket, with contents from `../mkdocs`

Extra bits required:

- Bucket with files to serve
- Entra ID application
- Images for the OAuth2 Proxy and GCS proxy service in Google Artifact Registry
- secrets for auth proxy (client secret, cookie secret)

Of course you can put any static files in the GCS bucket, not just MkDocs.

## Example usage

```hcl
// Project configuration
project_id = "my-project-id"
region     = "europe-west2"

// Domain name
domain_name = "docs.my-domain-name.com"

// Subnet CIDRs
private_subnet_cidr       = "10.8.0.0/26"
lb_subnet_cidr            = "10.8.0.128/26"
vpc_access_connector_cidr = "10.8.0.192/28"

// OAuth2 Proxy configuration
entra_tenant_id  = "12345678-1234-1234-1234-123456789012"
oauth2_client_id = "12345678-1234-1234-1234-123456789012"
oauth_allowed_email_domains = "my-domain.com,another-domain.com"

# Google Cloud Storage bucket for static files
gcs_bucket_name = "my-static-files-bucket"
```