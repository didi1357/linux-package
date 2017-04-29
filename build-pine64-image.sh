#!/bin/sh
#
# This scripts takes a simpleimage and a kernel tarball, resizes the
# secondary partition and creates a rootfs inside it. Then extracts the
# Kernel tarball on top of it, resulting in a full Pine64 disk image.
#
# Latest stuff can be found at the following locations:
# -  https://www.stdin.xyz/downloads/people/longsleep/pine64-images/simpleimage-pine64-latest.img.xz
# -  https://www.stdin.xyz/downloads/people/longsleep/pine64-images/linux/linux-pine64-latest.tar.xz"

SIMPLEIMAGE="$1"
KERNELTAR="$2"
DISTRO="$3"
COUNT="$4"
if [[ -z "$MODEL" ]]; then
  MODEL="pine64"
fi
export MODEL

if [ -z "$SIMPLEIMAGE" -o -z "$KERNELTAR" ]; then
	echo "Usage: $0 <simpleimage.img.xz> <kernel.tar.xz> [distro] [count]"
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

if [ -z "$DISTRO" ]; then
	DISTRO="xenial"
fi

if [ -z "$COUNT" ]; then
	COUNT=1
fi

SIMPLEIMAGE=$(readlink -f "$SIMPLEIMAGE")
KERNELTAR=$(readlink -f "$KERNELTAR")

SIZE=7300 # MiB
if [[ -z "$DATE" ]]; then
  DATE=$(date +%Y%m%H)
fi

PWD=$(readlink -f .)
TEMP=$(mktemp -p $PWD -d -t "$MODEL-build-XXXXXXXXXX")
IMAGE="$DISTRO-$MODEL-bspkernel-$DATE-$COUNT.img"
echo "> Building in $TEMP ..."

cleanup() {
    local arg=$?
    echo "> Cleaning up ..."
    umount "$TEMP/boot" || true
    umount $TEMP/rootfs/* || true
    umount "$TEMP/rootfs" || true
    kpartx -sd "$TEMP/$IMAGE" || true
    kpartx -sd "$IMAGE" || true
    rmdir "$TEMP/boot"
    rmdir "$TEMP/rootfs"
    rm -r "$TEMP"
    exit $arg
}
trap cleanup EXIT

set -ex

# Unpack
unxz -k --stdout "$SIMPLEIMAGE" > "$TEMP/$IMAGE"
# Enlarge
dd if=/dev/zero bs=1M seek=$(($SIZE-1)) count=1 of="$TEMP/$IMAGE"
# Resize
echo ", +" | sfdisk -N 2 "$TEMP/$IMAGE"

# Device
mkdir "$TEMP/boot"
mkdir "$TEMP/rootfs"
DEVICE=$(losetup --show --find "$TEMP/$IMAGE")
DEVICENAME=$(basename $DEVICE)
echo "> Device is $DEVICE ..."
kpartx -avs $DEVICE

# Resize filesystem
resize2fs /dev/mapper/${DEVICENAME}p2 || true

# Mount
mount /dev/mapper/${DEVICENAME}p1 "$TEMP/boot"
mount /dev/mapper/${DEVICENAME}p2 "$TEMP/rootfs"

sleep 2
(cd simpleimage && sh ./make_rootfs.sh "$TEMP/rootfs" "$KERNELTAR" "$DISTRO" "$TEMP/boot")

mv -v "$TEMP/$IMAGE" .

fstrim "$TEMP/rootfs"
