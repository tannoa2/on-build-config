#!/bin/bash +xe
set -e
set -x
vagrant global-status --prune
PACKERDIR="$WORKSPACE/build/packer/"
#BOX="$PACKERDIR/rackhd-${OS_VER}-$RACKHD_VERSION.box"
# to avoid File name too long ................ (Errno::ENAMETOOLONG)
#$BOX is a shorter path, to make vagrant happy
BOX="${WORKSPACE}/rackhd-${OS_VER}-${RACKHD_VERSION}.box"
rm $BOX -f # if previous link exists
ln -s "$PACKERDIR/rackhd-${OS_VER}-$RACKHD_VERSION.box"  $BOX

bash ./build-config/build-release-tools/post_test.sh \
--type vagrant \
--boxFile $BOX \
--controlNetwork vmnet1 \
--vagrantfile build-config/build-release-tools/Vagrantfile.in \
--rackhdVersion $RACKHD_VERSION
