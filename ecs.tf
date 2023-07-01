// ECR repo
resource "aws_ecr_repository" "repo" {
  name                 = "${var.name}-repo"
  image_tag_mutability = "MUTABLE"
}


resource "aws_kms_key" "key" {
  description             = "${var.name}-kms"
  deletion_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "logs" {
  name = "${var.name}-log-group"
}



// ECS Cluster with Logs
resource "aws_ecs_cluster" "cluster" {
  name = "${var.name}-ecs-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.key.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.logs.name
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name = aws_ecs_cluster.cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 0
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

data "aws_iam_policy_document" "agent_assume_role_policy_definition" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "task_execution_role_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}



resource "aws_iam_role" "task_role" {
  name               = "${var.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role_policy_definition.json
}

resource "aws_iam_role" "execution_role" {
  name               = "${var.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role_policy_definition.json
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_role" {
  policy = data.aws_iam_policy_document.task_execution_role_policy.json
  role   = aws_iam_role.execution_role.id
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${var.name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  task_role_arn            = aws_iam_role.task_role.arn
  execution_role_arn       = aws_iam_role.execution_role.arn
  container_definitions = jsonencode([
    {
      name   = "flask-app"
      image  = "${aws_ecr_repository.repo.repository_url}:latest"
      cpu    = 2
      memory = 512
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          awslogs-create-group : "true",
          awslogs-group : "awslogs-${var.name}"
          awslogs-region : var.region
          awslogs-stream-prefix : "awslogs-${var.name}"
        }
      }
      essential = true
      portMappings = [
        {
          containerPort = 9900
          hostPort      = 9900
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "service" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.cluster.id
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1
  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = [aws_default_subnet.default.id]
    assign_public_ip = true
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  tags = var.tags
}

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "zones" {
  state = "available"
}

resource "aws_default_subnet" "default" {
  availability_zone = data.aws_availability_zones.zones.names[0]
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.name}-sg"
  description = "Security group for ecs task"
  vpc_id      = data.aws_vpc.default.id
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group_rule" "allow_egress" {
  description       = "Allow egress to the internet"
  security_group_id = aws_security_group.ecs.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app" {
  security_group_id = aws_security_group.ecs.id
  type              = "ingress"
  from_port         = 9900
  to_port           = 9900
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

