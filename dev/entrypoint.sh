#!/bin/sh

set -eu

[ -n "${UMASK:-}" ] && umask "$UMASK"

KEY="${STGUIAPIKEY:-}"
PORT="${SYNCTHING_PORT:-8384}"
SYNC_PORT="${SYNCTHING_SYNC_PORT:-22000}"
FOLDER_ID="${SYNCTHING_FOLDER_ID:-swarm-stacks}"
FOLDER_PATH="${SYNCTHING_FOLDER_PATH:-/var/syncthing/data}"
FOLDER_LABEL="${SYNCTHING_FOLDER_LABEL:-Swarm deployment control}"

if [ -z "$KEY" ] || [ "$KEY" = "change-me-in-local-env" ]; then
    echo "Error: STGUIAPIKEY must be supplied through the deployment environment" >&2
    exit 1
fi

json_extract() {
    field="$1"
    sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

json_extract_array() {
    field="$1"
    grep -o '"'"$field"'"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

api() {
    method="$1"
    url="$2"
    data="${3:-}"
    if [ -n "$data" ]; then
        curl -sS -f -X "$method" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $KEY" \
            --max-time 30 \
            -d "$data" \
            "$url"
    else
        curl -sS -f -X "$method" \
            -H "X-API-Key: $KEY" \
            --max-time 30 \
            "$url"
    fi
}

api_url() {
    printf 'http://127.0.0.1:%s' "$PORT"
}

wait_for_syncthing() {
    echo "Waiting for Syncthing API..."
    until curl -sS -f --max-time 3 \
        -H "X-API-Key: $KEY" \
        "$(api_url)/rest/system/status" >/dev/null 2>&1; do
        sleep 1
    done
    sleep 3
}

configure_options() {
    current=$(api PATCH "$(api_url)/rest/config/options" \
        '{"globalAnnounceEnabled":false,"relaysEnabled":false,"natEnabled":false,"localAnnounceEnabled":true,"progressUpdateIntervalS":-1,"setLowPriority":false}' \
        2>/dev/null || true)
    [ -n "$current" ] || echo "Syncthing private-discovery options will be retried on the next start"
}

folder_payload() {
    my_id="$1"
    cat <<EOF
{
  "id": "${FOLDER_ID}",
  "label": "${FOLDER_LABEL}",
  "path": "${FOLDER_PATH}",
  "type": "sendreceive",
  "devices": [{"deviceID": "${my_id}"}],
  "rescanIntervalS": 3600,
  "fsWatcherEnabled": true,
  "ignorePerms": false,
  "autoNormalize": true,
  "scanProgressIntervalS": -1,
  "caseSensitiveFS": true,
  "sendOwnership": false,
  "syncOwnership": false,
  "maxConflicts": 10,
  "fsWatcherDelayS": 1
}
EOF
}

configure_folder() {
    mkdir -p "$FOLDER_PATH"
    my_id=$(api GET "$(api_url)/rest/system/status" | json_extract myID)
    [ -n "$my_id" ] || { echo "Could not determine local Syncthing device ID" >&2; return 1; }

    if api GET "$(api_url)/rest/config/folders/${FOLDER_ID}" >/dev/null 2>&1; then
        api PATCH "$(api_url)/rest/config/folders/${FOLDER_ID}" \
            '{"label":"'"$FOLDER_LABEL"'","path":"'"$FOLDER_PATH"'","type":"sendreceive","ignorePerms":false,"sendOwnership":false,"syncOwnership":false,"maxConflicts":10,"fsWatcherDelayS":1}' \
            >/dev/null
    else
        api POST "$(api_url)/rest/config/folders" "$(folder_payload "$my_id")" >/dev/null
    fi
}

local_ip() {
    ip=$(hostname -i 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    fi
    printf '%s' "$ip"
}

scan_for_peers() {
    ip="$1"
    prefix=$(printf '%s' "$ip" | cut -d. -f1-3)
    [ -n "$prefix" ] || return 0
    seq 1 254 | xargs -P 32 -I {} sh -c '
        prefix="$1"
        key="$2"
        port="$3"
        peer="${prefix}.${4}"
        if curl -sS -f --max-time 2 -o /dev/null \
            -H "X-API-Key: ${key}" \
            "http://${peer}:${port}/rest/system/status" 2>/dev/null; then
            printf "%s\\n" "$peer"
        fi
    ' sh "$prefix" "$KEY" "$PORT" {}
}

contains() {
    case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

add_or_update_device() {
    target_ip="$1"
    device_id="$2"
    device_ip="$3"
    target="http://${target_ip}:${PORT}/rest/config/devices"
    existing=$(api GET "$target" | json_extract_array deviceID | tr '\n' ' ')
    payload=$(printf '{"deviceID":"%s","addresses":["tcp://%s:%s"],"autoAcceptFolders":true}' \
        "$device_id" "$device_ip" "$SYNC_PORT")

    if contains "$existing" "$device_id"; then
        api PATCH "${target}/${device_id}" "$payload" >/dev/null 2>&1 || true
    else
        api POST "$target" "$payload" >/dev/null
    fi
}

configure_devices() {
    pairs="$1"
    for pair in $pairs; do
        target_ip=${pair%%|*}
        for other in $pairs; do
            other_ip=${other%%|*}
            other_id=${other#*|}
            [ "$target_ip" = "$other_ip" ] && continue
            add_or_update_device "$target_ip" "$other_id" "$other_ip"
        done
    done
}

configure_folder_devices() {
    ips="$1"
    ids="$2"
    for peer in $ips; do
        folder="http://${peer}:${PORT}/rest/config/folders/${FOLDER_ID}"
        [ "$peer" = "$(local_ip)" ] && folder="$(api_url)/rest/config/folders/${FOLDER_ID}"
        api PATCH "$folder" "$(printf '{"devices":[%s]}' "$ids")" >/dev/null 2>&1 || true
    done
}

configure_cluster() {
    wait_for_syncthing
    configure_options
    configure_folder

    self_ip=$(local_ip)
    [ -n "$self_ip" ] || { echo "Could not determine overlay address" >&2; return 1; }

    peers=$(scan_for_peers "$self_ip" | sort -u | tr '\n' ' ')
    all_ips="$self_ip $peers"
    pairs=""
    ids=""

    for peer in $all_ips; do
        response=$(curl -sS -f --max-time 10 \
            -H "X-API-Key: $KEY" \
            "http://${peer}:${PORT}/rest/system/status" 2>/dev/null || true)
        id=$(printf '%s' "$response" | json_extract myID)
        [ -n "$id" ] || continue
        pairs="$pairs ${peer}|${id}"
        ids="$ids {\"deviceID\":\"${id}\"},"
    done

    [ -n "$pairs" ] || { echo "No Syncthing peers discovered; local folder is ready"; return 0; }
    ids=$(printf '%s' "$ids" | sed 's/,$//')
    configure_devices "$pairs"
    configure_folder_devices "$all_ips" "$ids"
    echo "Syncthing cluster configuration completed"
}

configure_cluster > /proc/1/fd/1 2>/proc/1/fd/2 &

if [ "$(id -u)" = "0" ]; then
    binary="$1"
    if [ -n "${PCAP:-}" ]; then
        setcap "$PCAP" "$binary"
    else
        setcap -r "$binary" 2>/dev/null || true
    fi
    chown "${PUID}:${PGID}" "$HOME" 2>/dev/null || true
    exec su-exec "${PUID}:${PGID}" env HOME="$HOME" "$@"
else
    exec "$@"
fi
