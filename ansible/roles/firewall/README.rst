Firewall
========

Basic setup of `ferm <http://ferm.foo-projects.org/>`_ and
`ulogd2 <https://www.netfilter.org/projects/ulogd/>`_ (otherwise it wouldn't be
possible to log from the LXC).

Note that the basic ferm configuration is made to drop anything that could be
sensible.

Services are expected to name necessary rules as `/etc/ferm/input/*.conf`.

When in trouble, remember you can always add an ip*table rule like
`-j NFLOG --nflog-prefix 'example' --nflog-group 42` and then
`tcpdump -i nflog:42`.
