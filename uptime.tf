provider "aws" {
  region = "us-east-1"  # Update with your desired region
}

variable "ip" {
  type = string
  default = "70.224.95.9"
}

resource "aws_instance" "uptime" {
  ami           = "ami-022e1a32d3f742bd8"  # Replace with the desired AMI ID
  instance_type = "t2.large"                # Replace with the desired instance type
  key_name      = "sreuni"
  user_data     = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y docker
    # Create Prometheus Blackbox Exporter configuration file
    echo '
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: "webserver"
        static_configs:
          - targets: ["localhost:9090"]

      - job_name: "blackbox"
        metrics_path: /probe
        params:
          module: [http_2xx]  
        static_configs:
          - targets:
            - http://${aws_eip.webserver_eip.public_ip}/health   # Target to probe with HTTP.
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: blackbox-exporter-node1:9115
    ' | sudo tee uptime.yml

   
    # Start Docker services
    sudo systemctl enable docker
    sudo systemctl start docker

    # #run blackbox,prom and grafana
    # # sudo docker run -d -p 9115:9115 --name blackbox-exporter-node1 -v $(pwd)/blackbox.yml:/opt/bitnami/blackbox-exporter/conf/config.yml bitnami/blackbox-exporter:latest
    sudo docker network create mynetwork  # Create a user-defined network

    sudo docker run -d -p 9115:9115 --name blackbox-exporter-node1 --network mynetwork bitnami/blackbox-exporter:latest

    sudo docker run -d -p 9090:9090 --name prometheus -v $(pwd)/uptime.yml:/etc/prometheus/prometheus.yml --network mynetwork prom/prometheus

    sudo docker run -d -p 3000:3000 --name grafana --network mynetwork grafana/grafana
    EOF

  vpc_security_group_ids = [aws_security_group.uptime-sg.id]

  tags = {
    Name = "uptime-instance"
  }
}



resource "aws_instance" "webserver" {
  ami           = "ami-022e1a32d3f742bd8"  # Replace with the desired AMI ID
  instance_type = "t2.large"                # Replace with the desired instance type
  key_name      = "sreuni"
  user_data     = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y docker
    sudo systemctl enable docker
    sudo systemctl start docker


    # Start Nginx container
    echo '
    events {}

    http {
      server {
        listen 80;
        server_name localhost;

        location /health {
          return 200 "success";
        }
      }
    }
    ' | sudo tee nginx.conf

    sudo docker run -d -p 80:80 --name webserver -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf nginx
    EOF

  vpc_security_group_ids = [aws_security_group.webserver_sg.id]

  tags = {
    Name = "webserver"
  }
}

resource "aws_eip" "webserver_eip" {
  instance = aws_instance.webserver.id
  # vpc      = true
}


resource "aws_security_group" "uptime-sg" {
  name        = "prom-grafana-webserver-sg"
  description = "prom-grafana-webserver-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ip}/32"]
    
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["${var.ip}/32"]

  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["${var.ip}/32"]
   
  }

  ingress {
    from_port   = 9115
    to_port     = 9115
    protocol    = "tcp"
    cidr_blocks = ["${var.ip}/32"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prom-grafana-webserver-sg"
  }
}



resource "aws_security_group" "webserver_sg" {
  name        = "webserver-sg"
  description = "webserver-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.uptime-sg.id]  # Allow traffic from its own security group

  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ip}/32"]
   
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prom-grafana-webserver-sg"
  }
}



# sudo less /var/log/cloud-init-output.log
# https://www.stackhero.io/en/services/Prometheus/documentations/Blackbox-Exporter/Prometheus-Blackbox-Exporter-configuration