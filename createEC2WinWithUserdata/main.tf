terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-2"
}

resource "aws_vpc" "cc_vpc" {
  cidr_block           = var.cc_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "aws_vpc-ud"
  }
}

locals {
  ingress_rules = [{
    name        = "HTTPS"
    port        = 443
    description = "Ingress rules for port 443"
    },
    {
      name        = "HTTP"
      port        = 80
      description = "Ingress rules for port 80"
    },
    {
      name        = "SSH"
      port        = 22
      description = "Ingress rules for port 22"
    },
      {
      name        = "TCP"
      port        = 3389
      description = "Ingress rules for port 3389 for RDP"
  }]

}

resource "aws_security_group" "sg" {

  name        = "SG4EC2-UD"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.cc_vpc.id
  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  dynamic "ingress" {
    for_each = local.ingress_rules

    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "AWS security group dynamic block"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cc_vpc.id

  tags = {
    Name = "vpc_igw-ud"
  }
}

resource "aws_subnet" "public_subnet" {
  count              = 1
  vpc_id            = aws_vpc.cc_vpc.id
  cidr_block        = element(cidrsubnets(var.cc_vpc, 8, 4, 4), count.index)
  map_public_ip_on_launch = true
  availability_zone = "us-east-2a"

  tags = {
    Name = "public-subnet-ud"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public_rt-ud"
  }
}

resource "aws_route_table_association" "public_rt_asso" {
  subnet_id   = element(aws_subnet.public_subnet.*.id, 1)
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_instance" "app_server" {
  ami           = "ami-0321c04d7f279eb63"
  instance_type = "t2.medium"
  key_name = "kcConsole"
  count         = 1
  subnet_id   = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.sg.id]
  tags = {
    Name = "CC-ec2-${count.index}-userdata-tf"
  }
  user_data = <<EOF
                <powershell>
                    Set-ExecutionPolicy Bypass -Scope Process -Force; `
                        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                    #install octo-deploy
                    choco install octopusdeploy.tentacle -y
                    
                    cd "C:\Program Files\Octopus Deploy\Tentacle"
                    .\Tentacle.exe create-instance --instance "Tentacle" --config "C:\Octopus\Tentacle.config" --console
                    .\Tentacle.exe new-certificate --instance "Tentacle" --if-blank --console
                    .\Tentacle.exe configure --instance "Tentacle" --reset-trust --console
                    .\Tentacle.exe configure --instance "Tentacle" --home "C:\Octopus" --app "C:\Octopus\Applications" --port "10933" --console
                    .\Tentacle.exe configure --instance "Tentacle" --trust "FF4D07AB4D137360F15FE688DABD1427147D7BF1" --console
                    netsh advfirewall firewall add rule "name=Octopus Deploy Tentacle" dir=in action=allow protocol=TCP localport=10933
                    .\Tentacle.exe register-with --instance "Tentacle" --server "http://YOUR_OCTOPUS" --apiKey="API-YOUR_API_KEY" --role "web-server" --environment "Staging" --comms-style TentaclePassive --console
                    .\Tentacle.exe service --instance "Tentacle" --install --start --console

                    Add-Type -Path 'Newtonsoft.Json.dll'
                    Add-Type -Path 'Octopus.Client.dll'

                    $octopusApiKey = 'API-ABCXYZ'
                    $octopusURI = 'http://YOUR_OCTOPUS'

                    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusURI, $octopusApiKey
                    $repository = new-object Octopus.Client.OctopusRepository $endpoint

                    $tentacle = New-Object Octopus.Client.Model.MachineResource

                    $tentacle.name = "Tentacle registered from client"
                    $tentacle.EnvironmentIds.Add("Environments-1")
                    $tentacle.Roles.Add("WebServer")

                    $tentacleEndpoint = New-Object Octopus.Client.Model.Endpoints.ListeningTentacleEndpointResource
                    $tentacle.EndPoint = $tentacleEndpoint
                    $tentacle.Endpoint.Uri = "https://YOUR_TENTACLE:10933"
                    $tentacle.Endpoint.Thumbprint = "FF4D07AB4D137360F15FE688DABD1427147D7BF1"

                    $repository.machines.create($tentacle)


                    # Install IIS
                    Install-WindowsFeature -name Web-Server -IncludeManagementTools;
                    # Restart machine
                    shutdown -r -t 10;
                </powershell>
                EOF
  associate_public_ip_address = true
}

