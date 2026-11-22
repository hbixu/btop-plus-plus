#!/bin/sh
#
# entrypoint.sh - Prepares the container and starts the given command (ttyd + btop by default)
#
# btop reads the disk list from /etc/fstab by default (use_fstab = True), and the
# container's /etc/fstab is the (empty) Alpine one. This script generates /etc/fstab
# from the disks mounted into the container (e.g. -v /volume1:/volume1:ro), so they
# show up in btop's disks panel without changing btop's configuration.
# It also creates the default btop config file on first run.

set -e

generate_fstab() {
    # Filesystem types backed by a block device (lines without "nodev" in /proc/filesystems)
    physical_fstypes=$(grep -v '^nodev' /proc/filesystems | awk '{print $1}')

    # Docker bind mounts are recursive: mounting /volume1 also brings in the mounts nested
    # inside it (e.g. Synology's /volume1/@docker, btrfs subvolumes), which are the same disk.
    # Mounts are processed parents first (shortest path first), and a mount is skipped if it
    # is nested inside an already listed mount or uses an already listed device.
    included_mounts=""
    included_devices=""

    : > /etc/fstab
    awk '{ print length($2) " " $0 }' /proc/self/mounts | sort -n | cut -d' ' -f2- > /tmp/mounts.sorted
    while read -r device mountpoint fstype _; do
        case "$mountpoint" in
            # Container root and paths managed by Docker or by this image
            /|/config|/config/*|/etc/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*) continue ;;
        esac
        echo "$physical_fstypes" | grep -qx "$fstype" || continue

        nested=false
        for parent in $included_mounts; do
            case "$mountpoint" in "$parent"/*) nested=true ;; esac
        done
        [ "$nested" = true ] && continue
        case " $included_devices " in *" $device "*) continue ;; esac

        included_mounts="$included_mounts $mountpoint"
        included_devices="$included_devices $device"
        echo "$device $mountpoint $fstype ro 0 0" >> /etc/fstab
        echo "btop disk: $mountpoint ($fstype)"
    done < /tmp/mounts.sorted
    rm -f /tmp/mounts.sorted
}

# btop only writes its config file when it quits cleanly, so create it on first run
# (btop 1.4+ supports --default-config; older versions are skipped)
create_default_config() {
    config_dir="${XDG_CONFIG_HOME:-/config}/btop"
    config_file="$config_dir/btop.conf"
    [ -f "$config_file" ] && return 0
    mkdir -p "$config_dir"
    if btop --default-config > "$config_file.tmp" 2>/dev/null && grep -q '^color_theme' "$config_file.tmp"; then
        mv "$config_file.tmp" "$config_file"
        echo "btop config created: $config_file"
    else
        rm -f "$config_file.tmp"
    fi
}

if ! generate_fstab; then
    echo "WARNING: could not generate /etc/fstab; btop may not show the mounted disks" >&2
fi

if ! create_default_config; then
    echo "WARNING: could not create the default btop config" >&2
fi

exec "$@"
