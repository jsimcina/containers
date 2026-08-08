#!/usr/bin/env bash
#
# Fetch the Paleo.gg JWA Dinodex page, pull the embedded Next.js data JSON,
# and extract props.pageProps.dex.items into a flat JSON array.
#
# Each item's dna_source[] (array of {loc, time[]}) is flattened into two
# top-level comma-delimited fields: "location" and "time". The original
# "dna_source" field is dropped from the output. "sanctuary" is dropped from
# "location" entirely (not just left untranslated). Remaining location
# tokens are translated to display names via a fixed mapping (see loc_names
# below); any other untranslated token (e.g. "none") passes through
# unchanged. "time" is translated as a whole joined value via time_names
# below (e.g. "dawn,day,dusk,night" -> "Always"); any other combination
# passes through as the raw comma-joined value.
#
# A "creature_url" field is also added to each item:
#   https://www.paleo.gg/games/jurassic-world-alive/dinodex/<uuid>
#
# Usage: ./dinodex_extract.sh [output_file.json]

set -euo pipefail

URL="https://www.paleo.gg/games/jurassic-world-alive/dinodex"
OUT_JSON="${1:-dinodex_items.json}"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  echo "Install it with one of:" >&2
  echo "  choco install jq" >&2
  echo "  scoop install jq" >&2
  echo "  winget install jqlang.jq" >&2
  exit 1
fi

# On Windows, jq.exe is a native console binary and writes CRLF line endings,
# which corrupts downstream string handling. Strip it at the source. This is
# a no-op on Linux (no \r appears in native jq output there).
jq() {
  command jq "$@" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

HTML_FILE="$(mktemp)"
trap 'rm -f "$HTML_FILE"' EXIT

echo "Fetching $URL ..." >&2
curl -sfL -A "$USER_AGENT" "$URL" -o "$HTML_FILE"

# The page embeds its data as: <script id="__NEXT_DATA__" type="application/json">{...}</script>
NEXT_DATA="$(grep -o '<script id="__NEXT_DATA__"[^>]*>.*</script>' "$HTML_FILE" \
  | sed -e 's/^<script id="__NEXT_DATA__"[^>]*>//' -e 's/<\/script>$//')"

if [[ -z "$NEXT_DATA" ]]; then
  echo "Error: could not find __NEXT_DATA__ script tag on the page." >&2
  exit 1
fi

echo "Extracting props.pageProps.dex.items and flattening dna_source ..." >&2

jq '
  def uniq_ordered:
    reduce .[] as $x ([]; if index($x) then . else . + [$x] end);

  def loc_names: {
    "continent_NA/SA/US": "Continental(Americas)",
    "continent_EU/US": "Continental(Europe)",
    "continent_AF/AN/AS/OC/US": "Continental(Asia)",
    "short_range": "Short Range",
    "local_area_1": "Zone 1",
    "local_area_2": "Zone 2",
    "local_area_3": "Zone 3",
    "local_area_4": "Zone 4",
    "park": "Park",
    "raid": "Raid",
    "alliance_missions": "Alliance Incubator",
    "everywhere": "Everywhere",
    "arena": "Arena",
    "strike_towers": "Strike Towers"
  };

  def time_names: {
    "dawn,day,dusk,night": "Always",
    "dusk,night": "Night",
    "dawn,day": "Day"
  };

  .props.pageProps.dex.items
  | map(
      (.dna_source // []) as $ds
      | ($ds | map(.loc) | uniq_ordered | map(select(. != "sanctuary")) | map(loc_names[.] // .)) as $locs
      | ($ds | map(.time // []) | add | uniq_ordered | join(",")) as $time_str
      | del(.dna_source)
        + {
            location: ($locs | join(",")),
            time: (time_names[$time_str] // $time_str),
            creature_url: ("https://www.paleo.gg/games/jurassic-world-alive/dinodex/" + .uuid)
          }
    )
' <<< "$NEXT_DATA" > "$OUT_JSON"

COUNT="$(jq 'length' "$OUT_JSON")"
echo "Wrote $COUNT items to $OUT_JSON" >&2
