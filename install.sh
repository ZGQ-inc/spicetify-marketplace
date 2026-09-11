#!/usr/bin/env bash
# SpotX + Spicetify All-in-One Automated Installer (Linux Edition)
# Supports Spotify 1.2.x & 1.3.x (Rspack)
# GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion
# Telegram: https://t.me/ZGQinc

set -e

# ANSI Color Codes
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN} SpotX + Spicetify All-in-One Automated Installer (Linux)       ${NC}"
echo -e "${CYAN} Supports Spotify 1.2.x & 1.3.x (Rspack Architecture)           ${NC}"
echo -e "${CYAN} GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion            ${NC}"

# 1. Install or update Spotify on Debian/Ubuntu derivatives if apt is available
if command -v apt-get >/dev/null 2>&1; then
    echo -e "${YELLOW}[1/6] Setting up official Spotify APT repository...${NC}"
    sudo mkdir -p /etc/apt/keyrings
    curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/spotify.gpg 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null
    
    echo -e "${YELLOW}[1/6] Installing / Updating spotify-client...${NC}"
    sudo apt-get update -qq || true
    sudo apt-get install -y spotify-client || true
fi

# 2. Adjust Spotify directory permissions for Spicetify
linux_search_path() {
    local paths=("/opt" "/usr/share" "/usr/lib" "/var/lib/flatpak" "$HOME/.local/share")
    for path in "${paths[@]}"; do
        installPath=$(find "${path}" -type f -path "*/spotify*Apps/*" -not -path "*snap*" -name "xpui.spa" -print -quit 2>/dev/null | rev | cut -d/ -f3- | rev || true)
        if [[ -n "${installPath}" ]]; then
            return 0
        fi
    done
    return 1
}

echo -e "${YELLOW}[2/6] Configuring Spotify directory permissions...${NC}"
if linux_search_path; then
    echo -e "${GREEN}[+] Found Spotify path at: ${installPath}${NC}"
    sudo chmod a+wr "${installPath}" || true
    sudo chmod a+wr "${installPath}/Apps" -R || true
else
    echo -e "${YELLOW}[!] Warning: Spotify directory not auto-detected. Proceeding with standard paths.${NC}"
fi

# 3. Install SpotX-Bash
echo -e "${YELLOW}[3/7] Installing SpotX-Bash...${NC}"
(curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh | bash -s -- --noninteractive -d -e -f) || true

# 4. Install Spicetify CLI (bypassing internal Marketplace prompt so Spotify can be initialized first)
echo -e "${YELLOW}[4/7] Installing Spicetify CLI...${NC}"
sp_cli_sh=$(curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh)
echo "$sp_cli_sh" | sed '/Do you want to install spicetify Marketplace/,$d' | sh || true
export PATH="$HOME/.spicetify:$PATH"

# 5. Pre-launch Spotify, auto-grant local network permission, and install Marketplace
echo -e "${YELLOW}[5/7] Pre-launching Spotify, granting permissions, and installing Marketplace...${NC}"

# Launch Spotify in background to initialize browser cache and local database
echo -e "${CYAN}  -> Launching Spotify to initialize profile and runtime...${NC}"
spotify >/dev/null 2>&1 &
SP_PID=$!
sleep 4

# Auto-allow "Access other devices on your local network" in Chromium Preferences
python3 -c '
import json, os, glob
pref_patterns = [
    os.path.expanduser("~/.config/spotify/**/Preferences"),
    os.path.expanduser("~/.local/share/spotify/**/Preferences")
]
for pat in pref_patterns:
    for p in glob.glob(pat, recursive=True):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            prof = data.setdefault("profile", {})
            cs = prof.setdefault("content_settings", {})
            exc = cs.setdefault("exceptions", {})
            grant = {"https://login.app.spotify.com:443,*": {"setting": 1}}
            exc["local_network_access"] = grant
            exc["local_network"] = grant
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f)
        except Exception:
            pass
' 2>/dev/null || true

# Auto-allow / activate Allow button if xdotool is available
if command -v xdotool >/dev/null 2>&1; then
    xdotool search --name "Spotify" windowactivate key Return 2>/dev/null || true
fi

# Wait 5 seconds as requested
echo -e "${CYAN}  -> Waiting 5 seconds before applying Marketplace...${NC}"
sleep 5

# Terminate Spotify cleanly so Spicetify can patch files without locking conflicts
kill -9 "$SP_PID" 2>/dev/null || true
killall -9 spotify 2>/dev/null || true
sleep 1

# Install Spicetify Marketplace with automatic Yes input ("填Y回车")
echo -e "${CYAN}  -> Installing Spicetify Marketplace...${NC}"
(yes Y | curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh) || true

# 6. Install Curated Custom Apps & Extensions
echo -e "${YELLOW}[6/7] Downloading curated custom apps and extensions...${NC}"
APP_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/CustomApps"
EXT_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Extensions"
mkdir -p "$APP_PATH" "$EXT_PATH"
TMP_DIR=$(mktemp -d)

# Enhancify
echo -e "${CYAN}  -> Downloading Enhancify...${NC}"
enhancify_url=$(curl -s https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest | grep browser_download_url | grep zip | cut -d '"' -f 4 || true)
if [[ -n "$enhancify_url" ]]; then
    mkdir -p "$APP_PATH/Enhancify"
    curl -L "$enhancify_url" -o "$TMP_DIR/enhancify.zip"
    unzip -qo "$TMP_DIR/enhancify.zip" -d "$APP_PATH/Enhancify"
fi

# Stats (with UI observer patch)
echo -e "${CYAN}  -> Downloading Stats...${NC}"
stats_url=$(curl -s https://api.github.com/repos/harbassan/spicetify-apps/releases | grep browser_download_url | grep "stats.*\.zip" | head -n1 | cut -d '"' -f 4 || true)
if [[ -n "$stats_url" ]]; then
    curl -L "$stats_url" -o "$TMP_DIR/stats.zip"
    unzip -qo "$TMP_DIR/stats.zip" -d "$APP_PATH"
    target="$APP_PATH/stats/index.js"
    if [[ -f "$target" ]]; then
        sed -i 's/const resizeHost = document.querySelector(.Root__main-view .os-resize-observer-host).*;/const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");/' "$target"
    fi
fi
rm -rf "$TMP_DIR"

# Configure Spicetify
echo -e "${CYAN}  -> Configuring Spicetify options...${NC}"
spicetify restore backup || true
spicetify backup apply || true
spicetify config custom_apps marketplace || true
spicetify config custom_apps Enhancify || true
spicetify config custom_apps stats || true
spicetify config custom_apps lyrics-plus || true
spicetify config extensions bookmark.js || true
spicetify config extensions fullAppDisplay.js || true
spicetify config extensions keyboardShortcut.js || true
spicetify config extensions loopyLoop.js || true
spicetify config extensions popupLyrics.js || true
spicetify config extensions shuffle+.js || true
spicetify config extensions trashbin.js || true
spicetify config extensions webnowplaying.js || true
spicetify config sidebar_config 0 || true
spicetify apply || true

# 7. Apply Unified Compatibility Hotfix
echo -e "${YELLOW}[7/7] Applying SpotX + Spicetify compatibility hotfix...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/fix.sh" ]]; then
    bash "$SCRIPT_DIR/fix.sh"
else
    curl -sSL https://raw.githubusercontent.com/ZGQ-inc/spotx-spicetify-fusion/main/fix.sh | bash
fi

echo -e "${GREEN} Linux installation and compatibility hotfix finished!         ${NC}"
echo -e "${GREEN} Enjoy Spotify with SpotX adblocking and Spicetify custom apps! ${NC}"
