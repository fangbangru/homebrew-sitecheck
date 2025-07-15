set -uo pipefail

VERSION="0.1.7"

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

  cat <<EOF
Redirects to: $REDIR
IP address:    $IP
Hosting:       $ORG
Running on:    $SERVER
CMS:           $GEN
Powered by:    $XPBY
EOF
}

if [[ "${1:-}" == "detection" ]]; then
  shift
  if [[ -z "${1:-}" ]]; then
    echo -e "${RED}Usage: sitecheck detection <URL>${NC}"
    exit 1
  fi
  site_info "$1"
  exit 0
fi

# 功能：
#   • ping 测试
#   • HTTP 状态码
#   • 响应时间统计（DNS, Connect, TTFB, Total）
#   • HTTPS 延迟测试（可选 httping，支持跳过）
#   • 阈值告警（丢包率、延迟）
#   • 彩色输出
#   • JSON/CSV 结构化输出
#
# 用法：
#   sitecheck [OPTIONS] <URL>
#
# Options:
#   -h, --help             显示帮助信息
#   -v, --version          显示版本号
#   --no-httping           跳过 HTTPS 延迟测试
#   -c, --count <N>        ping/httping 请求次数（默认 3）
#   -t, --timeout <SEC>    curl 请求超时时间（秒，默认 10）
#   --warn-loss <PERCENT>  设置丢包率告警阈值（%）
#   --warn-latency <MS>    设置平均延迟告警阈值（ms）
#   --format <plain|json|csv> 输出格式（plain 默认）
#
# 示例：
#   sitecheck -c 5 -t 5 example.com
#   sitecheck --warn-loss 20 --warn-latency 300 --format json example.com

set -uo pipefail

VERSION="0.1.7"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

REQUIRED_CMDS=(ping curl bc awk)
MISSING_REQUIRED=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" &>/dev/null || MISSING_REQUIRED+=("$cmd")
done
if ((${#MISSING_REQUIRED[@]})); then
  echo -e "${RED}错误：以下必需命令缺失：${MISSING_REQUIRED[*]}${NC}"
  echo "请先安装，例如： brew install ${MISSING_REQUIRED[*]}"
  exit 1
fi

if ! command -v httping &>/dev/null; then
  echo -e "${YELLOW}警告：未安装 httping，将跳过 HTTPS 延迟测试。${NC}"
  echo "如需安装：httping，可执行 'brew install httping'"
fi

COUNT=3
TIMEOUT=10
NO_HTTPING=0
WARN_LOSS=100
WARN_LATENCY=1000
FORMAT="plain"
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: sitecheck [OPTIONS] <URL>

Options:
  -h, --help             显示帮助信息
  -v, --version          显示版本号
  --no-httping           跳过 HTTPS 延迟测试
  -c, --count <N>        ping/httping 请求次数（默认 3）
  -t, --timeout <SEC>    curl 请求超时时间（秒，默认 10）
  --warn-loss <PERCENT>  丢包率告警阈值（%）
  --warn-latency <MS>    平均延迟告警阈值（ms）
  --format <plain|json|csv> 输出格式（plain 默认）

Examples:
  sitecheck example.com
  sitecheck -c 5 -t 5 --warn-loss 20 --warn-latency 300 --format json example.com
EOF
      exit 0
      ;;
    -v|--version)
      echo "sitecheck version $VERSION"
      exit 0
      ;;
    --no-httping)
      NO_HTTPING=1
      shift
      ;;
    -c|--count)
      COUNT="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --warn-loss)
      WARN_LOSS="$2"
      shift 2
      ;;
    --warn-latency)
      WARN_LATENCY="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    -*)
      echo -e "${RED}未知选项: $1${NC}" >&2
      exit 1
      ;;
    *)
      URL="$1"
      shift
      ;;
  esac
done

if [ -z "${URL:-}" ]; then
  echo "Usage: sitecheck [OPTIONS] <URL>"
  exit 1
fi
[[ ! "$URL" =~ ^https?:// ]] && URL="https://$URL"

echo -e "正在检测: $URL\n  请求次数: $COUNT 次，curl 超时: ${TIMEOUT}s"

HOST=${URL#https://}; HOST=${HOST#http://}; HOST=${HOST%%/*}

# 1) ping 测试
PING_RAW=$(ping -c "$COUNT" "$HOST" 2>&1)
LOSS=$(echo "$PING_RAW" | awk -F", " '/packet loss/ {print $3+0}')
RTT_LINE=$(echo "$PING_RAW" | awk -F" = " '/min\/avg\/max\/stddev/ {print $2}')
MIN_RTT=$(echo "$RTT_LINE" | cut -d'/' -f1)
AVG_RTT=$(echo "$RTT_LINE" | cut -d'/' -f2)
MAX_RTT=$(echo "$RTT_LINE" | cut -d'/' -f3)
STDDEV_RTT=$(echo "$RTT_LINE" | cut -d'/' -f4)

# 阈值告警
if (( LOSS >= WARN_LOSS )); then
  LOSS_FLAG="${RED}"
  EXIT_CODE=2
else
  LOSS_FLAG="${GREEN}"
fi

AVG_INT=${AVG_RTT%.*}
if (( AVG_INT >= WARN_LATENCY )); then
  LAT_FLAG="${RED}"
  EXIT_CODE=2
else
  LAT_FLAG="${GREEN}"
fi

# 2) HTTP 状态码
HTTP_CODE=$(curl --max-time "$TIMEOUT" -o /dev/null -s -w "%{http_code}" "$URL")

# 3) 响应时间统计
read DNS CONNECT START TOTAL < <(
  curl --max-time "$TIMEOUT" -o /dev/null -s \
    -w "%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total}" \
    "$URL"
)

# 4) HTTPS 延迟测试
if (( NO_HTTPING == 0 )) && command -v httping &>/dev/null; then
  HTTPING_RAW=$(httping -G -k -c "$COUNT" "$URL" 2>&1)
  HTTPING_AVG=$(echo "$HTTPING_RAW" | awk -F"min/avg/max = " '{print $2}' | cut -d'/' -f2)
else
  HTTPING_AVG="null"
fi

# 输出
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
    echo -e "\n1) ping 测试\n$PING_RAW"
    echo -e "${LOSS_FLAG}丢包率: ${LOSS}% (阈值: ${WARN_LOSS}%)${NC}"
    echo -e "${LAT_FLAG}平均 RTT: ${AVG_RTT} ms (阈值: ${WARN_LATENCY} ms)${NC}"

    echo -e "\n2) HTTP 状态码: $HTTP_CODE"
    echo "   • 2xx 成功；3xx 重定向；4xx/5xx 错误"

    echo -e "\n3) 响应时间统计:"
    echo "   • DNS: ${DNS}s（正常 <0.1s）"
    echo "   • TCP+TLS 握手: ${CONNECT}s（正常 <0.05s）"
    echo "   • 首字节时间 (TTFB): ${START}s（越低越好）"
    echo "   • 总耗时: ${TOTAL}s"

    echo -e "\n4) HTTPS 延迟 (httping):"
    if [ "$HTTPING_AVG" != "null" ]; then
      echo "   $HTTPING_RAW"
      echo "   • httping 平均延迟: ${HTTPING_AVG} ms — 衡量 HTTPS 握手及首字节延迟。（已跳过证书验证）"
    else
      echo "   • 跳过或未安装 httping，未做 HTTPS 延迟测试。"
    fi
    ;;
esac

exit $EXIT_CODE
