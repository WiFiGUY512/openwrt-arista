#!/bin/bash
# Check a c360-make-stick image with tools that did not make it: xz, sfdisk,
# fsck.fat, mtools, and the Linux vfat driver (WSL or Linux; needs sudo for
# losetup and mount, and dosfstools + mtools).
#   verify-stick-img.sh <img> <artifacts dir>
set -u
IMG=$1 ART=$2
T=/tmp/c360img.$$
fail=0
ck() { if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }

echo "== xz"
ck "xz -t" "xz -t '$IMG.xz'"
xz -dc "$IMG.xz" > $T.img
a=$(sha256sum < $T.img | cut -d' ' -f1)
ck ".xz decompresses to the .img's checksum" "[ '$a' = '$(cut -d' ' -f1 "$IMG.sha256")' ]"
ck ".img on disk matches its .sha256" "[ \"\$(sha256sum < '$IMG' | cut -d' ' -f1)\" = '$a' ]"

echo "== partition table"
sfdisk -d $T.img 2>/dev/null | grep -E "start|label" | sed 's/^/  /'
ck "one partition at 2048, type c" "sfdisk -d $T.img 2>/dev/null | grep -q 'start=        2048,.*type=c'"

echo "== fsck.fat (read-only)"
LOOP=$(sudo -n losetup -f --show -o $((2048 * 512)) $T.img)
sudo -n fsck.fat -n -V -v $LOOP > $T.fsck 2>&1; rc=$?
sed 's/^/  /' $T.fsck | head -30
ck "fsck.fat exit 0 and no corrections" "[ $rc = 0 ] && ! grep -qiE 'wrong|differ|corrupt|invalid|lost|leaving|perform changes' $T.fsck"

echo "== mtools"
mdir -i $T.img@@1M -/ :: 2>&1 | sed 's/^/  /'
for f in initramfs.itb factory.ubi; do
	src=$(ls $ART/*arista_c360-*${f##*.} | grep -E "initramfs-uImage.itb|squashfs-factory.ubi" | grep "${f%%.*}" | head -1)
	[ "$f" = initramfs.itb ] && src=$(ls $ART/*initramfs-uImage.itb)
	[ "$f" = factory.ubi ] && src=$(ls $ART/*squashfs-factory.ubi)
	ck "mtools reads c360/$f identical to $(basename $src)" "[ \"\$(mtype -i $T.img@@1M ::c360/$f | sha256sum)\" = \"\$(sha256sum < $src)\" ]"
done
ck "mtools: volume label C360OPENWRT" "mlabel -i $T.img@@1M -s :: | grep -q C360OPENWRT"

echo "== Linux vfat mount (read-only)"
mkdir -p $T.mnt
sudo -n mount -t vfat -o ro $LOOP $T.mnt
ls -la $T.mnt $T.mnt/c360 | sed 's/^/  /'
ck "kernel mount: initramfs.itb identical" "cmp -s $T.mnt/c360/initramfs.itb $ART/*initramfs-uImage.itb"
ck "kernel mount: factory.ubi identical" "cmp -s $T.mnt/c360/factory.ubi $ART/*squashfs-factory.ubi"
ck "SHA256SUMS: factory.ubi line matches" "(cd $T.mnt/c360 && grep -E '  (factory.ubi|initramfs.itb)\$' SHA256SUMS | sha256sum -c --quiet)"
df -k $T.mnt | sed 's/^/  /'
sudo -n umount $T.mnt

echo "== writable: what the installer does (a backup directory, a gzip, fsck again)"
sudo -n mount -t vfat -o rw $LOOP $T.mnt
sudo -n mkdir $T.mnt/c360/backup-30862d0317ff-20261007-200000
head -c 33554432 /dev/urandom | sudo -n tee $T.mnt/c360/backup-30862d0317ff-20261007-200000/mtd0-test.bin.gz > /dev/null
sudo -n umount $T.mnt
sudo -n fsck.fat -n $LOOP > $T.fsck2 2>&1; rc=$?
ck "after writing 32 MiB through the kernel, fsck.fat still clean" "[ $rc = 0 ]"
sudo -n losetup -d $LOOP
rm -rf $T.img $T.mnt $T.fsck $T.fsck2
[ $fail = 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
