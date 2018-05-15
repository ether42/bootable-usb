OVH
===

Some setup to use `OVH <https://www.ovh.com/>`_ as an ISP.

You'll need to allow `ppp` devices in the container:

.. code-block:: text

   lxc.cgroup.devices.allow = c 108:0 rwm
   lxc.hook.autodev = sh -c 'mknod "$LXC_ROOTFS_MOUNT"/dev/ppp c 108 0'

Variables
---------

`ovh_ppp_interface`
~~~~~~~~~~~~~~~~~~~

The interface on which PPP will run.

`ovh_ppp_user` & `vault_ovh_ppp_user`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PPP username.
The default is `{{ vault_ovh_ppp_user }}`.

`ovh_ppp_password` & `vault_ovh_ppp_password`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PPP password.
The default is `{{ ovh_ppp_password }}`.
