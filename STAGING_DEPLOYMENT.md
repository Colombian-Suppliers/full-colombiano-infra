# 🚀 Staging Deployment Guide

## 📋 Overview

This guide covers deploying the Full Colombiano application to staging environment with the following subdomains:
- **Frontend**: https://stg.fullcolombiano.com
- **API**: https://api-stg.fullcolombiano.com

## 🔧 Prerequisites

### VPS Requirements
- Ubuntu 20.04+ or Debian 11+
- Minimum 2GB RAM, 2 CPU cores
- 20GB disk space
- Root or sudo access

### Domain Setup
- DNS A records pointing to VPS IP:
  - `stg.fullcolombiano.com` → VPS_IP
  - `api-stg.fullcolombiano.com` → VPS_IP

## 📦 VPS Initial Setup

### 1. Install Required Software

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2
sudo npm install -g pm2

# Install Nginx
sudo apt install -y nginx

# Install Certbot for SSL
sudo apt install -y certbot python3-certbot-nginx
```

### 2. Create Deployment Directories

```bash
sudo mkdir -p /opt/fullcolombiano/{backend,frontend-staging}
sudo chown -R $USER:$USER /opt/fullcolombiano
```

### 3. Setup SSL Certificates

```bash
# Get SSL certificates for both domains
sudo certbot certonly --nginx -d stg.fullcolombiano.com
sudo certbot certonly --nginx -d api-stg.fullcolombiano.com

# Auto-renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### 4. Setup Nginx

```bash
# Copy nginx configuration
sudo cp /opt/fullcolombiano/infra/nginx/staging.conf /etc/nginx/sites-available/staging.conf

# Enable site
sudo ln -s /etc/nginx/sites-available/staging.conf /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

### 5. Setup Firewall

```bash
# Allow SSH, HTTP, HTTPS
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 🔐 GitHub Secrets Setup

Add these secrets to both repositories (Settings → Secrets and variables → Actions):

### Required Secrets

```yaml
# VPS Connection
VPS_HOST: your-vps-ip-or-domain
VPS_USERNAME: your-ssh-username
VPS_SSH_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  your-private-key-here
  -----END OPENSSH PRIVATE KEY-----
VPS_PORT: 22

# Backend Secrets
STAGING_DB_PASSWORD: strong-database-password-here
STAGING_SECRET_KEY: long-random-secret-key-for-jwt

# Email Configuration (use real SMTP)
MAIL_USERNAME: your-email@gmail.com
MAIL_PASSWORD: your-app-password
MAIL_FROM: noreply@fullcolombiano.com
MAIL_SERVER: smtp.gmail.com
MAIL_PORT: 587

# Optional: Docker Hub (for caching)
DOCKER_USERNAME: your-dockerhub-username
DOCKER_PASSWORD: your-dockerhub-password
```

### Generate SSH Key for GitHub Actions

```bash
# On your local machine
ssh-keygen -t ed25519 -C "github-actions@fullcolombiano.com" -f ~/.ssh/github_actions

# Copy public key to VPS
ssh-copy-id -i ~/.ssh/github_actions.pub user@your-vps-ip

# Copy private key content for GitHub secret
cat ~/.ssh/github_actions
# Copy the entire output including BEGIN and END lines
```

### Generate Secret Key

```bash
# Generate a secure secret key
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

## 🚀 Deployment Process

### Automatic Deployment

Deployments trigger automatically when you push to `develop` or `staging` branches:

```bash
# Deploy backend
cd full-colombiano-backend
git checkout develop
git push origin develop

# Deploy frontend
cd full-colombiano-frontend
git checkout develop
git push origin develop
```

### Manual Deployment

You can also trigger deployments manually from GitHub:
1. Go to repository → Actions
2. Select "Deploy to Staging" workflow
3. Click "Run workflow"
4. Select branch and click "Run workflow"

## 🔍 Monitoring

### Check Backend Status

```bash
# SSH into VPS
ssh user@your-vps-ip

# Check Docker containers
cd /opt/fullcolombiano/backend
docker compose -f docker-compose.staging.yml ps

# View logs
docker compose -f docker-compose.staging.yml logs -f api

# Check API health
curl https://api-stg.fullcolombiano.com/health
```

### Check Frontend Status

```bash
# Check PM2 status
pm2 status

# View logs
pm2 logs fullcolombiano-frontend-staging

# Check frontend
curl https://stg.fullcolombiano.com
```

### Check Nginx

```bash
# Test configuration
sudo nginx -t

# View logs
sudo tail -f /var/log/nginx/stg.fullcolombiano.com.access.log
sudo tail -f /var/log/nginx/api-stg.fullcolombiano.com.access.log
```

## 🐛 Troubleshooting

### Backend Not Starting

```bash
# Check logs
docker compose -f docker-compose.staging.yml logs api

# Restart containers
docker compose -f docker-compose.staging.yml restart

# Rebuild if needed
docker compose -f docker-compose.staging.yml up -d --build
```

### Frontend Not Starting

```bash
# Check PM2 logs
pm2 logs fullcolombiano-frontend-staging --lines 100

# Restart
pm2 restart fullcolombiano-frontend-staging

# Delete and restart
pm2 delete fullcolombiano-frontend-staging
pm2 start ecosystem.config.js
```

### SSL Certificate Issues

```bash
# Renew certificates
sudo certbot renew

# Test renewal
sudo certbot renew --dry-run
```

### Database Issues

```bash
# Access database
docker compose -f docker-compose.staging.yml exec db psql -U fullcolombiano -d fullcolombiano_staging

# Run migrations manually
docker compose -f docker-compose.staging.yml exec api alembic upgrade head

# Seed data
docker compose -f docker-compose.staging.yml exec api python scripts/seed_staging.py
```

## 📊 Post-Deployment Checklist

- [ ] Backend API accessible at https://api-stg.fullcolombiano.com
- [ ] Frontend accessible at https://stg.fullcolombiano.com
- [ ] SSL certificates valid and auto-renewing
- [ ] Health check endpoint responding: `/health`
- [ ] API documentation accessible: `/docs`
- [ ] Database migrations applied
- [ ] Email service configured and working
- [ ] CORS configured correctly
- [ ] Logs accessible and rotating
- [ ] Monitoring setup (optional: Sentry, LogRocket)

## 🔄 Updating Deployment

### Update Backend

```bash
# Push to develop branch
git push origin develop

# Or manually on VPS
cd /opt/fullcolombiano/backend
git pull origin develop
docker compose -f docker-compose.staging.yml up -d --build
```

### Update Frontend

```bash
# Push to develop branch
git push origin develop

# Or manually on VPS
cd /opt/fullcolombiano/frontend-staging
git pull origin develop
npm run build
pm2 restart fullcolombiano-frontend-staging
```

## 🔒 Security Best Practices

1. **Use strong passwords** for database and secret keys
2. **Enable firewall** (UFW) with only necessary ports
3. **Keep system updated**: `sudo apt update && sudo apt upgrade`
4. **Use SSH keys** instead of passwords
5. **Disable root login** in `/etc/ssh/sshd_config`
6. **Setup fail2ban** to prevent brute force attacks
7. **Regular backups** of database and uploads
8. **Monitor logs** for suspicious activity

## 📝 Environment Variables

### Backend (.env.staging)

```env
# Database
DATABASE_URL=postgresql+asyncpg://fullcolombiano:PASSWORD@db:5432/fullcolombiano_staging
DATABASE_URL_SYNC=postgresql://fullcolombiano:PASSWORD@db:5432/fullcolombiano_staging

# Security
SECRET_KEY=your-secret-key-here

# Environment
ENVIRONMENT=staging
DEBUG=false

# URLs
FRONTEND_URL=https://stg.fullcolombiano.com
VERIFY_EMAIL_URL=https://stg.fullcolombiano.com/verify-email
RESET_PASSWORD_URL=https://stg.fullcolombiano.com/reset-password

# Email
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-app-password
MAIL_FROM=noreply@fullcolombiano.com
MAIL_FROM_NAME=Full Colombiano Staging
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587

# CORS
CORS_ORIGINS=https://stg.fullcolombiano.com,https://api-stg.fullcolombiano.com
```

### Frontend (ecosystem.config.js)

```javascript
env: {
  NODE_ENV: 'production',
  PORT: 3001,
  NEXT_PUBLIC_API_URL: 'https://api-stg.fullcolombiano.com'
}
```

## 🎯 Quick Commands

```bash
# Restart everything
cd /opt/fullcolombiano/backend && docker compose -f docker-compose.staging.yml restart
pm2 restart fullcolombiano-frontend-staging
sudo systemctl restart nginx

# View all logs
docker compose -f docker-compose.staging.yml logs -f &
pm2 logs fullcolombiano-frontend-staging &
sudo tail -f /var/log/nginx/*.log

# Check status
docker compose -f docker-compose.staging.yml ps
pm2 status
sudo systemctl status nginx
```

## 📞 Support

If you encounter issues:
1. Check logs first
2. Review this documentation
3. Check GitHub Actions workflow runs
4. Contact DevOps team

---

**Last Updated**: 2025-12-29
**Version**: 1.0.0

