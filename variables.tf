variable "environment" {
  default = "dev"
}

variable "openproject_image" {
  default = "openproject/openproject:15"   # official image – change tag as needed
}

variable "vpc_provisioning_parameters" {
  description = "MUST match your my-first-product.yaml Parameters section"
  type        = map(string)
  default = {
    # REPLACE these with exact parameter names from your YAML (open the S3 file locally)
    # Example for a typical "Simple-VPC-Product":
    VpcCIDR             = "10.0.0.0/16"
    EnvironmentName     = "openproject-dev"
    PublicSubnet1CIDR   = "10.0.1.0/24"
    PublicSubnet2CIDR   = "10.0.2.0/24"
    PrivateSubnet1CIDR  = "10.0.3.0/24"
    PrivateSubnet2CIDR  = "10.0.4.0/24"
    # Add any other parameters your product requires
  }
}
