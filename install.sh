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

grant_permissions() {
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
            exc["loopback_network"] = grant
            d_vals = data.setdefault("default_content_setting_values", {})
            d_vals["local_network_access"] = 1
            d_vals["local_network"] = 1
            prof.setdefault("default_content_setting_values", {})["local_network_access"] = 1
            prof.setdefault("default_content_setting_values", {})["local_network"] = 1
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f)
        except Exception:
            pass
' 2>/dev/null || true
}

# Pre-configure Chromium Preferences before starting
grant_permissions

# Launch Spotify in background to initialize browser cache and local database
echo -e "${CYAN}  -> Launching Spotify to initialize profile and runtime...${NC}"
spotify >/dev/null 2>&1 &
SP_PID=$!
sleep 3

# Grant permissions while running
grant_permissions

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
sleep 2

# Grant permissions again after exit
grant_permissions

# Install Spicetify Marketplace with automatic Yes input ("填Y回车")
echo -e "${CYAN}  -> Installing Spicetify Marketplace...${NC}"
(yes Y | curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh) || true

# 6. Configure Spicetify with Marketplace
echo -e "${YELLOW}[6/7] Configuring Spicetify with Marketplace...${NC}"
spicetify config custom_apps marketplace || true
spicetify apply || true

# 7. Apply Unified Compatibility Hotfix (Embedded)
echo -e "${YELLOW}[7/7] Applying SpotX + Spicetify compatibility hotfix...${NC}"

python3 - << 'EOF'
import os
import sys
import glob

themed_dir = os.path.expanduser("~/.config/spicetify/Extracted/Themed/xpui")
raw_dir = os.path.expanduser("~/.config/spicetify/Extracted/Raw/xpui")

search_paths = ["/opt/spotify", "/usr/share/spotify", "/usr/lib/spotify", os.path.expanduser("~/.local/share/spotify")]
target_dirs = [d for d in [themed_dir, raw_dir] if os.path.isdir(d)]
for sp in search_paths:
    app_xpui = os.path.join(sp, "Apps", "xpui")
    if os.path.isdir(app_xpui):
        target_dirs.append(app_xpui)

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

# Launch Spotify on Linux if available
if command -v spotify >/dev/null 2>&1; then
    echo -e "${CYAN}  -> Launching patched Spotify...${NC}"
    spotify >/dev/null 2>&1 &
fi

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN} Linux installation and compatibility hotfix finished!         ${NC}"
echo -e "${GREEN} Enjoy Spotify with SpotX adblocking and Spicetify custom apps! ${NC}"
echo -e "${GREEN}================================================================${NC}"
