# 最初は使いたいプロバイダを設定する
# プロバイダーとしてAWSを使い、ap-northeast-1リージョンにインフラをデプロイしたいということをTerraformに伝えている
provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_default_vpc" "default_terraform_practice_vpc" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_subnet" "default_terraform_practice_subnet_1a" {
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "Default Terraform Subnet for ap-northeast-1a"
  }
}

resource "aws_default_subnet" "default_terraform_practice_subnet_1c" {
  availability_zone = "ap-northeast-1c"
  tags = {
    Name = "Default Terraform Subnet for ap-northeast-1c"
  }
}


variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

# aws_security_groupと呼ばれる新しいリソースを作成している
# 0.0.0.0/0(どのIPアドレス)からも、ポート8080に対する内向きTCPリクエストを許可するという意味。
resource "aws_security_group" "example_instance" {
  name = "terraform-example-instance"

  # ingressはインバウンドルールを定義したい時に使うもの
  ingress {
    from_port = var.server_port # from_portとto_portはトラフィックを許可するポート範囲を表す。この場合だと8080しか許可してない
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# resource "aws_instance" "example_instance" {
#   ami = "ami-0a290015b99140cd1"
#   instance_type = "t2.micro"
#   vpc_security_group_ids = [aws_security_group.example_instance.id]

#   user_data = <<-EOF
#               #!/bin/bash
#               echo "Hello, World" > index.html
#               nohup busybox httpd -f -p ${var.server_port} &
#               EOF

#   # ユーザーデータを更新したら、インスタンスを消して起動する
#   user_data_replace_on_change = true

#   tags = {
#     Name = "terraform-example-ec2-instance"
#   }
# }

# output "public_ip" {
#   value = aws_instance.example_instance.public_ip
#   description = "The public IP address of the web server"
# }

output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}

# ASG内のインスタンスをどのように設定するかを、以下で定義する
resource "aws_launch_template" "example_asg_launch_template" {
  image_id = "ami-0a290015b99140cd1"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.example_instance.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  )

  # Autoscaling groupがある起動設定を使った場合に必須
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


# ASG自体の設定
resource "aws_autoscaling_group" "example_asg" {
  vpc_zone_identifier = data.aws_subnets.default.ids # vpc_zone_identifier はASGのインスタンスを起動するサブネット（サブネットID）のリストを指定する
  target_group_arns = [aws_lb_target_group.asg.arn] # この設定をすると、ASGで起動されたインスタンスは自動的にロードバランサ-のターゲットグループに登録される

  health_check_type = "ELB"

  min_size = 2
  max_size = 5

  launch_template {
    id = aws_launch_template.example_asg_launch_template.id
    version = "$Latest"
  }

  tag  {
    key = "Name"
    value = "terraform-asg-example" # 各インスタンスにterraform-asg-exampleというtagをつける
    propagate_at_launch = true
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  # インバウンドHTTPリクエストを許可
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # アウトバウンドHTTPリクエストをすべて許可
  # インターネット上のどこにでも、どのようなプロトコルでも、どのポートにでも自由に通信を送信できる状態になっている。
  egress {
    from_port = 0 # すべてのポート範囲を許可
    to_port = 0
    protocol = "-1" # すべてのプロトコルを許可
    cidr_blocks = ["0.0.0.0/0"] # インターネット上のすべてのIPアドレス（0.0.0.0/0）への通信を許可
  }
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
  description = "The IDs of the subnets"
}

# # aws_lbリソースを使って、ALB自体を作成
resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids # ロードバランサーにアタッチするsubnet_idのリスト
  security_groups = [aws_security_group.alb.id]
}

# ALBに対してリスナを定義する
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"

  # デフォルトではシンプルな404ページを返す
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

# ロードバランサーがトラフィックをASG内の健全なインスタンスに転送できるようにするために、定義する
resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port # このターゲットグループが、トラフィックを転送するポート番号
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id # このターゲットグループが配置されるVPC

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2 # ターゲットを健全と見なすために必要な、ヘルスチェックの連続成功回数
    unhealthy_threshold = 2 # ターゲットを不健全と見なすために必要な、ヘルスチェックの連続失敗回数
  }
}

# パスが一致するリクエストを、ASGが含まれるターゲットグループに送るリスナー
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100 # ルールの優先度

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}