provider "aws" {
  region  = "us-east-1"
  profile = "errinlarsen"
}

// The ORIGINAL registered Domain, hosted in Route53
resource "aws_route53_zone" "redirect_zone" {
  provider = aws
  name     = local.redirect_domain_name

  tags = {
    Name       = local.redirect_domain_name
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// My registered Domain, hosted in Route53
resource "aws_route53_zone" "site_zone" {
  provider = aws
  name     = local.site_domain_name

  tags = {
    Name       = local.site_domain_name
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// NS Records
// - When creating Route 53 zones, the NS and SOA records for the zone are
//   automatically created. Enabling the allow_overwrite argument will allow
//   managing these records in a single Terraform run without the requirement
//   for terraform import.
// - errinlarsen.com
resource "aws_route53_record" "redirect_ns_records" {
  provider        = aws
  zone_id         = aws_route53_zone.redirect_zone.zone_id
  allow_overwrite = true

  name = local.redirect_domain_name

  records = [
    aws_route53_zone.redirect_zone.name_servers[0],
    aws_route53_zone.redirect_zone.name_servers[1],
    aws_route53_zone.redirect_zone.name_servers[2],
    aws_route53_zone.redirect_zone.name_servers[3],
  ]

  ttl  = 30
  type = "NS"
}

// NS Records
// - errins.place
resource "aws_route53_record" "site_ns_records" {
  provider        = aws
  zone_id         = aws_route53_zone.site_zone.zone_id
  allow_overwrite = true

  name = local.site_domain_name

  records = [
    aws_route53_zone.site_zone.name_servers[0],
    aws_route53_zone.site_zone.name_servers[1],
    aws_route53_zone.site_zone.name_servers[2],
    aws_route53_zone.site_zone.name_servers[3],
  ]

  ttl  = 30
  type = "NS"
}

// The Certificate to secure domains; validated with a DNS CNAME record
resource "aws_acm_certificate" "cert" {
  provider          = aws
  domain_name       = local.site_domain_name
  validation_method = "DNS"
  subject_alternative_names = [
    "*.${local.site_domain_name}",
    "*.${local.redirect_domain_name}"
  ]

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name       = local.site_domain_name
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

# // The validation of that certificate, with that domain's CNAME records
# resource "aws_acm_certificate_validation" "redirect_cert_validation" {
#   provider        = aws
#   certificate_arn = aws_acm_certificate.cert.arn
#   # validation_record_fqdns = [for record in aws_route53_record.redirect_cert_cname_records : record.fqdn]
#   validation_record_fqdns = ["errinlarsen.com"]
# }

// The validation of that certificate, with that domain's CNAME records
resource "aws_acm_certificate_validation" "site_cert_validation" {
  provider        = aws
  certificate_arn = aws_acm_certificate.cert.arn
  # validation_record_fqdns = [for record in aws_route53_record.site_cert_cname_records : record.fqdn]
  # validation_record_fqdns = ["errins.place", "*.errins.place", "*.errinlarsen.com"]
  validation_record_fqdns = concat(
    [
      for record in aws_route53_record.redirect_cert_cname_records : record.fqdn
    ],
    [
      for record in aws_route53_record.site_cert_cname_records : record.fqdn
    ]
  )
}

// Creates 'A' Record for the `local.app_id` domain
// - resolving to the cloudfront distribution
resource "aws_route53_record" "redirect_alias_record" {
  provider = aws
  zone_id  = aws_route53_zone.redirect_zone.zone_id
  name     = "${local.app_id}.${local.redirect_domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.redirect_cf_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.redirect_cf_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

// Creates 'A' Record for the `local.app_id` domain
// - resolving to the cloudfront distribution
resource "aws_route53_record" "site_alias_record" {
  provider = aws
  zone_id  = aws_route53_zone.site_zone.zone_id
  name     = "${local.app_id}.${local.site_domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site_cf_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.site_cf_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

// The CNAME Records that will hold the redirect to the (Orig zone) Certificate
resource "aws_route53_record" "redirect_cert_cname_records" {
  provider = aws

  for_each = {
    for opt in aws_acm_certificate.cert.domain_validation_options : opt.domain_name => {
      name   = opt.resource_record_name
      record = opt.resource_record_value
      type   = opt.resource_record_type
    } if length(regexall(local.redirect_domain_name, opt.domain_name)) > 0
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.redirect_zone.zone_id
}

// The CNAME Records that will hold the redirect to the (place zone) Certificate
resource "aws_route53_record" "site_cert_cname_records" {
  provider = aws

  for_each = {
    for opt in aws_acm_certificate.cert.domain_validation_options : opt.domain_name => {
      name   = opt.resource_record_name
      record = opt.resource_record_value
      type   = opt.resource_record_type
    } if length(regexall(local.site_domain_name, opt.domain_name)) > 0
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.site_zone.zone_id
}

// S3 bucket to redirect:
// `local.app_id`.`local.redirect_domain_name -> `local.app_id`.`site_domain_name`
resource "aws_s3_bucket" "redirect_bucket" {
  provider      = aws
  bucket        = "${local.app_id}.${local.redirect_domain_name}"
  force_destroy = true
  acl           = "private"

  website {
    redirect_all_requests_to = "${local.app_id}.${local.site_domain_name}"
  }

  tags = {
    Name       = "${local.app_id}.${local.redirect_domain_name}"
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env"  = local.app_env
  }
}

// Public S3 bucket with the hosted/registered domain as the bucket name
// and with static site hosting enabled
resource "aws_s3_bucket" "site_bucket" {
  provider      = aws
  bucket        = "${local.app_id}.${local.site_domain_name}"
  force_destroy = true
  acl           = "private"

  website {
    index_document = "index.html"
  }

  tags = {
    Name       = "${local.app_id}.${local.site_domain_name}"
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// IAM Policy for the redirect domain's S3 bucket
// - to allow public read and CloudFront access
data "aws_iam_policy_document" "redirect_policy_doc" {
  provider = aws

  statement {
    sid       = "PublicCloudFront"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.redirect_bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

// IAM Policy for the site domain's S3 bucket
// - to allow public read and CloudFront access
data "aws_iam_policy_document" "site_policy_doc" {
  provider = aws

  statement {
    sid       = "PublicCloudFront"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site_bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

// Attach s3_policy (above) to orig domain redirect S3 bucket
resource "aws_s3_bucket_policy" "redirect_bucket_policy" {
  provider = aws
  bucket   = aws_s3_bucket.redirect_bucket.id
  policy   = data.aws_iam_policy_document.redirect_policy_doc.json
}

// Attach site_bucket_policy (above) to site domain's S3 bucket
resource "aws_s3_bucket_policy" "site_bucket_policy" {
  provider = aws
  bucket   = aws_s3_bucket.site_bucket.id
  policy   = data.aws_iam_policy_document.site_policy_doc.json
}

// Cloudfront - Distribution
resource "aws_cloudfront_distribution" "redirect_cf_distribution" {
  provider = aws

  origin {
    domain_name = aws_s3_bucket.redirect_bucket.website_endpoint
    origin_id   = local.redirect_s3_origin_id

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  # default_root_object = "index.html"
  aliases = [
    # "${local.app_id}.${local.site_domain_name}",
    "${local.app_id}.${local.redirect_domain_name}"
  ]
  price_class = "PriceClass_All"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.redirect_s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  tags = {
    Name       = "${local.app_id}.${local.redirect_domain_name}"
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// Cloudfront - Distribution
resource "aws_cloudfront_distribution" "site_cf_distribution" {
  provider = aws

  origin {
    domain_name = aws_s3_bucket.site_bucket.website_endpoint
    origin_id   = local.site_s3_origin_id

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases = [
    "${local.app_id}.${local.site_domain_name}" #,
    # "${local.app_id}.${local.redirect_domain_name}"
  ]
  price_class = "PriceClass_All"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.site_s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  tags = {
    Name       = "${local.app_id}.${local.site_domain_name}"
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// ResourceGroup to contain all-the-things
resource "aws_resourcegroups_group" "rgroup" {
  provider = aws
  name     = "${local.app_id}.${local.site_domain_name}-resource-group"

  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::CertificateManager::Certificate",
    "AWS::CloudFront::Distribution",
    "AWS::Route53::Domain",
    "AWS::Route53::HostedZone",
    "AWS::S3::Bucket"
  ],
  "TagFilters": [
    {
      "Key": "app:id",
      "Values": ["${local.app_id}"]
    }
  ]
}
JSON
  }

  tags = {
    Name       = "${local.app_id}.${local.site_domain_name}"
    "app:id"   = local.app_id
    "app:role" = local.app_role
    "app:env " = local.app_env
  }
}

// Get notified if you're spending money too fast...
resource "aws_budgets_budget" "monthly_budget" {
  provider          = aws
  name              = "${local.app_id}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "20.0"
  limit_unit        = "USD"
  time_period_start = "2020-12-31_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 55
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["errinlarsen@gmail.com"]
  }
}
