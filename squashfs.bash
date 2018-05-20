#!/usr/bin/env bash

readonly script_directory=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)
. "$script_directory"/library/source.bash

# --- dependencies -------------------------------------------------------------

hash ansible-playbook
hash debootstrap
hash mksquashfs

[ -n "${SSH_AUTH_SOCK:-}" ]

# --- build --------------------------------------------------------------------

[ "$(type -t customize)" = 'function' ] || customize() {
  # FIXME: remove -x to avoid printing password
  set -eux

  export DEBIAN_FRONTEND=noninteractive

  # for some firmwares
  sed 's/main/non-free/' /etc/apt/sources.list >> /etc/apt/sources.list
  apt-get update

  local -ar packages=(
    # utilities
    mg less tmux tcpdump
    # for this repository
    git-core python3-venv
    # firmwares
    firmware-misc-nonfree firmware-realtek firmware-iwlwifi
  ) && apt-get install --no-install-recommends -y "${packages[@]}"

  # root password
  printf '%s\n' "${PASSWORD:-root}" "${PASSWORD:-root}" | passwd root

  # clone this repository
  git clone https://github.com/ether42/bootable-usb.git /root/git

  # persist some important files without persisting whole /etc
  # (this is bad practice as /etc could become out of sync with the
  # rest of the os, either union / or don't persist /etc)
  mkdir /etc/mount && mv /etc/{fstab,crypttab} "$_"
  for file in fstab crypttab; do ln -s /etc/mount/"$file" /etc/"$file"; done
  echo localhost > /etc/hostname
  mkdir /etc/host && mv /etc/{hostname,hosts} "$_"
  for file in hostname hosts; do ln -s /etc/host/"$file" /etc/"$file"; done

  # to bootstrap internet, internet may be needed...
  # no need to install the package itself, only here for rescue
  (cd /root && apt-get download ppp)

  # ssh configuration
  mkdir /root/.ssh
  ssh-add -L > "$_"/authorized_keys
  # be sure to not embed secrets
  rm -f /etc/ssh/ssh_host_*_key*
  mkdir -p /etc/systemd/system/ssh.service.d
  cat > "$_"/override.conf << 'EOF'
[Service]
ExecStartPre=
ExecStartPre=/bin/bash -c 'for type in rsa ecdsa ed25519; do if [ ! -e /etc/ssh/ssh_host_"$type"_key ]; then ssh-keygen -f /etc/ssh/ssh_host_"$type"_key -N ""; fi; done'
ExecStartPre=/usr/sbin/sshd -t
EOF

  # FIXME: openvswitch relies on ifconfig
  # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=857178
  sed -i 's/ifconfig \("${IFACE}" up\)/ip link set dev \1/' \
    /usr/share/openvswitch/scripts/ifupdown.sh

  # FIXME: add a new dependency to console-setup
  # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=846256
  mkdir /etc/systemd/system/console-setup.service.d
  cat > "$_"/override.conf << 'EOF'
[Unit]
After=systemd-tmpfiles-setup.service
EOF

  # cleanup
  apt-get clean && rm -rf /var/lib/apt && rm -rf /var/cache/apt
  find /var/log/ -type f -delete
  rm -f /etc/machine-id
  > /etc/resolv.conf
}
declare -rfx customize

debian() {
  local -r chroot_directory=$1

  if ! [ -f "${CACHE:-}" ]; then
    local -ar packages=(
      # boot
      linux-image-amd64 systemd-sysv
      # optional, in case we need to compile something later
      linux-headers-amd64
      # networking
      ifupdown isc-dhcp-client
      # debian live
      live-boot
      # ansible
      python
    )

    local -ar debootstrap=(
      command debootstrap
      --arch amd64
      --merged-usr
      --include "${packages[*]}"
      --variant minbase
      sid "$chroot_directory"
    ) && "${debootstrap[@]}"
    if [ -n "${CACHE:-}" ]; then
      tar pacf "$CACHE" -C "$chroot_directory" .
    fi
  else
    tar xf "$CACHE" -C "$chroot_directory" .
  fi

  local -Ar mounts=(
    [proc]="$chroot_directory"/proc
    [sysfs]="$chroot_directory"/sys
    [devpts]="$chroot_directory"/dev/pts
  )
  for filesystem in "${!mounts[@]}"; do
    mount -t "$filesystem" none "${mounts[$filesystem]}"
  done

  # share ssh-agent's socket
  local -r ssh_agent_directory=$(dirname "$SSH_AUTH_SOCK")
  mkdir -p "$chroot_directory"/"$ssh_agent_directory" &&
    mount --bind "$ssh_agent_directory" "$_"

  ansible-playbook -i "$chroot_directory", ansible/playbooks/image.yml
  chroot "$chroot_directory" "$SHELL" -c customize

  umount "$chroot_directory"/"$ssh_agent_directory" && rmdir "$_"

  for filesystem in "${!mounts[@]}"; do
    umount "${mounts[$filesystem]}"
  done
}
declare -rf debian

squashfs() {
  local system_directory
  read -r system_directory < <(temporary_mount -t tmpfs none -o size=2G)

  debian "$system_directory"

  mksquashfs "$system_directory" "$1" -noappend
}
declare -rf squashfs

# --- execution ----------------------------------------------------------------

squashfs "${1:-debian.squashfs}"
