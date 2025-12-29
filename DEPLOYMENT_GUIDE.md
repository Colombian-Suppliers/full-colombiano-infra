# Guía Completa de Deployment

Guía paso a paso para desplegar Colombian Supply Backend y Frontend en el VPS.

## 📋 Pre-requisitos Completados

Antes de continuar, asegúrate de haber completado:

- ✅ [VPS_SSH_SETUP.md](VPS_SSH_SETUP.md) - Configuración SSH del VPS
- ✅ GitHub Secrets configurados en ambos repositorios
- ✅ VPS con Docker y Docker Compose instalados
- ✅ Usuario `deploy` creado y configurado

## 🏗️ Arquitectura de Deployment

```
┌─────────────────────────────────────────────────────┐
│  VPS (203.0.113.10)                                 │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  Traefik (Reverse Proxy + SSL)                │ │
│  │  Ports: 80, 443                                │ │
│  └───────┬───────────────────────────────────────┘ │
│          │                                          │
│  ┌───────▼──────────┐  ┌──────────────────────┐   │
│  │  Frontend        │  │  Backend             │   │
│  │  stg: :3001      │  │  stg: :8001          │   │
│  │  prod: :3000     │  │  prod: :8000         │   │
│  └──────────────────┘  └──────┬───────────────┘   │
│                                │                    │
│  ┌─────────────────────────────▼─────────────────┐ │
│  │  PostgreSQL                                    │ │
│  │  stg: :5433    prod: :5432                     │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  ┌────────────────────────────────────────────────┐ │
│  │  Redis                                         │ │
│  │  stg: :6380    prod: :6379                     │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## 🚀 Paso 1: Configurar Traefik (Reverse Proxy)

Traefik maneja:
- Routing por dominio
- SSL automático con Let's Encrypt
- Load balancing

### Crear configuración de Traefik:

```bash
# Conectar al VPS
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS

# Crear directorio
mkdir -p ~/apps/traefik
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
      - ./config:/config:ro
    networks:
      - colombian-staging-network
      - colombian-production-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.colombiansupply.com`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."  # Cambiar

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
  file:
    directory: "/config"
    watch: true

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

## 📦 Paso 2: Primer Deployment Manual (Backend)

### Preparar directorios:

```bash
# En el VPS
cd ~/apps/backend
mkdir -p backups

# Crear .env.staging
cat > .env.staging <<'EOF'
DATABASE_URL=postgresql://colombian:TU_PASSWORD_AQUI@postgres:5432/colombian_staging
POSTGRES_USER=colombian
POSTGRES_PASSWORD=TU_PASSWORD_AQUI
SECRET_KEY=TU_SECRET_KEY_AQUI
ENVIRONMENT=staging
CORS_ORIGINS=https://stg.colombiansupply.com
EOF

# Crear .env.production (similar)
cat > .env.production <<'EOF'
DATABASE_URL=postgresql://colombian:TU_PASSWORD_AQUI@postgres:5432/colombian_production
POSTGRES_USER=colombian
POSTGRES_PASSWORD=TU_PASSWORD_AQUI
SECRET_KEY=TU_SECRET_KEY_DIFERENTE_AQUI
ENVIRONMENT=production
CORS_ORIGINS=https://colombiansupply.com
SENTRY_DSN=TU_SENTRY_DSN
EOF
```

### Build y deploy inicial:

```bash
# Clonar repositorio (primera vez)
git clone https://github.com/Colombian-Suppliers/full-colombiano-backend.git temp-backend
cd temp-backend

# Build imagen
docker build -t colombian-backend:staging .

# Iniciar servicios
docker-compose -f docker-compose.staging.yml up -d

# Ver logs
docker-compose -f docker-compose.staging.yml logs -f

# Verificar salud
curl http://localhost:8001/health
```

## 🎨 Paso 3: Primer Deployment Manual (Frontend)

```bash
# En el VPS
cd ~/apps/frontend

# Crear .env.staging
cat > .env.staging <<'EOF'
NEXT_PUBLIC_API_URL=https://api-stg.colombiansupply.com
NEXT_PUBLIC_ENVIRONMENT=staging
NEXT_PUBLIC_SITE_URL=https://stg.colombiansupply.com
EOF

# Crear .env.production
cat > .env.production <<'EOF'
NEXT_PUBLIC_API_URL=https://api.colombiansupply.com
NEXT_PUBLIC_ENVIRONMENT=production
NEXT_PUBLIC_SITE_URL=https://colombiansupply.com
NEXT_PUBLIC_GA_ID=TU_GA_ID
EOF

# Clonar y build
git clone https://github.com/Colombian-Suppliers/full-colombiano-frontend.git temp-frontend
cd temp-frontend

docker build \
  --build-arg NEXT_PUBLIC_API_URL=https://api-stg.colombiansupply.com \
  --build-arg NEXT_PUBLIC_ENVIRONMENT=staging \
  -t colombian-frontend:staging .

# Iniciar
docker-compose -f docker-compose.staging.yml up -d

# Verificar
curl http://localhost:3001
```

## 🌐 Paso 4: Configurar DNS

En tu proveedor de DNS (Cloudflare, Route53, etc.):

```
# Staging
api-stg.colombiansupply.com  →  A  →  TU_IP_VPS
stg.colombiansupply.com       →  A  →  TU_IP_VPS

# Production
api.colombiansupply.com       →  A  →  TU_IP_VPS
colombiansupply.com           →  A  →  TU_IP_VPS
www.colombiansupply.com       →  A  →  TU_IP_VPS
```

Esperar 2-5 minutos para propagación DNS.

## ✅ Paso 5: Verificar Deployment

### Backend:

```bash
# Health check
curl https://api-stg.colombiansupply.com/health

# API docs
open https://api-stg.colombiansupply.com/docs

# Test endpoint
curl https://api-stg.colombiansupply.com/api/v1/products
```

### Frontend:

```bash
# Homepage
curl https://stg.colombiansupply.com

# Verificar en navegador
open https://stg.colombiansupply.com
```

## 🔄 Paso 6: Configurar CI/CD Automático

### En GitHub (ambos repos):

1. **Ir a Settings → Secrets → Actions**

2. **Agregar secrets** (ver VPS_SSH_SETUP.md):
   - `VPS_HOST`
   - `VPS_USER`
   - `VPS_SSH_KEY`
   - `STAGING_DATABASE_URL`
   - `STAGING_SECRET_KEY`
   - `STAGING_CORS_ORIGINS`
   - `PROD_DATABASE_URL`
   - `PROD_SECRET_KEY`
   - `PROD_CORS_ORIGINS`

3. **Hacer push a `develop`**:

```bash
# En tu máquina local
cd full-colombiano-backend
git checkout develop
git push origin develop

# Esto triggerea el workflow de staging automáticamente
```

4. **Ver el deployment en Actions**:
   - Ir a Actions tab en GitHub
   - Ver el workflow "Deploy to Staging" ejecutándose

## 🏷️ Paso 7: Deploy a Producción

### Crear tag de release:

```bash
# Backend
cd full-colombiano-backend
git checkout main
git tag -a v1.0.0 -m "First production release"
git push origin v1.0.0

# Esto triggerea el workflow de producción
```

### O deployment manual:

```bash
# En GitHub Actions
# Ir a "Deploy to Production" workflow
# Click "Run workflow"
# Seleccionar environment: production
# Ingresar version: v1.0.0
# Click "Run workflow"
```

## 📊 Paso 8: Monitoreo Post-Deployment

### Ver logs en tiempo real:

```bash
# Backend staging
ssh deploy@TU_IP_VPS
cd ~/apps/backend
docker-compose -f docker-compose.staging.yml logs -f backend

# Frontend production
cd ~/apps/frontend
docker-compose -f docker-compose.production.yml logs -f frontend
```

### Ver estado de servicios:

```bash
# Todos los contenedores
docker ps

# Uso de recursos
docker stats

# Logs de Traefik
cd ~/apps/traefik
docker-compose logs -f
```

### Health checks:

```bash
# Script de monitoreo
cat > ~/monitor.sh <<'EOF'
#!/bin/bash
echo "=== Health Checks ==="
echo ""
echo "Backend Staging:"
curl -s https://api-stg.colombiansupply.com/health | jq .
echo ""
echo "Backend Production:"
curl -s https://api.colombiansupply.com/health | jq .
echo ""
echo "Frontend Staging:"
curl -s -o /dev/null -w "%{http_code}" https://stg.colombiansupply.com
echo ""
echo "Frontend Production:"
curl -s -o /dev/null -w "%{http_code}" https://colombiansupply.com
echo ""
EOF

chmod +x ~/monitor.sh
./monitor.sh
```

## 🔧 Troubleshooting

### Contenedor no inicia:

```bash
docker-compose -f docker-compose.staging.yml logs backend
docker inspect colombian-backend-staging
```

### SSL no funciona:

```bash
# Ver logs de Traefik
cd ~/apps/traefik
docker-compose logs traefik | grep -i error

# Verificar certificados
docker-compose exec traefik cat /acme.json
```

### Base de datos no conecta:

```bash
# Entrar al contenedor
docker exec -it postgres-staging psql -U colombian -d colombian_staging

# Ver conexiones
\conninfo
\l
```

### Deployment falla en GitHub Actions:

```bash
# Verificar SSH desde Actions
# Ver logs del workflow en GitHub
# Verificar secrets están configurados
# Probar SSH manualmente:
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS "docker ps"
```

## 📝 Comandos Útiles

### Reiniciar servicios:

```bash
# Staging
cd ~/apps/backend
docker-compose -f docker-compose.staging.yml restart backend

# Production
docker-compose -f docker-compose.production.yml restart backend
```

### Ver logs específicos:

```bash
# Últimas 100 líneas
docker-compose logs --tail=100 backend

# Desde hace 1 hora
docker-compose logs --since 1h backend

# Follow logs
docker-compose logs -f backend
```

### Backup base de datos:

```bash
# Manual
docker exec postgres-production pg_dump -U colombian colombian_production > backup-$(date +%Y%m%d).sql

# Restaurar
cat backup-20250101.sql | docker exec -i postgres-production psql -U colombian -d colombian_production
```

### Limpiar recursos:

```bash
# Eliminar contenedores stopped
docker container prune -f

# Eliminar imágenes sin usar
docker image prune -a -f

# Eliminar volúmenes sin usar
docker volume prune -f

# Limpiar todo
docker system prune -a --volumes -f
```

## 🎉 Deployment Completo!

Ahora tienes:

- ✅ Backend staging en `https://api-stg.colombiansupply.com`
- ✅ Frontend staging en `https://stg.colombiansupply.com`
- ✅ Backend production en `https://api.colombiansupply.com`
- ✅ Frontend production en `https://colombiansupply.com`
- ✅ CI/CD automático con GitHub Actions
- ✅ SSL automático con Let's Encrypt
- ✅ Monitoreo y logs centralizados

## 📚 Próximos Pasos

1. Configurar backups automáticos (cron job)
2. Setup monitoring (Prometheus + Grafana)
3. Configurar alertas (email/Slack)
4. Implementar blue/green deployments
5. Setup CDN (Cloudflare)
6. Configurar WAF (Web Application Firewall)

Ver:
- `MONITORING_SETUP.md` - Configuración de monitoreo
- `BACKUP_STRATEGY.md` - Estrategia de backups
- `SCALING_GUIDE.md` - Guía de escalamiento

