#Reference: https://ixnfo.com/en/creating-dummy-interfaces-on-linux.html
# https://www.questioncomputer.com/loopback-adapter-on-ubuntu-18-04-like-on-cisco/
# LB FE IP1 -> Loop1
ip link add name loop1 type dummy
ip link set loop1 up
ip addr add 10.0.20.7/32 dev loop1

# LB FE IP2 -> Loop2
ip link add name loop2 type dummy
ip link set loop2 up
ip addr add 10.0.20.8/32 dev loop2

#Check
sudo lsmod | grep dummy

# IPTables
#https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands


sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT

sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT

sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 80 -m conntrack --ctstate ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -j DROP

# Loopbacks
sudo iptables -A INPUT -i loop1 -j ACCEPT
sudo iptables -A OUTPUT -o loop1 -j ACCEPT

sudo iptables -A INPUT -i loop2 -j ACCEPT
sudo iptables -A OUTPUT -o loop2 -j ACCEPT

# Display
iptables -L --line-numbers
sudo iptables -S
sudo iptables -L -v

# Allow rule 80:
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

sudo iptables -A OUTPUT -p tcp --sport 80 -j ACCEPT

# Drop Rule -> Check this: https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-iptables-on-ubuntu-14-04
sudo iptables -A INPUT -j DROP

sudo iptables -P INPUT DROP # Default Drop rule
sudo iptables -P INPUT ACCEPT

sudo iptables -I INPUT 4 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

sudo iptables -I INPUT 4 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Logging
sudo iptables -I INPUT 6 -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7
# https://help.ubuntu.com/community/IptablesHowTo


sudo iptables -A INPUT -i lo -j ACCEPT

sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 

### Working
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -j DROP
sudo iptables -L -v --line-numbers
iptables -L -v

# Insert loopback first rule
sudo iptables -I INPUT 1 -i lo -j ACCEPT

#  Delete
sudo iptables -A INPUT -j DROP
# Delete NAt rules
iptables -t nat -D POSTROUTING {number-here}

#Forward as router 
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -p tcp --dport 80 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -p tcp --dport 443 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -p tcp --dport 5201 -j ACCEPT
sudo iptables -A FORWARD -j DROP

# Delete Fowarder


# Change Policy for Forwarder:



# Reference Linux as Route/Firewall IP Tables: https://freelinuxtutorials.com/linux-as-a-router-and-firewall/

# output:

azureuser@az-hub-linux-nva1:~$ sudo iptables -L -v
Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
  980  146K ACCEPT     all  --  lo     any     anywhere             anywhere            
18820  180M ACCEPT     all  --  any    any     anywhere             anywhere             ctstate RELATED,ESTABLISHED
   10   600 ACCEPT     tcp  --  any    any     anywhere             anywhere             tcp dpt:http
  400 21308 DROP       all  --  any    any     anywhere             anywhere            

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
  225 90450 ACCEPT     all  --  any    any     anywhere             anywhere             ctstate RELATED,ESTABLISHED
    1    60 ACCEPT     tcp  --  eth0   any     anywhere             anywhere             tcp dpt:http
  776 46720 DROP       all  --  any    any     anywhere             anywhere            

Chain OUTPUT (policy ACCEPT 48 packets, 7534 bytes)
 pkts bytes target     prot opt in     out     source               destination         
 5536 3095K ACCEPT     all  --  any    eth0    anywhere             anywhere   