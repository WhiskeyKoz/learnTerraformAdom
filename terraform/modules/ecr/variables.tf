variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "repository_name" {
  description = "Repository name suffix; full name is <name_prefix>-<repository_name>."
  type        = string
  default     = "app"
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents overwriting an existing tag (recommended)."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "force_delete" {
  description = "Allow `terraform destroy` to delete the repository even if it still contains images."
  type        = bool
  default     = false
}

variable "max_image_count" {
  description = "Lifecycle policy: number of most recent images to keep."
  type        = number
  default     = 10
}
