#!/bin/sh

set -e

# Parse input parameters
usage() {
	echo "Usage: $0 --release|-r <jessie|wheezy> [options]
Options are:
 --minimal|-m
 --debootstrap-url|-u <debootstrap-mirror> (default: http://http.debian.net/debian)
 --sources.list-mirror|-s <source-list-mirror> (default: http://http.debian.net/debian)
 --extra-packages|-e <package>,<package>,...
 --hook-script|-hs <hook-script>
 --image-size|-is <image-size> (default: 1G)
 --automatic-resize|-ar
 --automatic-resize-space|-ars <suplementary-space> (default: 50M)
 --password|-p <root-password> (dangerous option: avoid it if possible)
For more info: man $0"
	exit 1
}

EXTRA=yes
for i in $@ ; do
	case "${1}" in
	"--extra-packages"|"-e")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the extra packages"
			usage
		fi
		EXTRA_PACKAGES=${2}
		shift
		shift
	;;
	"--debootstrap-url"|"-u")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the debootstrap URL"
			usage
		fi
		DEB_MIRROR=${2}
		shift
		shift
	;;
	"--minimal"|"-m")
		EXTRA=no
		shift
	;;
	"--automatic-resize"|"-ar")
		AUTOMATIC_RESIZE=yes
		shift
	;;
	"--automatic-resize-space"|"-ars")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the suplementary space"
			usage
		fi
		AUTOMATIC_RESIZE_SPACE=${2}
		shift
		shift
	;;
	"--image-size"|"-is")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the image size"
			usage
		fi
		IMAGE_SIZE=${2}
		shift
		shift
	;;
	"--hook-script"|"-hs")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the hook script"
			usage
		fi
		if ! [ -x "${2}" ] ; then
			echo "Hook script not executable"
		fi
		HOOK_SCRIPT=${2}
		shift
		shift
	;;
	"--sources.list-mirror"|"-s")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the hook script"
			usage
		fi
		SOURCE_LIST_MIRROR=${2}
		shift
		shift
	;;
	"--release"|"-r")
		if [ "${2}" = "wheezy" ] || [ "${2}" = "jessie" ] ; then
			RELEASE=${2}
			shift
			shift
		else
			echo "Release not recognized."
			usage
		fi
	;;
	"--password"|"-p")
		if [ -z "${2}" ] ; then
			echo "No parameter defining the root password"
		fi
		ROOT_PASSWORD=${2}
		shift
		shift
	;;
	*)
	;;
	esac
done

if [ -z "${RELEASE}" ] ; then
	echo "Release not recognized: please specify the -r parameter."
	usage
fi
if [ -z "${DEB_MIRROR}" ] ; then
	DEB_MIRROR=http://http.debian.net/debian
fi
if [ -z "${EXTRA_PACKAGES}" ] ; then
	EXTRA_PACKAGES=bash-completion,joe,most,screen,less,vim,bzip2
fi
if [ -z "${SOURCE_LIST_MIRROR}" ] ; then
	SOURCE_LIST_MIRROR=http://http.debian.net/debian
fi
if [ -z "${IMAGE_SIZE}" ] ; then
	IMAGE_SIZE=1
fi
if [ -z "${AUTOMATIC_RESIZE_SPACE}" ] ; then
	AUTOMATIC_RESIZE_SPACE=50
fi

NEEDED_PACKAGES=sudo,adduser,extlinux,openssh-server,linux-image-amd64,euca2ools,file,kbd
if [ "${RELEASE}" = "jessie" ] ; then
	NEEDED_PACKAGES=${NEEDED_PACKAGES},cloud-init,cloud-utils,cloud-initramfs-growroot
else
	# These are needed by cloud-init and friends, and since we don't want backports of them,
	# but just normal packages from Wheezy, we resolve dependencies by hand, prior to using
	# apt-get -t wheezy-backports install cloud-init cloud-utils cloud-initramfs-growroot
	NEEDED_PACKAGES=${NEEDED_PACKAGES},python,python-paramiko,python-argparse,python-cheetah,python-configobj,python-oauth,python-software-properties,python-yaml,python-boto,python-prettytable,initramfs-tools,python-requests
fi

if [ ${EXTRA} = "no" ] ; then
	PKG_LIST=${NEEDED_PACKAGES}
else
	PKG_LIST=${NEEDED_PACKAGES},${EXTRA_PACKAGES}
fi
if ! [ `whoami` = "root" ] ; then
	echo "You have to be root to run this script"
	exit 1
fi
FILE_NAME=debian-${RELEASE}-7.5.0-amd64
AMI_NAME=${FILE_NAME}.raw
rm -f ${AMI_NAME}

set -x

######################################
### Prepare the HDD (format, ext.) ###
######################################
PARTED=/sbin/parted
rm -f $AMI_NAME
qemu-img create ${AMI_NAME} ${IMAGE_SIZE}G

${PARTED} -s ${AMI_NAME} mktable msdos
${PARTED} -s -a optimal ${AMI_NAME} mkpart primary ext3 1Mi 100%
${PARTED} -s ${AMI_NAME} set 1 boot on
install-mbr ${AMI_NAME}
RESULT_KPARTX=`kpartx -asv ${AMI_NAME} 2>&1`

if echo "${RESULT_KPARTX}" | grep "^add map" ; then
	LOOP_DEVICE=`echo ${RESULT_KPARTX} | cut -d" " -f3`
	echo "kpartx mounted using: ${LOOP_DEVICE}"
else
	echo "It seems kpartx didn't mount the image correctly: exiting."
	exit 1
fi

mkfs.ext3 /dev/mapper/${LOOP_DEVICE}

# No fsck because of X days without checks
tune2fs -i 0 /dev/mapper/${LOOP_DEVICE}

MOUNT_DIR=`mktemp -d -t build-debimg.XXXXXX`
mount -o loop /dev/mapper/${LOOP_DEVICE} ${MOUNT_DIR}
debootstrap --verbose \
	--include=${PKG_LIST} \
	${RELEASE} ${MOUNT_DIR} ${DEB_MIRROR}

############################
### Customize the distro ###
############################
### Customize: access to the VM ###
# # # # # # # # # # # # # # # # # #
# Setup default root password to what has been set on the command line
if [ -n "${ROOT_PASSWORD}" ] ; then
	chroot ${MOUNT_DIR} sh -c "echo root:${ROOT_PASSWORD} | chpasswd"
fi

# Otherwise, we have a huge backdoor, since the root password
# is always the same.
#sed -i "s/PermitRootLogin yes/PermitRootLogin without-password/" ${MOUNT_DIR}/etc/ssh/sshd_config

### Customize: misc stuff ###
# # # # # # # # # # # # # # #
# Setup fstab
echo "# /etc/fstab: static file system information.
proc	/proc	proc	nodev,noexec,nosuid	0	0
/dev/sda1	/	ext3	errors=remount-ro	0	1
" > ${MOUNT_DIR}/etc/fstab
chroot ${MOUNT_DIR} mount /proc || true

echo "# disable pc speaker
blacklist pcspkr" >${MOUNT_DIR}/etc/modprobe.d/blacklist.conf

# Enable bash-completion by default
if [ ${EXTRA} = "yes" ] ; then
	echo "# enable bash completion in interactive shells
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi" >>${MOUNT_DIR}/etc/bash.bashrc

	# No clear for the tty1 console
	sed -i "s#1:2345:respawn:/sbin/getty 38400 tty1#1:2345:respawn:/sbin/getty --noclear 38400 tty1#" ${MOUNT_DIR}/etc/inittab
fi

# Turn off console blanking which is *very* annoying
# and increase KEYBOARD_DELAY because it can be annoying
# over network.
sed -i s/^BLANK_TIME=.*/BLANK_TIME=0/ ${MOUNT_DIR}/etc/kbd/config
sed -i s/^POWERDOWN_TIME=.*/POWERDOWN_TIME=0/ ${MOUNT_DIR}/etc/kbd/config
sed -i 's/^[ \t#]KEYBOARD_DELAY=.*/KEYBOARD_DELAY=1000/' ${MOUNT_DIR}/etc/kbd/config

rm -f ${MOUNT_DIR}/etc/ssh/ssh_host_*
rm -f ${MOUNT_DIR}/etc/udev/rules.d/70-persistent-net.rules
rm -f ${MOUNT_DIR}/lib/udev/write_net_rules


# Setup networking (eg: DHCP by default)
echo "# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The normal eth0
auto eth0
iface eth0 inet dhcp

# Maybe the VM has 2 NICs?
allow-hotplug eth1
iface eth1 inet dhcp

# Maybe the VM has 3 NICs?
allow-hotplug eth2
iface eth2 inet dhcp

pre-up sleep 5
" > ${MOUNT_DIR}/etc/network/interfaces

# Setup the default hostname (will be set by cloud-init
# at boot time anyway)
echo "debian.cloudstack.org" >${MOUNT_DIR}/etc/hostname

# This should be a correct default everywhere
echo "deb ${SOURCE_LIST_MIRROR} ${RELEASE} main
deb-src ${SOURCE_LIST_MIRROR} ${RELEASE} main" >${MOUNT_DIR}/etc/apt/sources.list

if [ "${RELEASE}" = "wheezy" ] ; then
	echo "deb ${SOURCE_LIST_MIRROR} wheezy-updates main
deb http://security.debian.org/ wheezy/updates main

deb ${SOURCE_LIST_MIRROR} wheezy-backports main
" >>${MOUNT_DIR}/etc/apt/sources.list
fi
chroot ${MOUNT_DIR} apt-get update
chroot ${MOUNT_DIR} apt-get upgrade -y

# Setup cloud-init, cloud-utils and cloud-initramfs-growroot
# These are only available from backports in Wheezy
if [ "${RELEASE}" = "wheezy" ] ; then
	chroot ${MOUNT_DIR} apt-get -t wheezy-backports install cloud-init cloud-utils cloud-initramfs-growroot -y
fi

# For OpenStack, we would like to use Ec2 and no other API
rm ${MOUNT_DIR}/etc/cloud/cloud.cfg.d/90_*
rm ${MOUNT_DIR}/etc/cloud/cloud.cfg
cp cloud.cfg ${MOUNT_DIR}/etc/cloud/cloud.cfg
cp cloud-set-guest-password.sh ${MOUNT_DIR}/etc/init.d/cloud-set-guest-password.sh
chmod 755 ${MOUNT_DIR}/etc/init.d/cloud-set-guest-password.sh
chroot ${MOUNT_DIR} insserv cloud-set-guest-password.sh

# Needed to have automatic mounts of /dev/vdb
echo "mount_default_fields: [~, ~, 'auto', 'defaults,nofail', '0', '2']" >> ${MOUNT_DIR}/etc/cloud/cloud.cfg
echo "manage_etc_hosts: true" >>${MOUNT_DIR}/etc/cloud/cloud.cfg

# Setting-up initramfs
chroot ${MOUNT_DIR} update-initramfs -u

chroot ${MOUNT_DIR} apt-get -y autoremove
chroot ${MOUNT_DIR} apt-get -y clean

KERNEL=`chroot ${MOUNT_DIR} find boot -name 'vmlinuz-*'`
RAMDISK=`chroot ${MOUNT_DIR} find boot -name 'initrd.img-*'`
UUID=`blkid -o value -s UUID /dev/mapper/${LOOP_DEVICE}`

cat << EOF > ${MOUNT_DIR}/boot/extlinux/extlinux.conf
default linux
timeout 1
label linux
kernel ${KERNEL}
append initrd=${RAMDISK} root=/dev/sda1 ro
EOF

cp ${MOUNT_DIR}/boot/extlinux/extlinux.conf ${MOUNT_DIR}/extlinux.conf
extlinux --install ${MOUNT_DIR}

zerofree -v /dev/mapper/${LOOP_DEVICE}

###################
### HOOK SCRIPT ###
###################
if [ -x ${HOOK_SCRIPT} ] ; then
	export BODI_CHROOT_PATH=${MOUNT_DIR}
	export BODI_RELEASE=${RELEASE}
	${HOOK_SCRIPT}
fi

##########################
### Unmount everything ###
##########################

chroot ${MOUNT_DIR} umount /proc || true
umount ${MOUNT_DIR}

if [ "${AUTOMATIC_RESIZE}" = "yes" ] ; then
	resize2fs -M /dev/mapper/${LOOP_DEVICE}
	FS_BLOCKS=`tune2fs -l /dev/mapper/${LOOP_DEVICE} | awk '/Block count/{print $3}'`
	WANTED_SIZE=`expr $FS_BLOCKS '*' 4 '/' 1024 + ${AUTOMATIC_RESIZE_SPACE}` # Add ${AUTOMATIC_RESIZE_SPACE}M
	resize2fs /dev/mapper/${LOOP_DEVICE} ${WANTED_SIZE}M

	FINAL_FS_BLOCKS=`tune2fs -l /dev/mapper/${LOOP_DEVICE} | awk '/Block count/{print $3}'`
	FINAL_IMG_SIZE=`expr '(' $FINAL_FS_BLOCKS + 258 ')' '*' 4 '/' 1024` # some blocks for mbr and multiple block size (4k)
fi

kpartx -d ${AMI_NAME}
rmdir ${MOUNT_DIR}

if [ "${AUTOMATIC_RESIZE}" = "yes" ] ; then
	# Rebuild a smaller partition table
	parted -s ${AMI_NAME} rm 1
	parted -s ${AMI_NAME} mkpart primary ext3 1Mi ${FINAL_IMG_SIZE}Mi
	parted -s ${AMI_NAME} set 1 boot on

	# Add 2M for the 1M at the beginning of the partition and some additionnal space 
	truncate -s `expr 3 + ${FINAL_IMG_SIZE}`M ${AMI_NAME}
	install-mbr ${AMI_NAME}
fi

mkdir -p dist/
rm -rf dist/* || true

cd dist

qemu-img convert -c -f raw ../${AMI_NAME} -O qcow2 ${FILE_NAME}-kvm.qcow2
bzip2 ${FILE_NAME}-kvm.qcow2

qemu-img convert -f raw ../${AMI_NAME} -O vmdk ${FILE_NAME}-vmware.vmdk
bzip2 ${FILE_NAME}-vmware.vmdk

qemu-img convert -f raw ../${AMI_NAME} -O vpc ${FILE_NAME}-hyperv.vhd
zip ${FILE_NAME}-hyperv.vhd.zip ${FILE_NAME}-hyperv.vhd
rm ${FILE_NAME}-hyperv.vhd

vhd-util convert -s 0 -t 1 -i ../${AMI_NAME} -o stagefixed.vhd
faketime '2010-01-01' vhd-util convert -s 1 -t 2 -i stagefixed.vhd -o ${FILE_NAME}-xen.vhd
rm *.bak
bzip2 ${FILE_NAME}-xen.vhd