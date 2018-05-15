TAYGA
=====

Setup `TAYGA <http://www.litech.org/tayga/>`_.

An ip6table to allow forwarding from the IPv6 interface to the `nat64`
interface is probably required.

An iptable to allow forwarding from the `nat64` interface to the IPv4
interface (for example `ppp0`) is probably required.
A `MASQUERADE` iptable is already enabled by Debian.

You'll need to allow `tun` devices in the container:

.. code-block:: text

   lxc.cgroup.devices.allow = c 10:200 rwm
   lxc.hook.autodev = sh -c 'mkdir -p "$LXC_ROOTFS_MOUNT"/dev/net && mknod "$LXC_ROOTFS_MOUNT"/dev/net/tun c 10 200'

Variables
---------

tayga_ipv4_address
~~~~~~~~~~~~~~~~~~

Can be any IPv4 address that TAYGA will use for itself.
The default is `192.168.255.1`.

tayga_ipv4_network
~~~~~~~~~~~~~~~~~~

Can be any IPv4 network that TAYGA will use for clients.
The default is `192.168.255.0/24`.

tayga_ipv6_address
~~~~~~~~~~~~~~~~~~

TAYGA's own IPv6 (can be local but is architecture-dependant, so no default).

tayga_ipv6_network
~~~~~~~~~~~~~~~~~~

Can be any IPv6 network that TAYGA will use as prefix for IPv4 translation.
The default is `64:ff9b::/96`.
