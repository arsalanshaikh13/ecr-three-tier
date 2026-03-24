# ECS Advanced ALB Routing Demo
A multi-service Node.js application demonstrating Advanced Application Load Balancer (ALB) routing with Amazon ECS. Consists of three Express.js services:

- **Books App**: Provides book data via REST API
- **Authors App**: Provides author data via REST API  
- **Dashboard App**: Frontend service that fetches and displays data from both Books and Authors services

Built for showcasing ECS service discovery, load balancing, and inter-service communication patterns.

## User Interfaces
![Dashboard App](./dashboard/public/ss/dashboard-01.png)

![Dashboard App](./dashboard/public/ss/dashboard-02.png)

![Authors App](./authors/public/ss/authors.png)

![Books App](./books/public/ss/books.png)

## Prerequisites 
1. Install [HomeBrew](https://brew.sh/)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Install [Colima](https://formulae.brew.sh/formula/colima)
```bash
brew install colima
```

3. Install [Docker](https://formulae.brew.sh/formula/docker)
```bash
brew install docker
```

4. Install [Docker Compose](https://formulae.brew.sh/formula/docker-compose)
```bash
brew install docker-compose
```

5. Starts Colima using Docker as the runtime
```bash
colima start --runtime docker
```

6. Install [AWS CLI V2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions)
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
```
```bash
sudo installer -pkg ./AWSCLIV2.pkg -target /
```
```bash
which aws
```
```bash
aws --version
```

## Local Docker Workflow
1. Build docker image
```bash
docker build -t node-monolith-app .
```
2. Run Docker image
```bash
docker run -p 3200:3200 node-monolith-app
```
3. Docker Compose Build
```bash
docker compose build
```

## Configure AWS CLI for IAM user
1. Set your configuration settings
```bash
aws configure
```
2. To check if the CLI configuration was successful
```bash
aws ecr describe-repositories
```

## Create a repository
```bash
aws ecr create-repository \
    --repository-name <repository-name> \
    --region <region>
```

## Authenticate to your default registry
```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <aws_account_id>.dkr.ecr.<region>.amazonaws.com
```

## Tag the image
```bash
docker tag <image-name>:latest <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>
```

## Push the image
```bash
docker push <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:latest
```

## Pull an image from Amazon ECR
```bash
docker pull <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:latest
```

## List images
```bash
aws ecr list-images --repository-name <repository-name> --region <region>
```

## Delete an image
```bash
aws ecr batch-delete-image \
      --repository-name <repository-name> \
      --image-ids imageTag=latest \
      --region <region>
```

## List repositories
```bash
aws ecr describe-repositories 
```

## Delete a repository
```bash
aws ecr delete-repository \
      --repository-name <repository-name> \
      --force \
      --region <region>
```

## Building and Pushing a Multi-Platform Docker Image to Amazon ECR
1. Create and Set Buildx Builder
```bash
docker buildx create --use
```

2. Initialize Buildx Builder
```bash
docker buildx inspect --bootstrap
```

3. Build Docker Image for ECS
```bash
docker buildx build \
  --platform linux/amd64 \
  -t <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:latest \
  --load .
```

4. Push Docker Image to Amazon ECR
```bash
docker push <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:latest
```