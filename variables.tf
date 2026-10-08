variable "environment" {
  type        = string
  description = "The deployment environment tier (dev, qa, prod)"
}

variable "notification_email" {
  type        = string
  description = "The target email address for patch failure alerts"
}

variable "max_concurrency" {
  type        = string
  description = "The maximum number or percentage of targets allowed to run the task in parallel"
}

variable "max_errors" {
  type        = string
  description = "The maximum number or percentage of errors allowed before halting execution"
}

variable "patch_burn_in_days" {
  type        = number
  description = "Number of days to wait before auto-approving a released patch"
}
