RSYSLOG client
==============

Install `RSYSLOG <https://www.rsyslog.com/>`_ and configure it to rely on a
remote syslog server.

Variables
---------

`rsyslog_servers`
~~~~~~~~~~~~~~~~~

.. code-block:: yaml

   rsyslog_servers:
     - syslog.example.org
     - 1.2.3.4
