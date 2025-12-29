# Contributing to Colombian Supply Infrastructure

Gracias por tu interés en contribuir! Este documento describe el proceso y estándares para contribuir a este repositorio.

## Código de Conducta

- Sé respetuoso y profesional
- Acepta crítica constructiva
- Enfócate en lo mejor para el proyecto
- Colabora de buena fe

## Cómo Contribuir

### Reportar Bugs

Crea un issue con:
- **Título claro**: "VPS k3s: Firewall no se configura en Ubuntu 24.04"
- **Pasos para reproducir**
- **Comportamiento esperado vs actual**
- **Versiones**: Terraform, kubectl, provider
- **Logs relevantes**

### Proponer Features

Crea un issue con:
- **Problema que resuelve**
- **Solución propuesta**
- **Alternativas consideradas**
- **Impacto en usuarios existentes**

### Contribuir Código

#### 1. Fork y Branch

```bash
# Fork en GitHub UI

# Clone tu fork
git clone https://github.com/TU_USUARIO/full-colombiano-infra.git
cd full-colombiano-infra

# Agregar upstream
git remote add upstream https://github.com/ORG/full-colombiano-infra.git

# Crear branch
git checkout -b feature/add-azure-aks-support
```

#### 2. Hacer Cambios

Seguir estándares:

**Terraform**:
- Usar `terraform fmt` antes de commit
- Variables con descripciones
- Outputs documentados
- README generado con `terraform-docs`

**Commits**:
- Seguir [Conventional Commits](https://www.conventionalcommits.org/)
- Ejemplos:
  - `feat(gke): add support for autopilot clusters`
  - `fix(vps): correct firewall rule for k3s api`
  - `docs(runbook): add section for certificate rotation`
  - `refactor(aws): simplify IRSA module`

#### 3. Testing

```bash
# Formatear código
terraform fmt -recursive .

# Validar
cd environments/dev
terraform init -backend=false
terraform validate

# Linting
tflint --recursive

# Security scan
tfsec .

# Generar docs
terraform-docs markdown table --output-file README.md \
  --output-mode inject modules/tu-modulo/
```

#### 4. Pre-commit

```bash
# Instalar pre-commit
pip install pre-commit

# Instalar hooks
pre-commit install

# Correr en todos los archivos
pre-commit run --all-files
```

#### 5. Crear Pull Request

```bash
git push origin feature/add-azure-aks-support
```

En GitHub:
- Crear PR desde tu branch a `main` (o `develop`)
- **Título**: Resumen claro (< 72 caracteres)
- **Descripción**:
  - Qué cambia
  - Por qué
  - Cómo testeaste
  - Screenshots si aplica
- **Checklist**:
  - [ ] Tests pasan
  - [ ] Documentación actualizada
  - [ ] Changelog actualizado (si aplica)
  - [ ] Breaking changes documentados

#### 6. Code Review

- Responde a comentarios constructivamente
- Haz cambios solicitados
- Push adicional al mismo branch actualiza PR
- Una vez aprobado, será merged

## Estándares de Código

### Estructura de Módulos

```
modules/infra_PROVIDER_TYPE/
├── main.tf           # Recursos principales
├── variables.tf      # Inputs con descriptions
├── outputs.tf        # Outputs con descriptions
├── versions.tf       # Provider versions (opcional)
├── README.md         # Generado con terraform-docs
└── templates/        # Templates si aplica
    └── script.sh
```

### Variables

```hcl
# ✅ BIEN
variable "cluster_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
  
  validation {
    condition     = can(regex("^1\\.(2[89]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.28 or higher."
  }
}

# ❌ MAL
variable "cv" {  # Nombre poco claro
  type = string
}
```

### Outputs

```hcl
# ✅ BIEN
output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

# ❌ MAL
output "endpoint" {  # Sin descripción
  value = module.eks.cluster_endpoint
}
```

### Resources

```hcl
# ✅ BIEN
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version
  
  vpc_config {
    subnet_ids = module.vpc.private_subnets
  }
  
  tags = local.common_tags
}

# ❌ MAL
resource "aws_eks_cluster" "cluster" {  # Nombre genérico
  name = "my-cluster"  # Hardcoded
  # Sin tags
}
```

### Locals

Usar locals para:
- Cálculos complejos
- Valores reutilizados
- Transformaciones de datos

```hcl
locals {
  cluster_name = "${var.environment}-${var.cluster_base_name}"
  
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}
```

### Comentarios

```hcl
# ✅ Explicar "por qué", no "qué"
# Disable Traefik to use nginx-ingress for consistency across providers
"--disable traefik"

# ❌ Obvio
# Set version to 1.28
version = "1.28"
```

## Documentación

### README de Módulos

Usar `terraform-docs`:

```bash
terraform-docs markdown table --output-file README.md \
  --output-mode inject modules/infra_aws_eks/
```

Incluir:
- Qué hace el módulo
- Cuándo usarlo
- Ejemplo de uso
- Decisiones de diseño importantes
- Troubleshooting común

### Docs Principales

- `ARCHITECTURE.md`: Decisiones arquitectónicas de alto nivel
- `RUNBOOK.md`: Procedimientos operacionales
- `MIGRATION_GUIDE.md`: Guías de migración

Actualizar cuando:
- Agregas nuevo provider
- Cambias flujo operacional
- Añades nueva funcionalidad mayor

## Testing

### Tests Manuales

Mínimo para cada PR:

```bash
# 1. Init
cd environments/dev
terraform init -backend=false

# 2. Validate
terraform validate

# 3. Plan (no ejecutar apply en PR)
terraform plan

# 4. Si es posible, apply en entorno de prueba
# Solo si tienes acceso a VPS/AWS/GCP de testing
```

### Tests Automatizados (CI)

GitHub Actions ejecuta automáticamente:
- `terraform fmt -check`
- `terraform validate`
- `tflint`
- `tfsec`
- `checkov`

Deben pasar todos antes de merge.

## Releases

Seguimos [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes (ej: cambiar interfaz de módulo)
- **MINOR**: Nuevos features (ej: agregar soporte GKE)
- **PATCH**: Bug fixes (ej: corregir firewall rule)

Ejemplos:
- `v1.0.0` → Primera release estable
- `v1.1.0` → Agregar soporte external-dns
- `v1.1.1` → Fix certificado no se emite
- `v2.0.0` → Cambiar variable `target_provider` a `infrastructure_provider`

## Breaking Changes

Si tu cambio rompe compatibilidad:

1. **Documentar en PR**:
   ```markdown
   ## Breaking Changes
   
   - Variable `eks_node_type` renombrada a `eks_instance_types` (ahora acepta lista)
   - Output `kubeconfig` eliminado; usar `kubeconfig_path` en su lugar
   
   ## Migration Guide
   
   ```hcl
   # Antes
   eks_node_type = "t3.medium"
   
   # Después
   eks_instance_types = ["t3.medium"]
   ```
   ```

2. **Agregar a CHANGELOG.md**

3. **Bumpar versión MAJOR**

## Checklist del Contributor

Antes de crear PR:

- [ ] Código formateado (`terraform fmt -recursive`)
- [ ] Sin errores de validación (`terraform validate`)
- [ ] Sin warnings de linting (`tflint`)
- [ ] Sin issues de seguridad críticos (`tfsec`)
- [ ] Documentación actualizada (README, docs/)
- [ ] CHANGELOG.md actualizado (si aplica)
- [ ] Commits siguen Conventional Commits
- [ ] Tests manuales ejecutados
- [ ] Pre-commit hooks pasan

## Checklist del Reviewer

Al revisar PR:

- [ ] Cambios tienen sentido arquitectónicamente
- [ ] Código sigue estándares del repo
- [ ] Documentación suficiente
- [ ] Sin hardcoded secrets/IPs
- [ ] Breaking changes claramente documentados
- [ ] CI/CD pasa
- [ ] Testeado manualmente (si es posible)

## Preguntas Frecuentes

**P: ¿Puedo contribuir sin acceso a AWS/GCP?**
R: Sí. Enfócate en código, docs, o testing en VPS (más barato).

**P: ¿Cuánto tarda en revisarse un PR?**
R: Objetivo: 48 horas para primera revisión. PRs complejos pueden tomar más.

**P: ¿Qué pasa si mi PR no se acepta?**
R: No te desanimes. Pedimos cambios para mantener calidad. Itera y mejora.

**P: ¿Puedo agregar soporte para Azure/DigitalOcean?**
R: ¡Absolutamente! Sigue la estructura de módulos existentes (vps/aws/gcp).

**P: ¿Debo abrir issue antes de PR?**
R: Para cambios grandes (nuevo provider, refactor mayor), sí. Para fixes pequeños, PR directo está bien.

## Contacto

- **Issues**: https://github.com/ORG/full-colombiano-infra/issues
- **Slack**: #platform-engineering (para empleados)
- **Email**: devops@colombiansupply.com

## Licencia

Al contribuir, aceptas que tu código se licencie bajo la misma licencia del proyecto (MIT).

---

**¡Gracias por contribuir!** 🎉

