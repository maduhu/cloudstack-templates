#!/bin/bash

which faketime >/dev/null 2>&1 && which vhd-util >/dev/null 2>&1
if [ $? == 0 ]; then
  set -e
  cd output-virtualbox-iso
  vboxmanage internalcommands converttoraw -format vmdk packer-virtualbox-iso-disk1.vmdk img.raw
  vhd-util convert -s 0 -t 1 -i img.raw -o stagefixed.vhd
  faketime '2010-01-01' vhd-util convert -s 1 -t 2 -i stagefixed.vhd -o debian-wheezy-xen.vhd
  rm *.bak
  bzip2 debian-wheezy-xen.vhd
  echo "$appliance exported for XenServer: dist/$appliance-$branch-xen.vhd.bz2"
else
  echo "** Skipping $appliance export for XenServer: faketime or vhd-util command is missing. **"
  echo "** faketime source code is available from https://github.com/wolfcw/libfaketime **"
fi

