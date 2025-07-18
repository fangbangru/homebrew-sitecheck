#!/bin/bash

# sitecheck — 可定制参数、阈值告警、彩色输出、JSON/CSV 输出的站点性能检测脚本
#           并内置 detection 子命令：站点信息探测（重定向/IP/主机/服务器/CMS/X‑Powered‑By）
#
# MIT License
# Copyright (c) 2025 fangbangru
# https://github.com/fangbangru/homebrew-sitecheck

set -uo pipefail
VERSION="0.1.9"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

# ----------------------------------------
# detection 子命令
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

  # 获取 SSL 证书信息
  local SSL_INFO
  if [[ "$URL" =~ ^https:// ]]; then
    SSL_INFO=$(echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | head -n2 | tr '\n' ' ')
    SSL_INFO=${SSL_INFO:-"SSL info unavailable"}
  else
    SSL_INFO="Not HTTPS"
  fi

  # 获取响应头中的一些有用信息
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

# ----------------------------------------
# 加载配置文件
load_config() {
  local config_file="$HOME/.sitecheck"
  if [[ -f "$config_file" ]]; then
    echo -e "${GREEN}加载配置文件: $config_file${NC}"
    # 安全地加载配置
    while IFS='=' read -r key value; do
      case "$key" in
        COUNT) COUNT="$value" ;;
        TIMEOUT) TIMEOUT="$value" ;;
        WARN_LOSS) WARN_LOSS="$value" ;;
        WARN_LATENCY) WARN_LATENCY="$value" ;;
        FORMAT) FORMAT="$value" ;;
        NO_HTTPING) NO_HTTPING="$value" ;;
      esac
    done < <(grep -E '^[A-Z_]+=' "$config_file" | grep -v '^#')
  fi
}

# ----------------------------------------
# 检查必需命令
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
QUIET=0

# 加载配置文件
load_config

# ----------------------------------------
# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: sitecheck [COMMAND] [OPTIONS] <URL>

Commands:
  detection              探测站点信息（重定向/IP/主机/服务器/CMS/X‑Powered‑By）
  batch <file>           批量检测文件中的多个站点（每行一个URL）

Options:
  -h, --help             显示帮助信息
  -v, --version          显示版本号
  --no-httping           跳过 HTTPS 延迟测试
  -c, --count <N>        ping/httping 请求次数（默认 3）
  -t, --timeout <SEC>    curl 请求超时时间（秒，默认 10）
  --warn-loss <PERCENT>  丢包率告警阈值（%）
  --warn-latency <MS>    平均延迟告警阈值（ms）
  --format <plain|json|csv> 输出格式（plain 默认）
  --config                   生成示例配置文件到 ~/.sitecheck
  --quiet                    静默模式，只输出结果不显示进度

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
        echo -e "${RED}Usage: sitecheck detection <URL>${NC}"
        exit 1
      fi
      site_info "$1"
      exit 0
      ;;
    batch)
      shift
      if [[ -z "${1:-}" ]] || [[ ! -f "$1" ]]; then
        echo -e "${RED}Usage: sitecheck batch <file>${NC}"
        echo -e "${RED}文件不存在或未指定${NC}"
        exit 1
      fi
      
      echo -e "${GREEN}批量检测模式，文件: $1${NC}"
      if [[ "$FORMAT" == "csv" ]]; then
        printf 'host,loss,avg_rtt,min_rtt,max_rtt,stddev_rtt,http_code,dns,connect,ttfb,total,httping_avg\n'
      fi
      
      while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        [[ "$url" =~ ^# ]] && continue
        
        if [[ "$FORMAT" == "csv" ]]; then
          QUIET=1 bash "$0" --format csv --no-httping "$url" | tail -n 1
        else
          echo -e "\n${YELLOW}=== 检测 $url ===${NC}"
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
        echo -e "${RED}错误：请求次数必须是 1-100 之间的正整数${NC}" >&2
        exit 1
      fi
      ;;
    -t|--timeout)
      if [[ "$2" =~ ^[1-9][0-9]*$ ]] && (( $2 <= 300 )); then
        TIMEOUT="$2"; shift 2
      else
        echo -e "${RED}错误：超时时间必须是 1-300 之间的正整数（秒）${NC}" >&2
        exit 1
      fi
      ;;
    --warn-loss)
      if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$2 >= 0 && $2 <= 100" | bc -l) )); then
        WARN_LOSS="$2"; shift 2
      else
        echo -e "${RED}错误：丢包率阈值必须是 0-100 之间的数字${NC}" >&2
        exit 1
      fi
      ;;
    --warn-latency)
      if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$2 >= 0" | bc -l) )); then
        WARN_LATENCY="$2"; shift 2
      else
        echo -e "${RED}错误：延迟阈值必须是非负数字（毫秒）${NC}" >&2
        exit 1
      fi
      ;;
    --format)
      case "$2" in
        plain|json|csv)
          FORMAT="$2"; shift 2 ;;
        *)
          echo -e "${RED}错误：无效的格式 '$2'。支持的格式：plain, json, csv${NC}" >&2
          exit 1 ;;
      esac
      ;;
    --config)
      echo "# sitecheck 配置文件
# 默认请求次数
COUNT=3
# 默认超时时间（秒）
TIMEOUT=10
# 丢包率告警阈值（%）
WARN_LOSS=20
# 延迟告警阈值（毫秒）
WARN_LATENCY=500
# 默认输出格式 (plain|json|csv)
FORMAT=plain
# 是否跳过 httping 测试 (0|1)
NO_HTTPING=0" > "$HOME/.sitecheck"
      echo -e "${GREEN}配置文件已创建: $HOME/.sitecheck${NC}"
      exit 0
      ;;
    --quiet)
      QUIET=1; shift ;;
    --no-color)
      GREEN=''; YELLOW=''; RED=''; NC=''; shift ;;
    -*)
      echo -e "${RED}未知选项: $1${NC}" >&2
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
  echo -e "正在检测: $URL\n  请求次数: $COUNT 次，curl 超时: ${TIMEOUT}s"
fi

HOST=${URL#https://}; HOST=${HOST#http://}; HOST=${HOST%%/*}

# ----------------------------------------
# 1) ping 测试
PING_RAW=$(ping -c "$COUNT" "$HOST" 2>&1)
LOSS=$(echo "$PING_RAW" | awk '/packet loss/ {for(i=1;i<=NF;i++) if($i ~ /%/) {gsub(/%/, "", $i); print $i+0; break}}')
RTT_LINE=$(echo "$PING_RAW" | awk -F" = " '/min\/avg\/max\/stddev/ {print $2}')

# 处理 RTT 数据，当 ping 失败时设置默认值
if [[ -n "$RTT_LINE" ]]; then
  # 清理 RTT 行，去掉末尾的 " ms"
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

# 阈值告警
if (( LOSS >= WARN_LOSS )); then LOSS_FLAG="${RED}"; EXIT_CODE=2; else LOSS_FLAG="${GREEN}"; fi
if [[ "$AVG_RTT" != "null" ]]; then
  AVG_INT=${AVG_RTT%.*}
  if (( AVG_INT >= WARN_LATENCY )); then LAT_FLAG="${RED}"; EXIT_CODE=2; else LAT_FLAG="${GREEN}"; fi
else
  LAT_FLAG="${YELLOW}"
fi

# 2) HTTP 状态码和响应时间统计（合并请求以提高效率）
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
  echo -e "${RED}警告：curl 请求失败，可能是网络问题或超时${NC}" >&2
fi


# 4) HTTPS 延迟 (httping)
if (( NO_HTTPING == 0 )) && command -v httping &>/dev/null; then
  HTTPING_RAW=$(httping -G -k -c "$COUNT" "$URL" 2>&1)
  HTTPING_AVG=$(echo "$HTTPING_RAW" \
  | awk -F"min/avg/max = " '{print $2}' \
  | cut -d'/' -f2 \
  | tr -d '\r' | tr -d '\n' | sed 's/^ *//;s/ *$//')
else
  HTTPING_AVG="null"
fi

# ----------------------------------------
# 输出结果
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
  echo "1) ping 测试"
  echo "$PING_RAW"
  echo "${LOSS_FLAG}丢包率: ${LOSS}% (阈值: ${WARN_LOSS}%)${NC}"
  if [[ "$AVG_RTT" != "null" ]]; then
    echo "${LAT_FLAG}平均 RTT: ${AVG_RTT} ms (阈值: ${WARN_LATENCY} ms)${NC}"
  else
    echo "${LAT_FLAG}平均 RTT: 无数据 (阈值: ${WARN_LATENCY} ms)${NC}"
  fi

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "2) HTTP 状态码: $HTTP_CODE"
  echo "   • 2xx 成功；3xx 重定向；4xx/5xx 错误"

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "3) 响应时间统计:"
  echo "   • DNS: ${DNS}s（正常 <0.1s）"
  echo "   • TCP+TLS 握手: ${CONNECT}s（正常 <0.05s）"
  echo "   • 首字节时间 (TTFB): ${START}s（越低越好）"
  echo "   • 总耗时: ${TOTAL}s"

  echo
  echo "------------------------------------------------------------------------"
  echo
  echo "4) HTTPS 延迟 (httping):"
  if [ "$HTTPING_AVG" != "null" ]; then
    echo "$HTTPING_RAW"
    echo "   • 平均延迟: ${HTTPING_AVG} ms"
  else
    echo "   • 跳过或未安装 httping，未做 HTTPS 延迟测试。"
  fi
  echo
  echo "------------------------------------------------------------------------"
  echo
    ;;
esac

exit $EXIT_CODE
