# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------
terraform {
  source = "../module"
}

remote_state {
  backend = "s3"

  config = {
    # Replace "immdom-example" with your desired name.
    bucket         = "immdom-example-tfstate"
    dynamodb_table = "immdom-example-tf-locks"

    encrypt        = true
    key            = "${path_relative_to_include()}/terraform.tfstate"

    # Change region for the S3 State bucket and DynamoDB Lock table if desired.
    # This does not need to match the region you run the modules in.
    region         = "us-east-2"

    # Enable the following to save costs in AWS for the S3 state bucket.
    skip_bucket_versioning         = true
    skip_bucket_accesslogging      = true 
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module specified in the terragrunt configuration above
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # The AWS region to apply the module in.
  aws_region = "us-east-2"

  # Enter the desired environment name here.
  name = "immdom-example"

  # Enter service definitions here.
  services = {
    "flask-app" = {
      service_db = true
      s3_bucket = true
    }
  }
}
