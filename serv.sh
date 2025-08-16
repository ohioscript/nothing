#!/bin/bash
set -e

fix_repo() {
echo "=== Fixing repo untuk Debian 11/12 EOL ==="

# Backup sources.list lama
cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F)

# Detect versi Debian
DEB_VER=$(grep -oE '^[0-9]+' /etc/debian_version | head -n1)

# Disable valid-until check
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99ignore-release-date

if [[ "$DEB_VER" == "11" ]]; then
    cat >/etc/apt/sources.list <<EOF
deb [check-valid-until=no] http://archive.debian.org/debian bullseye main contrib non-free
deb [check-valid-until=no] http://archive.debian.org/debian bullseye-updates main contrib non-free
EOF

elif [[ "$DEB_VER" == "12" ]]; then
    cat >/etc/apt/sources.list <<EOF
deb [check-valid-until=no] http://archive.debian.org/debian bookworm main contrib non-free
deb [check-valid-until=no] http://archive.debian.org/debian bookworm-updates main contrib non-free
deb [check-valid-until=no] http://archive.debian.org/debian-security bookworm-security main contrib non-free
EOF

else
    echo "? Versi Debian tidak disokong."
    exit 1
fi

# Update repo
apt-get update -o Acquire::Check-Valid-Until=false -y

echo "? Repo fixed untuk Debian $DEB_VER"
}

fix_repo

echo "Update & upgrade system"
apt-get update
apt-get upgrade -y

echo
echo "Install needed packages"
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release resolvconf docker.io

echo
echo "Prepare systemd-resolved"

echo "Stopping systemd-resolved service"
systemctl stop systemd-resolved.service || true

echo "Disabling systemd-resolved service"
systemctl disable systemd-resolved.service || true

echo "Masking systemd-resolved service"
systemctl mask systemd-resolved.service || true

echo "Removing /etc/resolv.conf symlink if exists"
if [ -L /etc/resolv.conf ]; then
    rm /etc/resolv.conf
fi

echo "Creating new /etc/resolv.conf"
echo "nameserver 1.1.1.1" > /etc/resolv.conf

echo
echo "Enable and restart resolvconf service"
systemctl enable resolvconf.service
systemctl restart resolvconf.service

# Buat folder dnslegasi kalau belum ada
mkdir -p dnslegasi
cd dnslegasi

echo "Membuat fail-fail dnslegasi..."

#dnslegasi script
cat > dnslegasi << 'EOF'
#!/bin/bash

PROG="$(basename $0)"
PROG_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"

typeset -A config
config=(
    [dns]='8.8.8.8,8.8.4.4'
    [iptables]='true'
    [ipv6nat]='true'
)

usage() {
    echo "Usage: $PROG <command>"
    echo
    echo "Commands:"
    echo "  help                            Show this help"
    echo "  start                           Start dnslegasi"
    echo "  stop                            Stop dnslegasi"
    echo "  restart                         Restart dnslegasi"
    echo "  enable                          Enable dnslegasi service (i.e. starts on boot)"
    echo "  disable                         Disable dnslegasi service"
    echo "  status                          Check dnslegasi status"
    echo "  add-ip                          Add allowed IP"
    echo "  rm-ip                           Remove allowed IP"
    echo "  list-ips                        List IPs"
    echo "  config-get [<option>]           Get value of a config option"
    echo "  config-set <option> [<value>]   Set value to a config option"
    echo
    echo "Config options:"
    echo "  dns <ip-list>           DNS servers (default: 8.8.8.8,8.8.4.4)"
    echo "  iptables <true|false>   Set iptables rules (default: true)"
    echo "  ipv6nat <true|false>    Create IPv6 NAT (default: true)"
}

load_config() {
    local line
    local var

    if [[ -f /etc/dnslegasi/config ]]; then
        while read line; do
            if echo "$line" | grep -qE '^[_a-zA-Z][-_a-zA-Z0-9]+='; then
                var="${line%%=*}"
                config[$var]="${line#*=}"
            fi
        done < /etc/dnslegasi/config
    fi
}

save_config() {
    local var
    for var in "${!config[@]}"; do
        echo "${var}=${config[$var]}"
    done > /etc/dnslegasi/config
}

is_true() {
    echo "$1" | grep -qiE '^[[:space:]]*(true|t|yes|y|1)[[:space:]]*$'
}

echo_err() {
    echo "$@" >&2
}

noout() {
    "$@" > /dev/null 2>&1
}

is_running() {
    docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null | grep -qE '^true$'
}

is_container() {
    [[ -n "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" ]]
}

is_num() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_ipv4() {
    local old_ifs="$IFS"
    local ip="$(echo "$1" | awk -F / '{ print $1 }')"
    local mask="$(echo "$1" | awk -F / '{ print $2 }')"
    local ret=0
    local x

    if [[ -n "$mask" ]]; then
        if ! is_num "$mask" || [[ "$mask" -lt 0 || "$mask" -gt 32 ]]; then
            return 1
        fi
    fi

    IFS='.'
    for x in $ip; do
        if ! is_num "$x" || [[ "$x" -lt 0 || "$x" -gt 255 ]]; then
            ret=1
            break
        fi
    done
    IFS="$old_ifs"

    return $ret
}

is_ipv6() {
    local old_ifs="$IFS"
    local ip="$(echo "$1" | awk -F / '{ print $1 }')"
    local mask="$(echo "$1" | awk -F / '{ print $2 }')"
    local ret=0
    local x

    if [[ -n "$mask" ]]; then
        if ! is_num "$mask" || [[ "$mask" -lt 0 || "$mask" -gt 128 ]]; then
            return 1
        fi
    fi

    IFS=':'
    for x in $ip; do
        if ! echo "$x" | grep -qE '^[a-fA-F0-9]{0,4}$'; then
            ret=1
            break
        fi
    done
    IFS="$old_ifs"

    return $ret
}

ipv6_iface() {
    ip -6 route | grep '^default' | sed 's/.*dev[[:space:]]\+\([^[:space:]]\+\).*/\1/'
}

has_global_ipv6() {
    local x

    for x in $(ipv6_iface); do
        if ip -6 addr show dev "$x" | grep -q 'scope global'; then
            return 0
        fi
    done

    return 1
}

create_systemd_service() {
local service="[Unit]
Description=Custom DNS Server VPN Legasi
Documentation=https://t.me/vpnlegasi
After=docker.service
Requires=docker.service

[Service]
ExecStart=$PROG_DIR/dnslegasi start-container
ExecStop=$PROG_DIR/dnslegasi stop-container

[Install]
WantedBy=multi-user.target"

    if ! echo "$service" | cmp -s - /etc/systemd/system/dnslegasi.service; then
        echo "$service" > /etc/systemd/system/dnslegasi.service
        systemctl daemon-reload
    fi
}

reset_iptables() {
    local chains=$(iptables -w -S | awk '/^-N dnslegasi/ { print $2 }')
    local x

    for x in $chains; do
        noout iptables -w -F $x
        iptables -w -S | grep -- "-j ${x}\([[:space:]]\|$\)" | tac | \
            awk '{ $1 = "-D"; system("iptables -w "$0) }'
        iptables -w -X $x
    done
}

reset_ip6tables() {
    local chains=$(ip6tables -w -S | awk '/^-N dnslegasi/ { print $2 }')
    local x

    for x in $chains; do
        noout ip6tables -w -F $x
        ip6tables -w -S | grep -- "-j ${x}\([[:space:]]\|$\)" | tac | \
            awk '{ $1 = "-D"; system("ip6tables -w "$0) }'
        ip6tables -w -X $x
    done
}

prepare_iptables() {
    reset_iptables

    # create chains
    iptables -w -N dnslegasi-input
    iptables -w -N dnslegasi-forward
    iptables -w -N dnslegasi-filter

    iptables -w -I INPUT -j dnslegasi-input
    iptables -w -I FORWARD -j dnslegasi-forward
    iptables -w -A dnslegasi-input -j dnslegasi-filter
    iptables -w -A dnslegasi-forward -o dnslegasi0 -j dnslegasi-filter

    # block our services for all IPs
    iptables -w -A dnslegasi-input ! -i lo -p tcp --dport 443 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-input ! -i lo -p tcp --dport 80 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-input ! -i lo -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-input ! -i lo -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable

    iptables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 443 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 80 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    iptables -w -A dnslegasi-forward -o dnslegasi0 -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable

    # unblock our services for the allowed IPs
    if [[ -f /etc/dnslegasi/allowed_ips ]]; then
        local x
        for x in $(cat /etc/dnslegasi/allowed_ips); do
            allow_ip "$x"
        done
    fi
}

prepare_ip6tables() {
    reset_ip6tables

    ip6tables -w -N dnslegasi-input
    ip6tables -w -N dnslegasi-forward
    ip6tables -w -N dnslegasi-filter

    ip6tables -w -I INPUT -j dnslegasi-input
    ip6tables -w -I FORWARD -j dnslegasi-forward
    ip6tables -w -A dnslegasi-input -j dnslegasi-filter
    ip6tables -w -A dnslegasi-forward -o dnslegasi0 -j dnslegasi-filter

    # block our services for all IPs
    ip6tables -w -A dnslegasi-input ! -i lo -p tcp --dport 443 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-input ! -i lo -p tcp --dport 80 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-input ! -i lo -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-input ! -i lo -p udp --dport 53 -j REJECT --reject-with icmp6-adm-prohibited

    ip6tables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 443 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 80 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-forward -o dnslegasi0 -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    ip6tables -w -A dnslegasi-forward -o dnslegasi0 -p udp --dport 53 -j REJECT --reject-with icmp6-adm-prohibited

    # unblock our services for the allowed IPs
    if [[ -f /etc/dnslegasi/allowed_ips ]]; then
        local x
        for x in $(cat /etc/dnslegasi/allowed_ips); do
            allow_ip "$x"
        done
    fi
}

start_container() {
    local x

    if is_running dnslegasi; then
        echo_err 'dnslegasi is not already running.'
        return 1
    fi

    noout docker network rm dnslegasi-net

    # in general IPv6 NAT is not suggested but some VPS providers do not offer
    # configurable IPv6 address range, so we workaround this.
    local ipv6_masq=0
    if is_true "${config[ipv6nat]}" && has_global_ipv6; then
        local net_opts=(--ipv6 --subnet=fd00::/64)
        ip6tables -t nat -I POSTROUTING -s fd00::/64 ! -o dnslegasi0 -j MASQUERADE
        sysctl -qw net.ipv6.conf.all.forwarding=1
        ipv6_masq=1
    fi

    noout docker network create "${net_opts[@]}" \
        --opt com.docker.network.bridge.name=dnslegasi0 \
        dnslegasi-net

    if is_true "${config[iptables]}"; then
        prepare_iptables
        prepare_ip6tables
    fi

    is_container dnslegasi && docker rm dnslegasi
    docker run -i --rm -p 53:53 -p 53:53/udp -p 80:80 -p 443:443 \
        --cap-add=NET_ADMIN --name dnslegasi \
        --net=dnslegasi-net \
        -e DNS_SERVER="${config[dns]}" \
        vpnlegasi/dnslegasi

    if is_true "${config[iptables]}"; then
        reset_iptables
        reset_ip6tables
    fi

    if is_true "$ipv6_masq"; then
        while noout ip6tables -t nat -D POSTROUTING -s fd00::/64 ! -o dnslegasi0 -j MASQUERADE; do
            true
        done
    fi
}

stop_container() {
    is_running dnslegasi || return 1
    docker stop dnslegasi
}

start() {
    if is_running dnslegasi; then
        echo_err 'dnslegasi is not already running.'
        return 1
    fi

    create_systemd_service
    systemctl start dnslegasi
}

stop() {
    systemctl stop dnslegasi
}

enable() {
    create_systemd_service
    systemctl enable dnslegasi
}

disable() {
    systemctl disable dnslegasi
}

status() {
    local boot=no
    local running=no

    [[ "$(systemctl is-enabled dnslegasi 2> /dev/null)" == "enabled" ]] && boot=yes
    is_running dnslegasi && running=yes

    echo "Start on boot: $boot"
    echo "Running: $running"
}

get_allowed_ips() {
    iptables -w -S dnslegasi-filter | grep -- "-j ACCEPT\([[:space:]]\|$\)" | \
        awk '{ sub("/32", "", $4); print $4 }' | sort | uniq
    ip6tables -w -S dnslegasi-filter | grep -- "-j ACCEPT\([[:space:]]\|$\)" | \
        awk '{ sub("/128", "", $4); print $4 }' | sort | uniq
    return 0
}

update_allowed_ips_file() {
    get_allowed_ips > /etc/dnslegasi/allowed_ips
}

allow_ip() {
    disallow_ip "$1" || return 1

    if is_ipv4 "$1"; then
        iptables -w -A dnslegasi-filter -s "$1" -j ACCEPT && return 0
    elif is_ipv6 "$1"; then
        ip6tables -w -A dnslegasi-filter -s "$1" -j ACCEPT && return 0
    fi

    return 1
}

disallow_ip() {
    if is_ipv4 "$1"; then
        while noout iptables -w -D dnslegasi-filter -s "$1" -j ACCEPT; do
            true
        done
        return 0
    elif is_ipv6 "$1"; then
        while noout ip6tables -w -D dnslegasi-filter -s "$1" -j ACCEPT; do
            true
        done
        return 0
    fi
    return 1

}

add_ip() {
    if ! is_running dnslegasi; then
        echo_err 'dnslegasi is not running.'
        return 1
    fi

    if ! is_true "${config[iptables]}"; then
        echo_err "This command is disabled because you have iptables config option as false."
        return 1
    fi

    allow_ip "$1" && update_allowed_ips_file
    return 0
}

rm_ip() {
    if ! is_running dnslegasi; then
        echo_err 'dnslegasi is not running.'
        return 1
    fi

    if ! is_true "${config[iptables]}"; then
        echo_err "This command is disabled because you have iptables config option as false."
        return 1
    fi

    disallow_ip "$1" && update_allowed_ips_file
    return 0
}

list_ips() {
    if ! is_running dnslegasi; then
        echo_err 'dnslegasi is not running.'
        return 1
    fi

    if ! is_true "${config[iptables]}"; then
        echo_err "This command is disabled because you have iptables config option as false."
        return 1
    fi

    get_allowed_ips
}

config_get() {
    local var="$1"
    shift

    if [[ -z "$var" ]]; then
        for var in "${!config[@]}"; do
            echo "${var}=${config[$var]}"
        done
    else
        echo "${config[$var]}"
    fi
    return 0
}

config_set() {
    local var="$1"
    shift
    if [[ -z "$@" ]]; then
        unset -v 'config[$var]'
    else
        config[$var]="$@"
    fi
    save_config
}

if [[ -z "$1" || "$1" == "help" ]]; then
    usage
    exit 0
fi

if [[ $(id -u) -ne 0 ]]; then
    echo_err "You must run it as root."
    exit 1
fi

mkdir -p /etc/dnslegasi
load_config

case "$1" in
    start-container)
        start_container
        ;;
    stop-container)
        stop_container
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    status)
        status
        ;;
    add-ip)
        shift
        add_ip "$1"
        ;;
    rm-ip)
        shift
        rm_ip "$1"
        ;;
    list-ips)
        list_ips
        ;;
    config-get)
        shift
        config_get "$@"
        ;;
    config-set)
        shift
        config_set "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac

EOF

chmod +x dnslegasi

# Dnsmasq
cat > dnsmasq.sh << 'EOF'
#!/bin/sh

ipv6_iface() {
    ip -6 route | grep '^default' | sed 's/.*dev[[:space:]]\+\([^[:space:]]\+\).*/\1/'
}

has_global_ipv6() {
    local x

    for x in $(ipv6_iface); do
        if ip -6 addr show dev "$x" | grep -q 'scope global'; then
            return 0
        fi
    done

    return 1
}

get_ext_ip() {
    dig +short myip.opendns.com @resolver1.opendns.com 2> /dev/null
}

get_ext_ipv6() {
    if has_global_ipv6; then
        dig AAAA +short myip.opendns.com @2620:0:ccc::2 2> /dev/null
    fi
}

cache_server=0
[ "$1" == "--cache" ] && cache_server=1

if [ "$cache_server" -eq 1 ]; then
    conf=/tmp/dnsmasq-cache.conf
    resolv=/tmp/dnsmasq-cache.resolv
else
    conf=/tmp/dnsmasq.conf
    resolv=/tmp/dnsmasq.resolv
fi

rm -f $conf $resolv

cat > $conf << EOF2
keep-in-foreground
no-hosts
resolv-file=$resolv
EOF2

if [ "$cache_server" -eq 1 ]; then
    echo "port=5399" >> $conf
    iptables -w -t nat -A OUTPUT -s 127.0.0.1 -p udp -m udp --dport 53 -j REDIRECT --to 5399
    iptables -w -t nat -A OUTPUT -s 127.0.0.1 -p tcp -m tcp --dport 53 -j REDIRECT --to 5399
else
    EXT_IP=${EXT_IP:-$(get_ext_ip)}
    EXT_IPV6=${EXT_IPV6:-$(get_ext_ipv6)}

    for x in $(cat /opt/dnslegasi/domains); do
        [[ -n "$EXT_IP" ]] && echo "address=/$x/$EXT_IP" >> $conf
        [[ -n "$EXT_IPV6" ]] && echo "address=/$x/$EXT_IPV6" >> $conf
    done
fi

DNS_SERVER="${DNS_SERVER:-8.8.8.8,8.8.4.4}"
DNS_SERVER="${DNS_SERVER//,/ }"

for x in $DNS_SERVER; do
    echo "nameserver $x" >> $resolv
done

exec dnsmasq -C $conf
EOF
chmod +x dnsmasq.sh

cat > sniproxy.sh << 'EOF'
#!/bin/sh

ipv6_iface() {
    ip -6 route | grep '^default' | sed 's/.*dev[[:space:]]\+\([^[:space:]]\+\).*/\1/'
}

has_global_ipv6() {
    local x

    for x in $(ipv6_iface); do
        if ip -6 addr show dev "$x" | grep -q 'scope global'; then
            return 0
        fi
    done

    return 1
}

resolver_mode=ipv4_only
has_global_ipv6 && resolver_mode=ipv6_first

cat > /tmp/sniproxy.conf << EOF_INNER
user nobody
group nobody

listener 80 {
    proto http
}

listener 443 {
    proto tls
}

resolver {
    nameserver 127.0.0.1
    mode $resolver_mode
}

table {
    .* *
}
EOF_INNER

exec sniproxy -c /tmp/sniproxy.conf -f
EOF
chmod +x sniproxy.sh

#domains file
cat > domains << EOF
akadns.net
akam.net
akamai.com
akamai.net
akamaiedge.net
akamaihd.net
akamaistream.net
akamaitech.net
akamaitechnologies.com
akamaitechnologies.fr
akamaized.net
edgekey.net
edgesuite.net
srip.net
footprint.net
level3.net
llnwd.net
edgecastcdn.net
cloudfront.net
netflix.com
netflix.net
nflximg.net
nflxvideo.net
nflxso.net
nflxext.com
hulu.com
huluim.com
hbonow.com
hbogo.com
hbo.com
amazon.com
amazon.co.uk
amazonvideo.com
hotstar.com
gov.my
viu.com
com.my
EOF

#Service
cat > services.ini << EOF
[program:dnsmasq]
autorestart = true
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /opt/dnslegasi/dnsmasq.sh

[program:dnsmasq-cache]
autorestart = true
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /opt/dnslegasi/dnsmasq.sh --cache

[program:sniproxy]
autorestart = true
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /opt/dnslegasi/sniproxy.sh
EOF

#Init
cat > my_init << 'EOF'
#!/bin/sh
is_privileged() {
    ip link add dummy0 type dummy > /dev/null 2>&1 || return 1
    ip link delete dummy0 > /dev/null 2>&1
    return 0
}
if ! is_privileged; then
    echo "This container needs to be run with '--privileged' or '--cap-add=NET_ADMIN' option" >&2
    exit 1
fi
exec supervisord -c /etc/supervisord.conf -n
EOF
chmod +x my_init

#Docker
cat > Dockerfile << EOF
FROM alpine
RUN apk add --no-cache supervisor bind-tools iptables sniproxy dnsmasq
ADD dnslegasi /usr/local/bin/
RUN mkdir -p /opt/dnslegasi
ADD dnsmasq.sh sniproxy.sh domains dnslegasi /opt/dnslegasi/
ADD services.ini /etc/supervisor.d/
ADD my_init /
RUN chmod +x /opt/dnslegasi/dnsmasq.sh
RUN chmod +x /opt/dnslegasi/sniproxy.sh
RUN chmod +x my_init
CMD ["/my_init"]
EOF

echo
echo "Build Docker image vpnlegasi/dnslegasi"
docker build -t vpnlegasi/dnslegasi .

echo
echo "Run container"
docker container rm -f dnslegasi 2>/dev/null || true
docker container run -d -p 53:53 -p 80:80 -p 443:443 vpnlegasi/dnslegasi:latest

echo
echo "Link dnslegasi binary"
ln -snf $PWD/dnslegasi /usr/local/bin/dnslegasi
chmod +x /usr/local/bin/dnslegasi

echo
echo "Start dnslegasi service"
dnslegasi start
sleep 5

echo "Enabling dnslegasi service"
dnslegasi enable
sleep 5

echo "Checking dnslegasi status"
dnslegasi status
sleep 5

echo "" >> client_ip
cd

clear
# Muat turun menu
wget -O /usr/bin/menu "https://raw.githubusercontent.com/ohioscript/nothing/main/menu"
chmod +x /usr/bin/menu

# Muat turun xp
wget -O /usr/bin/xp "https://raw.githubusercontent.com/ohioscript/nothing/main/xp"
chmod +x /usr/bin/xp

# cron job
if ! grep -q '/usr/bin/xp' /etc/crontab; then
cat << EOF >> /etc/crontab
# BEGIN_NETMANAGER
0 0 * * * root /usr/bin/xp # delete expired IP VPS License
# END_NETMANAGER
EOF
fi

if ! grep -q 'root reboot' /etc/crontab; then
cat << EOF >> /etc/crontab
# DNS_BEGIN_REBOOT
5 0 * * * root reboot # Reboot Server
# DNS_END_REBOOT
EOF
fi

# Setup /root/.profile supaya auto jalankan menu bila root login
cat > /root/.profile << 'END_PROFILE'
# ~/.profile: executed by Custom Shell VPN Legasi

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n || true
clear
menu
END_PROFILE

chmod 644 /root/.profile

# Bersihkan semua .sh di /root (pastikan cwd /root)
cd /root || exit
rm -f *.sh

# Set timezone ke Kuala Lumpur
timedatectl set-timezone Asia/Kuala_Lumpur

# Maklumkan reboot dan tunggu 10 saat
clear
echo -e "\033[0;34m------------------------------------\033[0m"
echo -e "\E[44;1;39m      Complete Install DNS Server   \E[0m"
echo -e "\033[0;34m------------------------------------\033[0m"
echo "Server will reboot in 10 seconds..."
sleep 10

reboot