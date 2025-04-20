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
