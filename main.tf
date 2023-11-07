provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "idalov-repo" {
  name = "idalov-repo"
}

resource "aws_vpc" "idalov_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "idalov-vpc"
  }
}

resource "aws_ecs_cluster" "idalov_cluster" {
  name = "idalov-cluster"
}

resource "aws_iam_role" "idalov_ecs_execution_role" {
  name               = "idalov-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "idalov_ecs_execution_role_policy_attachment" {
  role       = aws_iam_role.idalov_ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "idalov_task" {
  family = "idalov-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"
  execution_role_arn = aws_iam_role.idalov_ecs_execution_role.arn
  container_definitions = jsonencode([{
    name = "idalov-container"
    image = aws_ecr_repository.idalov-repo.repository_url
    portMappings = [{
      containerPort = 3000
      hostPort = 3000
    }]
  }])
}

resource "aws_ecs_service" "idalov_service" {
  name = "idalov-service"
  cluster = aws_ecs_cluster.idalov_cluster.id
  task_definition = aws_ecs_task_definition.idalov_task.arn
  launch_type = "FARGATE"
  desired_count = 1

  network_configuration {
    subnets = [aws_default_subnet.idalov_default_subnet_a.id, aws_default_subnet.idalov_default_subnet_b.id, aws_default_subnet.idalov_default_subnet_c.id]
    assign_public_ip = true
    security_groups = [aws_security_group.idalov_service_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.idalov_target_group.arn
    container_name = "idalov-container"
    container_port = 3000
  }
}

resource "aws_default_vpc" "default_vpc" {}

resource "aws_default_subnet" "idalov_default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "idalov_default_subnet_b" {
  availability_zone = "us-east-1b"
}

resource "aws_default_subnet" "idalov_default_subnet_c" {
  availability_zone = "us-east-1c"
}

resource "aws_alb" "idalov_app_lb" {
  name = "idalov-app-lb"
  load_balancer_type = "application"
  subnets = [aws_default_subnet.idalov_default_subnet_a.id, aws_default_subnet.idalov_default_subnet_b.id, aws_default_subnet.idalov_default_subnet_c.id]
  security_groups = [aws_security_group.idalov_lb_sg.id]
}

resource "aws_security_group" "idalov_lb_sg" {
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

resource "aws_security_group" "idalov_service_sg" {
  ingress {
    from_port = 3000
    to_port   = 3000
    protocol  = "tcp"
    security_groups = [aws_security_group.idalov_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_lb_target_group" "idalov_target_group" {
  name        = "idalov-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "idalov_listener" {
  load_balancer_arn = aws_alb.idalov_app_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.idalov_target_group.arn
  }
}