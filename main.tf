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
