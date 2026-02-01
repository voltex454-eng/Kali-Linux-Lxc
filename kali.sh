#!/bin/bash
# Kali Linux: Docker Mode (Optimized for GitHub Codespaces)
# Features: XFCE Desktop + VNC + Pinggy Tunnel

# --- COLORS ---
ORANGE='\033[1;33m'
GRAY='\033[1;90m'
GREEN='\033[1;32m'
NC='\033[0m'

CONTAINER_NAME="kali-gui-container"

clear
echo -e "${GRAY}------------------------------------------------${NC}"
echo -e "${ORANGE}   Kali Linux: Docker Mode (Codespaces)   ${NC}"
echo -e "${GRAY}------------------------------------------------${NC}"

# 1. Check for Docker
echo -e "${ORANGE}[1/7]${GRAY} Checking Docker Environment...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${ORANGE}Error:${NC} Docker not found! Codespaces usually has Docker."
    echo "Please ensure you are in a standard Codespace environment."
    exit 1
fi

# 2. Setup VNC Web Client (noVNC)
if [ ! -d "novnc" ]; then
    echo -e "${ORANGE}[2/7]${GRAY} Configuring VNC Viewer...${NC}"
    git clone --depth 1 https://github.com/novnc/noVNC.git novnc > /dev/null 2>&1
    git clone --depth 1 https://github.com/novnc/websockify novnc/utils/websockify > /dev/null 2>&1
fi

# 3. Run Kali Docker Container
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo -e "${ORANGE}[3/7]${GRAY} Container is already running.${NC}"
else
    echo -e "${ORANGE}[3/7]${GRAY} Pulling & Starting Kali Container...${NC}"
    # Remove old container if it exists but stopped
    docker rm -f $CONTAINER_NAME > /dev/null 2>&1
    
    # Run Docker with Port 5901 exposed for VNC
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p 5901:5901 \
        kalilinux/kali-rolling tail -f /dev/null > /dev/null
fi

# 4. Install GUI & VNC inside Docker
echo -e "${ORANGE}[4/7]${GRAY} Installing Desktop (This takes 5-8 mins)...${NC}"

# Create setup script for inside the container
cat << 'EOF' > setup_docker.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# Install XFCE, VNC Server, and essential tools
apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server dbus-x11 net-tools wget
apt-get clean

# Setup VNC Password (default: kali)
mkdir -p /root/.vnc
echo "kali" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# Create Startup Script
echo '#!/bin/bash
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
export USER=root
vncserver :1 -geometry 1280x720 -depth 24 -localhost no
' > /usr/local/bin/start-vnc
chmod +x /usr/local/bin/start-vnc
EOF

# Copy script into container and execute
docker cp setup_docker.sh "$CONTAINER_NAME":/root/
docker exec "$CONTAINER_NAME" bash /root/setup_docker.sh > /dev/null 2>&1

# 5. Start VNC Server
echo -e "${ORANGE}[5/7]${GRAY} Starting VNC Server...${NC}"
docker exec "$CONTAINER_NAME" /usr/local/bin/start-vnc > /dev/null 2>&1

# 6. Start noVNC Proxy
echo -e "${ORANGE}[6/7]${GRAY} Starting Display Bridge...${NC}"
# Connects Localhost:6080 -> Docker:5901
./novnc/utils/novnc_proxy --vnc localhost:5901 --listen 6080 > /dev/null 2>&1 &

# 7. Public URL (Pinggy)
echo -e "${ORANGE}[7/7]${GRAY} Generating Public Link...${NC}"

rm -f tunnel.log
# Tunnel port 6080 (noVNC)
nohup ssh -q -p 443 -R0:localhost:6080 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 free.pinggy.io > tunnel.log 2>&1 &

SSH_PID=$!
while ! grep -q "https://" tunnel.log; do
    sleep 1
done

PUBLIC_URL=$(grep -o "https://[^ ]*.pinggy.link" tunnel.log | head -n 1)

# --- FINAL CLEAN SCREEN ---
clear
echo -e "${GRAY}========================================================${NC}"
echo -e "${ORANGE}      ✅  KALI DOCKER STARTED! ${NC}"
echo -e "${GRAY}========================================================${NC}"
echo ""
echo -e "${GRAY} 🔗 ACCESS URL:  ${ORANGE}$PUBLIC_URL${NC}"
echo -e "${GRAY} 🔑 VNC Password: ${ORANGE}kali${NC}"
echo ""
echo -e "${GRAY}========================================================${NC}"
echo -e "${GRAY} ⏳ Wait 1 min if screen is black (Desktop loading)${NC}"
echo -e "${GRAY} 🛑 Stop: docker stop $CONTAINER_NAME${NC}"
echo -e "${GRAY}========================================================${NC}"

# Silent Loop
while kill -0 $SSH_PID 2>/dev/null; do
    sleep 5
done
