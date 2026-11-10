#!/bin/sh
#
# Server Passport v0.2
# Universal read-only server inventory
#
# Supported:
#   Linux (Debian, Ubuntu, RHEL, CentOS, etc.)
#   FreeBSD
#
# Usage:
#   ./server-passport.sh --help
#

VERSION="0.2"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

LC_ALL=C
export LC_ALL
umask 077

MODE="full"
FORMAT="txt"
OUTPUT=""
SECTION="all"
LIST_TOOLS=0
NO_COLOR=0

PROGRAM=`basename "$0"`

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

usage() {
cat <<EOF
$PROGRAM - Server Passport v$VERSION

Read-only technical inventory and diagnostic report.

PURPOSE:
  Discover hardware, operating system, storage topology,
  filesystems, network configuration, running services,
  applications, processes and installed packages.

SUPPORTED:
  Linux / Debian / Ubuntu / other Linux distributions
  FreeBSD

USAGE:
  $PROGRAM [OPTIONS]

OPTIONS:

  -h, --help
      Display this help.

  -v, --version
      Display program version.

  -q, --quick
      Quick inventory. Skip detailed package and security
      information.

  -f, --full
      Full inventory (default).

  -o, --output DIR
      Save report into specified directory.

      Without this option, report goes to stdout.

  --format FORMAT
      Output format:
        txt   Plain text (default)
        md    Markdown
        json  JSON envelope containing the report
        all   Generate all three formats (requires --output)

  --section NAME
      Collect only one section:

        system
        hardware
        storage
        filesystem
        network
        services
        applications
        processes
        packages
        security
        all

  --list-tools
      Show available diagnostic tools and exit.

  --no-color
      Disable colors (reserved for future colored output).

EXAMPLES:

  $PROGRAM --help

  $PROGRAM --quick

  $PROGRAM --full

  $PROGRAM --full --output /tmp/passport

  $PROGRAM --format md --output /tmp/passport

  $PROGRAM --format all --output /tmp/passport

  $PROGRAM --section storage

  $PROGRAM --section applications

  $PROGRAM --list-tools

NOTES:

  - No software is installed.
  - No system configuration is modified.
  - Root privileges are recommended for complete results.
  - Some information may be unavailable due to permissions
    or missing diagnostic tools.
  - The collector does not intentionally read application
    passwords or secret configuration values.

EOF
}

error() {
    echo "ERROR: $*" >&2
    echo "Use $PROGRAM --help for usage." >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo "$PROGRAM v$VERSION"
            exit 0
            ;;
        -q|--quick)
            [ "$MODE" = "full" ] || error "Conflicting modes"
            MODE="quick"
            shift
            ;;
        -f|--full)
            [ "$MODE" = "quick" ] && error "Conflicting modes"
            MODE="full"
            shift
            ;;
        -o|--output)
            [ $# -ge 2 ] || error "Missing output directory"
            OUTPUT="$2"
            shift 2
            ;;
        --format)
            [ $# -ge 2 ] || error "Missing format"
            FORMAT="$2"
            shift 2
            ;;
        --section)
            [ $# -ge 2 ] || error "Missing section"
            SECTION="$2"
            shift 2
            ;;
        --list-tools)
            LIST_TOOLS=1
            shift
            ;;
        --no-color)
            NO_COLOR=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            error "Unexpected argument: $1"
            ;;
    esac
done

[ $# -eq 0 ] || error "Unexpected arguments"

case "$FORMAT" in
    txt|md|json|all) ;;
    *) error "Invalid format: $FORMAT" ;;
esac

case "$SECTION" in
    all|system|hardware|storage|filesystem|network|services|applications|processes|packages|security)
        ;;
    *)
        error "Invalid section: $SECTION"
        ;;
esac

if [ "$FORMAT" = "all" ] && [ -z "$OUTPUT" ]; then
    error "--format all requires --output"
fi

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------

OS=`uname -s 2>/dev/null`
KERNEL=`uname -r 2>/dev/null`
ARCH=`uname -m 2>/dev/null`
HOST=`hostname 2>/dev/null`

case "$OS" in
    Linux) PLATFORM="Linux" ;;
    FreeBSD) PLATFORM="FreeBSD" ;;
    *) PLATFORM="Unsupported: $OS" ;;
esac

# ------------------------------------------------------------
# Diagnostic helpers
# ------------------------------------------------------------

has() {
    command -v "$1" >/dev/null 2>&1
}

run() {
    LABEL="$1"
    shift

    echo
    echo "### $LABEL"

    if has "$1"; then
        "$@" 2>&1
        RC=$?
        [ "$RC" -ne 0 ] && echo "[exit code: $RC]"
    else
        echo "[unavailable: $1]"
    fi
}

show_file() {
    LABEL="$1"
    FILE="$2"

    echo
    echo "### $LABEL"

    if [ -r "$FILE" ]; then
        cat "$FILE"
    else
        echo "[unavailable or permission denied]"
    fi
}

# ------------------------------------------------------------
# Tool discovery
# ------------------------------------------------------------

TOOLS="
dmidecode lshw lscpu hwinfo
sysctl dmesg
lsblk blkid fdisk
smartctl nvme
mdadm zpool zfs
pvs vgs lvs
geom gpart camcontrol
gmirror geli graid
df mount swapinfo
ip ifconfig netstat ss sockstat
systemctl service
ps top
dpkg rpm pkg
nginx apachectl httpd
mysql mysqld mariadb psql postgres
php php-fpm redis-server
docker podman virsh
"

list_tools() {
    echo "Server Passport v$VERSION"
    echo "Platform: $PLATFORM"
    echo
    echo "Available diagnostic tools:"
    echo

    for tool in $TOOLS; do
        if has "$tool"; then
            echo "[YES] $tool"
        else
            echo "[NO ] $tool"
        fi
    done
}

if [ "$LIST_TOOLS" -eq 1 ]; then
    list_tools
    exit 0
fi

# ------------------------------------------------------------
# Section collectors
# ------------------------------------------------------------

collect_system() {
    echo "## SYSTEM IDENTIFICATION"
    echo "Hostname: $HOST"
    echo "OS: $OS"
    echo "Kernel: $KERNEL"
    echo "Architecture: $ARCH"
    echo "Date: `date`"
    echo "User: `id 2>&1`"

    run "Uptime" uptime
    run "Kernel version" uname -a

    case "$OS" in
        Linux)
            show_file "OS release" /etc/os-release
            show_file "Kernel command line" /proc/cmdline
            ;;
        FreeBSD)
            run "FreeBSD version" freebsd-version
            run "System information" sysctl kern.ostype kern.osrelease
            ;;
    esac
}

collect_hardware() {
    echo "## HARDWARE"

    case "$OS" in
        Linux)
            run "CPU topology" lscpu
            show_file "CPU details" /proc/cpuinfo
            run "Memory" free -h
            show_file "Memory details" /proc/meminfo
            run "DMI information" dmidecode
            run "Hardware inventory" lshw -short
            ;;
        FreeBSD)
            run "CPU model" sysctl hw.model
            run "CPU count" sysctl hw.ncpu
            run "Physical memory" sysctl hw.physmem
            run "Memory statistics" vmstat -s
            run "Hardware messages" dmesg
            ;;
    esac
}

collect_storage() {
    echo "## STORAGE"

    case "$OS" in
        Linux)
            run "Block devices" lsblk -a
            run "Block identifiers" blkid
            run "Disk partitions" fdisk -l
            run "SCSI devices" lsscsi

            run "Software RAID" cat /proc/mdstat
            run "RAID configuration" mdadm --detail --scan

            run "LVM physical volumes" pvs -a
            run "LVM volume groups" vgs -a
            run "LVM logical volumes and devices" lvs -a -o +devices

            run "ZFS pools" zpool list -v
            run "ZFS topology" zpool status -v
            run "ZFS datasets" zfs list -t all
            run "ZFS properties" zfs get all
            ;;
        FreeBSD)
            run "GEOM disks" geom disk list
            run "GEOM providers" geom provider list
            run "Partition tables" gpart show -lp
            run "CAM devices" camcontrol devlist -v
            run "GEOM status" geom status
            run "Gmirror status" gmirror status
            run "GELI status" geli status
            run "ZFS pools" zpool list -v
            run "ZFS topology" zpool status -v
            run "ZFS datasets" zfs list -t all
            run "ZFS properties" zfs get all
            ;;
    esac

    run "SMART disk inventory" smartctl --scan
    run "NVMe inventory" nvme list
}

collect_filesystem() {
    echo "## FILESYSTEMS"

    run "Disk usage" df -h
    run "Mounted filesystems" mount

    case "$OS" in
        Linux)
            run "Filesystem types" df -T
            show_file "Filesystem configuration" /etc/fstab
            run "Swap" swapon -s
            ;;
        FreeBSD)
            run "Swap" swapinfo -h
            show_file "Filesystem configuration" /etc/fstab
            ;;
    esac
}

collect_network() {
    echo "## NETWORK"

    case "$OS" in
        Linux)
            run "IP addresses" ip address
            run "Network links" ip -details link
            run "Routes" ip route
            run "Listening sockets" ss -tulnp
            ;;
        FreeBSD)
            run "Interfaces" ifconfig -a
            run "Routes" netstat -rn
            run "Listening sockets" sockstat -46 -l
            ;;
    esac

    show_file "DNS configuration" /etc/resolv.conf
    show_file "Hosts configuration" /etc/hosts
}

collect_services() {
    echo "## SERVICES"

    case "$OS" in
        Linux)
            if has systemctl; then
                run "Running services" systemctl list-units --type=service --state=running --no-pager
                run "Installed service units" systemctl list-unit-files --type=service --no-pager
            else
                run "Service status" service --status-all
                run "Process initialization" ps -p 1 -f
            fi
            ;;
        FreeBSD)
            run "Enabled services" service -e
            show_file "rc.conf" /etc/rc.conf
            show_file "rc.conf.local" /etc/rc.conf.local
            ;;
    esac
}

collect_applications() {
    echo "## APPLICATIONS"

    echo
    echo "### Application processes"

    if has ps; then
        ps -ef 2>&1 | awk '
        BEGIN {
            IGNORECASE=1
            pattern="nginx|apache|httpd|mysql|maria|postgres|redis|php|tomcat|java|node|python|memcached|mongod|named|postfix|sendmail|exim|dovecot|haproxy|varnish|docker|containerd|sshd"
        }
        NR == 1 || $0 ~ pattern { print }
        '
    fi

    echo
    echo "### Application executables in PATH"

    for app in \
        nginx httpd apache2 apache \
        mysqld mariadbd postgres redis-server \
        php php-fpm php-cgi \
        python python3 perl ruby node java \
        tomcat memcached mongod named \
        postfix sendmail exim dovecot \
        haproxy varnish docker podman
    do
        if has "$app"; then
            echo "[FOUND] $app"
        fi
    done
}

collect_processes() {
    echo "## PROCESSES"
    run "All processes" ps -ef

    case "$OS" in
        FreeBSD)
            run "Process details" ps auxww
            ;;
    esac

    echo
    echo "### Listening ports"

    case "$OS" in
        Linux)
            run "TCP/UDP sockets" ss -tulnp
            run "Netstat fallback" netstat -tulnp
            ;;
        FreeBSD)
            run "Listening sockets" sockstat -46 -l
            run "Network sockets" netstat -an
            ;;
    esac
}

collect_packages() {
    echo "## INSTALLED PACKAGES"

    case "$OS" in
        Linux)
            if has dpkg; then
                run "Debian packages" dpkg-query -W
            elif has rpm; then
                run "RPM packages" rpm -qa
            else
                echo "[No supported package manager]"
            fi
            ;;
        FreeBSD)
            run "Installed packages" pkg info
            ;;
    esac
}

collect_security() {
    echo "## SECURITY"

    case "$OS" in
        Linux)
            run "SELinux" getenforce
            run "AppArmor" aa-status
            run "iptables" iptables -L -n
            run "nftables" nft list ruleset
            ;;
        FreeBSD)
            run "PF" pfctl -s info
            run "IPFW" ipfw list
            ;;
    esac

    run "System limits" ulimit -a
}

# ------------------------------------------------------------
# Report generation
# ------------------------------------------------------------

collect_report() {
    echo "# SERVER PASSPORT v$VERSION"
    echo
    echo "Generated: `date`"
    echo "Hostname: $HOST"
    echo "Platform: $PLATFORM"
    echo "Mode: $MODE"
    echo "Format: $FORMAT"

    if [ "$SECTION" != "all" ]; then
        echo
        echo "Selected section: $SECTION"
    fi

    for part in system hardware storage filesystem network services applications processes packages security; do

        [ "$SECTION" != "all" ] && [ "$SECTION" != "$part" ] && continue

        if [ "$MODE" = "quick" ]; then
            case "$part" in
                packages|security) continue ;;
            esac
        fi

        case "$part" in
            system)       collect_system ;;
            hardware)     collect_hardware ;;
            storage)      collect_storage ;;
            filesystem)   collect_filesystem ;;
            network)      collect_network ;;
            services)     collect_services ;;
            applications) collect_applications ;;
            processes)    collect_processes ;;
            packages)     collect_packages ;;
            security)     collect_security ;;
        esac
    done

    echo
    echo "# END OF SERVER PASSPORT"
}

# ------------------------------------------------------------
# Output handling
# ------------------------------------------------------------

TMP="/tmp/server-passport-$$"
REPORT="$TMP/report.txt"

if ! (umask 077 && mkdir "$TMP") 2>/dev/null; then
    error "Cannot create temporary directory: $TMP"
fi

trap 'rm -rf "$TMP"' 0
trap 'exit 1' 1 2 3 15

collect_report > "$REPORT" 2>&1

write_json() {
    FILE="$1"

    awk '
    BEGIN {
        printf "{\n  \"format\": \"server-passport\",\n"
        printf "  \"version\": "'"$VERSION"'",\n"
        printf "  \"report\": \""
    }
    {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        printf "%s\\n", $0
    }
    END {
        printf "\"\n}\n"
    }
    ' "$REPORT" > "$FILE"
}

if [ -n "$OUTPUT" ]; then
    if ! mkdir -p "$OUTPUT" 2>/dev/null; then
        error "Cannot create output directory: $OUTPUT"
    fi

    STAMP=`date '+%Y%m%d-%H%M%S'`
    BASE="$OUTPUT/server-passport-$HOST-$STAMP"

    case "$FORMAT" in
        txt)
            cp "$REPORT" "$BASE.txt" || error "Cannot write report"
            echo "Report: $BASE.txt" >&2
            ;;
        md)
            cp "$REPORT" "$BASE.md" || error "Cannot write report"
            echo "Report: $BASE.md" >&2
            ;;
        json)
            write_json "$BASE.json" || error "Cannot write JSON"
            echo "Report: $BASE.json" >&2
            ;;
        all)
            cp "$REPORT" "$BASE.txt" || error "Cannot write TXT"
            cp "$REPORT" "$BASE.md" || error "Cannot write Markdown"
            write_json "$BASE.json" || error "Cannot write JSON"
            echo "Reports:" >&2
            echo "  $BASE.txt" >&2
            echo "  $BASE.md" >&2
            echo "  $BASE.json" >&2
            ;;
    esac
else
    case "$FORMAT" in
        txt|md)
            cat "$REPORT"
            ;;
        json)
            write_json /dev/stdout
            ;;
    esac
fi

exit 0

