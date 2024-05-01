terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  shared_credentials_files = ["/path/to/credentials"]
  profile = "<yourawsprofile>"
}

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "${var.cluster_name}-cluster"
}

# Grab Default VPC
data "aws_vpc" "default" {
  default = true
}

# Use default subnets
data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Basic Security group enabling port 80 access
resource "aws_security_group" "lb" {
  name        = "${var.cluster_name}-lb-sg"
  description = "access to the application load balancer"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Basic Security group for the ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.cluster_name}-ecs-tasks-sg"
  description = "allow inbound access from the ALB only"

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The Application Load Balancer
resource "aws_lb" "alb" {
  name               = "${var.cluster_name}-alb"
  subnets            =  data.aws_subnets.default.ids
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
}

# The Application Load Balancer's Port 80 Listener
resource "aws_lb_listener" "https_forward" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

# Target group for the ECS Tasks to have their traffic routed to via ALB
resource "aws_lb_target_group" "target_group" {
  name        = "${var.cluster_name}-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "90"
    protocol            = "HTTP"
    matcher             = "200-299"
    timeout             = "20"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_execution" {
  assume_role_policy  = data.aws_iam_policy_document.ecs_task_execution_assume_role_doc.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    effect = "Allow"
  }
}

# Task Definitions for the containers, see task_definition.tpl.json.

## Important Notes around Bind Mounts:
# The module and the agent communicate over RPC via a Unix Socket so a bind mount is needed.to share a volume to write to the socket.
# Given Fargate does not allow the agent socket bind to occur on /var/run, the agent decides mount on /sigsci/tmp (it detects this) instead.
# The modules does not though, so the module configuration needs to be updated to look at /sigsci/tmp.
# You can review the nginx Dockerfile provided on how to hack around this quickly for this scenario, but ideally, you'll want a config mount to apply your nginx config if it deviates further.
# given the hack is based around the default nginx containers configuration. (however should still technically work with most).
data "template_file" "template_json" {
  template = templatefile("${path.module}/task_definition.tpl.json", {
    logs_name = "${var.cluster_name}-logs",
    shared_volume_name = "shared_socket"
    socket_path = "/sigsci/tmp"
    agent_key = "${var.agent_key}"
    agent_secret = "${var.agent_secret}"
  })
}

resource "aws_ecs_task_definition" "task_definition" {
  cpu                      = "512"
  memory                   = "1024"
  family                   = "${var.cluster_name}-task-definition"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  container_definitions    = data.template_file.template_json.rendered

  volume {
    name = "shared_socket"
  }
}

resource "aws_ecs_service" "service" {
  name            = "${var.cluster_name}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = var.task_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.https_forward, aws_iam_role.ecs_task_execution]
}

# CW Logs, you can view this in the deployed tasks logs and filter via `nginx` or `sigsci-agent`
resource "aws_cloudwatch_log_group" "simple_fargate_task_logs" {
  name = "${var.cluster_name}-logs"
}