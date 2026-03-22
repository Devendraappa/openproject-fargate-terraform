variable "environment" {
  default = "dev"
}

variable "openproject_image" {
  default = "openproject/openproject:15"   # official image – change tag as needed
}

# variable "vpc_provisioning_parameters" {
#   description = "MUST match your my-first-product.yaml Parameters section"
#   type        = map(string)
#   default = {
#     # REPLACE these with exact parameter names from your YAML (open the S3 file locally)
#     # Example for a typical "Simple-VPC-Product":
#     VpcCIDR             = "10.0.0.0/16"
#     EnvironmentName     = "openproject-dev"
#     PublicSubnet1CIDR   = "10.0.1.0/24"
#     PublicSubnet2CIDR   = "10.0.2.0/24"
#     PrivateSubnet1CIDR  = "10.0.3.0/24"
#     PrivateSubnet2CIDR  = "10.0.4.0/24"
#     # Add any other parameters your product requires
#   }
# }
# variable "vpc_provisioning_parameters" {
#   description = "Parameters that exactly match the template Parameters section"
#   type        = map(string)
#   default = {
#     EnvironmentName = "dev"              # or "openproject-dev", etc.
#     VpcCidrBlock    = "10.88.0.0/16"     # change if you want a different range
#     # Do NOT add any subnet CIDR parameters – they are not in the template
#   }
# }

variable "vpc_id" {
  description = "Optional override for VPC ID if Service Catalog does not provide one"
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Optional list of public subnet IDs to use if Service Catalog does not provide them"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "Optional list of private subnet IDs to use if Service Catalog does not provide them"
  type        = list(string)
  default     = []
}


variable "vpc_provisioning_parameters" {
  description = "Parameters for the new full-networking template"
  type        = map(string)
  default = {
    EnvironmentName     = "openproject"
    VpcCidrBlock        = "10.88.0.0/16"
    PublicSubnet1CIDR   = "10.88.1.0/24"
    PublicSubnet2CIDR   = "10.88.2.0/24"
    PrivateSubnet1CIDR  = "10.88.11.0/24"
    PrivateSubnet2CIDR  = "10.88.12.0/24"
  }
}