# Azure Load Balancer Frontend IP migration (Non-Zonal to Zonal)

This is an PoC to validate to migrate Internal Load Balancer to minimize downtime.

**DISCLAIMER:** This is a validation only and should not be used as final guidance.

## Intro

### Network Diagram

## Deploy this solution

wget -O migrate-lb-deploy.sh https://raw.githubusercontent.com/dmauser/azure-loadbalancer/main/migrate-azlb/migrate-lb-deploy.azcli
chmod +xr migrate-lb-deploy.sh
./migrate-lb-deploy.sh

## Validation

## Clean up

Delete resource group.