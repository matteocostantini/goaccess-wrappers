#!/bin/bash

LOG="/var/www/domhook.matteo-costantini.it/log/access.log"
GEOIP="/usr/share/GeoIP/GeoLite2-Country.mmdb"
OUTDIR="./continenti"

mkdir -p "$OUTDIR"

# 1. Genera JSON da GoAccess
goaccess "$LOG" \
  --log-format=COMBINED \
  --geoip-database="$GEOIP" \
  -o report.json \
  >/dev/null 2>&1

# 2. Estrai continenti e IP
jq -r '
  .geolocation.data[]
  | {continent: .continent, ips: [.items[].ip]}
' report.json \
| jq -s '
  group_by(.continent)[] |
  {
    continent: .[0].continent,
    ips: (map(.ips[]) | unique)
  }
' \
| while read -r line; do
    if [[ "$line" =~ \"continent\":\ \"([^\"]+)\" ]]; then
        CONT="${BASH_REMATCH[1]}"
        FILE="$OUTDIR/${CONT}.txt"
        echo -n "" > "$FILE"
    fi

    if echo "$line" | grep -q '"ips"'; then
        IPS=$(echo "$line" | sed -n 's/.*"ips":\[\([^]]*\)\].*/\1/p')
        echo "$IPS" | tr -d '"' | tr ',' '\n' >> "$FILE"
    fi
done

echo "✔ File generati in $OUTDIR"
