customize_chroot() {
    set -eux

    { echo "$root_password"; echo "$root_password"; } | passwd root
    rm /etc/hostname # default to localhost, as in /etc/hosts
    rm /etc/machine-id # systemd stuff
}
