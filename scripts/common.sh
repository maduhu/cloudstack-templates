#!/bin/bash
export PATH="/bin/:/usr/sbin:/usr/bin:/sbin:${PATH}"
apt="apt-get -qq -y"
yum="yum -q -y"

set -x

fail()
{
    echo "FATAL: $*"
    exit 1
}

if [ -x /usr/bin/lsb_release ] ; then
    OS="$(lsb_release -s -i | tr '[A-Z]' '[a-z]')"
    if [ "$OS" = "centos" ] ; then
        OSRELEASE="$(lsb_release -s -r | sed -e 's/\..*//')"
        run_cmd=""
        rootfs=""
    else
        OSRELEASE="$(lsb_release -s -c)"
    fi
elif [ -f /etc/redhat-release ] ; then
    OSRELEASE="$(awk '{print $3}' /etc/redhat-release | sed -e 's/\..*//')"
    OS="$(awk '{print tolower($1)}' /etc/redhat-release)"
    run_cmd=""
    rootfs=""
fi
