# Configuración SSH del VPS para CI/CD

Guía completa para configurar el acceso SSH del VPS y prepararlo para deployments automáticos desde GitHub Actions.

## 🔑 Paso 1: Generar SSH Keys para CI/CD

### En tu máquina local:

```bash
# Generar par de keys específico para CI/CD
ssh-keygen -t ed25519 -C "github-actions@colombiansupply.com" -f ~/.ssh/colombian_vps_deploy

# Esto genera dos archivos:
# - ~/.ssh/colombian_vps_deploy (private key) - NUNCA compartir
# - ~/.ssh/colombian_vps_deploy.pub (public key) - se instala en el VPS
```

### Ver las keys generadas:

```bash
# Public key (la que va al VPS)
cat ~/.ssh/colombian_vps_deploy.pub

# Private key (la que va a GitHub Secrets)
cat ~/.ssh/colombian_vps_deploy
```

## 🖥️ Paso 2: Configurar el VPS

### Conectarse al VPS inicialmente:

```bash
# Con tu método actual (password o key personal)
ssh root@TU_IP_VPS

# O si ya tienes key configurada:
ssh -i ~/.ssh/id_rsa root@TU_IP_VPS
```

### Crear usuario para deployments:

```bash
# En el VPS, como root:

# 1. Crear usuario deploy
adduser deploy
# Ingresar password temporal (lo cambiaremos después)

# 2. Agregar a grupo sudo (si necesita permisos elevados)
usermod -aG sudo deploy

# 3. Agregar a grupo docker (para deployments con Docker)
usermod -aG docker deploy

# 4. Verificar grupos
groups deploy
# Debe mostrar: deploy sudo docker
```

### Configurar SSH para el usuario deploy:

```bash
# Aún como root:

# 1. Crear directorio .ssh para el usuario deploy
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# 2. Crear archivo authorized_keys
touch /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# 3. Cambiar ownership
chown -R deploy:deploy /home/deploy/.ssh
```

### Agregar la public key al VPS:

```bash
# Método 1: Copiar desde tu máquina local
# En tu máquina local:
cat ~/.ssh/colombian_vps_deploy.pub | ssh root@TU_IP_VPS "cat >> /home/deploy/.ssh/authorized_keys"

# Método 2: Manualmente en el VPS
# En el VPS como root:
nano /home/deploy/.ssh/authorized_keys
# Pegar el contenido de ~/.ssh/colombian_vps_deploy.pub
# Guardar: Ctrl+O, Enter, Ctrl+X
```

### Verificar acceso SSH:

```bash
# Desde tu máquina local:
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS

# Si funciona, deberías entrar sin password
# Salir: exit
```

## 🔒 Paso 3: Securizar SSH (Recomendado)

### En el VPS como root:

```bash
# Editar configuración SSH
nano /etc/ssh/sshd_config

# Cambiar/agregar estas líneas:
PermitRootLogin no                    # Deshabilitar login root
PasswordAuthentication no             # Solo keys, no passwords
PubkeyAuthentication yes              # Habilitar autenticación por key
ChallengeResponseAuthentication no    # Deshabilitar challenge-response

# Guardar y reiniciar SSH
systemctl restart sshd

# ⚠️ IMPORTANTE: Antes de cerrar la sesión actual, 
# verifica en otra terminal que puedes conectarte con el usuario deploy
```

## 🐳 Paso 4: Preparar el VPS para Deployments

### Instalar Docker (si no está instalado):

```bash
# Como usuario deploy (o root)
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS

# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Verificar
docker --version
docker ps
```

### Instalar Docker Compose:

```bash
# Instalar Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verificar
docker-compose --version
```

### Crear estructura de directorios:

```bash
# Como usuario deploy
cd /home/deploy

# Crear directorios para las aplicaciones
mkdir -p apps/frontend
mkdir -p apps/backend
mkdir -p apps/nginx
mkdir -p apps/postgres

# Permisos
chmod -R 755 apps
```

### Configurar firewall (UFW):

```bash
# Como root o con sudo
sudo ufw status

# Si no está activo, configurar:
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 6443/tcp    # Kubernetes API (si usas k3s)

# Habilitar
sudo ufw --force enable

# Verificar
sudo ufw status
```

## 🔐 Paso 5: Configurar GitHub Secrets

### Ir a tu repositorio en GitHub:

1. **Frontend**: https://github.com/Colombian-Suppliers/full-colombiano-frontend
   - Settings → Secrets and variables → Actions → New repository secret

2. **Backend**: https://github.com/Colombian-Suppliers/full-colombiano-backend
   - Settings → Secrets and variables → Actions → New repository secret

### Secrets a crear (en AMBOS repositorios):

#### `VPS_HOST`
```
Valor: TU_IP_VPS (ejemplo: 203.0.113.10)
```

#### `VPS_USER`
```
Valor: deploy
```

#### `VPS_SSH_KEY`
```
Valor: Contenido completo de ~/.ssh/colombian_vps_deploy
```

Para obtener el contenido:
```bash
cat ~/.ssh/colombian_vps_deploy
# Copiar TODO el output (incluyendo BEGIN y END)
```

#### `VPS_PORT` (opcional)
```
Valor: 22
(Solo si SSH está en puerto diferente)
```

### Secrets adicionales por aplicación:

#### Backend:
```
DATABASE_URL=postgresql://user:password@localhost:5432/colombian_db
SECRET_KEY=tu-secret-key-super-seguro-aqui
ENVIRONMENT=production
```

#### Frontend:
```
NEXT_PUBLIC_API_URL=https://api.colombiansupply.com
NEXT_PUBLIC_ENVIRONMENT=production
```

## 🧪 Paso 6: Probar Conexión SSH desde GitHub Actions

### Crear workflow de prueba:

En cualquiera de los repos, crear `.github/workflows/test-ssh.yml`:

```yaml
name: Test SSH Connection

on:
  workflow_dispatch:  # Manual trigger

jobs:
  test-connection:
    runs-on: ubuntu-latest
    steps:
      - name: Test SSH Connection
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          port: 22
          script: |
            echo "✅ SSH connection successful!"
            whoami
            pwd
            docker --version
            docker-compose --version
```

### Ejecutar test:

1. Ir a Actions en GitHub
2. Seleccionar "Test SSH Connection"
3. Click en "Run workflow"
4. Verificar que se ejecuta sin errores

## 📋 Checklist de Configuración

### En tu máquina local:
- [ ] Generar SSH keys (`ssh-keygen`)
- [ ] Guardar private key en lugar seguro
- [ ] Copiar public key

### En el VPS:
- [ ] Crear usuario `deploy`
- [ ] Agregar a grupos `sudo` y `docker`
- [ ] Configurar `.ssh/authorized_keys`
- [ ] Instalar Docker y Docker Compose
- [ ] Crear estructura de directorios
- [ ] Configurar firewall (UFW)
- [ ] (Opcional) Securizar SSH

### En GitHub:
- [ ] Agregar secret `VPS_HOST`
- [ ] Agregar secret `VPS_USER`
- [ ] Agregar secret `VPS_SSH_KEY`
- [ ] Agregar secrets de aplicación
- [ ] Probar conexión con workflow de test

## 🔧 Troubleshooting

### "Permission denied (publickey)"

```bash
# Verificar permisos en el VPS
ls -la /home/deploy/.ssh/
# Debe ser:
# drwx------ (700) para .ssh/
# -rw------- (600) para authorized_keys

# Corregir si es necesario:
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
```

### "Host key verification failed"

```bash
# En GitHub Actions, agregar:
script: |
  ssh-keyscan -H ${{ secrets.VPS_HOST }} >> ~/.ssh/known_hosts
```

O usar `StrictHostKeyChecking=no` (menos seguro):
```yaml
with:
  script: |
    ssh -o StrictHostKeyChecking=no deploy@${{ secrets.VPS_HOST }} 'comando'
```

### Usuario deploy no puede ejecutar docker

```bash
# En el VPS:
sudo usermod -aG docker deploy

# Logout y login de nuevo
exit
ssh -i ~/.ssh/colombian_vps_deploy deploy@TU_IP_VPS

# Verificar
docker ps
```

### Firewall bloqueando conexión

```bash
# Verificar reglas
sudo ufw status verbose

# Asegurar que puerto 22 está abierto
sudo ufw allow 22/tcp
```

## 📚 Siguientes Pasos

Una vez configurado el SSH:

1. ✅ Configurar CI/CD workflows (ver archivos `.github/workflows/`)
2. ✅ Configurar Docker Compose en el VPS
3. ✅ Configurar nginx como reverse proxy
4. ✅ Configurar SSL con Let's Encrypt
5. ✅ Primer deployment

Ver guías:
- `BACKEND_DEPLOYMENT.md` - Deploy del backend
- `FRONTEND_DEPLOYMENT.md` - Deploy del frontend
- `NGINX_SETUP.md` - Configuración de nginx

## 🔐 Seguridad Adicional

### Fail2Ban (Protección contra brute force):

```bash
sudo apt install fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Cambiar puerto SSH (opcional):

```bash
# Editar /etc/ssh/sshd_config
sudo nano /etc/ssh/sshd_config

# Cambiar:
Port 2222  # O cualquier puerto > 1024

# Actualizar firewall
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp

# Reiniciar SSH
sudo systemctl restart sshd

# Actualizar GitHub Secret VPS_PORT = 2222
```

### Configurar SSH timeout:

```bash
# En /etc/ssh/sshd_config
ClientAliveInterval 300
ClientAliveCountMax 2
```

---

**¡Configuración SSH completa!** Ahora puedes proceder con los workflows de CI/CD.

