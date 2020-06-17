provider "aws" {
	region = "ap-south-1"
	profile = "anand"
}



resource "tls_private_key" "key1"{
	algorithm = "RSA"
}
resource "local_file" "keyfile"{
	depends_on = [tls_private_key.key1]
	content = tls_private_key.key1.private_key_pem
	filename = "webkey.pem"
}
resource "aws_key_pair" "webkey" {
  depends_on = [local_file.keyfile]
  key_name   = "webkey"
  public_key =  tls_private_key.key1.public_key_openssh
}




resource "aws_security_group" "sec_group" {
  name        = "web1_security"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-e5f2ef8d"

  ingress {
    description = "allow http inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ssh inbound"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_ssh"
  }
}





resource "aws_instance" "web1" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  security_groups = ["web1_security"]
  key_name  = "webkey"
  tags = {
    Name = "WebServer"
  }
}



resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.web1.availability_zone
  size              = 1
  tags = {
    Name = "myvol"
  }
}



resource "aws_volume_attachment" "ebs_att" {
  depends_on = [aws_instance.web1,aws_ebs_volume.ebs1]
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.web1.id
  force_detach = true
}



resource "null_resource" "nullremote3" {
  depends_on = [aws_volume_attachment.ebs_att]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/anand/tera/webserver/${local_file.keyfile.filename}")
    host     = aws_instance.web1.public_ip
  }

  provisioner "remote-exec" {
      inline = [
        "sudo yum install httpd  php git -y",
        "sudo systemctl restart httpd",
        "sudo systemctl enable httpd",
	"sudo mkfs.ext4  /dev/xvdd",
        "sudo mount  /dev/xvdd  /var/www/html",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/anandyyhs/Terraform1.git /var/www/html/"
      ]
    }

}


resource "aws_s3_bucket" "bucket1" {
  bucket = "anand.yyhs.bucket"
  acl    = "private"
  provisioner "local-exec" {
	    command = "git clone https://github.com/anandyyhs/Terraform1.git"
   }
  provisioner "local-exec" {
            when = destroy
	    command = "echo Y | rmdir/s Terraform1"
   }  
  tags = {
    Name = "anand.yyhs.bucket"
  }
}



resource "aws_s3_bucket_object" "object1" {
  bucket = aws_s3_bucket.bucket1.bucket
  key    = "image.jpg"
  
  source = "Terraform1/image.jpg"
  acl    = "public-read"
}





locals {
  s3_origin_id = "S3-anand.yyhs.bucket"
}


resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-anand.yyhs.bucket"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_s3_bucket_object.object1]
  origin {
    domain_name = "${aws_s3_bucket.bucket1.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  //comment             = "Some comment"
  default_root_object = "image.jpg"

  default_cache_behavior {
    allowed_methods  = [ "GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  
  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "s3_cloudfront"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



resource "null_resource" "nullremote4" {
  depends_on = [aws_cloudfront_distribution.s3_distribution]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =file("C:/Users/anand/tera/webserver/${local_file.keyfile.filename}")
    host     = aws_instance.web1.public_ip
  }

  provisioner "remote-exec" {
      inline = [
        "sudo echo https://${aws_cloudfront_distribution.s3_distribution.domain_name}/image.jpg > link.txt",
        "sudo mv link.txt /var/www/html/"
      ]
    }
}


resource "null_resource" "nulllocal1" {
depends_on = [null_resource.nullremote4]
provisioner "local-exec" {
	    command = "start chrome ${aws_instance.web1.public_ip}"
   }
}

output "instance_region" {
  value = aws_instance.web1.availability_zone
}

output "Web_server_ip" {
  value = aws_instance.web1.public_ip
}

