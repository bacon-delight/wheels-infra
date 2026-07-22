locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "opentofu"
    Repo        = "bacon-delight/wheels-infra"
  }
}
