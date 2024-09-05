#!/usr/bin/env bash
version=$(curl -sX GET "https://api.github.com/repos/advplyr/audiobookshelf/releases/latest" | jq --raw-output '.tag_name' 2>/dev/null)
tarball_url=$(curl -sX GET "https://api.github.com/repos/advplyr/audiobookshelf/releases/latest" | jq --raw-output '.tarball_url' 2>/dev/null)
version="${version#*v}"
version="${version#*release-}"
tarball_url="${tarball_url}"
printf "%s" "${version}"
printf "%s" "${tarball_url}"
