#!/bin/bash

#
#	Script uses Linux Bridge to create an IPv6-only bridge on OpenWRT 15.05
#
#	(Inside LAN)----->eth0.1 (br0) eth1----->(Outside LAN)
#					 (   brouter    )
#
#	Adapted from http://ebtables.netfilter.org/examples/basic.html#ex_brouter
#
#	Sets up Brouter ports eth0 & eth1
#		forwards IPv4 traffic via NAT from interfaces eth0.1 to eth1
#		bridges IPv6 traffic between eth0.1 and eth1
#
#	Requires: ebtables
#
#	Adapted from v6brouter.sh (for generic linux IPv6 brouter)
#
#
#	Craig Miller 16 February 2016

# BRouter interfaces
# 	INSIDE: is the RFC 1918 Private address
# 	OUTSIDE: is the public IP address
#	BRIDGE: is name of the bridge to create

# change these to match your interfaces
INSIDE=eth0.1
OUTSIDE=eth1
BRIDGE=br-lan

# IPv6 Management address
BRIDGE_IP6=2001:470:1d:583::11

# not used for OpenWRT
# change IPv4 address to match your IPv4 networks
INSIDE_IP=192.168.11.1
OUTSIDE_IP=10.1.1.177

# script version
VERSION=0.92

# get arg from CLI
arg=$1

if [ "$arg" == '-h' ]; then
	# show help
	echo "	$0 - sets up brouter to NAT IPv4, and bridge IPv6"
	echo "	-D    delete brouter, v6bridge, IPv4 NAT config"
	echo "	-R    restore openwrt bridge config"
	echo "	-h    this help"
	echo "  "
	echo " By Craig Miller - Version: $VERSION"
	exit 1
fi

CLEANUP=0
if [ "$arg" == "-D" ]; then
	# delete config
	CLEANUP=1
fi

RESTORE=0
if [ "$arg" == "-R" ]; then
	# delete config
	RESTORE=1
fi

echo "--- checking for ebtables"
which ebtables
ERR=$?
if (( $ERR == 1 ));then
	echo "ebtables not found, please install, quitting"
	exit 1
fi

# remove previous bridge
old_bridge=$(brctl show | grep $BRIDGE | cut -f 1)
if [ "$old_bridge" == "$BRIDGE" ] && [ $RESTORE -eq 0 ]; then
	echo "-- delete old bridge:$BRIDGE"
	brctl delif $BRIDGE $INSIDE 2> /dev/null
	brctl delif $BRIDGE $OUTSIDE 2> /dev/null
	ip link set $BRIDGE down 2> /dev/null
	brctl delbr $BRIDGE 2> /dev/null
	brctl show
	# remove config
	# remove IPv6 management address to bridge
	ip addr del  $BRIDGE_IP6/64 dev $BRIDGE	
fi

#restore openwrt default bridge, br-lan
if (( $RESTORE == 1 )); then
	echo "-- Restore old bridge:$BRIDGE"
	#brctl delif $BRIDGE $INSIDE 2> /dev/null
	brctl delif $BRIDGE $OUTSIDE 2> /dev/null
	ip link set $BRIDGE down 2> /dev/null
	#brctl delbr $BRIDGE 2> /dev/null
	brctl show

	# remove IPv6 management address to bridge
	ip addr del  $BRIDGE_IP6/64 dev $BRIDGE	2> /dev/null
	# restore original inside management address
	ip addr del  $INSIDE_IP/24 dev $INSIDE
	ifconfig $BRIDGE 0.0.0.0
	ip addr add  $INSIDE_IP/24 dev $BRIDGE
fi


if (( $CLEANUP == 1 )) || (( $RESTORE == 1 )); then
	# flush ebtables
	ebtables -F
	ebtables -t broute -F
	ebtables -P FORWARD ACCEPT
	echo "--- cleanup done"
	exit 0
fi

echo "--- configuring v6 bridge"
# add the bridge
brctl addbr $BRIDGE 2> /dev/null
brctl addif $BRIDGE $INSIDE 2> /dev/null
brctl addif $BRIDGE $OUTSIDE
ip link set $BRIDGE down
ip link set $BRIDGE up

brctl show $BRIDGE

# configure ebtables to bridge IPv6-only
ebtables -F
ebtables -A FORWARD -p IPV6 -j ACCEPT
ebtables -P FORWARD DROP
ebtables -L

#---- detect mac addresses
INSIDE_MAC=$(ip link show dev $INSIDE | grep link | cut -d " " -f 6)
OUTSIDE_MAC=$(ip link show dev $OUTSIDE | grep link | cut -d " " -f 6)

echo "--- assigning IPv6 management address $BRIDGE_IP6 to $BRIDGE"
# add IPv6/IPv4 management address to bridge
ip addr add  $BRIDGE_IP6/64 dev $BRIDGE

# add static IPv4 addresses to interfaces
ifconfig $BRIDGE 0.0.0.0
ifconfig $INSIDE $INSIDE_IP netmask 255.255.255.0
ifconfig $OUTSIDE $OUTSIDE_IP netmask 255.255.255.0

echo "--- configuring brouter ipv4 interface tables"
# broute table DROP, means forward to higher level stack
ebtables -t broute -F

#ebtables -t broute -A BROUTING -p ipv4 -i $INSIDE --ip-dst $INSIDE_IP -j DROP
#ebtables -t broute -A BROUTING -p ipv4 -i $OUTSIDE --ip-dst $OUTSIDE_IP -j DROP
ebtables -t broute -A BROUTING -p arp -i $INSIDE -d $INSIDE_MAC -j DROP
ebtables -t broute -A BROUTING -p arp -i $OUTSIDE -d $OUTSIDE_MAC -j DROP
#ebtables -t broute -A BROUTING -p arp -i $INSIDE --arp-ip-dst $INSIDE_IP -j DROP
#ebtables -t broute -A BROUTING -p arp -i $OUTSIDE --arp-ip-dst $OUTSIDE_IP -j DROP

# setup for router - accept all ipv4 packets with our MAC address
ebtables -t broute -A BROUTING -p ipv4 -i $INSIDE -d $INSIDE_MAC -j DROP
ebtables -t broute -A BROUTING -p ipv4 -i $OUTSIDE -d $OUTSIDE_MAC -j DROP

# allow DHCP request to go to stack
ebtables -t broute -A BROUTING -p ipv4 -i $INSIDE -d ff:ff:ff:ff:ff:ff  -j DROP


# show tables
ebtables -t broute -L

# NAT configuration (via iptables) remains unchanged


echo "--- pau"

