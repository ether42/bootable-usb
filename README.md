Some simple and extensible scripts left here as a reminder on how to create a bootable live USB key and ISO for both BIOS and UEFI.



---

### Overview

#### Supported architectures

| Component   | Notes
|:-----------:|:------
| ISO         | Bootable as ISO & disk, under BIOS or EFI x86_64 (OS is an AMD64 Debian)
| Disk        | Bootable as disk under BIOS or EFI x86_64
| EFI shell   | Executable under EFI x86_64

Support for EFI IA32 could be easily added.


#### Debian Live ISO

As root:
```shell
[PASSWORD=root] bash [-x] debian_iso.bash [debian.iso]
```
 - `PASSWORD` is root's password

To customize the ISO creation, edit the `customization` section of [`debian_iso.bash`](debian_iso.bash).

##### Boot menu

By default, GRUB will show the following menu:
```
 ┌ Debian Live
 ├ Debian Live (ip=frommedia)
 ├ Debian Live (nopersistence)
 └ Debian Live (verify-checksums)
```

The different flavors each add [live boot parameters][debian live boot options]:
 - `Debian Live`: boot the Debian Live ISO with some standard options
 - `Debian Live (ip=frommedia)`: boot the Debian Live ISO but retrieve the network configuration from the persistence
 - `Debian Live (nopersistence)`: boot the Debian Live ISO without any persistence
 - `Debian Live (verify-checksums)`: boot the Debian Live ISO and verify the checksums contained in the ISO then reboot

#### Disk image

As root:
```shell
[PASSWORD=root] [SIZE=1021] bash [-x] bootable_disk.bash /dev/sdX [path/to/created/debian.iso]
```
 - `PASSWORD` is the unlocking password of the LUKS-encrypted checksums (`checksum.bin`)
 - `SIZE` is the total EFI/data partition, `1021` is the default in order to fit into 1GiB disks

For testing purposes, it may be useful to create a loop device, as root:
```shell
truncate -s 1024MiB scratch.img
losetup --show -f scratch.img # then use /dev/loopX as the block device for `bootable_disk.bash`
```

To customize the image creation, add or remove `.bash` scripts in [`bootable_disk.d`](bootable_disk.d).

##### Partitions

| Partition | Size
|:---------:|:-----
| GRUB      | 1MiB
| EFI       | `SIZE`MiB

The first partition is aligned to 1MiB for performance reasons.
The `EFI` partition, stores everything from GRUB's configuration and modules to EFI applications and bootable images in a FAT filesystem.

##### Boot menu

By default, GRUB will show the following menu:
```
 ┌ Debian Live
 │ ┌ Debian Live
 │ ├ Debian Live (ip=frommedia)
 │ ├ Debian Live (nopersistence)
 │ └ Debian Live (verify-checksums)
 ├ EFI shell
 └ Verify contents
```
 - `Debian Live` submenu: refer to the Debian Live ISO description
 - `EFI shell`: starts [Tianocore's EFI shell](https://github.com/tianocore/tianocore.github.io/wiki/Efi-shell) (only if booted from 64-bit EFI)
 - `Verify contents`: check the disk integrity by entering the choosen password for the LUKS-encrypted checksums (note that the [`encryption`][debian live boot options] option isn't supported anymore with recent losetup)

#### QEMU testing

To quickly test the different components, use QEMU.

Get an EFI bios:
```shell
apt-get install ovmf # provides /usr/share/qemu/OVMF.fd
```

To test the ISO:
```shell
# bios
qemu-system-x86_64 -m 1024 --curses --cdrom debian.iso
qemu-system-x86_64 -m 1024 --curses --hda debian.iso
# efi
qemu-system-x86_64 -m 1024 --curses --cdrom debian.iso --bios /usr/share/qemu/OVMF.fd --nographic
qemu-system-x86_64 -m 1024 --curses --hda debian.iso --bios /usr/share/qemu/OVMF.fd --nographic
```

To test the disk image:
```shell
# bios
qemu-system-x86_64 -m 1024 --curses --hda scratch.img
# efi
qemu-system-x86_64 -m 1024 --curses --hda scratch.img --bios /usr/share/qemu/OVMF.fd --nographic
```



---

### Storage setup

#### Persistence

Create an encrypted [persistence partition](https://debian-live.alioth.debian.org/live-manual/stable/manual/html/live-manual.en.html#556).
During boot, the live init script will ask a password for each LUKS partition found (but it can not handle a persistence partition from an LVM volume over LUKS).
```shell
parted --script /dev/sdX mklabel gpt
parted --script --align optimal /dev/sdX mkpart encrypted-persistence 1MiB 8193MiB # 8GiB
cryptsetup luksFormat /dev/sdX1 # look for --cipher, see cryptsetup benchmark
cryptsetup luksOpen /dev/sdX1 encryped-persistence
mkfs.ext4 -L persistence /dev/mapper/encrypted-persistence
mount /dev/mapper/encrypted-persistence /mnt
echo '/ union' > /mnt/persistence.conf # refine this as needed, see below
umount /mnt
cryptsetup luksClose encrypted-persistence
reboot # for applying modifications, persistence.conf is read by scripts from the initramfs
```
If encryption is not a concern, remove the cryptsetup operations.

[Multiple persistences](https://debian-live.alioth.debian.org/live-manual/stable/manual/html/live-manual.en.html#583) can be configured.

It's safe to remove the USB key once booted due to the [`toram`][debian live boot options] option (unless a persistence partition is on the USB key itself).

Regarding the use of the persistence, fully persisting `/etc` without persisting `/bin` or `/var` (and others) may result in some parts of the OS being out of sync.
For example, persisting `/etc/passwd` via `/etc` across different ISO will create conflicting users as packages add new entries to the `/etc/passwd` of each different ISO but will in fact reuse the `/etc/passwd` from the persistence.
`/ union` may be a suitable solution to this problem but a more fine-grained alternative would be to only persist the directories that are really required (`/etc/network` may be a good example), which will ease ISO changes.
However, some files are not stored into a subdirectory like `fstab` or `crypttab`.
These two have been copied and symlinked to `/etc/mount` for convenience and they can be persisted by appending to `persistence.conf`:
```
/etc/mount
```



---

### Network setup

#### Dropbear

Dropbear will create the host keys at connection time.
To persist the keys, append to `persistence.conf`:
```
/etc/dropbear
```

#### Interfaces

Debian's `/etc/network/interfaces` includes `/etc/network/interfaces.d` by default.
To persist each interface configuration, append to `persistence.conf`:
```
/etc/network/interfaces.d
```
Booting the Debian Live must be done with [`ip=frommedia`][debian live boot options] else the live init script will rewrite `/etc/network/interfaces` in order to use DHCP.

#### Hosts

To persist hostname and hosts, append to `persistence.conf`:
```
/etc/host
```


---

### LXC setup

#### Persistence

Append to `persistence.conf`:
```
/etc/lxc
/var/lib/lxc
```

#### Storage

Due to persisting `/var/lib/lxc`, it is recommended to use LVM as the LXC's rootfs backend to keep the persistence partition tidy:
```shell
parted --script /dev/sdX mklabel gpt
parted --script --align optimal /dev/sdX mkpart lxc 1MiB 8193MiB # 8GiB
pvcreate /dev/sdX1
vgcreate lxc /dev/sdX1
lxc-create -n lxc-01 -B lvm --fssize 2GiB -t debian -- -r stretch # defaults: --vgname lxc --lvname $name --fssize 1GiB, note that any existing volume will be removed so don't `lvcreate -L 2GiB -n $name lxc`
```

Of course, the LVM volume could be over LUKS, this is done in a similar way as the encrypted persistence.
It is advised to add the LUKS volume to `/etc/crypttab` if it's desired to automatically start the LXC at boot.



---

More links:
 - this [repository's wiki](https://github.com/ether42/bootable-usb/wiki) provides more details on how one could use the build images
 - [GRUB manual](https://www.gnu.org/software/grub/manual/grub.html)
 - [Debian Live manual](https://debian-live.alioth.debian.org/live-manual/stable/manual/html/live-manual.en.html)
 - [Cryptsetup FAQ](https://gitlab.com/cryptsetup/cryptsetup/wikis/FrequentlyAskedQuestions)

[debian live boot options]: https://manpages.debian.org/live-boot-doc/live-boot.7.en.html#OPTIONS
