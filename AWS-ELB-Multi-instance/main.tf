provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "${var.aws_region}"
}

resource "aws_vpc" "default" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags = {
        Name = "${var.vpc_name}"
    }
}

resource "aws_internet_gateway" "default" {
    vpc_id = "${aws_vpc.default.id}"
	tags = {
        Name = "${var.IGW_name}"
    }
}

resource "aws_subnet" "subnet1-public" {
	vpc_id = "${aws_vpc.default.id}"
    cidr_block = "${var.public_subnet1_cidr}"
    availability_zone = "us-east-1a"

    tags = {
        Name = "${var.public_subnet1_name}"
    }
}

resource "aws_subnet" "subnet2-public" {
    vpc_id = "${aws_vpc.default.id}"
    cidr_block = "${var.public_subnet2_cidr}"
    availability_zone = "us-east-1b"

    tags = {
        Name = "${var.public_subnet2_name}"
    }
}

resource "aws_subnet" "subnet3-public" {
    vpc_id = "${aws_vpc.default.id}"
    cidr_block = "${var.public_subnet3_cidr}"
    availability_zone = "us-east-1c"

    tags = {
        Name = "${var.public_subnet3_name}"
    }
	
}


resource "aws_route_table" "terraform-public" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.default.id}"
    }

    tags = {
        Name = "${var.Main_Routing_Table}"
    }
}

resource "aws_route_table_association" "terraform-public" {
    subnet_id = "${aws_subnet.subnet1-public.id}"
    route_table_id = "${aws_route_table.terraform-public.id}"
}

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "8080 80 443 inbound traffic"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "tomcat port from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    }
}


resource "aws_instance" "web-1" {
	count = "${var.instance_count}"
    ami = "ami-00ddb0e5626798373"
    availability_zone = "us-east-1a"
    instance_type = "t2.nano"
    key_name = "${var.key_name}"
    subnet_id = "${aws_subnet.subnet1-public.id}"
    vpc_security_group_ids = ["${aws_security_group.allow_all.id}"]
    associate_public_ip_address = true	
	user_data= <<-EOF
             #!/bin/bash
			  apt update -y
              apt install nginx -y
			  rm /var/www/html/*.html
              echo "hey i am $(hostname -f)" > /var/www/html/index.html
              service nginx start
              chkconfig nginx on
EOF
    tags = {
        Name = "Server-${count.index + 1}"
        
    }
}


resource "aws_lb_target_group" "my-target-group" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  name        = "my-test-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "${aws_vpc.default.id}"
}

resource "aws_lb" "my-aws-alb" {
  name     = "jmsth-test-alb"
  internal = false
  security_groups = [
    "${aws_security_group.allow_all.id}",
  ]
	subnets = ["${aws_subnet.subnet1-public.id}","${aws_subnet.subnet2-public.id}", ]
	
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "jmsth-test-alb-listner" {
  
 load_balancer_arn = aws_lb.my-aws-alb.arn
      port                = 80
      protocol            = "HTTP"
      default_action {
        target_group_arn = "${aws_lb_target_group.my-target-group.arn}"
        type             = "forward"
      }
}
resource "aws_alb_target_group_attachment" "ec2_attach" {
  count = length(aws_instance.web-1)
  target_group_arn = aws_lb_target_group.my-target-group.arn
  target_id = aws_instance.web-1[count.index].id
}



