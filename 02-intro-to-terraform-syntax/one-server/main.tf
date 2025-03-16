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

resource "aws_default_subnet" "default_terraform_practice_subnet" {
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "Default Terraform Subnet for ap-northeast-1a"
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
  vpc_zone_identifier = data.aws_subnets.default.ids

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
