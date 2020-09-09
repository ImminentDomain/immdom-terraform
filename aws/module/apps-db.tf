################################################################################
# MySQL Aurora Databases
################################################################################
resource "random_password" "password" {
  for_each = local.services
  length   = 16
  special  = false
}

module "rds_sg" {
  for_each = local.services
  source   = "terraform-aws-modules/security-group/aws"
  version  = "3.16.0"

  name   = "${each.key}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  ingress_rules       = ["mysql-tcp"]
}

module "db" {
  for_each = local.services
  source   = "terraform-aws-modules/rds/aws"
  version  = "~> 2.0"

  identifier                          = replace(each.key, "-", "")
  engine                              = "mysql"
  engine_version                      = "5.7.19"
  instance_class                      = each.value.db_instance_type
  allocated_storage                   = each.value.db_disk_size
  create_db_instance                  = each.value.service_db
  name                                = replace(each.key, "-", "")
  tags                                = local.tags
  username                            = "admin"
  password                            = random_password.password[each.key].result
  port                                = "3306"
  iam_database_authentication_enabled = true
  vpc_security_group_ids              = [module.rds_sg[each.key].this_security_group_id]
  subnet_ids                          = var.private_networking ? module.vpc.private_subnets : module.vpc.public_subnets
  family                              = "mysql5.7"
  major_engine_version                = "5.7"
  maintenance_window                  = "Mon:00:00-Mon:03:00"
  backup_window                       = "03:00-06:00"
}
