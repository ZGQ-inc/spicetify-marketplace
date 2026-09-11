#!/usr/bin/env bash
# SpotX + Spicetify Unified Compatibility Hotfix Script (Linux Edition)
# Supports Spotify 1.2.x (Webpack) & 1.3.x+ (Rspack Architecture)
# GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion

set -e

# ANSI Color Codes
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN} SpotX + Spicetify Unified Compatibility Hotfix (Linux v2.1)   ${NC}"
echo -e "${CYAN} Supports Spotify 1.2.x (Webpack) & 1.3.x+ (Rspack)             ${NC}"
echo -e "${CYAN} GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion            ${NC}"

# 1. Terminate running Spotify processes
if pgrep -x "spotify" > /dev/null; then
    echo -e "${YELLOW}[*] Closing running Spotify processes...${NC}"
    killall -9 spotify 2>/dev/null || true
    sleep 1
fi

# 2. Locate Spotify and Spicetify directories on Linux
SPICETIFY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify"
THEMED_XPUI_DIR="$SPICETIFY_DIR/Extracted/Themed/xpui"
RAW_XPUI_DIR="$SPICETIFY_DIR/Extracted/Raw/xpui"

# Find system Spotify install path
SEARCH_PATHS=("/opt/spotify" "/usr/share/spotify" "/usr/lib/spotify" "$HOME/.local/share/spotify" "/var/lib/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify")
SPOTIFY_DIR=""
for p in "${SEARCH_PATHS[@]}"; do
    if [ -f "$p/Apps/xpui.spa" ] || [ -f "$p/spotify" ]; then
        SPOTIFY_DIR="$p"
        break
    fi
done

echo -e "${GREEN}[+] Spicetify config path: $SPICETIFY_DIR${NC}"
if [ -n "$SPOTIFY_DIR" ]; then
    echo -e "${GREEN}[+] Detected Spotify installation path: $SPOTIFY_DIR${NC}"
fi

# Target directories where xpui.js could exist
TARGET_XPUI_DIRS=()
if [ -d "$THEMED_XPUI_DIR" ]; then
    TARGET_XPUI_DIRS+=("$THEMED_XPUI_DIR")
fi
if [ -d "$RAW_XPUI_DIR" ]; then
    TARGET_XPUI_DIRS+=("$RAW_XPUI_DIR")
fi
if [ -n "$SPOTIFY_DIR" ] && [ -d "$SPOTIFY_DIR/Apps/xpui" ]; then
    TARGET_XPUI_DIRS+=("$SPOTIFY_DIR/Apps/xpui")
fi

if [ ${#TARGET_XPUI_DIRS[@]} -eq 0 ]; then
    echo -e "${YELLOW}[*] Extracted xpui folder not found in cache. Running 'spicetify backup apply'...${NC}"
    if command -v spicetify >/dev/null 2>&1; then
        spicetify backup apply || true
        if [ -d "$THEMED_XPUI_DIR" ]; then
            TARGET_XPUI_DIRS+=("$THEMED_XPUI_DIR")
        fi
    fi
fi

if [ ${#TARGET_XPUI_DIRS[@]} -eq 0 ]; then
    echo -e "${RED}[-] Error: Could not locate xpui.js. Please run 'spicetify backup apply' first.${NC}"
    exit 1
fi

# Python 3 helper to execute precise AST/string patching
apply_patch_python() {
    python3 - << 'EOF'
import os
import sys
import glob

themed_dir = os.path.expanduser("~/.config/spicetify/Extracted/Themed/xpui")
raw_dir = os.path.expanduser("~/.config/spicetify/Extracted/Raw/xpui")

target_dirs = [d for d in [themed_dir, raw_dir] if os.path.isdir(d)]

for xpui_dir in target_dirs:
    xpui_js = os.path.join(xpui_dir, "xpui.js")
    wrapper_js = os.path.join(xpui_dir, "helper", "spicetifyWrapper.js")
    
    if os.path.exists(xpui_js):
        with open(xpui_js, "r", encoding="utf-8") as f:
            content = f.read()
            
        patched = False
        
        # B1: Fix Spicetify 1.3.0 semver bug causing SyntaxError fatal black screen
        bad_snackbar = "Spicetify.Snackbar.enqueueImageSnackbar="
        if bad_snackbar in content:
            content = content.replace(bad_snackbar, "")
            patched = True
            print("  [+] Fixed SyntaxError corruption in xpui.js")

        # B2: Fix useNavigateStable runtime crash (Marketplace white screen)
        old_nav = "return(0,e.useNavigateStable)()"
        safe_nav = 'return(()=>{try{return(0,e.useNavigateStable)()}catch(err){return Spicetify?.Platform?.History?.push||Spicetify?.Platform?.History?.navigate||(()=>({}))}})()'
        if old_nav in content:
            content = content.replace(old_nav, safe_nav)
            patched = True
            print("  [+] Injected safe fallback for useNavigateStable")

        # B3: Fix RegistryContext useReducer on undefined
        old_reg = "(0,i.useContext)(e.yv)"
        safe_reg = "((0,i.useContext)(e.yv)||Spicetify?.Platform?.Registry||{entries:new Map()})"
        if old_reg in content and safe_reg not in content:
            content = content.replace(old_reg, safe_reg)
            patched = True
            print("  [+] Injected safe fallback for RegistryContext")

        # B4: Scan and inject spicetify-routes-*.js custom apps
        route_files = glob.glob(os.path.join(xpui_dir, "spicetify-routes-*.js"))
        custom_apps = []
        for rf in route_files:
            bname = os.path.basename(rf)
            if bname.startswith("spicetify-routes-") and bname.endswith(".js"):
                custom_apps.append(bname[len("spicetify-routes-"):-3])
                
        if custom_apps:
            chunk_chunks = []
            css_chunks = []
            app_id = 1001
            for app in custom_apps:
                bundle_name = f"spicetify-routes-{app}"
                if f':"{bundle_name}"' not in content:
                    chunk_chunks.append(f'{app_id}:"{bundle_name}",')
                if f'{app_id}:1' not in content:
                    css_chunks.append(f'{app_id}:1,')
                app_id += 1
                
            u_target = '.u=e=>""+(({'
            if chunk_chunks and u_target in content:
                content = content.replace(u_target, u_target + "".join(chunk_chunks))
                patched = True
                print("  [+] Injected Custom Apps chunk map into .u loader")

            css_target = '0!==d[e]&&({'
            if css_chunks and css_target in content:
                content = content.replace(css_target, css_target + "".join(css_chunks))
                patched = True
                print("  [+] Injected Custom Apps into MiniCss allowlist")

        if patched:
            with open(xpui_js, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"[SUCCESS] Patched {xpui_js}")
        else:
            print(f"[INFO] {xpui_js} is already up-to-date.")

    # C: Patch helper/spicetifyWrapper.js
    if os.path.exists(wrapper_js):
        with open(wrapper_js, "r", encoding="utf-8") as f:
            wcontent = f.read()
            
        wpatched = False
        target_chunk = "window?.webpackChunkclient_web||window?.rspackChunkclient_web"
        fixed_chunk = "window?.webpackChunkclient_web||window?.rspackChunkclient_web||window?.rspackChunk"
        if target_chunk in wcontent and fixed_chunk not in wcontent:
            wcontent = wcontent.replace(target_chunk, fixed_chunk)
            wpatched = True
            print("  [+] Hooked window.rspackChunk in spicetifyWrapper.js")

        uri_target = "Spicetify.React=f.find(m=>m?.useMemo),"
        uri_inject = '(()=>{let u=f.find(m=>m?.NQG?.PLAYLIST_V2);if(u){let s=u.o_h("spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.constructor;if(s){s.Type=u.NQG,s.from=u.o_h,s.fromString=u.Lce,s.idToHex=u.DY5,s.hexToId=u.dx2,Spicetify.URI=s}}})(),'
        if uri_target in wcontent and "Spicetify.URI=s" not in wcontent:
            wcontent = wcontent.replace(uri_target, uri_target + uri_inject)
            wpatched = True
            print("  [+] Injected dynamic Spicetify.URI export")

        if wpatched:
            with open(wrapper_js, "w", encoding="utf-8") as f:
                f.write(wcontent)
            print(f"[SUCCESS] Patched {wrapper_js}")

    # D: Fix push header in spicetify-routes-*.js
    for rf in glob.glob(os.path.join(xpui_dir, "spicetify-routes-*.js")):
        with open(rf, "r", encoding="utf-8") as f:
            rc = f.read()
        push_idx = rc.find(").push([[")
        if 0 < push_idx < 300:
            fixed_head = '(("u">typeof self?self:global).rspackChunk||=[]' + rc[push_idx:]
            with open(rf, "w", encoding="utf-8") as f:
                f.write(fixed_head)
            print(f"  [+] Fixed bundle push chain for {os.path.basename(rf)}")

EOF
}

echo -e "${CYAN}[*] Applying compatibility patches...${NC}"
if command -v python3 >/dev/null 2>&1; then
    apply_patch_python
else
    echo -e "${RED}[-] python3 is required to run the Linux hotfix script.${NC}"
    exit 1
fi

# Re-apply Spicetify to repack xpui.spa on Linux
if command -v spicetify >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Running 'spicetify apply' to re-bundle xpui.spa...${NC}"
    spicetify apply || true
fi

echo -e "${GREEN} [OK] All SpotX + Spicetify Linux compatibility patches applied!${NC}"
echo -e "${GREEN} Spotify 1.2.x & 1.3.x Rspack, Marketplace & extensions restored!${NC}"
