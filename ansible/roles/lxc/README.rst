LXC
===

Install `LXC <https://linuxcontainers.org/>`_ and some dependencies to make use
of it, like `Open vSwitch <https://www.openvswitch.org/>`_.

Unless something more complex is needed, a simple bridge can be achieved with:

.. code-block:: text

   auto bridge-enp0s3
   iface bridge-enp0s3 inet dhcp
     ovs_type OVSBridge
     ovs_ports enp0s3

   allow-bridge-enp0s3 enp0s3
   iface enp0s3 inet manual
     ovs_bridge bridge-enp0s3
     ovs_type OVSPort

It requires to use some helpers, as opposed to Open vSwitch's `fake bridges <https://github.com/openvswitch/ovs/blob/master/debian/openvswitch-switch.README.Debian>`_:

.. code-block:: text

   lxc.network.0.type = veth
   lxc.network.0.name = eth0
   lxc.network.0.hwaddr = 02:00:11:22:33:44
   lxc.network.0.flags = up
   lxc.network.0.script.up = /etc/lxc/ovs_bridge_up.sh bridge-enp0s3
   lxc.network.0.script.down = /etc/lxc/ovs_bridge_down.sh bridge-enp0s3

.. code-block:: bash

   lxc-create -n test-01 -B lvm --fssize 1GiB -t debian -- -r stretch

Variables
---------

`lxc_partitions`
~~~~~~~~~~~~~~~~

.. code-block:: yaml

   lxc_partitions:
     data-container-02: 32G

`lxc`
~~~~~

.. code-block:: yaml

   lxc:
     container-01: {}
     container-02:
       fs_size: 2G
       template_options: -r stretch
       container_config:
         - lxc.network.0.type = veth
         - lxc.network.0.flags = up
         - lxc.network.0.name = eth0
         - lxc.network.0.link = br0
         - lxc.network.0.hwaddr = 02:00:11:22:33:44
         - lxc.mount.entry = /dev/lxc/data-container-02 srv ext4 defaults 0 2
