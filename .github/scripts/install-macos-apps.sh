#!/usr/bin/env bash
set -uo pipefail

state_dir="$HOME/Library/Logs/SkyWorkflow"
status_file="$state_dir/apps-install.status"
report_file="$HOME/Desktop/应用安装状态.txt"
mkdir -p "$state_dir"
printf 'status=running\n' > "$status_file"
printf '桌面应用静默更新\n开始时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$report_file"
record_status() {
  message="$1"
  printf '%s  %s\n' "$(date '+%H:%M:%S')" "$message" >> "$report_file"
  escaped="$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  osascript -e "display notification \"$escaped\" with title \"桌面应用更新\"" >/dev/null 2>&1 || true
}
mark_failed_if_interrupted() {
  rc=$?
  if grep -q '^status=running$' "$status_file" 2>/dev/null; then
    printf 'status=failed\nexit_code=%s\n' "$rc" > "$status_file.tmp"
    mv "$status_file.tmp" "$status_file"
  fi
}
trap mark_failed_if_interrupted EXIT

install_qq() {
  record_status 'QQ：更新中'
  brew update && brew install --cask qq
}

install_official_dmg() {
  local label="$1" page="$2" url_pattern="$3"
  local url temp mount app app_base
  record_status "$label：获取下载地址"
  url="$(curl -fsSL --retry 3 "$page" | grep -oE "$url_pattern" | head -n 1 || true)"
  [[ -n "$url" ]] || { echo "$label download link not found on official page" >&2; return 1; }
  temp="$(mktemp -d)"
  mount="$temp/mount"
  mkdir -p "$mount"
  record_status "$label：下载中"
  if ! curl -fsSL --retry 3 "$url" -o "$temp/app.dmg"; then rm -rf "$temp"; return 1; fi
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$temp/app.dmg" >/dev/null; then rm -rf "$temp"; return 1; fi
  app="$(find "$mount" -maxdepth 4 -type d -name '*.app' -print -quit)"
  if [[ -z "$app" ]]; then hdiutil detach "$mount" -quiet || true; rm -rf "$temp"; return 1; fi
  app_base="$(basename "$app")"
  record_status "$label：静默安装中"
  if ! ditto "$app" "/Applications/$app_base"; then hdiutil detach "$mount" -quiet || true; rm -rf "$temp"; return 1; fi
  hdiutil detach "$mount" -quiet || true
  rm -rf "$temp"
}

install_qq > "$state_dir/qq-install.log" 2>&1 &
qq_pid=$!
install_official_dmg 'WeChat' 'https://mac.weixin.qq.com/' 'https://dldir1v6\.qq\.com/weixin/Universal/Mac/WeChatMac_[^" ]+\.dmg' > "$state_dir/wechat-install.log" 2>&1 &
wechat_pid=$!
install_official_dmg 'Bilibili' 'https://app.bilibili.com/index.html' 'https://dl\.hdslb\.com/mobile/fixed/pc_electron_mac/bili_mac\.dmg' > "$state_dir/bilibili-install.log" 2>&1 &
bilibili_pid=$!

if wait "$qq_pid"; then qq_status=ok; else qq_status=failed; fi
if wait "$wechat_pid"; then wechat_status=ok; else wechat_status=failed; fi
if wait "$bilibili_pid"; then bilibili_status=ok; else bilibili_status=failed; fi
record_status "QQ：$qq_status；微信：$wechat_status；哔哩哔哩：$bilibili_status"

{
  printf 'status=complete\n'
  printf 'completed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'QQ=%s\n' "$qq_status"
  printf 'WeChat=%s\n' "$wechat_status"
  printf 'Bilibili=%s\n' "$bilibili_status"
} > "$status_file.tmp"
mv "$status_file.tmp" "$status_file"

[[ "$qq_status" == ok ]] || echo "::warning::QQ installation failed; see $state_dir/qq-install.log"
[[ "$wechat_status" == ok ]] || echo "::warning::WeChat installation failed; see $state_dir/wechat-install.log"
[[ "$bilibili_status" == ok ]] || echo "::warning::Bilibili installation failed; see $state_dir/bilibili-install.log"
