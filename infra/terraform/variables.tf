variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "aws-modernized-demo"
}

variable "vpc_cidr" {
  description = "CIDR range for the demo VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "order_service_image" {
  description = "Container image URI for order-service"
  type        = string
}

variable "inventory_service_image" {
  description = "Container image URI for inventory-service"
  type        = string
}

variable "notification_service_image" {
  description = "Container image URI for notification-service"
  type        = string
}

variable "db_name" {
  description = "Database name used by order-service"
  type        = string
  default     = "orderdb"
}

variable "db_username" {
  description = "Database username stored in SSM Parameter Store"
  type        = string
  default     = "orderapp"
}

variable "order_created_topic" {
  description = "Kafka topic used for order-created events"
  type        = string
  default     = "orders.created"
}

variable "msk_bootstrap_brokers" {
  description = "Optional explicit MSK bootstrap brokers string. Leave empty to update after cluster creation."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common AWS tags"
  type        = map(string)
  default = {
    project = "aws-modernized-demo"
  }
}
