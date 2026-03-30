#!/bin/bash

# terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars -parallelism=20 -auto-approve