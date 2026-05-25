#!/bin/bash

CONFIG_FILE="${GOACCESS_PRESET_CONF:-/etc/goaccess-wrapper.yaml}"
HISTORY_LOG="${GOACCESS_HISTORY_LOG:-/var/log/goaccess-wrapper.log}"

# =============================
# FLAGS
# =============================
VHOST=""
PRESET_EXCLUDE=""
PRESET_INCLUDE=""
USER_EXCLUDE=()
USER_INCLUDE=()

LIST=0
CHECK=0
DRY_RUN=0
EXPLAIN=0

OUTPUT_DIR="/var/www/html"
OUTPUT_HTML=0

# explain storage
declare -A EXPLAIN_MAP

# =============================
# AUTO CONFIG
# =============================
create_default_config() {
  local file="$1"
  mkdir -p "$(dirname "$file")"

  cat > "$file" << 'EOF'
presets:
  localhost:
    exclude:
      - 127.0.0.1
      - ::1

  internal:
    exclude:
      - 10.0.0.0/8
      - 192.168.0.0/16
      - 172.16.0.0/12

  office:
    include:
      - 37.179.5.219

  machine:
    include: []
EOF

  chmod 600 "$file"
}

[[ ! -f "$CONFIG_FILE" ]] && create_default_config "$CONFIG_FILE"

# =============================
# REQUIREMENTS CHECK
# =============================
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
python3 -c "import yaml" 2>/dev/null || { echo "PyYAML required"; exit 1; }

# =============================
# YAML LOADER
# =============================
load_yaml() {
python3 - <<EOF
import yaml, json

with open("$CONFIG_FILE") as f:
    data = yaml.safe_load(f)

print(json.dumps(data))
EOF
}

CONFIG_JSON="$(load_yaml)"

# =============================
# USAGE
# =============================
usage() {
  echo "Usage:"
  echo "  -v vhost"
  echo "  -p exclude presets"
  echo "  -P include presets"
  echo "  -i exclude ip"
  echo "  -r include ip"
  echo "  -o output dir (default /var/www/html)"
  echo "  --list-presets"
  echo "  --check-config"
  echo "  --dry-run"
  echo "  --explain"
  exit 1
}

# =============================
# ARGS
# =============================
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v) VHOST="$2"; shift 2 ;;
    -p) PRESET_EXCLUDE="$2"; shift 2 ;;
    -P) PRESET_INCLUDE="$2"; shift 2 ;;
    -i) USER_EXCLUDE+=("$2"); shift 2 ;;
    -r) USER_INCLUDE+=("$2"); shift 2 ;;
    -o)
      OUTPUT_DIR="$2"
      OUTPUT_HTML=1
      shift 2
      ;;
    --list-presets) LIST=1; shift ;;
    --check-config) CHECK=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --explain) EXPLAIN=1; shift ;;
    *) usage ;;
  esac
done

# =============================
# VALIDATION
# =============================
if [[ $OUTPUT_HTML -eq 1 ]]; then
  if [[ "$OUTPUT_DIR" != /* ]]; then
    echo "ERROR: output directory must be an absolute path"
    exit 1
  fi
fi

# =============================
# PRESET FETCH
# =============================
get_preset() {
python3 - "$1" "$2" <<EOF
import json, sys
data = json.loads("""$CONFIG_JSON""")

preset = sys.argv[1]
ptype = sys.argv[2]

values = data["presets"].get(preset, {}).get(ptype, [])
print("\n".join(values))
EOF
}

# =============================
# LIST PRESETS
# =============================
list_presets() {
python3 - <<EOF
import json
data = json.loads("""$CONFIG_JSON""")

print("AVAILABLE PRESETS:")
for k in data["presets"]:
    print("-", k)
EOF
}

# =============================
# CIDR CHECK
# =============================
ip_in_cidr() {
python3 - <<EOF
import ipaddress
print(ipaddress.ip_address("$1") in ipaddress.ip_network("$2", strict=False))
EOF
}

# =============================
# BUILD LISTS
# =============================
ALL_EXCLUDE=()
ALL_INCLUDE=()

IFS=',' read -ra EP <<< "$PRESET_EXCLUDE"
IFS=',' read -ra IP <<< "$PRESET_INCLUDE"

for p in "${EP[@]}"; do
  [[ -z "$p" ]] && continue
  while read -r ip; do
    [[ -n "$ip" ]] && ALL_EXCLUDE+=("$ip")
  done < <(get_preset "$p" "exclude")
done

for p in "${IP[@]}"; do
  [[ -z "$p" ]] && continue
  while read -r ip; do
    [[ -n "$ip" ]] && ALL_INCLUDE+=("$ip")
  done < <(get_preset "$p" "include")
done

ALL_EXCLUDE+=("${USER_EXCLUDE[@]}")

SYSTEM_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n')
ALL_EXCLUDE+=($SYSTEM_IPS)

# =============================
# FILTER ENGINE + EXPLAIN
# =============================
FINAL_EXCLUDE=()

add_trace() {
  local ip="$1"
  local msg="$2"
  EXPLAIN_MAP["$ip"]+="$msg"$'\n'
}

for ip in "${ALL_EXCLUDE[@]}"; do
  skip=0

  for inc in "${ALL_INCLUDE[@]}"; do
    if [[ "$ip" == "$inc" ]]; then
      skip=1
      [[ $EXPLAIN -eq 1 ]] && add_trace "$ip" "INCLUDED (exact match)"
      break
    fi
  done

  for inc in "${ALL_INCLUDE[@]}"; do
    if [[ "$inc" == *"/"* ]]; then
      if ip_in_cidr "$ip" "$inc"; then
        skip=1
        [[ $EXPLAIN -eq 1 ]] && add_trace "$ip" "INCLUDED (CIDR match $inc)"
        break
      fi
    fi
  done

  if [[ $skip -eq 0 ]]; then
    FINAL_EXCLUDE+=("$ip")
    [[ $EXPLAIN -eq 1 ]] && add_trace "$ip" "EXCLUDED (default rule)"
  fi
done

# =============================
# GOACCESS COMMAND
# =============================
LOG_PATH="/var/www/${VHOST}/log/access.log"

CMD=(goaccess -c "$LOG_PATH"
  --log-format=COMBINED
  --geoip-database=/usr/share/GeoIP/GeoLite2-City.mmdb
  --geoip-database=/usr/share/GeoIP/GeoLite2-ASN.mmdb
)

for ip in "${FINAL_EXCLUDE[@]}"; do
  CMD+=("--exclude-ip=$ip")
done

# =============================
# OUTPUT HTML SUPPORT
# =============================
HTML_OUTPUT="$OUTPUT_DIR/report.html"

if [[ $OUTPUT_HTML -eq 1 ]]; then
  mkdir -p "$OUTPUT_DIR"
  CMD+=(
    -o "$HTML_OUTPUT"
    #--real-time-html
  )
  echo "HTML OUTPUT: $HTML_OUTPUT"
fi

# =============================
# OUTPUT
# =============================
echo "======================================"
echo "GOACCESS COMMAND:"
printf '%q ' "${CMD[@]}"
echo ""
echo "======================================"

[[ $OUTPUT_HTML -eq 1 ]] && echo "HTML OUTPUT: $HTML_OUTPUT"

# =============================
# EXPLAIN MODE
# =============================
if [[ $EXPLAIN -eq 1 ]]; then
  echo ""
  echo "================ EXPLAIN MODE ================"

  for ip in "${ALL_EXCLUDE[@]}"; do
    echo ""
    echo "IP: $ip"
    echo "--------------------------------------"
    echo -e "${EXPLAIN_MAP[$ip]}"
  done

  echo "=============================================="
fi

# =============================
# HISTORY
# =============================
echo "$(date '+%F %T') ${CMD[*]}" >> "$HISTORY_LOG"

# =============================
# MODES
# =============================
[[ $LIST -eq 1 ]] && list_presets && exit 0
[[ $CHECK -eq 1 ]] && echo "OK CONFIG" && exit 0
[[ $DRY_RUN -eq 1 ]] && exit 0

exec "${CMD[@]}"