# Template example from https://github.com/hashicorp/terraform/blob/master/examples/aws-two-tier/main.tf
#  modified by YC on 3/15/2017


variable "access_key" {}
variable "secret_key" {}


# Specify the provider and access details
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.aws_region}"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags {
    Name = "${var.username}_VPC"
    ENVIRONMENT = "TEST"
  }

}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
  tags {
    Name = "${var.username}_IGW"
    ENVIRONMENT = "TEST"
  }

}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags {
    Name = "${var.username}_subnet"
    ENVIRONMENT = "TEST"
  }

}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "${var.username}_ELB_SG"
  description = "For user ${var.username}, create by terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access from anywhere
  ingress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-vpc-no-public-ingress-sg
  }

 # HTTPS access from anywhere
  ingress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  #tfsec:ignore:aws-vpc-no-public-ingress-sg
  }

  # outbound internet access
  egress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-vpc-no-public-egress-sg
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "${var.username}_SG"
  description = "For user ${var.username}, create by terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access from Home
  ingress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["{{ X.X.X.X }}/32"]
  }

  # HTTP access from the VPC
  ingress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # Local network
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.0/24"]
  }

  # outbound internet access
  egress {
    description = "For user ${var.username}, create by terraform"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#tfsec:ignore:aws-elbv2-alb-not-public
resource "aws_elb" "web" {
  name = "${var.username}-elb"

  tags {
    Name = "${var.username}_ELB"
    ENVIRONMENT = "TEST"
  }

  subnets         = ["${aws_subnet.default.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
#  instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-east-1:{{ AWS_ACCT}}:certificate/{{ AWS_CERT }}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 6
    timeout             = 10
    target              = "HTTP:80"
    interval            = 20
  }


}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

/*
resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "centos"

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "${var.ec2_type}"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.default.id}"


  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
#  provisioner "remote-exec" {
#    inline = [
#    "sudo apt-get -y update",
#   "sudo apt-get -y install nginx",
#      "sudo service nginx start",
#    ]
#  }

tags {
    Name = "${var.username}_EC2"
    "OS"   = "CENTOS7"
    ENVIRONMENT = "TEST"
  }
}
*/

resource "aws_launch_configuration" "LC_conf" {
  name_prefix   = "${var.username}_LC"
  image_id      = "${lookup(var.aws_amis, var.aws_region)}"
  security_groups = ["${aws_security_group.default.id}"] 
  instance_type = "${var.ec2_type}"
  key_name = "${var.key_name}"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "autobot" {
  name                 = "${var.username}_AutoG"
  launch_configuration = "${aws_launch_configuration.LC_conf.name}"
  availability_zones        = ["${var.aws_region}a"]
  load_balancers            = ["${aws_elb.web.name}"]
  vpc_zone_identifier       = ["${aws_subnet.default.id}"]
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "OS"
    value               = "CENTOS7"
    propagate_at_launch = false
  }

  tag {
    key                 = "ENVIRONMENT"
    value               = "TEST"
    propagate_at_launch = false
  }

  tag {
    key                 = "OWNER"
    value               = "DevOPs"
    propagate_at_launch = false
  }

  tag {
    key                 = "COSTCENTER"
    value               = "TEST"
    propagate_at_launch = false
  }
}

resource "aws_route53_record" "www" {
   zone_id = "{{ ZONE_ID }}"
   name    = "${var.username}.{{ DOMAIN }}.com"
   type    = "CNAME"
   ttl     = "300"
   records = ["${aws_elb.web.dns_name}"]
}
