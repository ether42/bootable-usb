hostapd
=======

`hostapd <https://w1.fi/hostapd/>`_ setup.

The host will require `iw <https://github.com/lxc/lxc/issues/52>`_ to move the physical interface into the container:

.. code-block:: text

   lxc.network.$i.type = phys
   lxc.network.$i.link = wlp2s0
   lxc.network.$i.name = wlp2s0

.. todo:: sometimes after a reboot of the LXC, the wireless interface takes time to show up again...

Variables
---------

hostapd_bridge
~~~~~~~~~~~~~~

Name of the bridge.
The default is `bridge-{{ hostapd_bridged_interface }}`.

hostapd_bridged_interface
~~~~~~~~~~~~~~~~~~~~~~~~~

Must be defined, the interface to bridge.

hostapd_channel
~~~~~~~~~~~~~~~

Channel to use.
The default is 1.
Use 0 if automatic detection is supported.

hostapd_country_code
~~~~~~~~~~~~~~~~~~~~

Country code.
The default is `FR`.

hostapd_hw_mode
~~~~~~~~~~~~~~~

Operation mode.
The default is `g`.

hostapd_interface
~~~~~~~~~~~~~~~~~

Must be defined, the wireless interface to use.

hostapd_ssid
~~~~~~~~~~~~

Name of the SSID to broadcast.
The default is `SSID`.

hostapd_wpa_passphrase
~~~~~~~~~~~~~~~~~~~~~~

The SSID's WPA2 password.
The default is `{{ vault_hostapd_wpa_passphrase }}`.
