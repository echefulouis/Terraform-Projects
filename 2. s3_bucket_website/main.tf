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

#Section for configuring bucket as a static website
resource "aws_s3_bucket_website_configuration" "example" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }

}

#Code to make the Bucket Publicly accessible
resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.my_s3_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "example" {
  depends_on = [
    aws_s3_bucket_ownership_controls.example,
    aws_s3_bucket_public_access_block.example,
  ]

  bucket = aws_s3_bucket.my_s3_bucket.id
  acl    = "public-read"
}

resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  for_each     = fileset("website/", "**/*.*")
  key          = each.value
  source       = "website/${each.value}"
  content_type = each.value
}

resource "aws_s3_bucket_policy" "host_bucket_policy" {
  bucket =  aws_s3_bucket.my_s3_bucket.id 

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "s3:GetObject",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.my_s3_bucket.bucket}/*"
      }
    ]
  })
}

#Output the Bucket URL
output "website_url" {
  value = "${aws_s3_bucket.my_s3_bucket.bucket}.${aws_s3_bucket.my_s3_bucket.website_domain}"
}

