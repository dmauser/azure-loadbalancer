# Azure Load Balancer Frontend IP migration (Non-Zonal to Zonal)

**DISCLAIMER:** This lab/article is a proof of concept and should not be used, at this time, as recommended or official guidance.

**Content**

- [Summary](#summary-tldr)
- [Network Diagram](#network-diagram)
- [Deploy this solution](#deploy-this-solution)
- [Traffic symmetry validations](#traffic-symmetry-validations)
  - [Validation 1](#validation-1)
  - [Validation 2](#validation-2)
  - [Validation 3](#validation-3)
  - [Validation 4](#validation-4)
- [Migration](#migration)
- [Results](#results)
- [Clean up](#clean-up)

### Summary (TL;DR)

- This lab is a proof of concept to validate a non-Zonal frontend IP coexisting with a Zonal over a single Internal Load Balancer.
- The lab scope is for a specific scenario leveraging Internal Load Balancer (ILB) using NVA's as backends.
- Traffic between Spokes and On-premises routes over NVA via ILB that initially goes over a Frontend IP non-Zonal. The goal is to switch traffic progressively to a new Frontend IP zonal and avoid two potential issues:
  1. **Asymmetric routing** - the initial traffic uses non-Zonal IP Frontend IP in conjunction with the Zonal Frontend IP for return traffic.
  2. **Downtime** - when changing each UDR to use the newer Zonal Frontend IP while using other UDR points to the original Non-Zonal Frontend IP.
- Lab [results](#results) showed no downtime or asymmetric routing when using this approach for migrating Non-Zonal to Zonal Frontend IPs.

### Network Diagram

![](./media/networkdiagram.png)

### Components

- All VM's are accessible using SSH (restricted by your Home Public IP) Bastion or Serial Console.
- Default username is _azureuser_ and password _Msft123Msft123_.

**Azure side:**
 - Azure Hub (10.0.0.0/24) and two Spokes (Spoke1 - 10.0.1.0/24 and Spoke 2 - 10.0.2.0/24).
 - Each spoke as a Linux VM (az-spk1-lxvm and az-spk1-lxvm).
 - Two Linux NVAs (10.0.0.164, 10.0.0.165) with IPtables.
 - Internal Load Balancer (ILB) with two Frontend IPs: first non-zonal (10.0.0.166) and second zonal (10.0.0.166).
   - Two load balancer (LB) rules to each front end IP with HA ports using both Linux NVAs as backends.
   - LB rules have **Floating IP enabled** (this is required to re-use the same Backend as NIC)

**On-premises side:**
 - On-prem VNET (192.168.100.0/24) using VPN Gateway with S2S VPN to Azure.
 - Linux VM onprem-lxvm.

### Deploy this solution
The lab is also available in the above .azcli that you can rename as .sh (shell script) and execute. You can open [Azure Cloud Shell (Bash)](https://shell.azure.com) or Azure CLI via Linux (Ubuntu) and run the following commands to build the entire lab:

```Bash
wget -O migrate-lb-deploy.sh https://raw.githubusercontent.com/dmauser/azure-loadbalancer/main/migrate-azlb/migrate-lb-deploy.azcli
chmod +xr migrate-lb-deploy.sh
./migrate-lb-deploy.sh
```

**Note:** the provisioning process will take 30 minutes to complete. Also, note that Azure Cloud Shell has a 20 minutes timeout and make sure you watch the process to make sure it will not timeout causing the deployment to stop. You can hit enter during the process just to make sure Serial Console will not timeout. Otherwise, you can install it using any Linux. In can you have Windows OS you can get a Ubuntu + WSL2 and install Azure CLI.

### Traffic symmetry validations

Here the goal is to validate traffic symmetry by changing UDRs on Spokes and GatewaySubnet progressively from ILB non-zonal frontend IP 10.0.0.166 to zonal frontend IP 10.0.0.167. We will start by validating the lab before the changes (Validation 1), and we will change the UDR on Spoke 2 to use 10.0.0.167 (Validation 2) while the other UDRs are still pointing to the original 10.0.0.166. We will finish (Validation 3) by changing Spoke 1 to use 10.0.0.167 (zonal) while Spoke 2 uses the original 10.0.0.166 (zonal).

#### Validation 1

![validation1](./media/validation1.png)

```Bash
#Parameters
rg=lab-lb-migrate #Define your resource group
location=$(az group show -n $rg --query location -o tsv) #Set location

#Define parameters for Azure Hub and Spokes:
AzurehubName=az-hub #Azure Hub Name
AzurehubNamesubnetName=subnet1 #Azure Hub Subnet name where VM will be provisioned
Azurehubsubnet1Prefix=10.0.0.0/27 #Azure Hub Subnet address prefix
Azurespoke1Name=az-spk1 #Azure Spoke 1 name
Azurespoke2Name=az-spk2 #Azure Spoke 1 name
#Variables
nva1ip=$(az network nic show -g $rg --name $AzurehubName-lxnva1-nic --query "ipConfigurations[].privateIpAddress" -o tsv)
nva2ip=$(az network nic show -g $rg --name $AzurehubName-lxnva2-nic  --query "ipConfigurations[].privateIpAddress" -o tsv)
# Frontendip1 (non-zonal)
nvalbip1=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv)
# Frontendip2 (zonal)
nvalbip2=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv)

# 1) Connectivity tests before UDR change:

# Review the Linux NVAs have IPTables enforced
# Via Bastion or Serial console run:
sudo iptables -L -v -n --line-numbers

#Example/Expected output for FORWARD rules:
# {Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
#num   pkts bytes target     prot opt in     out     source               destination         
#1      157  8680 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
#2       60  2480 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:80
#3        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:443
#4        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
#5        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:22
#6        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:5201
#7        1    84 ACCEPT     icmp --  eth0   *       0.0.0.0/0            0.0.0.0/0            icmptype 8
#8        0     0 ACCEPT     icmp --  eth0   *       0.0.0.0/0            0.0.0.0/0            icmptype 0
#9        0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0  

# Access Bastion or Serial console on az-SPK1-lxvm:
# Run the following
ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4

# Access Bastion or Serial console on az-SPK2-lxvm:
# Run the following
ping 10.0.1.4 -c 5
sudo hping3 10.0.1.4 -S -p 80 -c 10
curl 10.0.1.4

# Optional - you can run commands from onprem-vmlx
ping 10.0.1.4 -c 5
sudo hping3 10.0.1.4 -S -p 80 -c 10
curl 10.0.1.4

ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4

# Optional - You can also remove NVA Linux icmp rule to ensure IPtables is being enforced
# Note: That will make ping to stop working on the following tests
sudo iptables -L -v -n --line-numbers

#Example:
# {Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
#num   pkts bytes target     prot opt in     out     source               destination         
#1      157  8680 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
#2       60  2480 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:80
#3        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:443
#4        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
#5        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:22
#6        0     0 ACCEPT     tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:5201
#7        1    84 ACCEPT     icmp --  eth0   *       0.0.0.0/0            0.0.0.0/0            icmptype 8
#8        0     0 ACCEPT     icmp --  eth0   *       0.0.0.0/0            0.0.0.0/0            icmptype 0
#9        0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0  
sudo iptables -D FORWARD 7 # Run once
sudo iptables -D FORWARD 7 # Run twice
sudo iptables -L -v -n --line-numbers
# Icmp lines should be removed.
# ====> Remember to run on both NVAs.
```

#### Validation 2

![validation2](./media/validation2.png)

```Bash
# 2) UDR Change on Spoke 2 to point to Zonal LBFE (Spoke 1 points to non-zonal LBFE)

## Dump non-zonal and Zonal LB Frontends

echo 'Frontendip1 (non-zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv &&\
echo 'Frontendip2 (zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv

## Updating UDRs -> SPK1 default route to Frontendip1 and SPK2 VM route to Frontendip2
# Frontendip1 (non-zonal)
nvalbip1=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv)
# Frontendip2 (zonal)
nvalbip2=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv)
# RT-Spoke1-to-nvalb
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke1-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke1-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
# RT-Spoke2-to-nvalb  
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke2-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke2-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none

#Check source/destination VMs effective routes
echo $Azurespoke1Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke1Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke1Name-lxvm-nic -o table
echo $Azurespoke2Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke2Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke2Name-lxvm-nic -o table

### Test/Actions
# (Optional)Capture Network Trace on both NVAs
sudo tcpdump -n host 10.0.1.4 and host 10.0.2.4 -w nva1test1.pcap
sudo tcpdump -n host 10.0.1.4 and host 10.0.2.4 -w nva2test1.pcap

Access Bastion or Serial console on 
# Access Bastion or Serial console on az-SPK1-lxvm:
# Run the following
ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4

# Access Bastion or Serial console on az-SPK2-lxvm:
# Run the following
ping 10.0.1.4 -c 5
sudo hping3 10.0.1.4 -S -p 80 -c 10
curl 10.0.1.4

# Access Bastion or Serial console on onprem-lxvm:
# Run the following commands.
ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4
```

#### Validation 3

![validation3](./media/validation3.png)

```Bash
# 3) UDR Change on Spoke 1 to point to Zonal LB (Spoke 2 points to non-zonal LBFE)

## Dump non-zonal and Zonal LB Frontends

echo 'Frontendip1 (non-zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv &&\
echo 'Frontendip2 (zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv

## Updating UDRs -> SPK1 default route to Frontendip1 and SPK2 VM route to Frontendip2
# Frontendip1 (non-zonal)
nvalbip1=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv)
# Frontendip2 (zonal)
nvalbip2=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv)
# RT-Spoke1-to-nvalb
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke1-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke1-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
# RT-Spoke2-to-nvalb  
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke2-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke2-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none

#Check source/destination VMs effective routes
echo $Azurespoke1Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke1Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke1Name-lxvm-nic -o table
echo $Azurespoke2Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke2Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke2Name-lxvm-nic -o table

### Test/Actions
# (Optional)Capture Network Trace on both NVAs
sudo tcpdump -n host 10.0.1.4 and host 10.0.2.4 -w nva1test1.pcap
sudo tcpdump -n host 10.0.1.4 and host 10.0.2.4 -w nva2test1.pcap

Access Bastion or Serial console on 
# Access Bastion or Serial console on az-SPK1-lxvm:
# Run the following
ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4

# Access Bastion or Serial console on az-SPK2-lxvm:
# Run the following
ping 10.0.1.4 -c 5
sudo hping3 10.0.1.4 -S -p 80 -c 10
curl 10.0.1.4

# Access Bastion or Serial console on onprem-lxvm:
# Run the following commands.
ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4
```

#### Validation 4

![validation4](./media/validation4.png)

```Bash
## Updating UDRs -> SPK1 default route to Frontendip1 and SPK2 VM route to Frontendip2

# RT-Spoke1-to-nvalb
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke1-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke1-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
# RT-Spoke2-to-nvalb  
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke2-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke2-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
# GatewaySubnet UDR
## Azure Hub Subnet 1
az network route-table route create --resource-group $rg --name HubSubnet1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
## Azure Spoke 1
az network route-table route create --resource-group $rg --name Spoke1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke1AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
## Azure Spoke 2
az network route-table route create --resource-group $rg --name Spok2-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke2AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none 

## Dump non-zonal and Zonal LB Frontends

echo 'Frontendip1 (non-zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv &&\
echo 'Frontendip2 (zonal)' &&\
az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv

#Check source/destination VMs effective routes
echo $Azurespoke1Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke1Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke1Name-lxvm-nic -o table
echo $Azurespoke2Name-lxvm &&\
az network nic show --resource-group $rg -n $Azurespoke2Name-lxvm-nic --query "ipConfigurations[].privateIpAddress" -o tsv &&\
az network nic show-effective-route-table --resource-group $rg -n $Azurespoke2Name-lxvm-nic -o table

### Test/Actions
# Access Bastion or Serial console on onprem-lxvm:
# Run the following commands.
ping 10.0.1.4 -c 5
sudo hping3 10.0.1.4 -S -p 80 -c 10
curl 10.0.1.4

ping 10.0.2.4 -c 5
sudo hping3 10.0.2.4 -S -p 80 -c 10
curl 10.0.2.4
```

### Migration

In this section, we will start by running a continuous connectivity check on all VMs and then change UDRs from non-zonal (10.0.0.166) frontend IP to zonal (10.0.0.167). The expectation is after you run the script below without any downtime. At a 60 seconds interval, each UDR will get updated to the new Zonal Front End IP.

1. Spoke2 UDR transitions 10.0.0.166 from to 10.0.0.167.
2. Spoke3 UDR transitions 10.0.0.166 from to 10.0.0.167
3. GatewaySubnet UDR transitions 10.0.0.166 from to 10.0.0.167

![migration](./media/migration.png)

```Bash
### Migration

# Variables:
Azurespoke1AddressSpacePrefix=10.0.1.0/24 
Azurespoke2AddressSpacePrefix=10.0.2.0/24
# Frontendip1 (non-zonal)
nvalbip1=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[0].privateIpAddress" -o tsv)
# Frontendip2 (zonal)
nvalbip2=$(az network lb show -g $rg --name $AzurehubName-nvalb --query "frontendIpConfigurations[1].privateIpAddress" -o tsv)

# Prequeisits
# Review all UDR or ensure all of them a pointing to the Non-Zonal Front End IP by running the following commands:
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke2-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke2-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
# RT-Spoke1-to-nvalb
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke1-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke1-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
# GatewaySubnet UDR
## Azure Hub Subnet 1
az network route-table route create --resource-group $rg --name HubSubnet1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
## Azure Spoke 1
az network route-table route create --resource-group $rg --name Spoke1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke1AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none
## Azure Spoke 2
az network route-table route create --resource-group $rg --name Spok2-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke2AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip1 \
 --output none

# Run a persistent connectivity test from all three VMs (spk1, spk2 and on-premises)
# spkvm1
sudo hping3 10.0.2.4 -S -p 80 -c 10000
# spkvm
sudo hping3 10.0.1.4 -S -p 80 -c 10000
# onpremvm (one or both)
sudo hping3 10.0.1.4 -S -p 80 -c 10000
sudo hping3 10.0.2.4 -S -p 80 -c 10000

# Update UDRs with intervals of one minute and check if there's any packet loss:

# RT-Spoke2-to-nvalb 
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke2-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke2-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
sleep 60
# RT-Spoke1-to-nvalb
az network route-table route update --resource-group $rg --name Default-to-nvalb --route-table-name RT-Spoke1-to-nvalb \
 --address-prefix 0.0.0.0/0 \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
az network route-table route create --resource-group $rg --name Hub-to-nvalb --route-table-name RT-Spoke1-to-nvalb   \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
sleep 60
# GatewaySubnet UDR
## Azure Hub Subnet 1
az network route-table route create --resource-group $rg --name HubSubnet1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurehubsubnet1Prefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
## Azure Spoke 1
az network route-table route create --resource-group $rg --name Spoke1-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke1AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
## Azure Spoke 2
az network route-table route create --resource-group $rg --name Spok2-to-nvalb --route-table-name RT-GWSubnet-to-nvalb \
 --address-prefix $Azurespoke2AddressSpacePrefix \
 --next-hop-type VirtualAppliance \
 --next-hop-ip-address $nvalbip2 \
 --output none
# Check all routes to ensure they are pointing to the new zonal frontend IP 10.0.0.167
rts=$(az network route-table list -g $rg --query [].name -o tsv)
for rt in $rts
do
 echo $rt
 az network route-table show -n $rt -g $rg --query routes -o table
done 
```

### Results

Based on the results below, there were no downtime found during the transition.

- az-spk1-lxvm:

```Bash
--- 10.0.2.4 hping statistic ---
1170 packets transmitted, 1170 packets received, 0% packet loss
round-trip min/avg/max = 2.6/7.6/17.4 ms
azureuser@az-spk1-lxvm:~$ 
```

- az-spk2-lxvm:
```bash
--- 10.0.1.4 hping statistic ---
1164 packets transmitted, 1164 packets received, 0% packet loss
round-trip min/avg/max = 2.3/7.6/15.4 ms
azureuser@az-spk2-lxvm:~$ 
```

- onprem-lxvm

```bash
--- 10.0.2.4 hping statistic ---
1146 packets transmitted, 1146 packets received, 0% packet loss
round-trip min/avg/max = 4.4/10.6/309.3 ms
azureuser@onprem-lxvm:~$ 
```

### Clean-up

```bash
# Parameters 
rg=lab-lb-migrate  #set resource group

### Clean up
az group delete -g $rg --no-wait 
```