# LB FE IP1 -> Loop1
ip link add name loop1 type dummy
ip link set loop1 up
ip addr add 10.0.20.7/32 dev loop1

# LB FE IP2 -> Loop2
ip link add name loop2 type dummy
ip link set loop2 up
ip addr add 10.0.20.8/32 dev loop2