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

resource "aws_instance" "example_instance" {
  ami = "ami-0a290015b99140cd1"
  instance_type = "t2.micro"

  tags = {
    Name = "terraform-example-ec2-instance"
  }
}
