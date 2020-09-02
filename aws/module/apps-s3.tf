################################################################################
# Service S3 Bucket
################################################################################
module "s3" {
  for_each = local.services

  # The AWS managed S3 module.
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "1.12.0"

  # Conditionally create it if the service definition requires it.
  create_bucket = each.value.s3_bucket

  # Adding the env name to the service name here because S3 bucket name uniqueness requirements.
  bucket = format("%s-%s", each.key, var.name)

  # We can make this configurable to public if wanted.
  acl           = "private"
  force_destroy = each.value.s3_force_destroy
}
