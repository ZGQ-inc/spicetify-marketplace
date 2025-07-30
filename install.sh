#!/bin/bash
# https://t.me/ZGQinc

set -e

echo "添加 Spotify 软件源..."
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null

echo "安装 Spotify..."
sudo apt-get update
sudo apt-get install -y spotify-client

echo "安装 SpotX..."
(curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh | sed '/^exit 0/d'  | bash -s - -d -e)

echo "安装 Spicetify..."
(curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sed '/^exit 0/d'  | sh)

echo "安装 Custom Apps..."

APP_PATH="$HOME/.config/spicetify/CustomApps"
TMP_DIR=$(mktemp -d)

echo "正在下载 Enhancify..."
enhancify_url=$(curl -s https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest | grep browser_download_url | grep zip | cut -d '"' -f 4)
if [[ -z "$enhancify_url" ]]; then
  echo "获取 Enhancify 下载链接失败。"
  exit 1
fi
mkdir -p "$APP_PATH/Enhancify"
curl -L "$enhancify_url" -o "$TMP_DIR/enhancify.zip"
unzip -o "$TMP_DIR/enhancify.zip" -d "$APP_PATH/Enhancify"

echo "正在下载 stats..."
stats_url=$(curl -s https://api.github.com/repos/harbassan/spicetify-apps/releases | grep browser_download_url | grep "stats.*\.zip" | head -n1 | cut -d '"' -f 4)
if [[ -z "$stats_url" ]]; then
  echo "获取 stats 下载链接失败。"
  exit 1
fi
curl -L "$stats_url" -o "$TMP_DIR/stats.zip"
unzip -o "$TMP_DIR/stats.zip" -d "$APP_PATH"

if [[ "$stats_url" =~ stats-v1\.1\.2/ ]]; then
  echo "Stats 版本是 1.1.2, 补丁 index.js..."
  target="$APP_PATH/stats/index.js"
  backup="$target.bak"

  if [[ -f "$backup" ]]; then
    echo "已 patch ，跳过。"
  else
    cp "$target" "$backup"
    sed -i 's/const resizeHost = document.querySelector(.Root__main-view .os-resize-observer-host).*;/const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");/' "$target"
    echo "patch 完成。"
    spicetify config custom_apps stats-
    spicetify apply
  fi
fi

echo "正在配置 Spicetify..."
spicetify config custom_apps Enhancify
spicetify config custom_apps stats
spicetify config custom_apps lyrics-plus
spicetify config extensions bookmark.js
spicetify config extensions fullAppDisplay.js
spicetify config extensions keyboardShortcut.js
spicetify config extensions loopyLoop.js
spicetify config extensions popupLyrics.js
spicetify config extensions shuffle+.js
spicetify config extensions trashbin.js
spicetify config extensions webnowplaying.js
spicetify config sidebar_config 0
spicetify apply

rm -rf "$TMP_DIR"

echo -e "\n安装完成。"