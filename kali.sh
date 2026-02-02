#!/bin/bash

# ==========================================
#  Kali Linux Auto-Deployer (Visible Mode) 👁️
#  Feature: Shows Live Installation Progress
# ==========================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

set +e

echo -e "${BLUE}============================================${NC}"
echo -e "   ${GREEN}🐉 Kali Linux Deployer (Visible Progress) 🐉${NC}   "
echo -e "${BLUE}============================================${NC}"

# --- 1. Fix User ID Mapping ---
echo -e "${YELLOW}🔧 Checking ID Mapping...${NC}"
if ! grep -q "root:1000000:65536" /etc/subuid; then
    echo "root:1000000:65536" | sudo tee -a /etc/subuid
fi
if ! grep -q "root:1000000:65536" /etc/subgid; then
    echo "root:1000000:65536" | sudo tee -a /etc/subgid
fi

# --- 2. Install & Reset LXD ---
echo -e "${BLUE}🔄 Preparing LXD...${NC}"
sudo apt-get update -qq || true

if ! command -v lxd &> /dev/null; then
    sudo apt-get install -y lxd lxd-client || sudo snap install lxd
fi

sudo systemctl restart lxd 2>/dev/null || sudo snap restart lxd 2>/dev/null
sleep 3

# Initialize LXD (Storage Fix Included)
sudo lxc waitready --timeout 15 2>/dev/null
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
- config: {}
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

# --- 3. Fix Image Server ---
echo -e "${BLUE}🌍 Syncing Image Server...${NC}"
sudo lxc remote add images https://images.linuxcontainers.org --protocol=simplestreams --accept-certificate 2>/dev/null || true

# --- 4. Launch Container ---
CONTAINER_NAME="kali-gui"

# Cleanup
sudo lxc stop "$CONTAINER_NAME" --force 2>/dev/null
sudo lxc delete "$CONTAINER_NAME" 2>/dev/null

echo -e "${BLUE}🚀 Launching Kali Container...${NC}"

# Launch
if sudo lxc launch images:kali/rolling "$CONTAINER_NAME" -c security.privileged=true -c security.nesting=true; then
    echo -e "${GREEN}✅ Kali Rolling Launched.${NC}"
elif sudo lxc launch images:kali "$CONTAINER_NAME" -c security.privileged=true -c security.nesting=true; then
    echo -e "${GREEN}✅ Kali Generic Launched.${NC}"
else
    echo -e "${RED}❌ Launch failed.${NC}"
    exit 1
fi

echo -e "${YELLOW}⏳ Waiting for network (10s)...${NC}"
sleep 10

# --- 5. Install GUI (WITH OUTPUT) ---
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}📦 STARTING DOWNLOAD & INSTALLATION${NC}"
echo -e "${YELLOW}   (Screen will scroll fast, don't panic!)${NC}"
echo -e "${BLUE}============================================${NC}"

# NOTE: Removed '> /dev/null' so you can see the progress
sudo lxc exec "$CONTAINER_NAME" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    echo 'Update started...'
    apt-get update -y
    echo 'Installing XFCE, VNC and Tools...'
    apt-get install -y kali-linux-default xfce4 xfce4-goodies tigervnc-standalone-server novnc python3-websockify dbus-x11 curl ssh
"

echo -e "${GREEN}✅ Installation Completed!${NC}"

# --- 6. Configure VNC ---
echo -e "${BLUE}🎨 Configuring VNC...${NC}"
sudo lxc exec "$CONTAINER_NAME" -- bash -c "
    mkdir -p ~/.vnc
    echo 'kali' | vncpasswd -f > ~/.vnc/passwd
    chmod 600 ~/.vnc/passwd
    echo '#!/bin/bash
    xrdb \$HOME/.Xresources
    startxfce4 &' > ~/.vnc/xstartup
    chmod +x ~/.vnc/xstartup
    vncserver :1 -geometry 1280x720 -depth 24
" > /dev/null 2>&1

# Start noVNC
sudo lxc exec "$CONTAINER_NAME" -- bash -c "nohup /usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen 6080 > /dev/null 2>&1 &"

# --- 7. Tunneling ---
echo -e "${BLUE}🌐 Starting Pinggy Tunnel...${NC}"
sudo lxc exec "$CONTAINER_NAME" -- bash -c "ssh -p 443 -L4300:localhost:4300 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -R0:localhost:6080 ap.free.pinggy.io > /root/pinggy.log 2>&1 &"

sleep 10

# --- 8. Get URL ---
echo -e "${BLUE}🔎 Fetching URL...${NC}"
URL=$(sudo lxc exec "$CONTAINER_NAME" -- grep -o "https://.*.free.pinggy.link" /root/pinggy.log | head -n 1)

if [ -z "$URL" ]; then
    URL=$(sudo lxc exec "$CONTAINER_NAME" -- grep -o "https://.*.pinggy.io" /root/pinggy.log | head -n 1)
fi

if [ -z "$URL" ]; then
    echo -e "${RED}❌ URL not found. Check logs manually.${NC}"
    sudo lxc exec "$CONTAINER_NAME" -- cat /root/pinggy.log
else
    echo -e "${GREEN}============================================${NC}"
    echo -e "🎉  ${BOLD}DEPLOYMENT SUCCESSFUL!${NC}"
    echo -e "🔗  URL:      ${BOLD}$URL${NC}"
    echo -e "🔑  Password: ${BOLD}kali${NC}"
    echo -e "${GREEN}============================================${NC}"
fi
