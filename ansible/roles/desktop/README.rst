An LXC as a desktop
===================

Make `X <https://www.x.org/>`_, `QEMU <https://www.qemu.org/>`_/`KVM <https://www.linux-kvm.org/>`_ available from an LXC.

Necessary LXC configuration:

.. code-block:: bash

   # you may want wish to tighten that one
   lxc.cap.drop =

   # basic requirements
   lxc.cgroup.devices.allow = c 226:* rwm
   lxc.mount.entry = /dev/dri mnt/dev/dri none bind,create=dir
   lxc.cgroup.devices.allow = c 13:* rwm
   lxc.mount.entry = /dev/input mnt/dev/input none bind,create=dir
   lxc.cgroup.devices.allow = c 116:* rwm
   lxc.mount.entry = /dev/snd mnt/dev/snd none bind,create=dir
   lxc.cgroup.devices.allow = c 4:7 rwm
   lxc.hook.autodev = sh -c 'mknod "$LXC_ROOTFS_MOUNT"/dev/tty7 c 4 7'
   lxc.mount.entry = /run/udev mnt/run/udev none bind,create=dir

   # QEMU/KVM
   lxc.cgroup.devices.allow = c 10:232 rwm
   lxc.hook.autodev = sh -c 'mknod "$LXC_ROOTFS_MOUNT"/dev/kvm c 10 232'
   lxc.cgroup.devices.allow = c 10:200 rwm
   lxc.mount.entry = /dev/net mnt/dev/net none bind,create=dir


To reload `PulseAudio <https://www.freedesktop.org/wiki/Software/PulseAudio/>`_, which is tightly integrated with `udev <https://www.freedesktop.org/software/systemd/man/udev.html>`_:

.. code-block:: bash

   pacmd unload-module module-udev-detect
   pacmd load-module module-udev-detect

Variables
---------

desktop_customize
~~~~~~~~~~~~~~~~~

Whether some personal configuration should be done.
The default is `true`.

desktop_tty
~~~~~~~~~~~

The virtual console to reserve.
The default is `tty7`.

desktop_user
~~~~~~~~~~~~

The desktop user to create.
The default is `ether`.
