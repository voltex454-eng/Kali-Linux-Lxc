#!/bin/bash

# ==========================================
#  Kali Linux LXC + VNC + Pinggy Automation
#  Mode: Silent & Stealthy 🥷
#  Fix: Bypasses Apt Update Errors
# ==========================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script will stop on serious errors, but we handle apt update manually
set -e

# --- 1. Environment Detection ---
echo -e "${BOLD}${CYAN}============================================${NC}"
echo -e "   ${BOLD}🐉 Kali Linux Auto-Deployer Script 🐉${NC}   "
echo -e "${BOLD}${CYAN}============================================${NC}"

IS_CODESPACE=false
if [ "$CODESPACES" == "true" ]; then
    IS_CODESPACE=true
    echo -e "${YELLOW}☁️  GitHub Codespaces detected.${NC}"
else
    echo -e "${YELLOW}💻  Local environment detected.${NC}"
fi

# --- 2. Host Setup (LXD) ---
echo -e "\n${BLUE}🔄 Updating host system...${NC}"

# FIX: || true added to ignore GPG errors from Yarn or other repos
sudo apt-get update -qq || echo -e "${YELLOW}⚠️  Update warnings ignored, proceeding installation...${NC}"

if ! command -v lxd &> /dev/null; then
    echo -e "${BLUE}🛠️  Installing LXD...${NC}"
    sudo apt-get install -y lxd lxd-client
fi

if ! sudo lxd waitready --timeout 15 2>/dev/null; then
    echo -e "${YELLOW}⚙️  Initializing LXD (Auto Mode)...${NC}"
    cat <<EOF | sudo lxd init --preseed
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: auto
  description: ""
  name: lxdbr0
  type: ""
  project: default
storage_pools:
- config:
    size: 10GB
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
cluster: null
EOF
fi

# --- 3. Container Launch ---
CONTAINER_NAME="kali-gui"

if sudo lxc list | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}🗑️  Cleaning up old container...${NC}"
    sudo lxc stop "$CONTAINER_NAME" --force
    sudo lxc delete "$CONTAINER_NAME"
fi

echo -e "${BLUE}🚀 Downloading and launching Kali Linux container...${NC}"
sudo lxc launch images:kali/current/amd64 "$CONTAINER_NAME"

echo -e "${YELLOW}⏳ Waiting for network...${NC}"
sleep 10

# --- 4. Installing GUI & VNC inside Container ---
echo -e "\n${CYAN}📦 Installing XFCE Desktop, VNC, and noVNC...${NC}"
echo -e "${YELLOW}☕  (Grab a coffee, this takes a few minutes...)${NC}"

# Install packages silently
sudo lxc exec "$CONTAINER_NAME" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null
    apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server novnc python3-websockify dbus-x11 curl ssh > /dev/null 2>&1
"

# --- 5. Configuring VNC ---
echo -e "${BLUE}🎨 Configuring VNC and noVNC...${NC}"

sudo lxc exec "$CONTAINER_NAME" -- bash -c "
    mkdir -p ~/.vnc
    echo 'kali' | vncpasswd -f > ~/.vnc/passwd
    chmod 600 ~/.vnc/passwd

    echo '#!/bin/bash
    xrdb \$HOME/.Xresources
    startxfce4 &' > ~/.vnc/xstartup
    chmod +x ~/.vnc/xstartup

    vncserver :1 -geometry 1280x720 -depth 24 > /dev/null 2>&1
"

# Start noVNC silently
sudo lxc exec "$CONTAINER_NAME" -- bash -c "nohup /usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen 6080 > /dev/null 2>&1 &"

echo -e "${GREEN}✅ GUI Services Started.${NC}"

# --- 6. Pinggy Tunnel Setup ---
echo -e "\n${CYAN}🌐 Establishing Pinggy Tunnel (Silent Mode)...${NC}"

# Running SSH completely silently
sudo lxc exec "$CONTAINER_NAME" -- bash -c "ssh -p 443 -L4300:localhost:4300 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -R0:localhost:6080 ap.free.pinggy.io > /root/pinggy.log 2>&1 &"

sleep 5

echo -e "${BOLD}${CYAN}============================================${NC}"
echo -e "🔎  Fetching your Access URL..."
echo -e "${BOLD}${CYAN}============================================${NC}"

# Loop to grab URL
URL=""
COUNTER=0
while [ -z "$URL" ] && [ $COUNTER -lt 20 ]; do
    URL=$(sudo lxc exec "$CONTAINER_NAME" -- grep -o "https://.*.free.pinggy.link" /root/pinggy.log | head -n 1)
    if [ -z "$URL" ]; then
         URL=$(sudo lxc exec "$CONTAINER_NAME" -- grep -o "https://.*.pinggy.io" /root/pinggy.log | head -n 1)
    fi
    sleep 2
    COUNTER=$((COUNTER+1))
done

if [ -z "$URL" ]; then
    echo -e "${RED}❌ Could not fetch URL automatically.${NC}"
    echo -e "${YELLOW}Here are the logs (if any):${NC}"
    sudo lxc exec "$CONTAINER_NAME" -- cat /root/pinggy.log
else
    echo -e "${GREEN}${BOLD}🎉 Deployment Successful!${NC}"
    echo ""
    echo -e "${CYAN}🔗 URL:         ${NC} ${BOLD}$URL${NC}"
    echo -e "${CYAN}🔑 VNC Pass:    ${NC} ${BOLD}kali${NC}"
    echo ""
    echo -e "${YELLOW}👉 Click the URL to access Kali Linux GUI.${NC}"
fi

echo -e "${BOLD}${CYAN}============================================${NC}"
