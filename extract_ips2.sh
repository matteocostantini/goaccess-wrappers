#!/bin/bash

LOG="/var/www/domhook.matteo-costantini.it/log/*"
GEOIP="/usr/share/GeoIP/GeoLite2-Country.mmdb"
OUTDIR="./continenti"

mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.txt

# 1. Genera JSON da GoAccess con zcat
for file in $LOG; do
    zcat -f "$file"
done | goaccess -c - \
  --log-format=COMBINED \
  --geoip-database="$GEOIP" \
  -o report.json \
  >/dev/null 2>&1

# 2. Estrai paesi e IP da hosts
jq -r '.hosts.data[] | "\(.country)|\(.data)"' report.json | while IFS='|' read -r country ip; do
    FILE="$OUTDIR/${country}.txt"
    echo "$ip" >> "$FILE"
done

echo "✔ File generati in $OUTDIR"
