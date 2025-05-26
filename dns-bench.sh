#!/bin/bash

if ! command -v dig >/dev/null 2>&1; then
  echo "🔧 'dig' not found. Attempting to install..."

  if [ -f /etc/debian_version ]; then
    apt update && apt install -y dnsutils
  elif [ -f /etc/redhat-release ]; then
    yum install -y bind-utils
  elif [ -f /etc/alpine-release ]; then
    apk add bind-tools
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm bind
  else
    echo "❌ Unknown distribution. Please install 'dig' manually."
    exit 1
  fi

  if ! command -v dig >/dev/null 2>&1; then
    echo "❌ Failed to install 'dig'. Exiting."
    exit 1
  fi
fi

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

declare -A dns_servers=(
  ["Cloudflare"]="1.1.1.1"
  ["Google"]="8.8.8.8"
  ["OpenDNS"]="208.67.222.222"
  ["Neustar"]="156.154.70.1"
  ["Level3"]="4.2.2.1"
)

domains=("google.com" "yandex.ru" "openai.com" "github.com" "wikipedia.org" "t.me" "instagram.com" "cloudflare.com" "speedtest.net")
repeats=10

declare -A results

total_tests=$((${#dns_servers[@]} * ${#domains[@]} * repeats))
completed=0

echo -e "🔍 ${CYAN}DNS Benchmark — running tests, please wait...${NC}"

for name in "${!dns_servers[@]}"; do
  ip=${dns_servers[$name]}
  total_dns_time=0

  for domain in "${domains[@]}"; do
    total_time=0
    for ((i=1; i<=repeats; i++)); do
      time=$(dig +stats @"$ip" "$domain" | grep "Query time" | awk '{print $4}')
      [[ -z "$time" ]] && time=1000
      total_time=$((total_time + time))
      ((completed++))
      percent=$((completed * 100 / total_tests))
      printf "\r⏳ Progress: %3d%%" "$percent"
    done
    avg_domain_time=$((total_time / repeats))
    total_dns_time=$((total_dns_time + avg_domain_time))
  done

  avg_total_time=$((total_dns_time / ${#domains[@]}))
  results["$name"]=$avg_total_time
done

echo -e "\r✅ Progress: 100% complete"

echo -e "\n\n📊 ${CYAN}Summary (sorted by average response time):${NC}"

sorted_results=($(for key in "${!results[@]}"; do
  echo -e "${results[$key]}\t$key"
done | sort -n))

best_dns=""
best_time=9999

for ((i=0; i<${#sorted_results[@]}; i+=2)); do
  time=${sorted_results[i]}
  name=${sorted_results[i+1]}

  if (( time <= 5 )); then
    color=$GREEN
  elif (( time <= 15 )); then
    color=$YELLOW
  else
    color=$RED
  fi

  printf "${color}%-15s : %3d ms${NC}\n" "$name" "$time"

  if (( time < best_time )); then
    best_time=$time
    best_dns=$name
  fi
done

case $best_dns in
  Cloudflare) best_ip="1.1.1.1" ;;
  Google)     best_ip="8.8.8.8" ;;
  OpenDNS)      best_ip="208.67.222.222" ;;
  Neustar)      best_ip="156.154.70.1" ;;
  Level3)       best_ip="4.2.2.1" ;;
  *)            best_ip="" ;;
esac

if [[ -n $best_dns && -n $best_ip ]]; then
  echo -e "\n🚀 Best DNS based on test results: ${GREEN}$best_dns${NC} with latency ~${GREEN}${best_time} ms${NC}"
  echo -e "\n📋 Recommended DNS configuration for Xray:"
  echo -e "${GREEN}{
  \"dns\": {
    \"servers\": [
      \"$best_ip\"
    ],
    \"queryStrategy\": \"ForceIPv4\"
  }
}${NC}"
elif [[ -n $best_dns && -z $best_ip ]]; then
  echo -e "\n❌ ${RED}Failed to determine IP for best DNS ($best_dns) in recommendation list. Check the IP mapping section.${NC}"
else
  echo -e "\n❌ ${RED}Failed to determine the best DNS server.${NC}"
fi
