#!/bin/bash
# arg1 should be Floating IP address and arg2 mac address of vm public NIC
# attach-floating.ip.sh 198.51.100.1 ff:11:aa:22:bb:66
ip=$1
interface=eth0
mac=$2
data="{\"ip_address\" : {\"mac\" : \"$mac\"}}"
# API command to transfer the floating IP
curl -u "$UPCLOUD_USERNAME:$UPCLOUD_PASSWORD" -X PATCH -H Content-Type:application/json https://api.upcloud.com/1.3/ip_address/$ip --data-binary "$data"

