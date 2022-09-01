
#variables
lbfeip1=$1
lbfeip2=$2

# Netplan to add loopback ips
cat <<EOF > /etc/netplan/01-network-manager-all.yaml
network:
    version: 2
    renderer: networkd
    ethernets:
        lo:
            addresses: [ "127.0.0.1/8", "::1/128", "$lbfeip1", "$lbfeip2" ]
EOF
# Apply netplan 
netplan apply