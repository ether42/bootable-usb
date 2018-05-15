radvd
=====

Basic setup of `radvd <http://www.litech.org/radvd/>`_.

For the RDNSS to be stored in `/etc/resolv.conf` you'll need
something like `rdnssd <http://rdnssd.linkfanel.net/>`_ on a Debian-based
system.

Note that non-default routes will probably be dropped by most clients for now
(see Linux's
`accept_ra_rt_info_max_plen <https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt>`_
for example).

Variables
---------

`radvd`
~~~~~~~

A dictionary specifying radvd's configuration:

.. code-block:: text

   radvd:

     # will allow anyone to have an ULA from this interface
     eth0:
       AdvSendAdvert: 'on'
       prefixes:
         fd...::/64:
           AdvOnLink: 'on'
           AdvAutonomous: 'on'

     # will only allow specified clients to have an ULA from this interface,
     # set recursive DNS servers to Google's DNS64,
     # and modify the default route's priority
     eth1:
       AdvSendAdvert: 'on'
       prefixes:
         fd...::/64:
           AdvOnLink: 'on'
           AdvAutonomous: 'on'
       clients:
         - fe80::...
         - fe80::...
       routes:
         ::/0:
           AdvRoutePreference: high
       rdnss:
         - 2001:4860:4860::64
         - 2001:4860:4860::6464
