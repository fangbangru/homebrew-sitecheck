# sitecheck - Customizable site performance testing script with threshold alerts, colored output, JSON/CSV export
#           Built-in detection command: site information probe (redirects/IP/host/server/CMS/X-Powered-By)
#
# MIT License
# Copyright (c) 2025 BANGRUI FANG
# https://github.com/fangbangru/homebrew-sitecheck

set -uo pipefail
VERSION="0.2.0"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

site_info() {
  local URL="$1"
  [[ ! "$URL" =~ ^https?:// ]] && URL="https://$URL"
  local HOST=${URL#https://}; HOST=${HOST#http://}; HOST=${HOST%%/*}

  local REDIR
  REDIR=$(curl -s -o /dev/null -w '%{redirect_url}' -L "$URL")
  REDIR=${REDIR:-$URL}

  local IP
  IP=$(dig +short A "$HOST" | head -n1)
  IP=${IP:-Unknown}

  local ORG
  ORG=$(whois "$IP" 2>/dev/null \
    | grep -E '^(Org(Name|anization)|Registrant Organization):' \
    | head -n1 \
    | cut -d: -f2- \
    | sed 's/^ *//')
  ORG=${ORG:-Unknown}

  local SERVER
  SERVER=$(curl -s -I -L "$URL" \
    | grep -i '^Server:' \
    | head -n1 \
    | cut -d' ' -f2-)
  SERVER=${SERVER:-Unknown}

  local GEN
  GEN=$(curl -s "$URL" \
    | grep -i '<meta[^>]*name=["'"'"']generator["'"'"']' \
    | head -n1 \
    | sed -E 's/.*content=["'"'"']([^"'"'"']+).*/\1/')
  GEN=${GEN:-Unknown}

  local XPBY
  XPBY=$(curl -s -I "$URL" \
    | grep -i '^X-Powered-By:' \
    | head -n1 \
    | cut -d' ' -f2-)
  XPBY=${XPBY:-Unknown}

  local SSL_INFO
  if [[ "$URL" =~ ^https:// ]]; then
    SSL_INFO=$(echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | head -n2 | tr '\n' ' ')
    SSL_INFO=${SSL_INFO:-"SSL info unavailable"}
  else
    SSL_INFO="Not HTTPS"
  fi

  local HEADERS
  HEADERS=$(curl -s -I "$URL" | grep -E "^(Content-Type|Cache-Control|Last-Modified):" | head -n3 | sed 's/^/  /')
  HEADERS=${HEADERS:-"  No additional headers"}

  cat <<EOF
Redirects to: $REDIR
IP address:   $IP
Hosting:      $ORG
Running on:   $SERVER
CMS:          $GEN
Powered by:   $XPBY
SSL Info:     $SSL_INFO
Headers:
$HEADERS
EOF
}

load_config() {
  local config_file="$HOME/.sitecheck"
  if [[ -f "$config_file" ]]; then
    printf "${GREEN}Loading config file: %s${NC}\n" "$config_file"

    local temp_file=$(mktemp)
    grep -E '^[A-Z_]+=' "$config_file" | grep -v '^#' > "$temp_file"
    
    while IFS='=' read -r key value; do
      case "$key" in
        COUNT) COUNT="$value" ;;
        TIMEOUT) TIMEOUT="$value" ;;
        WARN_LOSS) WARN_LOSS="$value" ;;
        WARN_LATENCY) WARN_LATENCY="$value" ;;
        FORMAT) FORMAT="$value" ;;
        NO_HTTPING) NO_HTTPING="$value" ;;
      esac
    done < "$temp_file"
    
    rm -f "$temp_file"
  fi
}

REQUIRED_CMDS=(ping curl bc awk)
MISSING_REQUIRED=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" &>/dev/null || MISSING_REQUIRED+=("$cmd")
done
if ((${#MISSING_REQUIRED[@]})); then
  printf "${RED}Error: The following required commands are missing: %s${NC}\n" "${MISSING_REQUIRED[*]}"
  echo "Please install them first, e.g.: brew install ${MISSING_REQUIRED[*]}"
  exit 1
fi

if ! command -v httping &>/dev/null; then
  printf "${YELLOW}Warning: httping not installed, will skip HTTPS latency test.${NC}\n"
  echo "To install httping, run: 'brew install httping'"
fi

COUNT=3
TIMEOUT=10
NO_HTTPING=0
WARN_LOSS=100
WARN_LATENCY=1000
FORMAT="plain"
EXIT_CODE=0
QUIET=0

load_config

# ----------------------------------------
# Parameter parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: sitecheck [COMMAND] [OPTIONS] <URL>

Commands:
  detection              Detect site information (redirects/IP/host/server/CMS/X-Powered-By)
  batch <file>           Batch test multiple sites from file (one URL per line)

Options:
  -h, --help                 Show help information
  -v, --version              Show version number
  --no-httping               Skip HTTPS latency test
  -c, --count <N>            Number of ping/httping requests (default 3)
  -t, --timeout <SEC>        curl request timeout in seconds (default 10)
  --warn-loss <PERCENT>      Packet loss warning threshold (%)
  --warn-latency <MS>        Average latency warning threshold (ms)
  --format <plain|json|csv>  Output format (plain default)
  --config                   Generate sample config file to ~/.sitecheck
  --quiet                    Quiet mode, only output results without progress

Examples:
  sitecheck example.com
  sitecheck detection example.com
  sitecheck -c 5 -t 5 --warn-loss 20 --warn-latency 300 --format json example.com
EOF
      exit 0
      ;;
    -v|--version)
      echo "sitecheck version $VERSION"
      exit 0
      ;;
    detection)
      shift
      if [[ -z "${1:-}" ]]; then
        printf "${RED}Usage: sitecheck detection <URL>${NC}\n"
        exit 1
      fi
      site_info "$1"
      exit 0
      ;;
    batch)
      shift
      if [[ -z "${1:-}" ]] || [[ ! -f "$1" ]]; then
        printf "${RED}Usage: sitecheck batch <file>${NC}\n"
        printf "${RED}File not found or not specified${NC}\n"
        exit 1
      fi
      
      printf "${GREEN}Batch test mode, file: %s${NC}\n" "$1"
      if [[ "$FORMAT" == "csv" ]]; then
        printf 'host,loss,avg_rtt,min_rtt,max_rtt,stddev_rtt,http_code,dns,connect,ttfb,total,httping_avg\n'
      fi
      
      while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        [[ "$url" =~ ^# ]] && continue
        
        if [[ "$FORMAT" == "csv" ]]; then
          QUIET=1 bash "$0" --format csv --no-httping "$url" | tail -n 1
        else
          printf "\n${YELLOW}=== Testing $url ===${NC}"
          bash "$0" --no-httping "$url"
        fi
      done < "$1"
      exit 0
      ;;
    --no-httping)
      NO_HTTPING=1; shift ;;
    -c|--count)
      if [[ "$2" =~ ^[1-9][0-9]*$ ]] && (( $2 <= 100 )); then
        COUNT="$2"; shift 2
      else
        printf "${RED}Error: Request count must be a positive integer between 1-100${NC}" >&2
        exit 1
      fi
      ;;
    -t|--timeout)
      if [[ "$2" =~ ^[1-9][0-9]*$ ]] && (( $2 <= 300 )); then
        TIMEOUT="$2"; shift 2
      else
        printf "${RED}Error: Timeout must be a positive integer between 1-300 seconds${NC}" >&2
        exit 1
      fi
      ;;
    --warn-loss)
      if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$2 >= 0 && $2 <= 100" | bc -l) )); then
        WARN_LOSS="$2"; shift 2
      else
        printf "${RED}Error: Packet loss threshold must be a number between 0-100${NC}" >&2
        exit 1
      fi
      ;;
    --warn-latency)
      if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$2 >= 0" | bc -l) )); then
        WARN_LATENCY="$2"; shift 2
      else
        printf "${RED}Error: Latency threshold must be a non-negative number (milliseconds)${NC}" >&2
        exit 1
      fi
      ;;
    --format)
      case "$2" in
        plain|json|csv)
          FORMAT="$2"; shift 2 ;;
        *)
          printf "${RED}Error: Invalid format '$2'. Supported formats: plain, json, csv${NC}" >&2
          exit 1 ;;
      esac
      ;;
    --config)
      echo "# sitecheck configuration file
# Default request count
COUNT=3
# Default timeout (seconds)
TIMEOUT=10
# Packet loss warning threshold (%)
WARN_LOSS=20
# Latency warning threshold (milliseconds)
WARN_LATENCY=500
# Default output format (plain|json|csv)
FORMAT=plain
# Skip httping test (0|1)
NO_HTTPING=0" > "$HOME/.sitecheck"
      printf "${GREEN}Config file created: %s${NC}\n" "$HOME/.sitecheck"
      exit 0
      ;;
    --quiet)
      QUIET=1; shift ;;
    --no-color)
      GREEN=''; YELLOW=''; RED=''; NC=''; shift ;;
    -*)
      printf "${RED}Unknown option: $1${NC}" >&2
      exit 1 ;;
    *)
      URL="$1"; shift ;;
  esac
done

if [ -z "${URL:-}" ]; then
  echo "Usage: sitecheck [COMMAND] [OPTIONS] <URL>"
  exit 1
fi
[[ ! "$URL" =~ ^https?:// ]] && URL="https://$URL"

if [[ $QUIET -eq 0 ]]; then
  printf "Testing: %s\n  Requests: %d times, curl timeout: %ds\n" "$URL" "$COUNT" "$TIMEOUT"
fi

HOST=${URL#https://}; HOST=${HOST#http://}; HOST=${HOST%%/*}

PING_RAW=$(ping -c "$COUNT" "$HOST" 2>&1)
LOSS=$(echo "$PING_RAW" | awk '/packet loss/ {for(i=1;i<=NF;i++) if($i ~ /%/) {gsub(/%/, "", $i); print $i+0; break}}')
RTT_LINE=$(echo "$PING_RAW" | awk -F" = " '/min\/avg\/max\/stddev/ {print $2}')

if [[ -n "$RTT_LINE" ]]; then
  RTT_LINE_CLEAN=${RTT_LINE% ms}
  MIN_RTT=$(echo "$RTT_LINE_CLEAN" | cut -d'/' -f1)
  AVG_RTT=$(echo "$RTT_LINE_CLEAN" | cut -d'/' -f2)
  MAX_RTT=$(echo "$RTT_LINE_CLEAN" | cut -d'/' -f3)
  STDDEV_RTT=$(echo "$RTT_LINE_CLEAN" | cut -d'/' -f4)
else
  MIN_RTT="null"
  AVG_RTT="null"
  MAX_RTT="null"
  STDDEV_RTT="null"
fi

if (( LOSS >= WARN_LOSS )); then LOSS_FLAG="${RED}"; EXIT_CODE=2; else LOSS_FLAG="${GREEN}"; fi
if [[ "$AVG_RTT" != "null" ]]; then
  AVG_INT=${AVG_RTT%.*}
  if (( AVG_INT >= WARN_LATENCY )); then LAT_FLAG="${RED}"; EXIT_CODE=2; else LAT_FLAG="${GREEN}"; fi
else
  LAT_FLAG="${YELLOW}"
fi

CURL_RESULT=$(curl --max-time "$TIMEOUT" -o /dev/null -s \
  -w "%{http_code} %{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total}" \
  "$URL" 2>/dev/null)

if [[ $? -eq 0 && -n "$CURL_RESULT" ]]; then
  HTTP_CODE=$(awk '{print $1}' <<< "$CURL_RESULT")
  DNS=$(awk '{print $2}' <<< "$CURL_RESULT")
  CONNECT=$(awk '{print $3}' <<< "$CURL_RESULT")
  START=$(awk '{print $4}' <<< "$CURL_RESULT")
  TOTAL=$(awk '{print $5}' <<< "$CURL_RESULT")
else
  HTTP_CODE="000"
  DNS="null"
  CONNECT="null"
  START="null"
  TOTAL="null"
  printf "${RED}Warning: curl request failed, possibly due to network issues or timeout${NC}" >&2
fi

if (( NO_HTTPING == 0 )) && command -v httping &>/dev/null; then
  HTTPING_RAW=$(httping -G -k -c "$COUNT" "$URL" 2>&1)
  HTTPING_AVG=$(echo "$HTTPING_RAW" \
  | awk -F"min/avg/max = " '{print $2}' \
  | cut -d'/' -f2 \
  | tr -d '\r' | tr -d '\n' | sed 's/^ *//;s/ *$//')
else
  HTTPING_AVG="null"
fi

case "$FORMAT" in
  json)
    printf '{'
    printf '"host":"%s",' "$HOST"
    printf '"loss":%s,"avg_rtt":%s,"min_rtt":%s,"max_rtt":%s,"stddev_rtt":%s,' \
      "$LOSS" "$AVG_RTT" "$MIN_RTT" "$MAX_RTT" "$STDDEV_RTT"
    printf '"http_code":%s,' "$HTTP_CODE"
    printf '"dns":%s,"connect":%s,"ttfb":%s,"total":%s,' "$DNS" "$CONNECT" "$START" "$TOTAL"
    printf '"httping_avg":%s' "${HTTPING_AVG}"
    printf '}\n'
    ;;
  csv)
    printf 'host,loss,avg_rtt,min_rtt,max_rtt,stddev_rtt,http_code,dns,connect,ttfb,total,httping_avg\n'
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$HOST" "$LOSS" "$AVG_RTT" "$MIN_RTT" "$MAX_RTT" "$STDDEV_RTT" \
      "$HTTP_CODE" "$DNS" "$CONNECT" "$START" "$TOTAL" "$HTTPING_AVG"
    ;;
  *)
  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "1) Ping Test"
  echo "$PING_RAW"
  echo "${LOSS_FLAG}Packet Loss: ${LOSS}% (threshold: ${WARN_LOSS}%)${NC}"
  if [[ "$AVG_RTT" != "null" ]]; then
    echo "${LAT_FLAG}Average RTT: ${AVG_RTT} ms (threshold: ${WARN_LATENCY} ms)${NC}"
  else
    echo "${LAT_FLAG}Average RTT: No data (threshold: ${WARN_LATENCY} ms)${NC}"
  fi

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "2) HTTP Status Code: $HTTP_CODE"
  echo "   • 2xx Success; 3xx Redirect; 4xx/5xx Error"

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "3) Response Time Statistics:"
  echo "   • DNS: ${DNS}s (normal <0.1s)"
  echo "   • TCP+TLS Handshake: ${CONNECT}s (normal <0.05s)"
  echo "   • Time to First Byte (TTFB): ${START}s (lower is better)"
  echo "   • Total Time: ${TOTAL}s"

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "4) HTTPS Latency (httping):"
  if [ "$HTTPING_AVG" != "null" ]; then
    echo "$HTTPING_RAW"
    echo "   • Average Latency: ${HTTPING_AVG} ms"
  else
    echo "   • Skipped or httping not installed, no HTTPS latency test performed."
  fi
  echo
  echo "------------------------------------------------------------------------"
  echo
    ;;
esac

exit $EXIT_CODE
