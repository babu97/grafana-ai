# -----------------------------------------------------------------------------
# HTTPS without owning a domain: CloudFront in front of the ALB.
#
#   browser ──HTTPS──► CloudFront (*.cloudfront.net cert) ──HTTP + secret header──► ALB ──► rag-app
#
# CloudFront is used as a secure front door, NOT a cache: every request goes
# to the app (CachingDisabled), POST is allowed, and answers stream through.
# -----------------------------------------------------------------------------

# AWS-managed policies, looked up by name rather than hard-coding IDs.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Forward headers, cookies and query strings — but not Host, so the ALB sees
# its own hostname rather than *.cloudfront.net.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_function" "allowlist" {
  name    = "${var.name}-allowlist"
  runtime = "cloudfront-js-2.0"
  comment = "IPv4 allowlist for the RAG demo"
  publish = true
  code = templatefile("${path.module}/allowlist.js.tftpl", {
    allowed_json = jsonencode(var.allowed_cidrs)
  })
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = "${var.name}: HTTPS front door for the RAG shop app"
  price_class     = "PriceClass_100" # Europe + North America edges only (cheapest)
  is_ipv6_enabled = false            # the allowlist function checks IPv4 only
  http_version    = "http2and3"

  origin {
    origin_id   = "alb"
    domain_name = var.origin_domain

    custom_origin_config {
      origin_protocol_policy   = "http-only" # CloudFront -> ALB stays inside AWS
      http_port                = 80
      https_port               = 443
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = var.origin_read_timeout
      origin_keepalive_timeout = 60
    }

    # The ALB rejects requests without this header — so nobody can skip
    # CloudFront (and its HTTPS + allowlist) by calling the ALB directly.
    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_header
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false # don't buffer the token stream for gzip

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.allowlist.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # The free, AWS-provided *.cloudfront.net certificate.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}
