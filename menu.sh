#!/bin/bash
# Color Validation
DF='\e[39m'
Bold='\e[1m'
Blink='\e[5m'
yell='\e[33m'
red='\e[31m'
green='\e[32m'
blue='\e[34m'
PURPLE='\e[35m'
CYAN='\e[36m'
Lred='\e[91m'
Lgreen='\e[92m'
Lyellow='\e[93m'
NC='\e[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\e[36m'
LIGHT='\033[0;37m'
owner="vpnlegasi"
host="https://raw.githubusercontent.com"
directory="resources/main/service"
ISP=$(curl -s ipinfo.io/org | cut -d " " -f 2-10 )
MYIP=$(wget -qO- ipinfo.io/ip);

PERMISSION() {
    admin=$(curl -sS ${host}/${owner}/ip-admin/main/access | awk '{print $2}' | grep -w "$MYIP")

    if [[ "$admin" == "$MYIP" ]]; then
        clear
        echo -e "${green}Permission Accepted...${NC}"
    else
        clear
        rm -rf *.sh /etc/admin > /dev/null 2>&1
        echo -e "${red}Permission Denied!${NC}"
        echo "Your IP NOT REGISTER / EXPIRED | Contact me at Telegram @vpnlegasi to Unlock"
        sleep 2
        exit 1
    fi
}

PERMISSION

CLIENT_FILE="/root/dnslegasi/client_ip"

# ----------------- Helpers -----------------
print_header() {
    local title="$1"
    clear
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m       $title    \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
}

list_clients() {
    grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 2-4 | nl -s ') '
}

select_client() {
    local total=$(grep -c -E "^### " "$CLIENT_FILE")
    local choice=""
    until [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; do
        if [[ $total -eq 1 ]]; then
            read -rp "Select one client [1]: " choice
            choice=${choice:-1}
        else
            read -rp "Select one client [1-$total]: " choice
        fi
    done
    echo "$choice"
}

get_new_expiry() {
    local old_exp="$1"
    local add_days="$2"
    local today=$(date +%Y-%m-%d)
    local old_sec=$(date -d "$old_exp" +%s)
    local now_sec=$(date -d "$today" +%s)
    local diff_days=$(( (old_sec - now_sec) / 86400 ))
    [[ $diff_days -lt 0 ]] && diff_days=0
    date -d "$((diff_days + add_days)) days" +%Y-%m-%d
}

press_any_key() {
    read -n 1 -s -r -p "Press any key to return to menu"
    menu
}

# ----------------- Main Functions -----------------
add_ip() {
    print_header "ADD CLIENT IP SERVER"
    read -p "IP Address  : " ip_address

    if ! grep -qw "$ip_address" "$CLIENT_FILE"; then
        read -p "Validity (days) : " ip_exp
        read -p "Client Name     : " client

        exp=$(date -d "+$ip_exp days" +"%Y-%m-%d")
        hariini=$(date +"%Y-%m-%d")

        echo "### $ip_address $exp $client" >> "$CLIENT_FILE"
        dnslegasi add-ip "$ip_address"

        clear
        MYIP=$(wget -qO- ipinfo.io/ip)
        links="wget -O /usr/bin/menu_nf ${host}/${owner}/${directory}/menu_nf.sh && chmod +x /usr/bin/menu_nf"

        echo -e "\033[0;34m-------------------------------\033[0m"
        echo -e "\E[44;1;39mClient IP DNS Added Successfully\E[0m"
        echo -e "\033[0;34m-------------------------------\033[0m"
        echo "  Your Public IP    : $MYIP"
        echo "  Registered IP     : $ip_address"
        echo "  Validity Period   : $ip_exp Days"
        echo "  Register Date     : $hariini"
        echo "  Expiry Date       : $exp"
        echo "  Client Name       : $client"
        echo -e "\033[0;34m-------------------------------\033[0m"
        echo ""
        echo "  Link to install DNS & Check Region (if not installed):"
        echo -e '```'
        echo "${links}"
        echo -e '```'
        echo "Type 'menu_nf' after install to start"
        echo ""
        echo -e "\033[0;34m-------------------------------\033[0m"

        press_any_key
    else
        exp=$(grep "$ip_address" "$CLIENT_FILE" | awk '{print $3}')
        client=$(grep "$ip_address" "$CLIENT_FILE" | awk '{print $4}')
        print_header "ADD CLIENT IP SERVER"
        echo "IP already registered:"
        echo "  Registered IP    : $ip_address"
        echo "  Expiry Date      : $exp"
        echo "  Client Name      : $client"
        press_any_key
    fi
}

del_ip() {
    print_header "DELETE CLIENT IP SERVER"
    MYIP=$(wget -qO- ipinfo.io/ip)

    NUMBER_OF_CLIENTS=$(grep -c -E "^### " "$CLIENT_FILE")
    if [[ $NUMBER_OF_CLIENTS -eq 0 ]]; then
        echo "No client IP found."
        press_any_key
    fi

    list_clients
    CLIENT_NUMBER=$(select_client)

    ip_address=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}p")
    client=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}p")

    sed -i "/^### $ip_address /d" "$CLIENT_FILE"
    dnslegasi rm-ip "$ip_address"

    echo -e "\033[0;34m-------------------------------\033[0m"
    echo " Client IP DNS Deleted Successfully"
    echo "  IP DNS Server : $MYIP"
    echo "  Client IP VPS : $ip_address"
    echo "  Client Name   : $client"
    echo -e "\033[0;34m-------------------------------\033[0m"

    press_any_key
}

renew_ip() {
    print_header "RENEW CLIENT IP SERVER"
    NUMBER_OF_CLIENTS=$(grep -c -E "^### " "$CLIENT_FILE")
    if [[ $NUMBER_OF_CLIENTS -eq 0 ]]; then
        echo "No client IP found."
        press_any_key
    fi

    list_clients
    CLIENT_NUMBER=$(select_client)

    ip_address=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}p")
    exp=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}p")
    client=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}p")

    masaaktif=""
    until [[ "$masaaktif" =~ ^[0-9]+$ ]] && [ "$masaaktif" -gt 0 ]; do
        read -rp "Renew (days): " masaaktif
    done

    new_exp_date=$(get_new_expiry "$exp" "$masaaktif")
    sed -i "s/^### $ip_address $exp/### $ip_address $new_exp_date/g" "$CLIENT_FILE"

    hariini=$(date +%Y-%m-%d)
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo "  Client IP DNS Renew Successfully"
    echo "  Ip VPS Client : $ip_address"
    echo "  Day Add       : $masaaktif Days"
    echo "  Renew Date    : $hariini"
    echo "  Expired Date  : $new_exp_date"
    echo "  Client Name   : $client"
    echo -e "\033[0;34m-------------------------------\033[0m"

    press_any_key
}

change_ip() {
    print_header "CHANGE IP CLIENT"
    MYIP=$(wget -qO- ipinfo.io/ip)

    NUMBER_OF_CLIENTS=$(grep -c -E "^### " "$CLIENT_FILE")
    if [[ $NUMBER_OF_CLIENTS -eq 0 ]]; then
        echo "No clients found."
        press_any_key
    fi

    list_clients
    CLIENT_NUMBER=$(select_client)

    old_ip=$(grep -E "^### " "$CLIENT_FILE" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}p")
    oldexp=$(grep -E "^### " "$CLIENT_FILE" | grep "$old_ip" | awk '{print $3}')
    oldclient=$(grep -E "^### " "$CLIENT_FILE" | grep "$old_ip" | awk '{print $4}')

    read -rp "PLEASE KEY IN NEW IP : " ip_address
    if grep -qw "$ip_address" "$CLIENT_FILE"; then
        echo "New IP $ip_address is already registered."
        press_any_key
    fi

    echo "### ${ip_address} ${oldexp} ${oldclient}" >> "$CLIENT_FILE"
    dnslegasi rm-ip "$old_ip"
    dnslegasi add-ip "$ip_address"
    sed -i "/$old_ip/d" "$CLIENT_FILE"

    links="wget -O /usr/bin/menu_nf ${host}/${owner}/${directory}/menu_nf.sh && chmod +x /usr/bin/menu_nf"
    hariini=$(date +%Y-%m-%d)

    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m Client IP Change Successfully \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo "  Private IP DNS 👇  "
    echo -e '```'
    echo -e "$MYIP"
    echo -e '```'
    echo "  Change From  IP : $old_ip"
    echo "  Change To    IP : $ip_address"
    echo "  Change Date     : $hariini"
    echo "  Expired Date    : $oldexp"
    echo "  Client Name     : $oldclient"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo ""
    echo "  Link Tanam DNS & Check Region 👇 (Jika Tiada Sahaja) :"
    echo -e '```'
    echo -e "${links}"
    echo -e '```'
    echo " 🌟 Type 👉 menu_nf selepas install 🌟 "
    echo -e "\033[0;34m-------------------------------\033[0m"

    press_any_key
}

client_dns() {
clear
echo -e "\033[0;34m-------------------------------\033[0m"
echo -e "    No.   IPVPS   EXP DATE   CLIENT NAME"
echo -e "\033[0;34m-------------------------------\033[0m"
grep -E "^### " "/root/dnslegasi/client_ip" | cut -d ' ' -f 2-4 | nl -s '. '
echo -e "\033[0;34m-------------------------------\033[0m"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
}

add-proxy() {
    clear -x
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m         Add Proxy Domain      \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo ""
    read -p "Please Type Proxy Domain : " domain
    if grep -qwF "$domain" /root/dnslegasi/domains 2>/dev/null; then
        clear -x
        echo -e "\033[0;34m-------------------------------\033[0m"
        echo -e "\E[44;1;39m         Add Proxy Domain      \E[0m"
        echo -e "\033[0;34m-------------------------------\033[0m"
        echo ""
        echo "Domain already exists in proxy list!"
        echo ""
        echo "Do you want to add another proxy domain? (y/n)"
        read -r ans
        case "$ans" in
            [Yy]* ) add-proxy ;;
            * ) menu ;;
        esac
        return
    fi
    clear -x
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m         Add Proxy Domain      \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    dnslegasi stop > /dev/null 2>&1
    echo "$domain" >> /root/dnslegasi/domains
    sleep 1
    dnslegasi restart > /dev/null 2>&1
    clear
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39mProxy Domain Successfully Added\E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo ""
    echo "Successfully added proxy domain: $domain"
    echo ""
    echo -e "\033[0;34m-------------------------------\033[0m"
    read -n 1 -s -r -p "Press any key to back on menu"
    menu
}

del-proxy() {
    clear -x
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "    No.   Proxy Domain"
    echo -e "\033[0;34m-------------------------------\033[0m"
    if [ ! -s /root/dnslegasi/domains ]; then
        echo "No proxy domains found."
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        menu
        return
    fi
    nl -w2 -s') ' /root/dnslegasi/domains
    echo ""
    NUMBER_OF_DOMAINS=$(wc -l < /root/dnslegasi/domains)
    until [[ ${DOMAIN_NUMBER} -ge 1 && ${DOMAIN_NUMBER} -le ${NUMBER_OF_DOMAINS} ]]; do
        if [[ ${DOMAIN_NUMBER} == 1 ]]; then
            read -rp "Select domain to delete [1]: " DOMAIN_NUMBER
        else
            read -rp "Select domain to delete [1-${NUMBER_OF_DOMAINS}]: " DOMAIN_NUMBER
        fi
    done
    DOMAIN_TO_DELETE=$(sed -n "${DOMAIN_NUMBER}p" /root/dnslegasi/domains)
    sed -i "${DOMAIN_NUMBER}d" /root/dnslegasi/domains
    dnslegasi stop > /dev/null 2>&1
    dnslegasi restart > /dev/null 2>&1
    clear
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m Proxy Domain Successfully Deleted \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo ""
    echo "Deleted domain: $DOMAIN_TO_DELETE"
    echo ""
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo "Do you want to delete another proxy domain? (y/n)"
    read -r ans
    case "$ans" in
        [Yy]* ) del-proxy ;;
        * ) menu ;;
    esac
}

fast_1() {
clear -x
echo -e "\033[0;34m-------------------------------\033[0m"
echo -e "\E[44;1;39m   FAST.COM TESTER VPN LEGASI  \E[0m"
echo -e "\033[0;34m-------------------------------\033[0m"
fast
echo -e "\033[0;34m-------------------------------\033[0m"
echo -e "\E[44;1;39m   FAST.COM TESTER VPN LEGASI  \E[0m"
echo -e "\033[0;34m-------------------------------\033[0m"
read -n 1 -s -r -p "Press any key to back on menu"
menu
}

change_resolver() {
    clear -x
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m Change IP Resolver VPN LEGASI \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    cd /root/dnslegasi

    # Buang resolver.conf lama dan tulis IP baru (overwrite, satu baris sahaja)
    read -p "Add Resolver: " IPR
    echo "$IPR" > /root/dnslegasi/resolver.conf

    echo -e "Please Wait While System Run"

    systemctl stop docker > /dev/null 2>&1
    systemctl disable dnslegasi > /dev/null 2>&1

    stop_and_remove_containers() {
        local pattern="$1"
        if [ -z "$pattern" ]; then
            containers=$(docker ps -a -q)
        else
            containers=$(docker ps -a | grep "$pattern" | awk '{print $1}')
        fi

        if [ -n "$containers" ]; then
            docker stop $containers
            docker rm $containers
        fi
    }

    remove_images() {
        local pattern="$1"
        if [ -z "$pattern" ]; then
            images=$(docker images -a -q)
        else
            images=$(docker images -a | grep "$pattern" | awk '{print $3}')
        fi

        if [ -n "$images" ]; then
            for image in $images; do
                associated_containers=$(docker ps -a --filter=ancestor="$image" -q)
                if [ -n "$associated_containers" ]; then
                    docker stop $associated_containers
                    docker rm $associated_containers
                fi
                docker rmi "$image"
            done
        fi
    }

    stop_and_remove_containers > /dev/null 2>&1
    remove_images > /dev/null 2>&1

    sed1 () {
        IP1=$(grep "nameserver" /root/dnslegasi/sniproxy.sh | awk '{print $2}')
        IP2=$(cat /root/dnslegasi/resolver.conf)

        # Gantikan IP lama dengan IP baru di sniproxy.sh
        sed -i "s/$IP1/$IP2/g" /root/dnslegasi/sniproxy.sh
    }

    sed1 > /dev/null 2>&1

    docker build -t vpnlegasi/dnslegasi . > /dev/null 2>&1
    docker run -d -p 53:53 -p 80:80 -p 443:443 vpnlegasi/dnslegasi > /dev/null 2>&1

    systemctl start dnslegasi
    systemctl enable dnslegasi > /dev/null 2>&1
    systemctl restart dnslegasi

    sleep 2
    containers1=$(docker ps --filter status=exited -q)
    docker rm -v $containers1

    cd
    clear
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m Change IP Resolver VPN LEGASI \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e " New IP Resolver : $IPR"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m Change IP Resolver VPN LEGASI \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    read -n 1 -s -r -p "Press any key to back on menu"
    menu
}

ipresolv() {
    clear -x
    local IPR
    IPR=$(grep "nameserver" /root/dnslegasi/sniproxy.sh | awk '{print $2}')
    
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e "\E[44;1;39m       Show IP Resolver VPN LEGASI       \E[0m"
    echo -e "\033[0;34m-------------------------------\033[0m"
    echo -e " IP Resolver : $IPR"
    echo -e "\033[0;34m-------------------------------\033[0m"
    
    read -n 1 -s -r -p "Press any key to back on menu"
    menu
}


clear -x
echo -e "\033[0;34m-------------------------------\033[0m"
echo -e "\E[44;1;39m       MENU ADD DNS SERVER     \E[0m"
echo -e "\033[0;34m-------------------------------\033[0m"
    echo "[01] Add IP "
    echo "[02] Delete IP"
    echo "[03] Renew IP"
    echo "[04] Show Client DNS"
    echo "[05] Change Client DNS"
    echo "[06] Update Latest Script"
    echo "[07] Speedtest Server (ookla)"
    echo "[08] Speedtest Server (fast.com)"
    echo "[09] Show Resolver IP Access DNS"
    echo "[10] Change Resolver IP Access DNS"
    echo "[11] Add Proxy Domain/Bypass Access DNS"
    echo "[12] Remove Proxy Domain/Bypass Access DNS"
    echo "[13] Menu Add Nameserver & Check Netflix Region"
    echo ""
echo -e "\033[0;34m-------------------------------\033[0m"
echo ""
read -p "Please Choose Option Number : " menu
menu=$(echo "$menu" | sed 's/^0*//')

case $menu in
1)
    add_ip
    ;;
2)
    del_ip
    ;;
3)
    renew_ip
    ;;
4)
    client_dns
    ;;
5)
    change_ip
    ;;
6)
    update_sc
    ;;
7)
    speedtest
    ;;
8)
    fast_1
    ;;
9)
    ipresolv
    ;;
10)
    change_resolver
    ;;
11)
    add-proxy
    ;;
12)
    del-proxy
    ;;
13)
    menu_nf
    ;;
*)
    echo "Pilihan tidak sah."
    ;;
esac
