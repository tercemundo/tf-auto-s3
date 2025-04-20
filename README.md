# Usuario IAM AWS con Terraform y Backend Remoto

Este proyecto configura un usuario IAM en AWS llamado "juan" usando Terraform, con un backend remoto para almacenar el estado en S3 y utilizando DynamoDB para gestionar los bloqueos de estado.

## Arquitectura

La solución implementa:

1. **Tabla DynamoDB** para bloqueos de estado de Terraform
2. **Bucket S3** para almacenar el archivo de estado de Terraform (tfstate)
3. **Usuario IAM** llamado "juan" sin contraseña
4. **Configuración de backend remoto** que usa el bucket S3 y la tabla DynamoDB

## Requisitos previos

- AWS CLI instalado y configurado
- Terraform instalado (versión recomendada: 1.0+)
- Credenciales AWS con permisos para crear recursos IAM, DynamoDB y S3

## Estructura del proyecto

```
├── main.tf           # Definición principal de recursos
├── backend.tf        # Configuración del backend remoto
└── setup.sh          # Script para configuración automática
```

## Detalles de implementación

### Recursos creados

**Tabla DynamoDB (terraform-state-locks)**
- Clave hash: LockID
- Capacidad de lectura: 1
- Capacidad de escritura: 1

**Bucket S3 (terraform-state-juan-storage)**
- Configurado con protecciones de acceso público
- Sin encriptación
- Sin versionado
- Sin políticas adicionales

**Usuario IAM (juan)**
- Sin contraseña configurada
- Ruta por defecto "/"

### Configuración del backend

El backend remoto se configura para usar:
- El bucket S3 `terraform-state-juan-storage`
- La clave `terraform.tfstate`
- La región `us-east-1`
- Bloqueo de estado mediante `use_lockfile = true`

## Ficheros principales

### main.tf

```hcl
# Configuración del proveedor AWS
provider "aws" {
  region = "us-east-1"
}

# Creación de la tabla DynamoDB para el bloqueo de estado
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  hash_key     = "LockID"
  read_capacity  = 1
  write_capacity = 1

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Creación del bucket S3 para el estado remoto (depende de DynamoDB)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-juan-storage"
  depends_on = [aws_dynamodb_table.terraform_locks]
}

# Configuración del control de acceso público para el bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Creación del usuario IAM sin contraseña
resource "aws_iam_user" "juan" {
  name = "juan"
}
```

### backend.tf

```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-juan-storage"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
```

### setup.sh

```bash
#!/bin/bash

# 1. Eliminar cualquier archivo de backend existente y estado local
echo "Limpiando configuración existente..."
rm -f backend.tf
rm -f terraform.tfstate*
rm -rf .terraform

# 2. Crear el archivo principal sin backend
cat > main.tf << EOF
# Configuración del proveedor AWS
provider "aws" {
  region = "us-east-1"
}

# Creación de la tabla DynamoDB para el bloqueo de estado
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  hash_key     = "LockID"
  read_capacity  = 1
  write_capacity = 1

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Creación del bucket S3 para el estado remoto (depende de DynamoDB)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-juan-storage"
  depends_on = [aws_dynamodb_table.terraform_locks]
}

# Configuración del control de acceso público para el bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Creación del usuario IAM sin contraseña
resource "aws_iam_user" "juan" {
  name = "juan"
}
EOF

# 3. Inicializar terraform con backend local
echo "Inicializando Terraform con backend local..."
terraform init

# 4. Aplicar la configuración para crear los recursos
echo "Creando recursos..."
terraform apply -auto-approve

# 5. Esperar unos segundos para asegurarse de que el bucket está disponible
echo "Esperando a que los recursos estén completamente disponibles..."
sleep 10

# 6. Crear un archivo backend.tf después de que los recursos existan
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket       = "terraform-state-juan-storage"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
EOF

# 7. Reinicializar terraform con backend remoto
echo "Migrando a backend remoto..."
terraform init -migrate-state -force-copy
```

## Instrucciones de uso

### Configuración automática

1. **Preparar el entorno**:
   ```bash
   chmod +x setup.sh
   ```

2. **Ejecutar el script de configuración**:
   ```bash
   ./setup.sh
   ```
   
   Este script:
   - Limpia cualquier configuración existente
   - Crea los archivos de configuración necesarios
   - Inicializa Terraform con un backend local
   - Crea los recursos en AWS
   - Configura el backend remoto
   - Migra el estado al backend remoto

### Configuración manual

Si prefieres realizar la configuración paso a paso:

1. **Crear los archivos de configuración**:
   - Crea `main.tf` con la definición de recursos
   - No incluyas inicialmente la configuración del backend

2. **Inicializar y crear recursos**:
   ```bash
   terraform init
   terraform apply
   ```

3. **Configurar el backend remoto**:
   - Crea `backend.tf` con la configuración del backend S3
   - Migra el estado al backend remoto:
   ```bash
   terraform init -migrate-state
   ```

## Verificación del backend remoto

Para verificar que el backend está configurado correctamente como remoto:

1. **Comprobar el estado actual**:
   ```bash
   terraform state pull
   ```

2. **Verificar en AWS**:
   ```bash
   aws s3 ls s3://terraform-state-juan-storage/
   ```
   Deberías ver el archivo terraform.tfstate en el bucket.

3. **Revisar configuración local**:
   - No debería existir archivo `terraform.tfstate` en tu directorio local
   - El directorio `.terraform` contendrá solo información sobre la configuración del backend

## Solución de problemas

### Error "Bucket no existe"

Si recibes un error indicando que el bucket S3 no existe durante la migración del estado:
- Asegúrate de que el bucket se ha creado correctamente
- Espera unos minutos después de la creación del bucket antes de intentar migrar el estado
- Verifica que tienes permisos suficientes para acceder al bucket

### Error de capacidad en DynamoDB

Si recibes errores relacionados con la capacidad de la tabla DynamoDB:
- Asegúrate de incluir `read_capacity = 1` y `write_capacity = 1` en la configuración de la tabla

### Conflictos con backend existente

Si enfrentas errores relacionados con la inicialización del backend:
- Limpia la configuración existente (`rm -rf .terraform`)
- Asegúrate de que no existe un archivo `backend.tf` durante la creación inicial de recursos

## Consideraciones de seguridad

- El bucket S3 tiene configuradas protecciones de acceso público
- El usuario IAM "juan" se crea sin contraseña, requiriendo configuración adicional para acceso
- Considera añadir políticas IAM específicas según las necesidades

## Mantenimiento

Para futuras modificaciones de la infraestructura:
1. Modifica los archivos Terraform según sea necesario
2. Ejecuta `terraform plan` para revisar los cambios propuestos
3. Ejecuta `terraform apply` para aplicar los cambios

El estado se mantendrá automáticamente en el backend remoto, permitiendo colaboración entre equipos y mayor seguridad.
