#!/bin/bash
# Kali Linux: LXC Container Mode (LXD)
# Features: XFCE Desktop + VNC + Pinggy Tunnel

# --- COLORS ---
ORANGE='\033[1;33m'
GRAY='\033[1;90m'
GREEN='\033[1;32m'
NC='\033[0m'

CONTAINER_NAME="kali-gui"

clear
echo -e "${GRAY}------------------------------------------------${NC}"
echo -e "${ORANGE}   Kali Linux: LXC Container (LXD Mode)   ${NC}"
echo -e "${GRAY}------------------------------------------------${NC}"

# 1. Check & Install LXD/Snap
echo -e "${ORANGE}[1/7]${GRAY} Checking System Requirements...${NC}"
if ! command -v lxd &> /dev/null; then
    echo -e "${GRAY}Installing LXD via Snap...${NC}"
    sudo apt-get update -y > /dev/null 2>&1
    sudo apt-get install -y snapd > /dev/null 2>&1
    sudo snap install lxd
    sudo lxd init --auto
fi

# Ensure git/wget for tools
sudo apt-get install -y git wget > /dev/null 2>&1

# 2. Setup VNC Web Client (noVNC)
if [ ! -d "novnc" ]; then
    echo -e "${ORANGE}[2/7]${GRAY} Configuring VNC Viewer...${NC}"
    git clone --depth 1 https://github.com/novnc/noVNC.git novnc > /dev/null 2>&1
    git clone --depth 1 https://github.com/novnc/websockify novnc/utils/websockify > /dev/null 2>&1
fi

# 3. Create Kali Container
if sudo lxc list | grep -q "$CONTAINER_NAME"; then
    echo -e "${ORANGE}[3/7]${GRAY} Container exists. Starting...${NC}"
    sudo lxc start "$CONTAINER_NAME" > /dev/null 2>&1
else
    echo -e "${ORANGE}[3/7]${GRAY} Creating Kali Container (First time takes time)...${NC}"
    # Launching official Kali image from images server
    sudo lxc launch images:kali/current/amd64 "$CONTAINER_NAME"
    
    # Wait for network
    sleep 5
fi

# 4. Install GUI & VNC inside Container
echo -e "${ORANGE}[4/7]${GRAY} Setting up Desktop Environment (This may take 5-10 mins)...${NC}"

# We push a setup script inside the container to handle the heavy lifting
cat << 'EOF' > setup_internal.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
# Update and install XFCE4 and TigerVNC (lighter than full kali-desktop)
apt-get update
apt-get install -y xfce4 xfce4-goodies dbus-x11 tigervnc-standalone-server net-tools
apt-get clean

# Setup VNC Password (default: kali)
mkdir -p /root/.vnc
echo "kali" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# Create Startup Script
cat << 'VNCSTART' > /usr/local/bin/start-vnc
#!/bin/bash
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
export USER=root
vncserver :1 -geometry 1280x720 -depth 24 -localhost no
VNCSTART
chmod +x /usr/local/bin/start-vnc
EOF

# Transfer and run script inside LXC
sudo lxc file push setup_internal.sh "$CONTAINER_NAME"/root/
sudo lxc exec "$CONTAINER_NAME" -- bash /root/setup_internal.sh > /dev/null 2>&1

# 5. Start VNC Server inside Container
echo -e "${ORANGE}[5/7]${GRAY} Starting VNC Server...${NC}"
sudo lxc exec "$CONTAINER_NAME" -- /usr/local/bin/start-vnc > /dev/null 2>&1

# Get Container IP
CONTAINER_IP=$(sudo lxc list "$CONTAINER_NAME" -c 4 --format csv | cut -d" " -f1)

if [ -z "$CONTAINER_IP" ]; then
    echo "Error: Could not get Container IP. Retrying..."
    sleep 5
    CONTAINER_IP=$(sudo lxc list "$CONTAINER_NAME" -c 4 --format csv | cut -d" " -f1)
fi

echo -e "${GREEN}Container IP: $CONTAINER_IP${NC}"

# 6. Start noVNC Proxy (Connect Host -> Container)
echo -e "${ORANGE}[6/7]${GRAY} Starting Display Bridge...${NC}"
./novnc/utils/novnc_proxy --vnc "$CONTAINER_IP":5901 --listen 6080 > /dev/null 2>&1 &

# 7. Public URL (Pinggy)
echo -e "${ORANGE}[7/7]${GRAY} Generating Public Link...${NC}"

rm -f tunnel.log
# Tunnel the noVNC port (6080)
nohup ssh -q -p 443 -R0:localhost:6080 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 free.pinggy.io > tunnel.log 2>&1 &

SSH_PID=$!
while ! grep -q "https://" tunnel.log; do
    sleep 1
done

PUBLIC_URL=$(grep -o "https://[^ ]*.pinggy.link" tunnel.log | head -n 1)

# --- FINAL CLEAN SCREEN ---
clear
echo -e "${GRAY}========================================================${NC}"
echo -e "${ORANGE}      ✅  KALI LXC STARTED! ${NC}"
echo -e "${GRAY}========================================================${NC}"
echo ""
echo -e "${GRAY} 🔗 ACCESS URL:  ${ORANGE}$PUBLIC_URL${NC}"
echo -e "${GRAY} 🔑 VNC Password: ${ORANGE}kali${NC}"
echo ""
echo -e "${GRAY}========================================================${NC}"
echo -e "${GRAY} ⏳ First boot installs XFCE, might take time.${NC}"
echo -e "${GRAY} 🛑 To Stop: Press Ctrl + C${NC}"
echo -e "${GRAY}========================================================${NC}"

# Silent Loop
while kill -0 $SSH_PID 2>/dev/null; do
    sleep 5
done
