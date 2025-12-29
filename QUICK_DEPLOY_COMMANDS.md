# Comandos Rápidos de Deployment

Todos los comandos necesarios para desplegar Colombian Supply desde cero.

## 🔑 1. Generar SSH Keys (Tu Máquina Local)

```bash
# Generar key pair
ssh-keygen -t ed25519 -C "github-actions@colombiansupply.com" -f ~/.ssh/colombian_vps_deploy

# Ver public key (para copiar al VPS)
cat ~/.ssh/colombian_vps_deploy.pub

# Ver private key (para GitHub Secrets)
cat ~/.ssh/colombian_vps_deploy
```

## 🖥️ 2. Configurar VPS (Primera Vez)

```bash
# Conectar como root (o tu usuario inicial)
ssh root@TU_IP_VPS

# Crear usuario deploy
adduser deploy
usermod -aG sudo,docker deploy

# Configurar SSH para deploy
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# Agregar tu public key (pegar contenido de ~/.ssh/colombian_vps_deploy.pub)
nano /home/deploy/.ssh/authorized_keys

# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker deploy

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Configurar firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Logout y login como deploy
exit
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS
```

## 📁 3. Crear Estructura de Directorios (VPS como deploy)

```bash
# Crear directorios
mkdir -p ~/apps/{traefik,backend,frontend,postgres,nginx}

# Verificar
ls -la ~/apps/
```

## 🌐 4. Setup Traefik (Reverse Proxy + SSL)

```bash
# Conectar al VPS
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS

cd ~/apps/traefik

# Crear docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./acme.json:/acme.json
    networks:
      - colombian-staging-network
      - colombian-production-network

networks:
  colombian-staging-network:
    external: true
  colombian-production-network:
    external: true
EOF

# Crear traefik.yml
cat > traefik.yml <<'EOF'
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: colombian-production-network

certificatesResolvers:
  letsencrypt:
    acme:
      email: devops@colombiansupply.com
      storage: /acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO

accessLog: {}
EOF

# Crear archivo para certificados
touch acme.json
chmod 600 acme.json

# Crear networks
docker network create colombian-staging-network
docker network create colombian-production-network

# Iniciar Traefik
docker-compose up -d

# Verificar
docker-compose logs -f
```

## 🔐 5. Configurar GitHub Secrets

### Backend Repository:
```
Ir a: https://github.com/Colombian-Suppliers/full-colombiano-backend/settings/secrets/actions

Crear estos secrets:
- VPS_HOST = TU_IP_VPS
- VPS_USER = deploy
- VPS_SSH_KEY = (contenido de ~/.ssh/colombian_vps_deploy)
- VPS_PORT = 22
- STAGING_DATABASE_URL = postgresql://colombian:PASSWORD@postgres:5432/colombian_staging
- STAGING_SECRET_KEY = (generar random: openssl rand -hex 32)
- STAGING_CORS_ORIGINS = https://stg.colombiansupply.com
- PROD_DATABASE_URL = postgresql://colombian:PASSWORD@postgres:5432/colombian_production
- PROD_SECRET_KEY = (generar random: openssl rand -hex 32)
- PROD_CORS_ORIGINS = https://colombiansupply.com
- SENTRY_DSN = (opcional)
```

### Frontend Repository:
```
Ir a: https://github.com/Colombian-Suppliers/full-colombiano-frontend/settings/secrets/actions

Crear estos secrets:
- VPS_HOST = TU_IP_VPS
- VPS_USER = deploy
- VPS_SSH_KEY = (contenido de ~/.ssh/colombian_vps_deploy)
- VPS_PORT = 22
- STAGING_API_URL = https://api-stg.colombiansupply.com
- PROD_API_URL = https://api.colombiansupply.com
- GA_ID = (opcional)
```

## 🗄️ 6. Setup Backend (Primer Deploy Manual)

```bash
# En el VPS
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS
cd ~/apps/backend

# Clonar repo
git clone https://github.com/Colombian-Suppliers/full-colombiano-backend.git temp
cd temp

# Crear .env.staging
cat > .env.staging <<'EOF'
DATABASE_URL=postgresql://colombian:CAMBIAR_PASSWORD@postgres:5432/colombian_staging
POSTGRES_USER=colombian
POSTGRES_PASSWORD=CAMBIAR_PASSWORD
SECRET_KEY=CAMBIAR_SECRET_KEY
ENVIRONMENT=staging
CORS_ORIGINS=https://stg.colombiansupply.com
EOF

# Build imagen
docker build -t colombian-backend:staging .

# Copiar docker-compose a directorio principal
cp docker-compose.staging.yml ../
cd ..

# Iniciar servicios
docker-compose -f docker-compose.staging.yml up -d

# Ver logs
docker-compose -f docker-compose.staging.yml logs -f

# Verificar (en otra terminal)
curl http://localhost:8001/health
```

## 🎨 7. Setup Frontend (Primer Deploy Manual)

```bash
# En el VPS
cd ~/apps/frontend

# Clonar repo
git clone https://github.com/Colombian-Suppliers/full-colombiano-frontend.git temp
cd temp

# Crear .env.staging
cat > .env.staging <<'EOF'
NEXT_PUBLIC_API_URL=https://api-stg.colombiansupply.com
NEXT_PUBLIC_ENVIRONMENT=staging
NEXT_PUBLIC_SITE_URL=https://stg.colombiansupply.com
EOF

# Build imagen
docker build \
  --build-arg NEXT_PUBLIC_API_URL=https://api-stg.colombiansupply.com \
  --build-arg NEXT_PUBLIC_ENVIRONMENT=staging \
  -t colombian-frontend:staging .

# Copiar docker-compose
cp docker-compose.staging.yml ../
cd ..

# Iniciar
docker-compose -f docker-compose.staging.yml up -d

# Ver logs
docker-compose -f docker-compose.staging.yml logs -f

# Verificar
curl http://localhost:3001
```

## 🌐 8. Configurar DNS

En tu proveedor DNS (Cloudflare, Route53, etc.):

```
Tipo  Nombre                       Valor        TTL
A     api-stg.colombiansupply.com  TU_IP_VPS    300
A     stg.colombiansupply.com      TU_IP_VPS    300
A     api.colombiansupply.com      TU_IP_VPS    300
A     colombiansupply.com          TU_IP_VPS    300
A     www.colombiansupply.com      TU_IP_VPS    300
```

Esperar 2-5 minutos para propagación.

## ✅ 9. Verificar Deployment

```bash
# Backend staging
curl https://api-stg.colombiansupply.com/health
curl https://api-stg.colombiansupply.com/docs

# Frontend staging
curl https://stg.colombiansupply.com

# En navegador
open https://stg.colombiansupply.com
open https://api-stg.colombiansupply.com/docs
```

## 🚀 10. Deploy Automático con GitHub Actions

### Staging (automático en push a develop):

```bash
# En tu máquina local
cd full-colombiano-backend
git checkout develop
git add .
git commit -m "feat: initial setup"
git push origin develop

# Esto triggerea el workflow automáticamente
# Ver en: https://github.com/Colombian-Suppliers/full-colombiano-backend/actions
```

### Production (manual con tag):

```bash
# Backend
cd full-colombiano-backend
git checkout main
git merge develop
git tag -a v1.0.0 -m "First production release"
git push origin main
git push origin v1.0.0

# Frontend
cd full-colombiano-frontend
git checkout main
git merge develop
git tag -a v1.0.0 -m "First production release"
git push origin main
git push origin v1.0.0

# Ver deployments en Actions tab
```

## 📊 11. Monitoreo

```bash
# Ver todos los contenedores
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS
docker ps

# Ver logs en tiempo real
cd ~/apps/backend
docker-compose -f docker-compose.staging.yml logs -f backend

cd ~/apps/frontend
docker-compose -f docker-compose.staging.yml logs -f frontend

# Ver uso de recursos
docker stats

# Health checks
curl https://api-stg.colombiansupply.com/health
curl https://stg.colombiansupply.com
```

## 🔄 12. Comandos Útiles

### Reiniciar servicios:

```bash
# Backend staging
cd ~/apps/backend
docker-compose -f docker-compose.staging.yml restart backend

# Frontend production
cd ~/apps/frontend
docker-compose -f docker-compose.production.yml restart frontend

# Traefik
cd ~/apps/traefik
docker-compose restart traefik
```

### Ver logs:

```bash
# Últimas 100 líneas
docker-compose -f docker-compose.staging.yml logs --tail=100 backend

# Últimas 1 hora
docker-compose -f docker-compose.staging.yml logs --since=1h backend

# Seguir logs en tiempo real
docker-compose -f docker-compose.staging.yml logs -f backend
```

### Backup base de datos:

```bash
# Crear backup
docker exec postgres-staging pg_dump -U colombian colombian_staging > backup-$(date +%Y%m%d-%H%M%S).sql

# Restaurar backup
cat backup-20250129-120000.sql | docker exec -i postgres-staging psql -U colombian -d colombian_staging
```

### Limpiar recursos:

```bash
# Eliminar contenedores stopped
docker container prune -f

# Eliminar imágenes sin usar
docker image prune -a -f

# Limpiar todo
docker system prune -a --volumes -f
```

## 🆘 Troubleshooting

### Contenedor no inicia:

```bash
docker-compose -f docker-compose.staging.yml logs backend
docker inspect colombian-backend-staging
```

### SSL no funciona:

```bash
cd ~/apps/traefik
docker-compose logs traefik | grep -i error
cat acme.json
```

### No puedo conectar a la base de datos:

```bash
# Verificar que postgres está corriendo
docker ps | grep postgres

# Entrar al contenedor
docker exec -it postgres-staging psql -U colombian -d colombian_staging

# Ver conexiones
\conninfo
\l
\dt
```

### GitHub Actions falla:

```bash
# Verificar SSH desde local
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS "docker ps"

# Verificar secrets en GitHub
# Settings → Secrets → Actions

# Ver logs del workflow en GitHub Actions tab
```

## 🎉 ¡Listo!

Ahora tienes:

- ✅ VPS configurado con Docker
- ✅ Traefik con SSL automático
- ✅ Backend staging: https://api-stg.colombiansupply.com
- ✅ Frontend staging: https://stg.colombiansupply.com
- ✅ CI/CD automático con GitHub Actions
- ✅ Monitoreo y logs

## 📚 Próximos Pasos

1. Deploy a producción (repetir pasos con archivos .production)
2. Configurar backups automáticos
3. Setup monitoring (Prometheus + Grafana)
4. Configurar alertas
5. Implementar CDN

Ver guías completas:
- `VPS_SSH_SETUP.md` - Setup detallado de SSH
- `DEPLOYMENT_GUIDE.md` - Guía completa de deployment
- `MONITORING_SETUP.md` - Configuración de monitoreo

