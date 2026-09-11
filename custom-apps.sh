#!/usr/bin/env bash
# SpotX + Spicetify Fusion - Curated Custom Apps & Extensions Installer (Linux Edition)
# GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN} SpotX + Spicetify Fusion - Custom Apps & Extensions Installer${NC}"
echo -e "${CYAN} Curated: Enhancify, Stats (patched), lyrics-plus & Extensions${NC}"

export PATH="$HOME/.spicetify:$PATH"

if ! command -v spicetify >/dev/null 2>&1; then
    echo -e "${RED}[X] spicetify CLI not found! Please run install.sh first.${NC}"
    exit 1
fi

APP_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/CustomApps"
EXT_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Extensions"
mkdir -p "$APP_PATH" "$EXT_PATH"
TMP_DIR=$(mktemp -d)

# 1. Enhancify
echo -e "${YELLOW}[1/4] Installing Enhancify...${NC}"
enhancify_url=$(curl -s https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest | grep browser_download_url | grep zip | cut -d '"' -f 4 || true)
if [[ -n "$enhancify_url" ]]; then
    mkdir -p "$APP_PATH/Enhancify"
    curl -L "$enhancify_url" -o "$TMP_DIR/enhancify.zip"
    unzip -qo "$TMP_DIR/enhancify.zip" -d "$APP_PATH/Enhancify"
    echo -e "${GREEN}  [+] Enhancify installed successfully.${NC}"
fi

# 2. Stats
echo -e "${YELLOW}[2/4] Installing Stats...${NC}"
stats_url=$(curl -s https://api.github.com/repos/harbassan/spicetify-apps/releases | grep browser_download_url | grep "stats.*\.zip" | head -n1 | cut -d '"' -f 4 || true)
if [[ -n "$stats_url" ]]; then
    curl -L "$stats_url" -o "$TMP_DIR/stats.zip"
    unzip -qo "$TMP_DIR/stats.zip" -d "$APP_PATH"
    target="$APP_PATH/stats/index.js"
    if [[ -f "$target" ]]; then
        sed -i 's/const resizeHost = document.querySelector(.Root__main-view .os-resize-observer-host).*;/const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");/' "$target"
        echo -e "${GREEN}  [+] Stats resize observer patched.${NC}"
    fi
    echo -e "${GREEN}  [+] Stats installed successfully.${NC}"
fi
rm -rf "$TMP_DIR"

# 3. Configure Spicetify and Apply
echo -e "${YELLOW}[3/4] Configuring Spicetify custom apps and extensions...${NC}"
spicetify config custom_apps Enhancify stats lyrics-plus || true
spicetify config extensions bookmark.js fullAppDisplay.js keyboardShortcut.js loopyLoop.js popupLyrics.js shuffle+.js trashbin.js webnowplaying.js || true
spicetify config sidebar_config 0 || true
spicetify apply || true

# 4. Patch Rspack chunk map and route push chains
echo -e "${YELLOW}[4/4] Applying Rspack compatibility patches for custom apps...${NC}"

SPOTIFY_DIR=""
for candidate in \
    "$HOME/.local/share/spotify-launcher/install/usr/share/spotify" \
    "/usr/share/spotify" \
    "/opt/spotify" \
    "/usr/lib/spotify" \
    "/var/lib/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify" \
    "$HOME/.local/share/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify"
do
    if [[ -d "$candidate/Apps" ]]; then
        SPOTIFY_DIR="$candidate"
        break
    fi
done

if [[ -n "$SPOTIFY_DIR" ]]; then
    python3 -c "
import os, glob

spotify_dir = '$SPOTIFY_DIR'
apps_dir = os.path.join(spotify_dir, 'Apps', 'xpui')
xpui_js = os.path.join(apps_dir, 'xpui.js')

if os.path.exists(xpui_js):
    with open(xpui_js, 'r', encoding='utf-8') as f:
        content = f.read()

    route_files = glob.glob(os.path.join(apps_dir, 'spicetify-routes-*.js'))
    custom_apps = []
    for rf in route_files:
        bn = os.path.basename(rf)
        if bn.startswith('spicetify-routes-') and bn.endswith('.js'):
            custom_apps.append(bn[len('spicetify-routes-'):-3])

    chunk_map = ''
    css_map = ''
    app_id = 1001
    for app in custom_apps:
        b_name = f'spicetify-routes-{app}'
        if f':\"{b_name}\"' not in content:
            chunk_map += f'{app_id}:\"{b_name}\",'
        if f'{app_id}:1' not in content:
            css_map += f'{app_id}:1,'
        app_id += 1

    patched = False
    u_target = '.u=e=>\"\"+(({'
    if chunk_map and u_target in content:
        content = content.replace(u_target, u_target + chunk_map)
        patched = True

    css_target = '0!==d[e]&&({'
    if css_map and css_target in content:
        content = content.replace(css_target, css_target + css_map)
        patched = True

    if patched:
        with open(xpui_js, 'w', encoding='utf-8') as f:
            f.write(content)
        print('  [+] xpui.js custom app chunk map updated.')

    for rf in route_files:
        with open(rf, 'r', encoding='utf-8') as f:
            rc = f.read()
        push_idx = rc.find(').push([[')
        if 0 < push_idx < 300:
            fixed = '((\"u\">typeof self?self:global).rspackChunk||=[])' + rc[push_idx:]
            with open(rf, 'w', encoding='utf-8') as f:
                f.write(fixed)
            print(f'  [+] Fixed push chain for {os.path.basename(rf)}')
"
fi

killall -9 spotify 2>/dev/null || true
spotify >/dev/null 2>&1 &

echo -e "${GREEN} Custom apps and extensions installed and patched successfully!${NC}"