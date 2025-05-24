variable "project_id" {
  description = "The ID of the project in which the resources will be created."
  type        = string
}

variable "region" {
  description = "The region in which the resources will be created."
  type        = string
}

variable "private_subnet_cidr" {
  description = "The CIDR block for the private subnet."
  type        = string
}

variable "lb_subnet_cidr" {
  description = "The CIDR block for the load balancer subnet."
  type        = string
}

variable "vpc_access_connector_cidr" {
  description = "The CIDR block for the VPC access connector."
  type        = string
}

variable "domain_name" {
  description = "The domain name for the Cloud Run service."
  type        = string
}

variable "entra_tenant_id" {
  description = "The ID of the Entra tenant."
  type        = string
}

variable "oauth2_client_id" {
  description = "The OAuth2 client ID for the Cloud Run service."
  type        = string
}

variable "oauth_allowed_email_domains" {
  description = "The allowed email domains for OAuth2 authentication, separated by commas."
  type        = string
}

variable "gcs_bucket_name" {
  description = "The name of the Google Cloud Storage bucket for static files."
  type        = string
}