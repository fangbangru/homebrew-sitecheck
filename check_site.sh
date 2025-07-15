#!/usr/bin/env bash
# 带详细解释的站点性能检测脚本（含自检功能）
# 用法: ./check_site.sh <URL>

# ===== 自检依赖命令 =====
REQUIRED_CMDS=(ping curl bc awk)
# httping 可选
OPTIONAL_CMDS=(httping)
MISSING_REQUIRED=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING_REQUIRED+=("$cmd")
  fi
done
if [ ${#MISSING_REQUIRED[@]} -ne 0 ]; then
  echo "错误：检测到以下必需命令缺失：${MISSING_REQUIRED[*]}"
  echo "请先安装，例如："
  echo "  brew install ${MISSING_REQUIRED[*]}"
  exit 1
fi

# 检查 httping，可选提示
if ! command -v httping &>/dev/null; then
  echo "警告：未安装 httping，将跳过 HTTPS 延迟测试。"  
  echo "如需安装：httping，可执行 'brew install httping'"
fi

# ===== 开始性能检测 =====
URL="$1"
if [ -z "$URL" ]; then
  echo "Usage: $0 <URL>"
  exit 1
fi

# 如果没有协议头，则自动加 https://
if [[ ! "$URL" =~ ^https?:// ]]; then
  URL="https://$URL"
fi

echo "正在检测: $URL"

# 1) ping 测试
echo -e "\n1) ping 测试"
HOST=${URL#https://}
HOST=${HOST#http://}
HOST=${HOST%%/*}
echo "→ 解析到主机：$HOST"
PING_RAW=$(ping -c 3 "$HOST" 2>&1)
echo "$PING_RAW"
LOSS=$(echo "$PING_RAW" | awk -F", " '/packet loss/ {print $3}' | awk '{print $1}' | tr -d '%')
RTT_LINE=$(echo "$PING_RAW" | awk -F" = " '/min\/avg\/max\/stddev/ {print $2}')
MIN_RTT=$(echo "$RTT_LINE" | cut -d'/' -f1)
AVG_RTT=$(echo "$RTT_LINE" | cut -d'/' -f2)
MAX_RTT=$(echo "$RTT_LINE" | cut -d'/' -f3)
STDDEV_RTT=$(echo "$RTT_LINE" | cut -d'/' -f4)
echo "-- 解释："
if (( $(echo "$LOSS > 0" | bc -l) )); then
  echo "   • 丢包率 ${LOSS}%：存在丢包，可能网络质量不佳或防火墙丢弃 ICMP。"
else
  echo "   • 丢包率 0%：网络通畅，无 ICMP 丢包。"
fi
if [ -z "$RTT_LINE" ]; then
  echo "   • 无 RTT 数据，可能所有包均丢失。"
else
  if (( $(echo "$AVG_RTT > 200" | bc -l) )); then
    PERF_DESC="响应较慢"
  elif (( $(echo "$AVG_RTT > 100" | bc -l) )); then
    PERF_DESC="延迟适中"
  else
    PERF_DESC="延迟很低，网络性能优秀"
  fi
  echo "   • RTT(min/avg/max/stddev) = ${MIN_RTT}/${AVG_RTT}/${MAX_RTT}/${STDDEV_RTT} ms：${PERF_DESC}。"
fi

# 2) HTTP 状态码
echo -e "\n2) HTTP 状态码"
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" "$URL")
echo "HTTP Code: $HTTP_CODE"
echo "-- 解释："
case "$HTTP_CODE" in
  2??) echo "   • 2xx 成功：请求已正常处理，内容可访问。" ;;
  3??) echo "   • 3xx 重定向：资源已重定向，可能需要跟随 Location。" ;;
  4??) echo "   • 4xx 客户端错误：请求有误或无权访问（如403/404）。" ;;
  5??) echo "   • 5xx 服务端错误：服务器内部故障或不可用。" ;;
  *)    echo "   • 未知状态码：请检查 URL 或网络环境。" ;;
esac

# 3) 响应时间统计
echo -e "\n3) 响应时间统计"
CURL_STATS=$(curl -o /dev/null -s -w "DNS:%{time_namelookup} Connect:%{time_connect} StartTransfer:%{time_starttransfer} Total:%{time_total}" "$URL")
echo "$CURL_STATS"
echo "-- 解释："
DNS=$(echo "$CURL_STATS" | awk -F"DNS:" '{print $2}' | awk '{print $1}')
CONNECT=$(echo "$CURL_STATS" | awk -F"Connect:" '{print $2}' | awk '{print $1}')
START=$(echo "$CURL_STATS" | awk -F"StartTransfer:" '{print $2}' | awk '{print $1}')
TOTAL=$(echo "$CURL_STATS" | awk -F"Total:" '{print $2}' | awk '{print $1}')

echo "   • DNS 解析：${DNS}s（正常 <0.1s）"
echo "   • TCP+TLS 握手：${CONNECT}s（正常 <0.05s）"
echo "   • 首字节时间：${START}s（服务器处理+网络，越低越好）"
echo "   • 总耗时：${TOTAL}s（整体请求延迟）"

# 4) httping 延迟
echo -e "\n4) httping 延迟"
if command -v httping &>/dev/null; then
  echo "→ 使用 httping 跳过 SSL 验证（-k）并测试延迟"
  HTTPING_RAW=$(httping -G -k -c 3 "$URL" 2>&1)
  echo "$HTTPING_RAW"
  echo "-- 解释："
  HTTPING_AVG=$(echo "$HTTPING_RAW" | awk -F"min/avg/max = " '{print $2}' | cut -d'/' -f2)
  echo "   • httping 平均延迟 ${HTTPING_AVG} ms：衡量 HTTPS 握手及首字节延迟。（已跳过证书验证）"
else
  echo "   • 未安装 httping，跳过此项。（可用 'brew install httping' 安装）"
fi
