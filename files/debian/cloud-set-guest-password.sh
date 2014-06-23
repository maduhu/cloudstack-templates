#!/bin/bash
#
# Init file for Password Download Client
#
# chkconfig: 345 98 02
# description: Password Download Client

# Modify this line to specify the user (default is root)
user=root
# Add your DHCP lease file here
DHCP_FILES="/var/lib/dhcp/dhclient.eth0.leases"

for DHCP_FILE in $DHCP_FILES
do
	if [ -f $DHCP_FILE ]
	then
		DOMR_IP=$(grep dhcp-server-identifier $DHCP_FILE | tail -1 | awk '{print $NF}' | tr -d '\;')
		break;
	fi
done

password=$(wget -t 3 -T 20 -O - --header "DomU_Request: send_my_password" $DOMR_IP:8080)

if [ $? -ne 0 ]
then
	exit 1
fi

password=$(echo $password | tr -d '\r')

if [ -n "$password" ] && [ "$password" != "bad_request" ] && [ "$password" != "saved_password" ]
then
	echo "$user:$password" | chpasswd
	if [ $? -gt 0 ]
	then
		usermod -p `mkpasswd $password 42` $user
		if [ $? -gt 0 ]
		then
			exit 1
		fi
	fi
	wget -t 3 -T 20 -O - --header "DomU_Request: saved_password" $DOMR_IP:8080
fi

exit 0