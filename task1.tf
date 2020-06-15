/* Specify the provider to interact the resources supported and configure it proper credentials before use. */ 
/*   To configure: aws configure --profile profilename */

provider "aws" {
	region = "ap-south-1"
	profile = "kajal"
}
/************************************************************************************************************************/

data "aws_vpc" "selected" {
  default = true
}

/* Generate a private key and encode it as pem */

resource "tls_private_key" "example" {
  algorithm   = "RSA"
}

resource "local_file" "private-key" {
    content     = "tls_private_key.key.private_key_pem"Y
    filename = "mykey.pem"
    file_permission = 0400
}

resource "aws_key_pair" "key-pair" {
  key_name   = "mykey"
  public_key = tls_private_key.example.public_key_openssh
}

/*****************************************************************************************/
/* Create security group and allow HTTP, SSH and ICMP protocols */

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls1"
  description = "Allow_tls"
  vpc_id      = "${data.aws_vpc.selected.id}"

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "ping-icmp"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls1"
  }
}
/***********************************************************************************************************************/
/* Launch an OS, attach the key generated and the security groups created. SSH into the OS and install the webserver and the required SDK's  */

resource "aws_instance" "web" {
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	key_name = aws_key_pair.key-pair.key_name
	security_groups = [ aws_security_group.allow_tls.name ]

connection {
	type     = "ssh"
   	user     = "ec2-user"
  	private_key = tls_private_key.example.private_key_pem
    	host     = aws_instance.web.public_ip
  }
provisioner "remote-exec" {
	inline = [
  	"sudo yum install httpd php git -y",
	"sudo systemctl restart httpd",
	"sudo systemctl enable httpd",
	]
}
tags = {
	Name = "lwos1"
	}
}
/*******************************************************************************************************************************/
/* Fetch the availability zone of the instance and create an EBS volume in the same zone. 

resource "aws_ebs_volume" "lw_ebs" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "lw_ebs"
  }
}

/* Attach the volume created to the instance */
resource "aws_volume_attachment" "ebs_att" {

  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.lw_ebs.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}

/*************************************************************************************************************************/
output "myos_ip" {
  value = aws_instance.web.public_ip
}

/* [Optional]*/
resource "null_resource" "nullocal2" {
	provisioner "local-exec" {
	command = "echo ${aws_instance.web.public_ip} > publicip.txt"
	}
}

/*********************************************************************************************************************************/
/ *Provisioners are used to model specific actions on the local machine or on a remote machine in order to prepare servers or other infrastructure objects for service.*/
/* Provisioners need a null-resource that is a do-nothing container for the actions taken by a provisioner. */

resource "null_resource" "nullremote3" {

/* Tells Terraform that EBS volume must be formatted, mounted and store data only after the created volume has been attched to the instance. */

depends_on = [
	aws_volume_attachment.ebs_att,
	]

connection {
 	type     = "ssh"
   	user     = "ec2-user"
  	private_key = tls_private_key.example.private_key_pem
    	host     = aws_instance.web.public_ip
  }
provisioner "remote-exec" {
	inline = [
	"sudo mkfs.ext4 /dev/xvdh",
	"sudo mount /dev/xvdh /var/www/html",
	"sudo rm -rf /var/www/html/*",
	"sudo git clone https://github.com/kajal1706043/multi_cloudTask1.git /var/www/html"			
	]
	}
}
/**********************************************************************************************************************/

/*Tells Terraform that the IP address must be viewed onto the browser only after the instance is completely ready with the webpage. */
resource "null_resource" "nulllocal1" {

depends_on = [
	null_resource.nullremote3,
]

	provisioner "local-exec" {
		command = "start chrome ${aws_instance.web.public_ip}"
	}
}

/*************************************************************************************************************************/
/*Create an S3 bucket and grant public access to it */
resource "aws_s3_bucket" "b" {
  bucket = "tsk1bucket"
  acl    = "public-read"

  tags = {
    Name        = "mybucket"
  }
}

/* Deploy an image into the bucket from Github. */
resource "aws_s3_bucket_object" "deployimage" {
	bucket = aws_s3_bucket.b.bucket
	key = "cloudtask1.jpg"
	source = "git_image/Hybrid-Cloud.jpg"
	acl = "public-read"
}

/* null-resources are the first to be executed by Terraform. Thus, the image on github is first download onto the local machine*/

resource "null_resource" "nulllocal4" {
provisioner "local-exec" {
	command = "git clone https://github.com/kajal1706043/task1_s3.git git_image"
}
/* To remove the image from the local system when the infrastructure is destroyed */
provisioner "local-exec" {
	when = destroy
	command = "rmdir /s /q git_image"
}
}
/********************************************************************************************************************************/

#Create a CloudFront Distribution with the created S3 bucket as Origin
locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.b.bucket_domain_name
    origin_id   = "${local.s3_origin_id}"
}

default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
viewer_protocol_policy = "allow-all"
}
enabled             = true
restrictions {
     geo_restriction {
      	restriction_type = "none"
    }
}
viewer_certificate {
    cloudfront_default_certificate = true
  }
}
/*******************************************************************************************************************************/



