Overview
========

Some simple scripts left here as a reminder on how to create a bootable live USB key and ISO for both BIOS and UEFI.

Supported architectures
-----------------------

.. list-table::

   * - Component
     - Notes

   * - Squashfs
     - Filesystem of an AMD64 Debian
   * - ISO
     - Bootable as ISO & disk, under BIOS or EFI x86_64
   * - Disk
     - Bootable as disk under BIOS or EFI x86_64
   * - EFI shell
     - Executable under EFI x86_64

Support for EFI IA32 could be easily added.

Debian Squashfs
---------------

.. code-block:: bash

   [CACHE=cache.tar.gz] [PASSWORD=root] bash [-x] squashfs.bash [debian.squashfs]

- `PASSWORD` is the root password of the system

To customize the OS creation, edit the `customize` function of `squashfs.bash` or add it to your environment.

Debian Live ISO
---------------

.. code-block:: bash

   bash [-x] iso.bash [debian.squashfs] [debian.iso]

Boot menu
~~~~~~~~~

By default, GRUB will show the following menu:

.. code-block:: text

   ┌ Debian Live
   ├ Debian Live (ip=frommedia)
   ├ Debian Live (nopersistence)
   └ Debian Live (verify-checksums)

The different flavours each add `live boot parameters <https://manpages.debian.org/live-boot-doc/live-boot.7.en.html#OPTIONS>`_:

- `Debian Live`: boot the Debian Live ISO with some standard options
- `Debian Live (ip=frommedia)`: boot the Debian Live ISO but retrieve the network configuration from the persistence
- `Debian Live (nopersistence)`: boot the Debian Live ISO without any persistence
- `Debian Live (verify-checksums)`: boot the Debian Live ISO and verify the checksums contained in the ISO then reboot

Disk image
----------

.. code-block:: bash

   [PASSWORD=root] [SIZE=1021] bash [-x] iso.bash /dev/sdX [debian.iso]

- `PASSWORD` is the unlocking password of the LUKS-encrypted checksums (`checksum.bin`)
- `SIZE` is the total EFI/data partition, `1021` is the default in order to fit into 1GiB disks

For testing purposes, it may be useful to create a loop device:

.. code-block:: bash

   truncate -s 1024MiB scratch.img
   losetup --show -f scratch.img # then use /dev/loopX as the block device

Partitions
~~~~~~~~~~

.. list-table::

   * - Partition
     - Size

   * - GRUB
     - 1MiB
   * - EFI
     - `SIZE`\ MiB

The first partition is aligned to 1MiB for performance reasons.
The `EFI` partition, stores everything from GRUB's configuration and modules to EFI applications and bootable images in a FAT filesystem.

By default, GRUB will show the following menu:

.. code-block:: text

   ┌ Debian Live
   │ ┌ Debian Live
   │ ├ Debian Live (ip=frommedia)
   │ ├ Debian Live (nopersistence)
   │ └ Debian Live (verify-checksums)
   ├ EFI shell
   └ Verify contents

- `Debian Live` sub-menu: refer to the `Boot menu`_
- `EFI shell`: starts `Tianocore's EFI shell <https://github.com/tianocore/tianocore.github.io/wiki/Efi-shell>`_ (only if booted from 64-bit EFI)
- `Verify contents`: check the disk integrity by entering the choosen password for the LUKS-encrypted checksums (note that the `encryption <https://manpages.debian.org/live-boot-doc/live-boot.7.en.html#OPTIONS>`_ option isn't supported anymore with recent losetup)

QEMU testing
------------

To quickly test the different components, use QEMU.

Get an EFI bios:

.. code-block:: bash

   apt-get install ovmf # provides /usr/share/qemu/OVMF.fd

To test the ISO:

.. code-block:: bash

   # bios
   qemu-system-x86_64 -m 1024 --curses --cdrom debian.iso
   qemu-system-x86_64 -m 1024 --curses --hda debian.iso
   # efi
   qemu-system-x86_64 -m 1024 --curses --cdrom debian.iso --bios /usr/share/qemu/OVMF.fd --nographic
   qemu-system-x86_64 -m 1024 --curses --hda debian.iso --bios /usr/share/qemu/OVMF.fd --nographic

To test the disk image:

.. code-block:: bash

   # bios
   qemu-system-x86_64 -m 1024 --curses --hda scratch.img
   # efi
   qemu-system-x86_64 -m 1024 --curses --hda scratch.img --bios /usr/share/qemu/OVMF.fd --nographic

Storage setup
-------------

Persistence
~~~~~~~~~~~

Create an encrypted `persistence partition <https://debian-live.alioth.debian.org/live-manual/stable/manual/html/live-manual.en.html#556>`_.
During boot, the live init script will ask a password for each LUKS partition found (but it can not handle a persistence partition from an LVM volume over LUKS).

.. code-block:: bash

   parted --script /dev/sdX mklabel gpt

   # encrypted persistence
   parted --script --align optimal /dev/sdX mkpart encrypted-persistence 1MiB $((4 * 1024 + 1))MiB # 4GiB
   cryptsetup luksFormat /dev/sdX1 # look for --cipher, see cryptsetup benchmark
   cryptsetup luksOpen /dev/sdX1 encrypted-persistence
   mkfs.ext4 -L persistence /dev/mapper/encrypted-persistence
   mount /dev/mapper/encrypted-persistence /mnt
   echo '/ union' > /mnt/persistence.conf # refine this as needed, see below
   umount /mnt
   cryptsetup luksClose encrypted-persistence

If encryption is not a concern, remove the cryptsetup operations.

`Multiple persistences <https://debian-live.alioth.debian.org/live-manual/stable/manual/html/live-manual.en.html#583>`_  can be configured.

It's safe to remove the USB key once booted due to the `toram <https://manpages.debian.org/live-boot-doc/live-boot.7.en.html#OPTIONS>`_ option (unless a persistence partition is on the USB key itself).

Regarding the use of the persistence, fully persisting `/etc` without persisting `/bin` or `/var` (and others) may result in some parts of the OS being out of sync.
For example, persisting `/etc/passwd` via `/etc` across different ISO will create conflicting users as packages add new entries to the `/etc/passwd` of each different ISO but will in fact reuse the `/etc/passwd` from the persistence.
`/ union` may be a suitable solution to this problem but a more fine-grained alternative would be to only persist the directories that are really required (`/etc/network` may be a good example), which will ease ISO changes.

An example `persistence.conf`:

.. code-block:: text

   # to store interfaces' configuration
   /etc/network/interfaces.d
   # to store OpenSSH's host keys
   /etc/ssh
   # to store LXC's configuration
   /var/lib/lxc

   # to store /etc/host{name,s}
   /etc/host
   # to store /etc/{fs,crypt}tab
   /etc/mount

   # to store custom RSYSLOG configuration (mainly for forwarding)
   /etc/rsyslog.d

LXC
~~~

.. code-block:: bash

   # encrypted lxc
   parted --script --align optimal /dev/sdX mkpart encrypted-lxc $((4 * 1024 + 1))MiB $((12 * 1024 + 1))MiB # 8GiB
   cryptsetup luksFormat /dev/sdX2
   cryptsetup luksOpen /dev/sdX2 encrypted-lxc
   pvcreate /dev/mapper/encrypted-lxc
   vgcreate lxc /dev/mapper/encrypted-lxc
   cryptsetup luksClose encrypted-lxc

   # crypttab
   cat >> /etc/crypttab << 'EOF'
   encrypted-lxc /dev/disk/by-id/...-part2
   EOF


If encryption is not a concern, remove the cryptsetup operations.

swap
~~~~

At each boot, to encrypt the swap (and lose its content):

.. code-block:: bash

   # encrypted swap (reset at each boot)
   parted --script --align optimal /dev/sdX mkpart encrypted-swap $((12 * 1024 + 1))MiB $((13 * 1024 + 1))MiB # 1GiB

   # crypttab
   cat >> /etc/crypttab << 'EOF'
   encrypted-swap /dev/disk/by-id/...-part3 /dev/urandom swap
   EOF

Ansible
-------

`Ansible <https://www.ansible.com>`_ is used to manage the OS & LXC setup.

A minimal set of files to configure `localhost` is given thereafter, see the roles for more information.

`ansible/inventory/all`:

.. code-block:: text

   localhost

`ansible/inventory/group_vars/all`:

.. code-block:: text

   rsyslog_servers:
     - ...

`ansible/inventory/host_vars/localhost`:

.. code-block:: text

   lxc: {}

`ansible/playbooks/localhost.yml`:

.. code-block:: yaml

   #!/usr/bin/env ansible-playbook

   - hosts: localhost
     connection: local
     roles:
       - systemd
       - irqbalance
       - lxc
       - openssh-server
       - rsyslog-client
       - rdnssd

Roles
=====

.. toctree::
   :maxdepth: 2
   :glob:

   ansible/roles/*/README
