#!/bin/sh

#variables
lbfeip1=$1
lbfeip2=$2

# Enable IPv4 and IPv6 forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sed -i "/net.ipv4.ip_forward=1/ s/# *//" /etc/sysctl.conf
sed -i "/net.ipv6.conf.all.forwarding=1/ s/# *//" /etc/sysctl.conf

echo "Installing IPTables-Persistent"
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
apt-get -y install iptables-persistent

# Enable NAT to Internet
iptables -t nat -A POSTROUTING -d 10.0.0.0/8 -j ACCEPT
iptables -t nat -A POSTROUTING -d 172.16.0.0/12 -j ACCEPT
iptables -t nat -A POSTROUTING -d 192.168.0.0/16 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Allow NVA only 
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i eth0 -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -i eth0 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth0 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i eth0 -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -i eth0 -p tcp --dport 5201 -j ACCEPT
iptables -A FORWARD -i eth0 -p icmp --icmp-type echo-request -j ACCEPT
iptables -A FORWARD -i eth0 -p icmp --icmp-type echo-reply -j ACCEPT
iptables -A FORWARD -j DROP

# Save to IPTables file for persistence on reboot
iptables-save > /etc/iptables/rules.v4

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
