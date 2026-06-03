#!/bin/bash

# ============================================================
#  USO:
#    ./extract_geoip.sh --countries IT,FR --continents EU,NA access.log
#    ./extract_geoip.sh --list-countries
#    ./extract_geoip.sh --list-continents
# ============================================================

GEOIP_DB="/usr/share/GeoIP/GeoLite2-Country.mmdb"
OUT_COUNTRIES="ip_paesi.txt"
OUT_CONTINENTS="ip_continenti.txt"

COUNTRIES=""
CONTINENTS=""
LOGS=""

# ============================================================
#  LISTE STATICHE (ISO2 + nome)
# ============================================================

declare -A COUNTRY_NAMES=(
    ["IT"]="Italy"
    ["FR"]="France"
    ["DE"]="Germany"
    ["ES"]="Spain"
    ["US"]="United States"
    ["CA"]="Canada"
    ["GB"]="United Kingdom"
    ["CN"]="China"
    ["JP"]="Japan"
    ["IN"]="India"
    # Aggiungibili altri se vuoi
)

declare -A CONTINENT_NAMES=(
    ["EU"]="Europe"
    ["NA"]="North America"
    ["SA"]="South America"
    ["AF"]="Africa"
    ["AS"]="Asia"
    ["OC"]="Oceania"
)

# ============================================================
#  FUNZIONI DI STAMPA LISTE
# ============================================================

print_countries() {
    echo "Lista Paesi (ISO2 → Nome):"
    for code in "${!COUNTRY_NAMES[@]}"; do
        printf "%-3s %s\n" "$code" "${COUNTRY_NAMES[$code]}"
    done
    exit 0
}

print_continents() {
    echo "Lista Continenti (Codice → Nome):"
    for code in "${!CONTINENT_NAMES[@]}"; do
        printf "%-3s %s\n" "$code" "${CONTINENT_NAMES[$code]}"
    done
    exit 0
}

# ============================================================
#  PARSING OPZIONI
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --countries)
            COUNTRIES="$2"
            shift 2
            ;;
        --continents)
            CONTINENTS="$2"
            shift 2
            ;;
        --list-countries)
            print_countries
            ;;
        --list-continents)
            print_continents
            ;;
        --help|-h)
            echo "Uso: $0 [--countries IT,FR] [--continents EU,NA] <logfile>"
            echo "     $0 --list-countries"
            echo "     $0 --list-continents"
            exit 0
            ;;
        *)
            LOGS="$1"
            shift
            ;;
    esac
done

# ============================================================
#  VALIDAZIONE PARAMETRI
# ============================================================
if [ -z "$LOGS" ]; then
    echo "ERRORE: devi specificare il file di log come ultimo parametro."
    exit 1
fi

if [ ! -f "$LOGS" ] && [ ! -f "$LOGS.gz" ]; then
    echo "ERRORE: log non trovato: $LOGS"
    exit 1
fi

if [ ! -f "$GEOIP_DB" ]; then
    echo "ERRORE: database GeoIP non trovato: $GEOIP_DB"
    exit 1
fi

if [ -z "$COUNTRIES" ] && [ -z "$CONTINENTS" ]; then
    echo "ERRORE: devi specificare almeno --countries o --continents."
    exit 1
fi

IFS=',' read -r -a COUNTRY_LIST <<< "$COUNTRIES"
IFS=',' read -r -a CONTINENT_LIST <<< "$CONTINENTS"

# ============================================================
#  ESTRAZIONE IP UNICI
# ============================================================
echo "Estrazione IP unici da: $LOGS"

IP_LIST=$(mktemp)
zcat -f "$LOGS" | awk '{print $1}' | sort -u > "$IP_LIST"

# ============================================================
#  RESET OUTPUT
# ============================================================
> "$OUT_COUNTRIES"
> "$OUT_CONTINENTS"

# ============================================================
#  LOOP GEOIP
# ============================================================
echo "Risoluzione GeoIP..."

while read -r ip; do
    country=$(mmdblookup --file "$GEOIP_DB" --ip "$ip" country iso_code 2>/dev/null \
              | awk -F'"' '/"/{print $2}')

    continent=$(mmdblookup --file "$GEOIP_DB" --ip "$ip" continent code 2>/dev/null \
                | awk -F'"' '/"/{print $2}')

    # Match paesi
    for c in "${COUNTRY_LIST[@]}"; do
        if [ "$country" = "$c" ]; then
            echo "$ip" >> "$OUT_COUNTRIES"
        fi
    done

    # Match continenti
    for k in "${CONTINENT_LIST[@]}"; do
        if [ "$continent" = "$k" ]; then
            echo "$ip" >> "$OUT_CONTINENTS"
        fi
    done

done < "$IP_LIST"

rm "$IP_LIST"

echo "Completato."
echo "IP dei paesi selezionati → $OUT_COUNTRIES (tot: $(wc -l < "$OUT_COUNTRIES"))"
echo "IP dei continenti selezionati → $OUT_CONTINENTS (tot: $(wc -l < "$OUT_CONTINENTS"))"
