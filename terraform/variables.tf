locals {
  app_id   = "barrowmaze"
  app_role = "jekyll"
  app_env  = "production"

  redirect_domain_name  = "errinlarsen.com"
  redirect_s3_origin_id = "S3-${local.app_id}.${local.redirect_domain_name}"

  site_domain_name  = "errins.place"
  site_s3_origin_id = "S3-${local.app_id}.${local.site_domain_name}"
}
