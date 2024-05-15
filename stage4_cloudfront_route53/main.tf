provider "aws" {
  region = "us-east-1"

}

#Block to Create S3 Bucket
resource "aws_s3_bucket" "my_s3_bucket" {
  bucket = var.bucket_name
  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

#upload files into the s3 bucket
resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  for_each     = fileset("website/", "**/*.*")
  key          = each.value
  source       = "website/${each.value}"
  content_type = each.value
}

#Bucket Settings
resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.my_s3_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "private_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.bucket_ownership]

  bucket = aws_s3_bucket.my_s3_bucket.id
  acl    = "private"
}

#Requested a TLS cert from ACM
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domainName
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
#My Hosted Zone
data "aws_route53_zone" "domain" {
  name         = var.domainName
  private_zone = false
}

#DNS Validation with Route 53
resource "aws_route53_record" "cert-cname" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain.zone_id
}


resource "aws_acm_certificate_validation" "example-validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert-cname : record.fqdn]
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "OAI for my s3 bucket"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.my_s3_bucket.bucket_regional_domain_name
    origin_id                = var.bucket_name

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [var.domainName]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.bucket_name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "Cloud Destribution"
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method = "sni-only"
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.my_s3_bucket.arn}/*"
        Principal = {
          CanonicalUser = aws_cloudfront_origin_access_identity.origin_access_identity.s3_canonical_user_id
        }
      }
    ]
  })

}

resource "aws_route53_record" "Domain-a" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = var.domainName
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}