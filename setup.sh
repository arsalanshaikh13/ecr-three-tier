#!/bin/bash

terraform apply -var-file=dev.tfvars -parallelism=20 -auto-approve