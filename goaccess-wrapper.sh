#!/bin/bash

CONFIG_FILE="${GOACCESS_PRESET_CONF:-/etc/goaccess-wrapper.yaml}"
HISTORY_LOG="${GOACCESS_HISTORY_LOG:-/var/log/goaccess-wrapper.log}"

# =============================
# AUTO CONFIG YAML
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
    exclude:
      - 37.179.5.219

  machine:
    include: []
EOF

  chmod 600 "$file"
}

[[ ! -f "$CONFIG_FILE" ]] && create_default_config "$CONFIG_FILE"

# =============================
# YAML PARSER (python, robust)
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
# DEPENDENCIES CHECK
# =============================
command -v python3 >/dev/null || {
  echo "❌ python3 required"
  exit 1
}

python3 -c "import yaml" 2>/dev/null || {
  echo "❌ PyYAML required: pip install pyyaml"
  exit 1
}

# =============================
# ARGUMENTS
# =============================
VHOST=""
PRESET_EXCLUDE=""
PRESET_INCLUDE=""
USER_EXCLUDE=()
USER_INCLUDE=()
LIST=0
CHECK=0
DRY_RUN=0

usage() {
  echo "Usage:"
  echo "  -v vhost"
  echo "  -p exclude presets (comma)"
  echo "  -P include presets (comma)"
  echo "  --list-presets"
  echo "  --check-config"
  echo "  --dry-run"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v) VHOST="$2"; shift 2 ;;
    -p) PRESET_EXCLUDE="$2"; shift 2 ;;
    -P) PRESET_INCLUDE="$2"; shift 2 ;;
    -i) USER_EXCLUDE+=("$2"); shift 2 ;;
    -r) USER_INCLUDE+=("$2"); shift 2 ;;
    --list-presets) LIST=1; shift ;;
    --check-config) CHECK=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done

# =============================
# PRESET EXTRACTOR (python)
# =============================
get_preset_values() {
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

print("AVAILABLE PRESETS:\n")
for k,v in data["presets"].items():
    print(f"- {k}")
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

IFS=',' read -ra EX_PRESETS <<< "$PRESET_EXCLUDE"
IFS=',' read -ra IN_PRESETS <<< "$PRESET_INCLUDE"

for p in "${EX_PRESETS[@]}"; do
  [[ -z "$p" ]] && continue
  while read -r ip; do
    [[ -n "$ip" ]] && ALL_EXCLUDE+=("$ip")
  done < <(get_preset_values "$p" "exclude")
done

for p in "${IN_PRESETS[@]}"; do
  [[ -z "$p" ]] && continue
  while read -r ip; do
    [[ -n "$ip" ]] && ALL_INCLUDE+=("$ip")
  done < <(get_preset_values "$p" "include")
done

# user IPs
ALL_EXCLUDE+=("${USER_EXCLUDE[@]}")

SYSTEM_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n')
ALL_EXCLUDE+=($SYSTEM_IPS)

# =============================
# FILTERING ENGINE
# =============================
FINAL_EXCLUDE=()

for ip in "${ALL_EXCLUDE[@]}"; do
  skip=0

  for inc in "${ALL_INCLUDE[@]}"; do
    [[ "$ip" == "$inc" ]] && skip=1 && break
  done

  for inc in "${ALL_INCLUDE[@]}"; do
    [[ "$inc" == *"/"* ]] && ip_in_cidr "$ip" "$inc" && skip=1 && break
  done

  [[ $skip -eq 0 ]] && FINAL_EXCLUDE+=("$ip")
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
# OUTPUT
# =============================
echo "======================================"
echo "GOACCESS COMMAND:"
printf '%q ' "${CMD[@]}"
echo ""
echo "======================================"

# =============================
# HISTORY
# =============================
echo "$(date '+%F %T') ${CMD[*]}" >> "$HISTORY_LOG"

# =============================
# MODES
# =============================
[[ $LIST -eq 1 ]] && list_presets && exit 0
[[ $CHECK -eq 1 ]] && echo "OK YAML config" && exit 0

[[ $DRY_RUN -eq 1 ]] && exit 0

exec "${CMD[@]}"