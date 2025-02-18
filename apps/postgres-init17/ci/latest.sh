#!/usr/bin/env bash
version=$(curl -sX GET "https://pkgs.alpinelinux.org/package/edge/main/x86_64/postgresql17-client" | grep -oP '(?<=>)(.*?)(?=<\/strong>)' 2>/dev/null)
version="${version%%_*}"
version="${version%%-*}"
printf "%s" "${version}"
