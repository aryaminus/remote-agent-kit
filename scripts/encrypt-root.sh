#!/usr/bin/env bash
# encrypt-root.sh — run AS ROOT IN HETZNER RESCUE to put an existing box's
# root filesystem on LUKS2. Converts the plain ext4 root (<disk>1) into:
#   <disk>1 = 1 GiB ext4 /boot (unencrypted — GRUB must read the kernel)
#   <disk>2 = LUKS2 (argon2id) → /dev/mapper/cryptroot → ext4 /
# <disk>14 (BIOS boot) and <disk>15 (EFI) — the Hetzner Ubuntu layout — are left untouched.
# Data round-trips through an attached Hetzner Volume (VOL).
# In rescue the disk order can SWAP (the server disk may be sdb and the
# volume sda) — check /dev/disk/by-id, then pass everything explicitly:
#   DISK=/dev/sdX VOL=/dev/disk/by-id/scsi-0HC_Volume_<id> \
#   OLD_UUID=$(blkid -o value -s UUID /dev/sdX1) \
#   P1_START=<start sector of partition 1 from: sgdisk -p /dev/sdX> \
#   ./encrypt-root.sh copy
# Prereqs on the live box BEFORE rescue: cryptsetup-initramfs, dropbear-initramfs,
# /etc/dropbear/initramfs/authorized_keys, and IP=:::::<nic>:dhcp in
# initramfs.conf where <nic> is the EARLY-BOOT name (udevadm info
# /sys/class/net/eth0 | grep ID_NET_NAME_PATH, e.g. enp1s0), NOT eth0.
# Afterwards: delete the volume and the pre-encryption snapshot — both are
# unencrypted copies of the disk.
#
# Stages (each idempotent-ish, re-run a failed one):
#   ./encrypt-root.sh copy       # sda1 → volume (old disk untouched)
#   ./encrypt-root.sh encrypt    # repartition + luksFormat (YOU type the passphrase)
#   ./encrypt-root.sh restore    # volume → encrypted root, fstab/crypttab/grub/initramfs
set -euo pipefail

DISK=${DISK:?set DISK=/dev/sdX (the server disk)}
VOL=${VOL:?set VOL=/dev/disk/by-id/scsi-0HC_Volume_<id>}
OLD_UUID=${OLD_UUID:?set OLD_UUID to the current root fs UUID (blkid <disk>1)}
P1_START=${P1_START:?set P1_START to partition 1 start sector (sgdisk -p <disk>)}
P1_SIZE=+1G
OLD=/mnt/old VOLMNT=/mnt/vol NEW=/mnt/new

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root (rescue system)"
grep -q "^${DISK}" /proc/mounts && [[ "${1:-}" == copy ]] && die "$DISK is mounted — are you in rescue?"
for t in sgdisk rsync cryptsetup partprobe; do command -v $t >/dev/null || apt-get install -y gdisk rsync cryptsetup parted; done
[[ -b $VOL ]] || die "no volume at $VOL (attach the Hetzner volume, check lsblk)"

copy() {
  [[ "$(blkid -o value -s UUID ${DISK}1)" == "$OLD_UUID" ]] || die "sda1 is not the expected plain root — already converted?"
  if ! blkid -o value -s LABEL "$VOL" 2>/dev/null | grep -qx migrate; then
    mkfs.ext4 -F -L migrate "$VOL"
  fi
  mkdir -p $OLD $VOLMNT
  mountpoint -q $OLD || mount -o ro ${DISK}1 $OLD
  mountpoint -q $VOLMNT || mount "$VOL" $VOLMNT
  rsync -aHAXx --numeric-ids --delete --info=progress2 $OLD/ $VOLMNT/root/
  # verify: a second dry-run must find nothing left to transfer
  local diff; diff=$(rsync -aHAXxn --numeric-ids --delete --itemize-changes $OLD/ $VOLMNT/root/ | wc -l)
  [[ $diff -eq 0 ]] || die "verification found $diff differing entries — re-run copy"
  touch $VOLMNT/.copy-complete
  umount $OLD
  echo "COPY OK: $(du -sh $VOLMNT/root | cut -f1) on volume. Next: ./encrypt-root.sh encrypt"
}

encrypt() {
  mkdir -p $VOLMNT; mountpoint -q $VOLMNT || mount "$VOL" $VOLMNT
  [[ -f $VOLMNT/.copy-complete ]] || die "copy not verified — refusing to wipe sda1"
  grep -q "^${DISK}1 " /proc/mounts && umount ${DISK}1
  if ! cryptsetup isLuks ${DISK}2 2>/dev/null; then
    sgdisk -d 1 -n 1:${P1_START}:${P1_SIZE} -t 1:8300 -c 1:boot \
                -n 2:0:0 -t 2:8309 -c 2:cryptroot $DISK
    partprobe $DISK; udevadm settle; sleep 2
    mkfs.ext4 -F -L boot ${DISK}1
    echo; echo ">>> Choose the disk passphrase now. Type YES (capitals) to confirm. Store it in your password manager."
    cryptsetup luksFormat --type luks2 --pbkdf argon2id --label cryptroot ${DISK}2
  fi
  [[ -b /dev/mapper/cryptroot ]] || cryptsetup open ${DISK}2 cryptroot
  blkid /dev/mapper/cryptroot | grep -q ext4 || mkfs.ext4 -L root /dev/mapper/cryptroot
  echo "ENCRYPT OK. Next: ./encrypt-root.sh restore"
}

restore() {
  mkdir -p $VOLMNT $NEW; mountpoint -q $VOLMNT || mount "$VOL" $VOLMNT
  [[ -b /dev/mapper/cryptroot ]] || cryptsetup open ${DISK}2 cryptroot
  mountpoint -q $NEW || mount /dev/mapper/cryptroot $NEW
  mkdir -p $NEW/boot; mountpoint -q $NEW/boot || mount ${DISK}1 $NEW/boot
  rsync -aHAXx --numeric-ids --delete --exclude=/lost+found --exclude=/boot/lost+found \
        --info=progress2 $VOLMNT/root/ $NEW/
  mkdir -p $NEW/boot/efi; mountpoint -q $NEW/boot/efi || mount ${DISK}15 $NEW/boot/efi

  local LUKS_UUID BOOT_UUID
  LUKS_UUID=$(blkid -o value -s UUID ${DISK}2)
  BOOT_UUID=$(blkid -o value -s UUID ${DISK}1)
  # fstab: root → mapper, add /boot
  sed -i "s|^/dev/disk/by-uuid/${OLD_UUID} .*|/dev/mapper/cryptroot / ext4 defaults 0 1|" $NEW/etc/fstab
  grep -q " /boot ext4" $NEW/etc/fstab || echo "UUID=${BOOT_UUID} /boot ext4 defaults 0 2" >> $NEW/etc/fstab
  echo "cryptroot UUID=${LUKS_UUID} none luks,discard,initramfs" > $NEW/etc/crypttab
  # unlock prompt on the Hetzner web console (tty1 must be the LAST console=)
  sed -i 's|console=tty1 console=ttyS0|console=ttyS0 console=tty1|' $NEW/etc/default/grub
  sed -i 's|^GRUB_TIMEOUT=0|GRUB_TIMEOUT=2|' $NEW/etc/default/grub

  for d in dev dev/pts proc sys run; do mountpoint -q $NEW/$d || mount --bind /$d $NEW/$d; done
  chroot $NEW /usr/bin/env DISK="$DISK" /bin/bash -euc '
    update-initramfs -u -k all
    grub-install "$DISK"
    update-grub
    lsinitramfs /boot/initrd.img | grep -q "sbin/cryptsetup" || { echo "initramfs lacks cryptsetup"; exit 1; }
    lsinitramfs /boot/initrd.img | grep -q "dropbear" || { echo "initramfs lacks dropbear"; exit 1; }
    ROOTFS=$(blkid -o value -s UUID /dev/mapper/cryptroot); grep -q "root=UUID=${ROOTFS}" /boot/grub/grub.cfg || { echo "grub.cfg does not boot cryptroot"; exit 1; }
  '
  echo "--- fstab"; cat $NEW/etc/fstab; echo "--- crypttab"; cat $NEW/etc/crypttab
  sync; umount -l $NEW/run 2>/dev/null || true   # /run bind drags nested mounts along
  umount -R $NEW; cryptsetup close cryptroot; umount $VOLMNT
  echo "RESTORE OK. Rescue is one-boot only: reboot, then from your laptop: make unlock"
}

case "${1:-}" in
  copy) copy ;; encrypt) encrypt ;; restore) restore ;;
  *) echo "usage: $0 copy|encrypt|restore"; exit 2 ;;
esac
