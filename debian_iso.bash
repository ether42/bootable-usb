#!/usr/bin/env bash

declare -r script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null \
  && pwd)
. "$script_directory"/library/source.bash

# --- dependencies ------------------------------------------------------------

hash debootstrap
hash grub-mkimage
hash mksquashfs
hash sha256sum
hash xorriso

# --- customization -----------------------------------------------------------

customize_debian() { # customizable, executed inside the chrooted system
  set -eu
  export DEBIAN_FRONTEND=noninteractive

  # for some firmwares
  sed 's/main/non-free/' /etc/apt/sources.list >> /etc/apt/sources.list
  apt-get update

  # keyboard & console
  # for some reason, console-setup doesn't respect debconf-set-selections
  # without doing an interactive dpkg-reconfigure from the console so let's
  # setup everything manually as it would have done...
  cat > /etc/default/console-setup << EOF
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Terminus"
FONTSIZE="8x14"
EOF
  cat > /etc/default/keyboard << EOF
XKBMODEL="pc104"
XKBLAYOUT="us"
XKBVARIANT="alt-intl"
EOF

  # locales
  # it's prefered to use debconf-set-selections instead of /etc/locale.gen
  # to correctly populate /etc/default/locale with LANG
  debconf-set-selections << EOF
locales locales/default_environment_locale select en_US.UTF-8
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
EOF

  # firmwares and pythons are heavyweight :(
  local -ar packages=( # additional packages to install
    # disk
    parted cryptsetup lvm2
    # networking (ntp via systemd-timesyncd)
    openvswitch-switch dropbear-bin
    # virtualization
    # debian template requires debootstrap & rsync
    # iw is required to setup a wireless interface as lxc.network.type = phys
    lxc debootstrap rsync iw
    # usability
    # tmux requires an utf-8 locale
    # initramfs hooks also complain about kbd & console-setup
    less mg tmux locales kbd console-setup
    # administration
    rsyslog tcpdump
    # collectd
    collectd-core libpython2.7 python-lxc python-openvswitch sysstat libatasmart4 libsensors4
    # firmwares
    firmware-misc-nonfree firmware-realtek firmware-iwlwifi
  ) && apt-get install --no-install-recommends -y "${packages[@]}"

  # password
  printf '%s\n' "${PASSWORD-root}" "${PASSWORD-root}" | passwd root

  # systemd's stuff
  rm -f /etc/machine-id # force an unique identifier (and first time boot)
  mkdir -p /etc/systemd/system-preset && cat >> "$_/00-override.preset" << EOF
# use libc
disable systemd-resolved.service
# use debian's networking
disable systemd-networkd.*
disable systemd-networkd-wait-online.service
# not needed FIXME: still triggered by something...
disable apt-daily-upgrade.*
disable apt-daily.*
EOF
  sed -i 's/#\(Storage=\)auto/\1none/' /etc/systemd/journald.conf # syslog only

  # ssh (dropbear-run provides SysV init script but isn't suited to our use)
  # the advantages being its small size and lazy generation of the host's keys
  cat > /etc/systemd/system/dropbear.service << EOF
[Unit]
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/mkdir -p /etc/dropbear
ExecStart=/usr/sbin/dropbear -R -F
# exit 1 on INT TERM HUP
SuccessExitStatus=1
Restart=always
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable dropbear
  [ ! -d /etc/dropbear ]

  # FIXME: add a new dependency to console-setup
  # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=846256
  mkdir /etc/systemd/system/console-setup.service.d
  cat > "$_"/override.conf << EOF
[Unit]
After=systemd-tmpfiles-setup.service
EOF

  # persist some important files without persisting whole /etc
  # (this is bad practice as /etc could become out of sync with the
  # rest of the os, either union / or don't persist /etc)
  mkdir /etc/mount && mv /etc/{fstab,crypttab} "$_"
  for file in fstab crypttab; do ln -s /etc/mount/"$file" /etc/"$file"; done

  echo localhost > /etc/hostname
  mkdir /etc/host && mv /etc/{hostname,hosts} "$_"
  for file in hostname hosts; do ln -s /etc/host/"$file" /etc/"$file"; done

  # don't make rsyslog log to files but to another host (to be later edited)
  sed -i -e '$a*/' -e '/#### RULES ####/!b;n;n;c/*' /etc/rsyslog.conf
  echo '*.* @127.0.0.1' > /etc/rsyslog.d/forward.conf # blackhole everything

  # FIXME: remove ifconfig dependency in openvswitch's ifupdown hooks
  sed -i 's/ifconfig \("${IFACE}" up\)/ip link set dev \1/' \
    /etc/network/if-pre-up.d/openvswitch

  # to bootstrap internet, internet may be needed...
  # no need to install the package itself, only here for rescue
  # all dependencies are already provided (tcpdump also depends on libcap)
  (cd /root && apt-get download ppp)

  # avoid dns configuration from chroot
  > /etc/resolv.conf

  # collectd setup
  mkdir -p /etc/collectd/collectd.conf.d
  cat > /etc/collectd/collectd.conf << EOF
FQDNLookup true
TypesDB "/usr/share/collectd/types.db"
Interval 10

LoadPlugin syslog
<Plugin syslog>
  LogLevel info
</Plugin>

<Include "/etc/collectd/collectd.conf.d">
  Filter "*.conf"
</Include>
EOF
  cat > /etc/collectd/collectd.conf.d/load.conf << EOF
LoadPlugin load
<Plugin load>
  ReportRelative false
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/cpu.conf << EOF
LoadPlugin cpu
<Plugin cpu>
  ReportByCpu false
  ReportByState true
  ValuesPercentage true
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/smart.conf << EOF
# may spam ata errors on the kernel log when used on virtual machines (VirtualBox & Hyper-V)
LoadPlugin smart
<Plugin smart>
  # can't use /dev/sg* as collectd matches on the block subsystem
  Disk "/^loop[[:digit:]]+$/"
  IgnoreSelected true
  UseSerial true
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/df.conf << EOF
LoadPlugin df
<Plugin df>
  # ignore rootfs; else, the root file-system would appear twice, causing
  # one of the updates to fail and spam the log
  FSType rootfs
  # ignore the usual virtual / temporary file-systems
  FSType sysfs
  FSType proc
  FSType devtmpfs
  FSType devpts
  FSType tmpfs
  FSType fusectl
  FSType cgroup
  FSType squashfs
  IgnoreSelected true
  ReportByDevice false
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/sensors.conf << EOF
LoadPlugin sensors
<Plugin sensors>
  UseLabels true
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/memory.conf << EOF
LoadPlugin memory
<Plugin memory>
  ValuesAbsolute true
  ValuesPercentage false
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/swap.conf << EOF
LoadPlugin swap
<Plugin swap>
  ReportByDevice false
  ReportBytes true
  ValuesAbsolute true
  ValuesPercentage false
</Plugin>
EOF
  cat > /etc/collectd/collectd.conf.d/network.conf << EOF
LoadPlugin network
<Plugin network>
  Server "localhost"
</Plugin>
EOF

  # slim down & cleanup
  apt-get clean && rm -rf /var/lib/apt && rm -rf /var/cache/apt
  rm -rf /var/log/*
}
declare -rfx customize_debian

# --- steps -------------------------------------------------------------------

build_debian() { # debootstrap the debian, should maybe use live-build?
  local -r chroot_directory=$1 && shift
  rm -rf "$chroot_directory"

  local -ar packages=(
    # boot
    # strangely enough, linux-image-amd64=4.9+80 will make grub
    # complain (error in its gzio module, it's fine with other kernels)
    linux-image-amd64 systemd-sysv
    # the corresponding version may later be unavailable so it's better
    # to grab the headers while we can (depends on gcc)
    linux-headers-amd64
    # networking
    ifupdown isc-dhcp-client
    # debian live scripts
    live-boot
  )
  local -ar debootstrap_command=(
    debootstrap
    --arch amd64
    --merged-usr # use symlinks for most of root directories
    --include "${packages[*]}"
    --variant minbase
    sid "$chroot_directory"
  ) && "${debootstrap_command[@]}"

  # necessary mountpoints
  local -Ar mounts=(
    [proc]="$chroot_directory"/proc
    [sysfs]="$chroot_directory"/sys
    [devpts]="$chroot_directory"/dev/pts
  )
  for filesystem in "${!mounts[@]}"; do
    mount -t "$filesystem" none "${mounts[$filesystem]}"
  done

  # user-defined customization
  chroot "$chroot_directory" bash -c customize_debian

  # copy the readme and wiki for easier reference and copy/paste
  cp "$script_directory"/README.md "$chroot_directory"/root/
  if hash git; then
    git clone --depth 1 'https://github.com/ether42/bootable-usb.wiki.git' \
      "$chroot_directory"/root/wiki

    # also copy some collectd scripts for iostat, LXC & Open vSwitch
    git clone --depth 1 'https://gist.github.com/ether42/cd3de784821f631c49f3a4a814719734' \
      "$chroot_directory"/etc/collectd/collectd.conf.d/python
    cat > "$chroot_directory"/etc/collectd/collectd.conf.d/python.conf << EOF
LoadPlugin python

TypesDB "/etc/collectd/collectd.conf.d/python/lxc_ovs_plugin.db"
TypesDB "/etc/collectd/collectd.conf.d/python/iostat_plugin.db"

<Plugin python>
  ModulePath "/etc/collectd/collectd.conf.d/python"
  LogTraces true
  Interactive false

  Import "lxc_ovs_plugin"
  # <Module lxc_ovs_plugin>
  #   OVSDB "unix:/var/run/openvswitch/db.sock"
  # </Module>

  Import "iostat_plugin"
  <Module iostat_plugin>
    Interval 10
  </Module>
</Plugin>
EOF
  fi

  # force cryptsetup into the initramfs
  sed -i 's/^#CRYPTSETUP=$/CRYPTSETUP=y/' \
    "$chroot_directory"/etc/cryptsetup-initramfs/conf-hook
  # regenerate the initramfs
  chroot "$chroot_directory" update-initramfs -u

  for filesystem in "${!mounts[@]}"; do
    umount "${mounts[$filesystem]}"
  done
}
declare -rf build_debian

build_grub() { # build all grub images, output their paths
  local -r grub_prefix=/boot/grub/
  local -r grub_directory=$1/$grub_prefix

  generate_grub_image() {
    local -r format=$1 && shift
    local ouptut
    read -r output < <(temporary_file)
    local -ar grub_mkimage_command=(
      grub-mkimage
      --format "$format"
      --prefix "${grub_prefix%/}"
      --config "$(grub_config_base)"
      --output "$output"
    ) && "${grub_mkimage_command[@]}" "$@"
    printf -- '%s\n' "$output"
  }
  declare -rf generate_grub_image

  # based on grub-install...
  local data='(*.mod|*.o|*.lst|boot.img|grub.efi|core.img|core.efi|modinfo.sh)'
  mkdir -p "$grub_directory"/fonts && cp "$grub_share"/unicode.pf2 "$_"

  local -ar i386_pc_modules=(iso9660 biosdisk)
  local -ar x86_64_efi_modules=(iso9660)
  for format in i386-pc x86_64-efi; do
    # copy grub's modules
    mkdir -p "$grub_directory/$format"
    cp /usr/lib/grub/"$format"/*$data "$grub_directory$format"

    # generate grub images for each format and medium
    local -n modules=${format/-/_}_modules
    local output
    read -r output < <(generate_grub_image "$format" "${modules[@]}")
    if [ "$format" = i386-pc ]; then
      # cdrom image
      cat "$grub_i386_pc_lib"cdboot.img "$output" \
        > "$grub_directory$format".cdboot.img
      printf -- '%s\n' "$grub_prefix$format".cdboot.img
      # disk image
      cat "$grub_i386_pc_lib"boot.img "$output" > "$output.$format".boot.img
      printf -- '%s\n' "$output.$format".boot.img
    elif [ "$format" = x86_64-efi ]; then
      # efi image
      local -r efi_filesystem=$grub_directory$format.img
      truncate --size 512K "$efi_filesystem"
      efi_format "$efi_filesystem"
      local efi_filesystem_mount
      read -r efi_filesystem_mount < <(mount_temporary "$efi_filesystem")
      mkdir -p "$efi_filesystem_mount"/efi/boot
      mv "$output" "$_"/bootx64.efi
      umount "$efi_filesystem_mount"
      printf -- '%s\n' "$grub_prefix$format".img
    else
      !
    fi
  done

  cat "$(grub_config_base)" "$(grub_config_debian_live)" \
    > "$grub_directory"/grub.cfg
}
declare -rf build_grub

build_iso() {
  local iso_directory
  read -r iso_directory < <(temporary_directory)

  # build the squashfs from the chroot directory
  local system_directory
  read -r system_directory < <(temporary_directory)
  build_debian "$system_directory"
  mkdir -p "$iso_directory"/live
  mksquashfs "$system_directory" "$_"/filesystem.squashfs -noappend
  (cd "$iso_directory" && # FIXME? add boot/*
    sha256sum live/* > sha256sum.txt) # optional, for verify-checksums option

  # build the bootable images
  < <(build_grub "$iso_directory") readarray -t outputs
  [ ${#outputs[@]} -eq 3 ]

  # build the iso
  declare -ar xorriso_command=(
    xorriso -as mkisofs
    "$iso_directory"
    -verbose
    # iso generation
    -full-iso9660-filenames
    -joliet
    -rational-rock
    -graft-points
    # -volid 'Debian' # more exist
    -output "$1"
    --boot-catalog-hide
    # bios
    -eltorito-boot "${outputs[0]}"
    -no-emul-boot
    -boot-load-size 4 #?
    -boot-info-table
    --embedded-boot "${outputs[1]}"
    --protective-msdos-label
    # efi
    -eltorito-alt-boot
    --efi-boot "${outputs[2]}"
    -no-emul-boot
    -isohybrid-gpt-basdat #?
  ) && "${xorriso_command[@]}"
}
declare -rf build_iso

# --- execution ---------------------------------------------------------------

build_iso "${1:-debian.iso}"
