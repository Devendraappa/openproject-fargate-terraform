# 1. Provision VPC + networking via your existing Service Catalog product
resource "aws_servicecatalog_provisioned_product" "vpc" {
  name                       = "openproject-vpc-${var.environment}"
  product_id                 = "prod-wpdpc4t3kfp5o"
  provisioning_artifact_id   = "pa-wydhtz4vrujz4"   # from your product details
  launch_role_arn            = "arn:aws:iam::478389845602:role/ServiceCatalog-VPC-Launch-Role" # optional but recommended if constraint exists

  dynamic "provisioning_parameters" {
    for_each = var.vpc_provisioning_parameters
    content {
      key   = provisioning_parameters.key
      value = provisioning_parameters.value
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Wait up to 30 min for VPC to be ready
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Extract outputs from the provisioned product (adjust keys to match your CFN template Outputs)
locals {
  vpc_outputs = { for o in aws_servicecatalog_provisioned_product.vpc.outputs : o.output_key => o.output_value }

  vpc_id             = local.vpc_outputs["VPCID"]                # common key name
  public_subnet_ids  = split(",", local.vpc_outputs["PublicSubnets"]  != null ? local.vpc_outputs["PublicSubnets"]  : "")
  private_subnet_ids = split(",", local.vpc_outputs["PrivateSubnets"] != null ? local.vpc_outputs["PrivateSubnets"] : "")
}

# 2. Security Groups
resource "aws_security_group" "alb" {
  name        = "openproject-alb-sg"
  vpc_id      = local.vpc_id
  description = "ALB security group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "openproject-ecs-sg"
  vpc_id      = local.vpc_id
  description = "ECS Fargate tasks"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "openproject-rds-sg"
  vpc_id      = local.vpc_id
  description = "RDS PostgreSQL"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

# 3. DB Subnet Group (using private subnets from Service Catalog)
resource "aws_db_subnet_group" "main" {
  name       = "openproject-db-subnet-group"
  subnet_ids = local.private_subnet_ids
}

# 4. Secrets Manager (DB + OpenProject secrets)
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "secret_key_base" {
  length  = 64
  special = true
}

resource "aws_secretsmanager_secret" "openproject" {
  name                    = "openproject-secrets-${var.environment}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "openproject" {
  secret_id = aws_secretsmanager_secret.openproject.id
  secret_string = jsonencode({
    database_password = random_password.db.result
    secret_key_base   = random_password.secret_key_base.result
  })
}

# 5. RDS PostgreSQL (in private subnets from Service Catalog)
resource "aws_db_instance" "openproject" {
  identifier             = "openproject-db-${var.environment}"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "openproject"
  username               = "openproject"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = false
  publicly_accessible    = false

  tags = { Environment = var.environment }
}

# 6. IAM Roles for ECS
resource "aws_iam_role" "ecs_task_execution" {
  name = "openproject-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra policy to read Secrets Manager
resource "aws_iam_role_policy" "secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["secretsmanager:GetSecretValue"]
      Effect   = "Allow"
      Resource = aws_secretsmanager_secret.openproject.arn
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "openproject-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# 7. ECS Cluster + Task Definition + Service (Fargate)
resource "aws_ecs_cluster" "main" {
  name = "openproject-cluster"
}

resource "aws_ecs_task_definition" "openproject" {
  family                   = "openproject"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "openproject"
    image     = var.openproject_image
    essential = true
    portMappings = [{ containerPort = 80, hostPort = 80, protocol = "tcp" }]

    environment = [
      { name = "OPENPROJECT_DATABASE__HOST",     value = aws_db_instance.openproject.address },
      { name = "OPENPROJECT_DATABASE__PORT",     value = "5432" },
      { name = "OPENPROJECT_DATABASE__USER",     value = aws_db_instance.openproject.username },
      { name = "OPENPROJECT_DATABASE__NAME",     value = aws_db_instance.openproject.db_name },
      { name = "OPENPROJECT_DATABASE__ENCODING", value = "utf8" },
      { name = "SECRET_KEY_BASE",                value = "PLACEHOLDER" }   # will be overridden by secret
    ]

    secrets = [
      {
        name      = "OPENPROJECT_DATABASE__PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.openproject.arn}:database_password::"
      },
      {
        name      = "SECRET_KEY_BASE"
        valueFrom = "${aws_secretsmanager_secret.openproject.arn}:secret_key_base::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/openproject"
        awslogs-region        = "ap-south-1"
        awslogs-create-group  = "true"
        awslogs-stream-prefix = "openproject"
      }
    }
  }])
}

resource "aws_ecs_service" "openproject" {
  name            = "openproject-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.openproject.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.openproject.arn
    container_name   = "openproject"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]
}

# 8. ALB + Target Group
resource "aws_lb" "openproject" {
  name               = "openproject-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids
}

resource "aws_lb_target_group" "openproject" {
  name        = "openproject-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    interval            = 300
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.openproject.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openproject.arn
  }
}

# 9. Auto Scaling (CPU + Memory) – exactly as you wanted
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.openproject.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 60.0
  }
}
