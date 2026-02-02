#!/bin/bash

# ==========================================
#  Kali Linux LXC + VNC + Pinggy Automation
#  Fix: SubUID/SubGID Mapping (Nested Fix) 🔧
# ==========================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Disable stop-on-error to handle setups manually
set +e 

echo -e "${BOLD}${CYAN}============================================${NC}"
echo -e "   ${BOLD}🐉 Kali Linux Auto-Deployer (ID Fix) 🐉${NC}   "
echo -e "${BOLD}${CYAN}============================================${NC}"

# --- 1. System Update ---
echo -e "\n${BLUE}🔄 Updating host system...${NC}"
sudo apt-get update -qq || echo -e "${YELLOW}⚠️  Update warnings ignored...${NC}"

# --- 2. Install LXD ---
if ! command -v lxd &> /dev/null; then
    echo -e "${BLUE}🛠️  Installing LXD...${NC}"
    sudo apt-get install -y lxd lxd-client || sudo snap install lxd
fi

# --- 3. CRITICAL FIX: Configure SubUID/SubGID ---
# Ye step "Failed ID" error ko fix karega
echo -e "${BLUE}🔧 Configuring User ID Mapping (The Fix)...${NC}"
if ! grep -q "root:1000000:65536" /etc/subuid; then
    echo "root:1000000:65536" | sudo tee -a /etc/subuid
fi
if ! grep -q "root:1000000:65536" /etc/subgid; then
    echo "root:1000000:65536" | sudo tee -a /etc/subgid
fi

# Restart LXD to apply changes
echo -e "${YELLOW}♻️  Restarting LXD service...${NC}"
sudo systemctl restart lxd 2>/dev/null || sudo snap restart lxd 2>/dev/null

# --- 4. Initialize LXD ---
if ! sudo lxd waitready --timeout 15 2>/dev/null; then
    echo -e "${YELLOW}⚙️  Initializing LXD...${NC}"
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

# --- 5. Fix Image Remote ---
sudo lxc remote add images https://images.linuxcontainers.org --protocol=simplestreams --accept-certificate 2>/dev/null || true

# --- 6. Container Launch ---
CONTAINER_NAME="kali-gui"

if sudo lxc list | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}🗑️  Cleaning up old container...${NC}"
    sudo lxc stop "$CONTAINER_NAME" --force 2>/dev/null
    sudo lxc delete "$CONTAINER_NAME" 2>/dev/null
fi

echo -e "${BLUE}🚀 Launching Kali Linux container...${NC}"

# Try Privileged first (Most likely to work in Codespaces)
if sudo lxc launch images:kali/rolling "$CONTAINER_NAME" -c security.privileged=true -c security.nesting=true; then
    echo -e "${GREEN}✅ Success! Kali Rolling Launched (Privileged).${NC}"
elif sudo lxc launch images:kali "$CONTAINER_NAME" -c security.privileged=true -c security.nesting=true; then
    echo -e "${GREEN}✅ Success! Kali Generic Launched (Privileged).${NC}"
else
    # Fallback to Unprivileged if Privileged fails
    echo -e "${YELLOW}⚠️  Privileged mode failed. Trying unprivileged...${NC}"
    if sudo lxc launch images:kali/rolling "$CONTAINER_NAME"; then
         echo -e "${GREEN}✅ Success! Kali Rolling Launched (Unprivileged).${NC}"
    else
         echo -e "${RED}❌ Error: Launch failed completely.${NC}"
         echo -e "${YELLOW}Debug suggestion: Try running this in a fresh Codespace.${NC}"
         exit 1
    fi
fi

echo -e "${YELLOW}⏳ Waiting for network...${NC}"
sleep 10

# --- 7. Installing GUI & VNC ---
echo -e "\n${CYAN}📦 Installing XFCE Desktop, VNC, and noVNC...${NC}"
echo -e "${YELLOW}☕  (This takes time! Don't close terminal...)${NC}"

sudo lxc exec "$CONTAINER_NAME" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y kali-linux-default xfce4 xfce4-goodies tigervnc-standalone-server novnc python3-websockify dbus-x11 curl ssh
" > /dev/null 2>&1

# --- 8. Configuring VNC ---
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

echo -e "${GREEN}✅ GUI Services Started.${NC}"

# --- 9. Pinggy Tunnel Setup ---
echo -e "\n${CYAN}🌐 Establishing Pinggy Tunnel...${NC}"

sudo lxc exec "$CONTAINER_NAME" -- bash -c "ssh -p 443 -L4300:localhost:4300 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -R0:localhost:6080 ap.free.pinggy.io > /root/pinggy.log 2>&1 &"

sleep 8

echo -e "${BOLD}${CYAN}============================================${NC}"
echo -e "🔎  Fetching your Access URL..."
echo -e "${BOLD}${CYAN}============================================${NC}"

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
    echo -e "Check logs manually: sudo lxc exec $CONTAINER_NAME -- cat /root/pinggy.log"
else
    echo -e "${GREEN}${BOLD}🎉 Deployment Successful!${NC}"
    echo ""
    echo -e "${CYAN}🔗 URL:         ${NC} ${BOLD}$URL${NC}"
    echo -e "${CYAN}🔑 VNC Pass:    ${NC} ${BOLD}kali${NC}"
    echo ""
    echo -e "${YELLOW}👉 Click the URL to access Kali Linux GUI.${NC}"
fi
echo -e "${BOLD}${CYAN}============================================${NC}"
