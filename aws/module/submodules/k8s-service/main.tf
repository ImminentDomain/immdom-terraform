resource "kubernetes_secret" "db" {
  count = var.create ? 1 : 0

  metadata {
    name = "${var.name}-db"

    labels = {
      app     = var.name
      managed = "terraform"
    }
  }

  data = {
    "db_host" = var.db_host
    "db_name" = var.db_name
    "db_user" = var.db_user
    "db_pass" = var.db_pass
    "db_port" = var.db_port
  }
}

resource "kubernetes_config_map" "s3" {
  count = var.create ? 1 : 0

  metadata {
    name = "${var.name}-s3"

    labels = {
      app     = var.name
      managed = "terraform"
    }
  }

  data = {
    "s3_bucket_name" = var.s3_bucket_name
    "s3_bucket_arn"  = var.s3_bucket_arn
  }
}

resource "kubernetes_service_account" "app_sa" {
  count = var.create ? 1 : 0

  metadata {
    name = var.name

    labels = {
      app     = var.name
      managed = "terraform"
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${var.account_id}:role/${var.name}-role"
    }
  }

  secret {
    name = kubernetes_secret.db[count.index].metadata.0.name
  }

  automount_service_account_token = true
}

resource "kubernetes_deployment" "app" {
  count = var.create ? 1 : 0

  metadata {
    name = var.name

    labels = {
      app     = var.name
      managed = "terraform"
    }
  }

  # Don't wait because the initial deploy will have no images pushed to the ECR repo
  wait_for_rollout = false

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app     = var.name
        managed = "terraform"
      }
    }

    template {
      metadata {
        labels = {
          app     = var.name
          managed = "terraform"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account.app_sa[count.index].metadata.0.name
        automount_service_account_token = true

        container {
          image = var.ecr_repository
          name  = var.name

          port {
            container_port = var.container_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.db[count.index].metadata.0.name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.s3[count.index].metadata.0.name
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec.0.template.0.spec.0.container.0.image
    ]
  }
}

resource "kubernetes_service" "app" {
  count = var.create ? 1 : 0

  metadata {
    name = var.name

    labels = {
      app     = var.name
      managed = "terraform"
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment.app[count.index].metadata.0.labels.app
    }

    port {
      port        = var.container_port
      target_port = var.container_port
    }

    type = "LoadBalancer"
  }
}
