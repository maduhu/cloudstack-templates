#!/bin/bash 
#
# Init file for SSH Public Keys Download Client
#
### BEGIN INIT INFO
# Provides:             cloud-set-guest-sshkey
# Required-Start:       $local_fs $syslog $network
# Required-Stop:        $local_fs $syslog $network
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    SSH Public Keys Download Client
### END INIT INFO

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

password=$(wget -t 3 -T 5 -O - --header "DomU_Request: send_my_password" $DOMR_IP:8080)

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
