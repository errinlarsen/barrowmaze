provider "aws" {
  region  = "us-east-1"
  profile = "errinlarsen"
}

// My registered Domain, hosted in Route53
resource "aws_route53_zone" "hosted_zone" {
  provider = aws
  name     = local.root_domain_name

  tags = {
    Name       = local.root_domain_name
    "app:id"   = "barrowmaze"
    "app:role" = "jekyll"
    "app:env " = "production"
  }
}

// The Certificate to secure my domain; validated with a DNS CNAME record
resource "aws_acm_certificate" "cert" {
  provider                  = aws
  domain_name               = local.root_domain_name
  validation_method         = "DNS"
  subject_alternative_names = ["*.${local.root_domain_name}"]

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name       = local.root_domain_name
    "app:id"   = "barrowmaze"
    "app:role" = "jekyll"
    "app:env " = "production"
  }
}

// The validation of that certificate, with that domain's CNAME records
resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cname_records : record.fqdn]
}

// NS Records
// - When creating Route 53 zones, the NS and SOA records for the zone are
//   automatically created. Enabling the allow_overwrite argument will allow
//   managing these records in a single Terraform run without the requirement
//   for terraform import.
resource "aws_route53_record" "ns_records" {
  provider        = aws
  zone_id         = aws_route53_zone.hosted_zone.zone_id
  allow_overwrite = true

  name = local.root_domain_name

  records = [
    aws_route53_zone.hosted_zone.name_servers[0],
    aws_route53_zone.hosted_zone.name_servers[1],
    aws_route53_zone.hosted_zone.name_servers[2],
    aws_route53_zone.hosted_zone.name_servers[3],
  ]

  ttl  = 30
  type = "NS"
}

// Creates `A' Record for the barrowmaze domain
// - resolving to the cloudfront distribution
resource "aws_route53_record" "root_static_site_a_record" {
  provider = aws
  zone_id  = aws_route53_zone.hosted_zone.zone_id
  name     = "barrowmaze.${local.root_domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.cf_s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cf_s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

// The CNAME Records that will hold the redirect to the Certificate
resource "aws_route53_record" "cname_records" {
  provider = aws

  for_each = {
    for opt in aws_acm_certificate.cert.domain_validation_options : opt.domain_name => {
      name   = opt.resource_record_name
      record = opt.resource_record_value
      type   = opt.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.hosted_zone.zone_id
}

// Public S3 bucket with the hosted/registered domain as the bucket name
// and with static site hosting enabled
resource "aws_s3_bucket" "root_static_site" {
  provider      = aws
  bucket        = "barrowmaze.${local.root_domain_name}"
  force_destroy = true
  acl           = "private"

  website {
    index_document = "index.html"
  }

  tags = {
    Name       = "barrowmaze.${local.root_domain_name}"
    "app:id"   = "barrowmaze"
    "app:role" = "jekyll"
    "app:env " = "production"
  }
}

// IAM Policy for the ROOT domain's S3 bucket(s)
// - to allow public read and CloudFront access
data "aws_iam_policy_document" "s3_policy" {
  provider = aws

  statement {
    sid       = "PublicCloudFront"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.root_static_site.arn}/*"]

    principals {
      type = "AWS"
      # identifiers = [aws_cloudfront_origin_access_identity.cf_origin_access_identity.iam_arn]
      identifiers = ["*"]
    }
  }
}

// Attach s3_policy (above) to root domain static site S3 bucket
resource "aws_s3_bucket_policy" "root_static_site_policy" {
  provider = aws
  bucket   = aws_s3_bucket.root_static_site.id
  policy   = data.aws_iam_policy_document.s3_policy.json
}

// Cloudfront - Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "cf_origin_access_identity" {
  provider = aws
  comment  = "barrowmaze.${local.root_domain_name}"
}

// Cloudfront - Distribution
resource "aws_cloudfront_distribution" "cf_s3_distribution" {
  provider = aws

  origin {
    domain_name = aws_s3_bucket.root_static_site.website_endpoint
    origin_id   = local.s3_origin_id

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
  aliases             = ["barrowmaze.${local.root_domain_name}"]
  price_class         = "PriceClass_All"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

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
    Name       = "barrowmaze.${local.root_domain_name}"
    "app:id"   = "barrowmaze"
    "app:role" = "jekyll"
    "app:env " = "production"
  }
}

// ResourceGroup to contain all-the-things
resource "aws_resourcegroups_group" "rgroup" {
  provider = aws
  name     = "barrowmaze.${local.root_domain_name}-resource-group"

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
      "Values": ["barrowmaze"]
    }
  ]
}
JSON
  }

  tags = {
    Name       = "barrowmaze.${local.root_domain_name}"
    "app:id"   = "barrowmaze"
    "app:role" = "jekyll"
    "app:env " = "production"
  }
}

// Get notified if you're spending money too fast...
resource "aws_budgets_budget" "monthly_budget" {
  provider          = aws
  name              = "barrowmaze-monthly-budget"
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
