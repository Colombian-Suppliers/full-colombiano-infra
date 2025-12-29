#!/bin/bash

# Full Colombiano - VPS Staging Setup Script
# This script sets up a fresh VPS for staging deployment

set -e

echo "🚀 Full Colombiano - VPS Staging Setup"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Running as root"

# Update system
echo -e "\n${YELLOW}Updating system...${NC}"
apt update && apt upgrade -y
echo -e "${GREEN}✓${NC} System updated"

# Install Docker
echo -e "\n${YELLOW}Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER
    rm get-docker.sh
    echo -e "${GREEN}✓${NC} Docker installed"
else
    echo -e "${GREEN}✓${NC} Docker already installed"
fi

# Install Docker Compose
echo -e "\n${YELLOW}Installing Docker Compose...${NC}"
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}✓${NC} Docker Compose installed"
else
    echo -e "${GREEN}✓${NC} Docker Compose already installed"
fi

# Install Node.js 20
echo -e "\n${YELLOW}Installing Node.js 20...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    echo -e "${GREEN}✓${NC} Node.js installed"
else
    echo -e "${GREEN}✓${NC} Node.js already installed ($(node -v))"
fi

# Install PM2
echo -e "\n${YELLOW}Installing PM2...${NC}"
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
    echo -e "${GREEN}✓${NC} PM2 installed"
else
    echo -e "${GREEN}✓${NC} PM2 already installed"
fi

# Install Nginx
echo -e "\n${YELLOW}Installing Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo -e "${GREEN}✓${NC} Nginx installed"
else
    echo -e "${GREEN}✓${NC} Nginx already installed"
fi

# Install Certbot
echo -e "\n${YELLOW}Installing Certbot...${NC}"
if ! command -v certbot &> /dev/null; then
    apt install -y certbot python3-certbot-nginx
    systemctl enable certbot.timer
    systemctl start certbot.timer
    echo -e "${GREEN}✓${NC} Certbot installed"
else
    echo -e "${GREEN}✓${NC} Certbot already installed"
fi

# Create deployment directories
echo -e "\n${YELLOW}Creating deployment directories...${NC}"
mkdir -p /opt/fullcolombiano/{backend,frontend-staging,infra}
chown -R $SUDO_USER:$SUDO_USER /opt/fullcolombiano
echo -e "${GREEN}✓${NC} Directories created"

# Setup firewall
echo -e "\n${YELLOW}Configuring firewall...${NC}"
if ! ufw status | grep -q "Status: active"; then
    ufw --force enable
fi
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo -e "${GREEN}✓${NC} Firewall configured"

# Setup log rotation
echo -e "\n${YELLOW}Setting up log rotation...${NC}"
cat > /etc/logrotate.d/fullcolombiano << 'EOF'
/var/log/nginx/stg.fullcolombiano.com.*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
    endscript
}
EOF
echo -e "${GREEN}✓${NC} Log rotation configured"

# Print summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ VPS Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Setup DNS A records:"
echo "   - stg.fullcolombiano.com → $(curl -s ifconfig.me)"
echo "   - api-stg.fullcolombiano.com → $(curl -s ifconfig.me)"
echo ""
echo "2. Get SSL certificates:"
echo "   sudo certbot certonly --nginx -d stg.fullcolombiano.com"
echo "   sudo certbot certonly --nginx -d api-stg.fullcolombiano.com"
echo ""
echo "3. Copy nginx configuration:"
echo "   sudo cp /opt/fullcolombiano/infra/nginx/staging.conf /etc/nginx/sites-available/"
echo "   sudo ln -s /etc/nginx/sites-available/staging.conf /etc/nginx/sites-enabled/"
echo "   sudo nginx -t && sudo systemctl restart nginx"
echo ""
echo "4. Add GitHub Actions secrets (see STAGING_DEPLOYMENT.md)"
echo ""
echo "5. Push to develop branch to trigger deployment"
echo ""
echo -e "${YELLOW}⚠️  Remember to logout and login again for Docker group changes to take effect${NC}"

