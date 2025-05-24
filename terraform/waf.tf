resource "google_compute_security_policy" "oauth2_proxy_security_policy" {
  name = "oauth2-proxy-security-policy"
  project = var.project_id
  description = "Security policy for OAuth2 Proxy"

  // session fixation protection
  rule {
    priority    = 1006
    description = "session fixation attacks"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sessionfixation-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  // protocol attack mitigation
  rule {
    priority    = 1005
    description = "Block protocol attacks"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'sensitivity': 3})"
      }
    }
  }

  // scanners
  rule {
    priority    = 1004
    description = "Scanner detection"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  // remote code execution
  rule {
    priority    = 1003
    description = "Block remote code execution attempts"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 3})"
      }
    }
  }

  // local file intrusion detection
  rule {
    priority    = 1002
    description = "Block local file inclusion attempts"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  // remote file intrusion detection
  rule {
    priority    = 1001
    description = "Block remote file inclusion attempts"
    action      = "deny(502)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    priority    = 1000
    description = "Non-UK traffic"
    action      = "deny(502)"

    match {
      expr {
        expression = "origin.region_code != 'GB'"
      }
    }
  }

  // Rate limiting
  rule {
    priority    = 2000
    description = "Rate limit requests"
    action      = "throttle"
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(403)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  rule {
    priority    = 2147483647
    description = "default-allow-all"
    action      = "allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
