#!/bin/bash

CLIENT_FILE="/root/dnslegasi/client_ip"
TODAY=$(date +%Y-%m-%d)

if [[ ! -f "$CLIENT_FILE" ]]; then
    exit 1
fi

while IFS= read -r line; do
    if [[ "$line" =~ ^### ]]; then
        ip=$(echo "$line" | awk '{print $2}')
        exp=$(echo "$line" | awk '{print $3}')
        client=$(echo "$line" | awk '{print $4}')
        if [[ "$exp" < "$TODAY" ]]; then
            sed -i "/### $ip $exp $client/d" "$CLIENT_FILE"
            dnslegasi rm-ip "$ip"
        fi
    fi
done < "$CLIENT_FILE"

exit 0
