terraform {
  backend "s3" {
    bucket         = "devendra-service-catalog-templates-ap-south-1"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    
    use_lockfile   = true   # Native locking enabled
  }
}