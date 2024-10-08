#!/usr/bin/env bash

: "${GLUETUN_CONTROL_SERVER_HOST:=localhost}"
: "${GLUETUN_CONTROL_SERVER_PROTOCOL:=http}"
: "${GLUETUN_CONTROL_SERVER_PORT:=8000}"
: "${QBITTORRENT_PROTOCOL:=http}"
: "${QBITTORRENT_HOST:=localhost}"
: "${QBITTORRENT_WEBUI_PORT:=8080}"
: "${LOG_TIMESTAMP:=true}"
: "${MAM_ID_PATH:=/}"

mam_location="${MAM_ID_PATH}"
gluetun_origin="${GLUETUN_CONTROL_SERVER_PROTOCOL}://${GLUETUN_CONTROL_SERVER_HOST}:${GLUETUN_CONTROL_SERVER_PORT}"
qb_origin="${QBITTORRENT_PROTOCOL}://${QBITTORRENT_HOST}:${QBITTORRENT_WEBUI_PORT}"

declare -A gluetun_urls=(
  ["pub_ip"]="${gluetun_origin}/v1/publicip/ip"
  ["portforwarded"]="${gluetun_origin}/v1/openvpn/portforwarded"
)
declare -A qbittorrent_urls=(
  ["prefs"]="${qb_origin}/api/v2/app/preferences"
  ["setPrefs"]="${qb_origin}/api/v2/app/setPreferences"
)

log() {
  gum_opts=(
    "--structured"
  )

  if [[ "${LOG_TIMESTAMP}" = "true" ]]; then
    gum_opts+=(
      "--time" "rfc3339"
    )
  fi

  gum log "${gum_opts[@]}" "$@"
}

get_vpn_external_ip() {
  local url="$1"
  output=$(curl -us qbit:qbit "${url}")
  echo "${output}" | jq -r .'public_ip'
}

# Function to send a GET request and extract the port from the response
get_port_from_url_gluetun() {
  local url="$1"
  local port_key

  # Try 'port' key first
  output=$(curl -us qbit:qbit "${url}")
  port_key=$(echo "${output}" | jq -r '.port')

  if [[ "${port_key}" == "null" ]]; then
    # If 'port' key is null, try 'listen_port' key
    output=$(curl -us qbit:qbit "${url}")
    port_key=$(echo "${output}" | jq -r '.listen_port')
  fi

  echo "${port_key}"
}

get_port_from_url_gluetun() {
  local url="$1"
  local port_key

  # Try 'port' key first
  output=$(curl -s "${url}")
  port_key=$(echo "${output}" | jq -r '.port')

  if [[ "${port_key}" == "null" ]]; then
    # If 'port' key is null, try 'listen_port' key
    output=$(curl -s "${url}")
    port_key=$(echo "${output}" | jq -r '.listen_port')
  fi

  echo "${port_key}"
}

# Function to send a POST request with JSON data
send_post_request() {
  local url="$1"
  local port="$2"
  local payload="{\"listen_port\":${port}}"

  curl -s -X POST -d json="${payload}" "${url}"
}

log --level info "Starting check" \
  "gluetun_url" "${gluetun_origin}" \
  "qBittorrent_url" "${qb_origin}"

external_ip=$(get_vpn_external_ip "${gluetun_urls["pub_ip"]}")

if [[ -z "${external_ip}" ]]; then
  log --level error "External IP is empty. Potential VPN or internet connection issue."
fi

gluetun_port=$(get_port_from_url_gluetun "${gluetun_urls["portforwarded"]}")
qbittorrent_port=$(get_port_from_url "${qbittorrent_urls["prefs"]}")

log --level info "Fetched configuration" \
  "external_ip" "${external_ip}" \
  "gluetun_forwarded_port" "${gluetun_port}" \
  "qBittorrent_listen_port" "${qbittorrent_port}"

if [[ "${gluetun_port}" -eq "${qbittorrent_port}" ]]; then
  log --level info "qBittorrent listen port is already set to ${qbittorrent_port}. No need to change."
else
  log --level info "Updating qBittorrent listen port to ${gluetun_port}."
  send_post_request "${qbittorrent_urls["setPrefs"]}" "${gluetun_port}"
  qbittorrent_port=$(get_port_from_url "${qbittorrent_urls["prefs"]}")
  curl -c "${mam_location}" -b "${mam_location}" https://t.myanonamouse.net/json/dynamicSeedbox.php
fi

nc -z "${external_ip}" "${gluetun_port}" &>/dev/null
