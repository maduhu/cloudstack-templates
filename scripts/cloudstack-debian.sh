#!/bin/bash
. /tmp/common.sh
set -x

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

debconf-set-selections <<< "libssl1.0.0 libssl1.0.0/restart-services string ssh ntp exim4"
debconf-set-selections <<< "libssl1.0.0:amd64 libssl1.0.0/restart-services string ssh ntp exim4"

debconf-set-selections <<< "libssl1.0.0 libssl1.0.0/restart-failed error"
debconf-set-selections <<< "libssl1.0.0:amd64 libssl1.0.0/restart-failed error"

echo 'deb http://ftp.uk.debian.org/debian wheezy-backports main' >> /etc/apt/sources.list

# Remove isc-dhcp-client as it does not work properly with this right now,
# it will be replaced with pump for the time being
$apt update
$apt remove isc-dhcp-client
$apt install pump cloud-utils cloud-init cloud-initramfs-growroot bash-completion

# use our specific config
mv -f /tmp/cloud.cfg /etc/cloud/cloud.cfg
# remove distro installed package to ensure Cloudstack is only enabled
rm -f /etc/cloud/cloud.cfg.d/90_*

$apt install sudo rsync curl less

# enable hvc0

cat >> /etc/inittab << EOF
vc:2345:respawn:/sbin/getty 38400 hvc0
EOF

# Remove 5s grub timeout to speed up booting
cat <<EOF > /etc/default/grub
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.

GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="debian-installer=en_US"
EOF

update-grub

# Tweak sshd to prevent DNS resolution (speed up logins)
echo 'UseDNS no' >> /etc/ssh/sshd_config

# Make sure sudo works properly with cloudstack
sed -i 's/env_reset/env_reset\nDefaults\t\!requiretty/' /etc/sudoers

# Fix networking to auto bring up eth0 and work correctly with cloud-init
sed -i 's/allow-hotplug eth0/auto eth0/' /etc/network/interfaces

echo "" > /etc/apt/apt.conf

$apt autoremove
$apt autoclean
$apt clean