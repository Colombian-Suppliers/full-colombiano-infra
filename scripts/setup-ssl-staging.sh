#!/bin/bash

# =============================================================================
# SSL Certificate Setup Script for Full Colombiano Staging
# =============================================================================
# This script automates the setup of SSL certificates for staging subdomains
# and configures nginx to serve both production and staging environments.
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STAGING_FRONTEND_DOMAIN="stg.fullcolombiano.com"
STAGING_API_DOMAIN="api-stg.fullcolombiano.com"
EMAIL="${SSL_EMAIL:-admin@fullcolombiano.com}"  # Use env var or default
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CERTBOT_DIR="/etc/letsencrypt/live"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed"
        return 1
    fi
    print_success "$1 is installed"
    return 0
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

print_header "Pre-flight Checks"

check_root

# Check required commands
REQUIRED_COMMANDS=("nginx" "certbot" "docker" "curl")
ALL_INSTALLED=true

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        ALL_INSTALLED=false
    fi
done

if [ "$ALL_INSTALLED" = false ]; then
    print_error "Please install missing dependencies before continuing"
    exit 1
fi

# =============================================================================
# DNS Verification
# =============================================================================

print_header "DNS Verification"

print_info "Checking DNS records for staging domains..."

check_dns() {
    local domain=$1
    local ip=$(dig +short "$domain" | head -n1)
    
    if [ -z "$ip" ]; then
        print_error "DNS record not found for $domain"
        return 1
    else
        print_success "DNS record found for $domain: $ip"
        return 0
    fi
}

DNS_OK=true
if ! check_dns "$STAGING_FRONTEND_DOMAIN"; then
    DNS_OK=false
fi

if ! check_dns "$STAGING_API_DOMAIN"; then
    DNS_OK=false
fi

if [ "$DNS_OK" = false ]; then
    print_warning "DNS records are not configured properly"
    print_info "Please add A records for:"
    print_info "  - $STAGING_FRONTEND_DOMAIN"
    print_info "  - $STAGING_API_DOMAIN"
    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# =============================================================================
# Install Certbot (if needed)
# =============================================================================

print_header "Certbot Installation"

if ! command -v certbot &> /dev/null; then
    print_info "Installing Certbot..."
    apt update
    apt install -y certbot python3-certbot-nginx
    print_success "Certbot installed"
else
    print_success "Certbot is already installed"
fi

# =============================================================================
# Generate SSL Certificates
# =============================================================================

print_header "SSL Certificate Generation"

generate_cert() {
    local domain=$1
    
    if [ -d "$CERTBOT_DIR/$domain" ]; then
        print_warning "Certificate for $domain already exists"
        read -p "Do you want to regenerate it? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    print_info "Generating certificate for $domain..."
    
    certbot certonly --nginx \
        -d "$domain" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --force-renewal
    
    if [ $? -eq 0 ]; then
        print_success "Certificate generated for $domain"
        return 0
    else
        print_error "Failed to generate certificate for $domain"
        return 1
    fi
}

# Generate certificates
CERTS_OK=true
if ! generate_cert "$STAGING_FRONTEND_DOMAIN"; then
    CERTS_OK=false
fi

if ! generate_cert "$STAGING_API_DOMAIN"; then
    CERTS_OK=false
fi

if [ "$CERTS_OK" = false ]; then
    print_error "Failed to generate some certificates"
    exit 1
fi

# =============================================================================
# Backup Existing Nginx Configuration
# =============================================================================

print_header "Nginx Configuration Backup"

if [ -f "$NGINX_CONF_DIR/fullcolombiano" ]; then
    BACKUP_FILE="$NGINX_CONF_DIR/fullcolombiano.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backing up existing configuration to $BACKUP_FILE"
    cp "$NGINX_CONF_DIR/fullcolombiano" "$BACKUP_FILE"
    print_success "Backup created"
else
    print_info "No existing configuration found, creating new one"
fi

# =============================================================================
# Deploy Nginx Configuration
# =============================================================================

print_header "Nginx Configuration Deployment"

# Check if the complete.conf file exists in the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_COMPLETE_CONF="$SCRIPT_DIR/../nginx/complete.conf"

if [ ! -f "$NGINX_COMPLETE_CONF" ]; then
    print_error "Nginx configuration file not found: $NGINX_COMPLETE_CONF"
    exit 1
fi

print_info "Copying nginx configuration..."
cp "$NGINX_COMPLETE_CONF" "$NGINX_CONF_DIR/fullcolombiano"
print_success "Configuration copied"

# Enable the site
print_info "Enabling site..."
ln -sf "$NGINX_CONF_DIR/fullcolombiano" "$NGINX_ENABLED_DIR/fullcolombiano"
print_success "Site enabled"

# Remove default site if it exists
if [ -f "$NGINX_ENABLED_DIR/default" ]; then
    print_info "Removing default nginx site..."
    rm -f "$NGINX_ENABLED_DIR/default"
    print_success "Default site removed"
fi

# =============================================================================
# Test Nginx Configuration
# =============================================================================

print_header "Nginx Configuration Test"

print_info "Testing nginx configuration..."
if nginx -t; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed"
    print_warning "Restoring backup..."
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$NGINX_CONF_DIR/fullcolombiano"
        print_info "Backup restored"
    fi
    exit 1
fi

# =============================================================================
# Reload Nginx
# =============================================================================

print_header "Nginx Reload"

print_info "Reloading nginx..."
systemctl reload nginx
print_success "Nginx reloaded successfully"

# =============================================================================
# Setup Auto-Renewal
# =============================================================================

print_header "Auto-Renewal Setup"

print_info "Enabling certbot timer for auto-renewal..."
systemctl enable certbot.timer
systemctl start certbot.timer
print_success "Auto-renewal enabled"

print_info "Testing renewal process (dry run)..."
if certbot renew --dry-run; then
    print_success "Renewal test passed"
else
    print_warning "Renewal test failed, but certificates are still valid"
fi

# =============================================================================
# Verification
# =============================================================================

print_header "Verification"

print_info "Checking SSL certificates..."
certbot certificates

print_info "\nTesting HTTPS endpoints..."

test_endpoint() {
    local url=$1
    local name=$2
    
    print_info "Testing $name: $url"
    
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" | grep -q "200\|301\|302"; then
        print_success "$name is accessible"
    else
        print_warning "$name returned an unexpected status code"
    fi
}

# Test endpoints (these might fail if services aren't running yet)
test_endpoint "https://$STAGING_FRONTEND_DOMAIN" "Staging Frontend"
test_endpoint "https://$STAGING_API_DOMAIN/health" "Staging API"

# =============================================================================
# Summary
# =============================================================================

print_header "Setup Complete!"

echo -e "${GREEN}SSL certificates have been generated and nginx has been configured.${NC}\n"

echo -e "${BLUE}Next Steps:${NC}"
echo -e "1. Start the backend Docker containers:"
echo -e "   ${YELLOW}cd /var/www/fullcolombiano-stg/backend${NC}"
echo -e "   ${YELLOW}docker compose -f docker-compose.staging.yml up -d${NC}\n"

echo -e "2. Build and start the frontend:"
echo -e "   ${YELLOW}cd /var/www/fullcolombiano-stg/frontend${NC}"
echo -e "   ${YELLOW}npm ci && npm run build${NC}"
echo -e "   ${YELLOW}pm2 start npm --name fullcolombiano-frontend-stg -- start -- -p 3001${NC}\n"

echo -e "3. Test the staging endpoints:"
echo -e "   ${YELLOW}curl https://$STAGING_FRONTEND_DOMAIN${NC}"
echo -e "   ${YELLOW}curl https://$STAGING_API_DOMAIN/health${NC}\n"

echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  Check certificates:     ${YELLOW}sudo certbot certificates${NC}"
echo -e "  Test nginx config:      ${YELLOW}sudo nginx -t${NC}"
echo -e "  Reload nginx:           ${YELLOW}sudo systemctl reload nginx${NC}"
echo -e "  Check nginx logs:       ${YELLOW}sudo tail -f /var/log/nginx/error.log${NC}"
echo -e "  Force renew cert:       ${YELLOW}sudo certbot renew --force-renewal${NC}\n"

echo -e "${GREEN}✓ SSL setup completed successfully!${NC}\n"

