#!/usr/bin/env bash
#
# Look up up to MAX_CREATURES creatures (by name, key, or uuid —
# case-insensitive) in a local dinodex_items.json (produced by
# dinodex_extract.sh), then for each one walk the Paleo.gg fusion tree
# starting from its detail page:
#
#   https://paleo.gg/games/jurassic-world-alive/dinodex/<creaturename>
#
# On each page visited, props.pageProps.detail.ingredients and .hybrids are
# read. Every name found in .hybrids is visited in turn (breadth-first,
# de-duplicated) until a branch's hybrids list is empty. Every hybrid
# encountered (the root creature itself is excluded) is collected as
# {uuid, name, rarity}.
#
# Output is a JSON array on stdout, one object per creature parameter (in
# the order given). All object keys, at every nesting level, are sorted
# alphabetically (jq -S). Shape (key order shown alphabetically):
#   {
#     class, creature_url, location, name, rarity, time, uuid   -- the
#                                       parameter creature itself; "name",
#                                       "creature_url", "location", and
#                                       "time" are looked up by uuid in the
#                                       local dinodex data
#     ingredients: [{creature_url, location, name, rarity, time, uuid}, ...]
#                                              -- omitted only when the
#                                              parameter creature's hybrid_type
#                                              is "non_hybrid". The uuid list
#                                              comes from detail.ingredients
#                                              (the direct ingredients only,
#                                              same count regardless of tier);
#                                              each uuid's rarity is looked up
#                                              in detail.evolutionData, while
#                                              name/location/time/creature_url
#                                              are looked up in the local
#                                              dinodex_items.json (not
#                                              refetched from the site)
#     hybrids: [{creature_url, name, rarity, uuid}, ...]  -- downstream
#                                              fusion chain; creature_url is
#                                              looked up the same way
#   }
# A creature parameter that fails to resolve (no match / ambiguous match) is
# skipped with a warning on stderr rather than aborting the whole batch.
#
# Usage: ./dinodex_hybrid_chain.sh [-f dinodex_items.json] <name|key|uuid> [<name|key|uuid> ...]
#        Up to $DINODEX_MAX_CREATURES (default 10) creature parameters.

set -euo pipefail

BASE_URL="https://paleo.gg/games/jurassic-world-alive/dinodex"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
SLEEP_BETWEEN="${DINODEX_SLEEP:-0.3}"
SLEEP_BETWEEN_CREATURES="${DINODEX_CREATURE_SLEEP:-3}"
MAX_CREATURES="${DINODEX_MAX_CREATURES:-10}"
ITEMS_FILE="dinodex_items.json"
CREATURES=()

usage() {
  echo "Usage: $0 [-f dinodex_items.json] <name|key|uuid> [<name|key|uuid> ...]" >&2
  echo "       Up to $MAX_CREATURES creature parameters." >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires a path." >&2; exit 1; }
      ITEMS_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do CREATURES+=("$1"); shift; done
      ;;
    -*)
      echo "Error: unknown option '$1'." >&2
      usage
      exit 1
      ;;
    *)
      CREATURES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#CREATURES[@]} -eq 0 ]]; then
  usage
  exit 1
fi

if [[ ${#CREATURES[@]} -gt $MAX_CREATURES ]]; then
  echo "Error: at most $MAX_CREATURES creature parameters are supported (got ${#CREATURES[@]})." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

# On Windows, jq.exe is a native console binary and writes CRLF line endings.
# That stray \r survives `read`/process-substitution and corrupts values used
# as URL segments or array keys downstream, so strip it at the source. This
# is a no-op on Linux (no \r appears in native jq output there).
jq() {
  command jq "$@" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

if [[ ! -f "$ITEMS_FILE" ]]; then
  echo "Error: items file '$ITEMS_FILE' not found. Run dinodex_extract.sh first." >&2
  exit 1
fi

# uuid -> {name, location, time, creature_url}, sourced from the local
# dinodex data (no extra HTTP requests needed to resolve creature/ingredient
# names or look up dna_source location/time/creature_url).
#
# This lookup is passed to jq via --slurpfile (a file path) rather than
# --argjson (an inline string): jq.exe is a native Windows binary subject to
# Windows' command-line length limit, and an inline --argjson blob this size
# (500+ items) reliably blows past it with "Argument list too long". Kept
# this way on Linux too for a single consistent code path.
ITEM_LOOKUP_FILE="$(mktemp)"
trap 'rm -f "$ITEM_LOOKUP_FILE"' EXIT
jq '[.[] | {key: .uuid, value: {name, location, time, creature_url}}] | from_entries' "$ITEMS_FILE" > "$ITEM_LOOKUP_FILE"

# Cache of already-fetched detail pages (uuid/key -> detail JSON), shared
# across all creature parameters in this run so overlapping fusion-tree
# branches aren't re-fetched.
declare -A FETCH_CACHE

# --- Fetch + parse a single creature detail page ---------------------------
# Prints {name, uuid, rarity, class, hybrid_type, ingredients[], hybrids[],
# evolutionData{}} as JSON on success.

fetch_detail() {
  local key="$1"
  local url="$BASE_URL/$key"
  local html next_data detail

  if [[ -n "${FETCH_CACHE[$key]:-}" ]]; then
    printf '%s' "${FETCH_CACHE[$key]}"
    return 0
  fi

  if ! html="$(curl -sfL -A "$USER_AGENT" "$url")"; then
    echo "Warning: failed to fetch $url" >&2
    return 1
  fi

  next_data="$(grep -o '<script id="__NEXT_DATA__"[^>]*>.*</script>' <<< "$html" \
    | sed -e 's/^<script id="__NEXT_DATA__"[^>]*>//' -e 's/<\/script>$//')"

  if [[ -z "$next_data" ]]; then
    echo "Warning: could not find __NEXT_DATA__ on $url" >&2
    return 1
  fi

  detail="$(jq '.props.pageProps.detail
      | {name, uuid, rarity, class, hybrid_type,
         ingredients: (.ingredients // []),
         hybrids: (.hybrids // []),
         evolutionData: (.evolutionData // {})}' \
    <<< "$next_data")" || return 1

  FETCH_CACHE["$key"]="$detail"
  printf '%s' "$detail"
}

# --- Resolve one creature parameter + walk its fusion tree -----------------
# Prints the creature's result object as JSON on stdout; returns 1 (no
# stdout) if the query doesn't resolve to exactly one item.

process_creature() {
  local query="$1"
  local matches_json match_count root_key

  matches_json="$(jq --arg q "$query" '
    [ .[] | select(
        ((.name // "") | ascii_downcase) == ($q | ascii_downcase)
        or ((.key  // "") | ascii_downcase) == ($q | ascii_downcase)
        or ((.uuid // "") | ascii_downcase) == ($q | ascii_downcase)
      )
    ]
  ' "$ITEMS_FILE")"

  match_count="$(jq 'length' <<< "$matches_json")"

  if [[ "$match_count" -eq 0 ]]; then
    echo "Error: no item found matching '$query' (checked name, key, uuid)." >&2
    return 1
  fi

  if [[ "$match_count" -gt 1 ]]; then
    echo "Error: '$query' matched $match_count items — not unique:" >&2
    jq -r '.[] | "  - \(.name) (key=\(.key), uuid=\(.uuid))"' <<< "$matches_json" >&2
    return 1
  fi

  root_key="$(jq -r '.[0].key' <<< "$matches_json")"
  echo "Matched: $(jq -r '.[0].name' <<< "$matches_json") (key=$root_key)" >&2

  local -A visited
  local queue=("$root_key")
  local results="[]"
  local is_root=1
  local root_uuid="" root_name="" root_rarity="" root_class="" root_hybrid_type="" root_creature_url="" root_location="" root_time="" root_ingredients="[]"
  local key detail uuid name rarity ingredients_display hybrid_count h

  visited["$root_key"]=1

  while [[ ${#queue[@]} -gt 0 ]]; do
    key="${queue[0]}"
    queue=("${queue[@]:1}")

    if ! detail="$(fetch_detail "$key")" || [[ -z "$detail" ]]; then
      continue
    fi

    uuid="$(jq -r '.uuid' <<< "$detail")"
    name="$(jq -r '.name' <<< "$detail")"
    rarity="$(jq -r '.rarity' <<< "$detail")"
    ingredients_display="$(jq -r '.ingredients | join(", ")' <<< "$detail")"
    hybrid_count="$(jq '.hybrids | length' <<< "$detail")"

    echo "Visited: $name (key=$key) rarity=$rarity ingredients=[$ingredients_display] hybrids_found=$hybrid_count" >&2

    if [[ "$is_root" -eq 1 ]]; then
      is_root=0
      root_uuid="$uuid"
      root_rarity="$rarity"
      root_class="$(jq -r '.class' <<< "$detail")"
      root_hybrid_type="$(jq -r '.hybrid_type' <<< "$detail")"
      root_name="$(jq -rn --slurpfile items "$ITEM_LOOKUP_FILE" --arg u "$root_uuid" '$items[0][$u].name // $u')"
      root_creature_url="$(jq -rn --slurpfile items "$ITEM_LOOKUP_FILE" --arg u "$root_uuid" '$items[0][$u].creature_url // ""')"
      root_location="$(jq -rn --slurpfile items "$ITEM_LOOKUP_FILE" --arg u "$root_uuid" '$items[0][$u].location // ""')"
      root_time="$(jq -rn --slurpfile items "$ITEM_LOOKUP_FILE" --arg u "$root_uuid" '$items[0][$u].time // ""')"

      if [[ "$root_hybrid_type" != "non_hybrid" ]]; then
        root_ingredients="$(jq --slurpfile itemsfile "$ITEM_LOOKUP_FILE" '
          ($itemsfile[0]) as $items
          | . as $root
          | ($root.ingredients // [])
          | map({
              uuid: .,
              name: ($items[.].name // .),
              rarity: ($root.evolutionData[.].rarity // null),
              location: ($items[.].location // null),
              time: ($items[.].time // null),
              creature_url: ($items[.].creature_url // null)
            })
        ' <<< "$detail")"
        echo "Root hybrid_type is '$root_hybrid_type' — including $(jq 'length' <<< "$root_ingredients") ingredient creature(s) from ingredients (rarity via evolutionData, name/location/time via local dinodex data)." >&2
      fi
    else
      results="$(jq --arg u "$uuid" --arg n "$name" --arg r "$rarity" --slurpfile itemsfile "$ITEM_LOOKUP_FILE" '
        ($itemsfile[0]) as $items
        | . + [{uuid: $u, name: $n, rarity: $r, creature_url: ($items[$u].creature_url // null)}]
      ' <<< "$results")"
    fi

    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      if [[ -z "${visited[$h]:-}" ]]; then
        visited["$h"]=1
        queue+=("$h")
      fi
    done < <(jq -r '.hybrids[]?' <<< "$detail")

    sleep "$SLEEP_BETWEEN"
  done

  if [[ "$root_hybrid_type" != "non_hybrid" ]]; then
    jq -n --arg uuid "$root_uuid" --arg name "$root_name" --arg rarity "$root_rarity" --arg class "$root_class" \
      --arg creature_url "$root_creature_url" --arg location "$root_location" --arg time "$root_time" \
      --argjson ingredients "$root_ingredients" --argjson hybrids "$results" \
      '{uuid: $uuid, name: $name, rarity: $rarity, class: $class, creature_url: $creature_url, location: $location, time: $time, ingredients: $ingredients, hybrids: $hybrids}'
  else
    jq -n --arg uuid "$root_uuid" --arg name "$root_name" --arg rarity "$root_rarity" --arg class "$root_class" \
      --arg creature_url "$root_creature_url" --arg location "$root_location" --arg time "$root_time" \
      --argjson hybrids "$results" \
      '{uuid: $uuid, name: $name, rarity: $rarity, class: $class, creature_url: $creature_url, location: $location, time: $time, hybrids: $hybrids}'
  fi
}

# --- Process each creature parameter ----------------------------------------

ALL_RESULTS="[]"
FIRST_CREATURE=1

for query in "${CREATURES[@]}"; do
  if [[ "$FIRST_CREATURE" -eq 0 ]]; then
    sleep "$SLEEP_BETWEEN_CREATURES"
  fi
  FIRST_CREATURE=0

  echo "=== Processing '$query' ===" >&2
  if creature_result="$(process_creature "$query")"; then
    ALL_RESULTS="$(jq --argjson r "$creature_result" '. + [$r]' <<< "$ALL_RESULTS")"
  else
    echo "Skipping '$query'." >&2
  fi
done

jq -S '.' <<< "$ALL_RESULTS"
