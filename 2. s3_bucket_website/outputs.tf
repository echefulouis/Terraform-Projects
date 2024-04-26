#Output the Bucket URL
output "website_bucket_domain_name" {
  description = "The bucket domain name. Will be of format bucketname.s3.amazonaws.com."
  value       = aws_s3_bucket.my_s3_bucket.bucket_domain_name
}