variable "aws_region" {
  description = "AWS region for all resources"

  type    = string
  default = "us-west-2"
}

variable "lambda_function_name" {
  default = "translate"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.61"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.3"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }

  required_version = "1.4.4"
}

resource "null_resource" "lambda_build" {
  triggers = {
    source_code_md5 = filemd5("./translate/main.go")
  }

  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o ./bin/lambda-translate -C ./translate"
    working_dir = path.module
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "lambda-as-microservice"
  length = 2
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id

  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.ownership]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

resource "aws_lambda_function" "translate" {
  function_name    = var.lambda_function_name
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.file_upload.key
  handler          = "lambda-translate"
  source_code_hash = data.archive_file.zip.output_base64sha256
  role             = aws_iam_role.role_lambda.arn
  runtime          = "go1.x"
  memory_size      = 128
  timeout          = 10

  environment {
    variables = {
      TRANSLATE_TABLE    = aws_dynamodb_table.translate.name
      SENTENCE_QUEUE_URL = aws_sqs_queue.write_queue.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.log_group,
  ]
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.role_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_s3_object" "file_upload" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "lambda-translate.zip"
  source = data.archive_file.zip.output_path

  etag                   = data.archive_file.zip.output_md5
  server_side_encryption = "AES256"
}

data "archive_file" "zip" {
  type        = "zip"
  source_file = "./translate/bin/lambda-translate"
  output_path = "./lambda-translate.zip"
  depends_on  = [null_resource.lambda_build]
}

resource "aws_iam_role" "role_lambda" {
  name = "role_lambda"

  assume_role_policy = data.aws_iam_policy_document.allow_lambda.json
}

data "aws_iam_policy_document" "allow_lambda" {
  version = "2012-10-17"

  statement {
    sid = ""

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "policy_dynamodb_lambda" {
  name = "policy_dynamodb_lambda"
  role = aws_iam_role.role_lambda.id

  policy = data.aws_iam_policy_document.allow_dynamodb_lambda.json
}

data "aws_iam_policy_document" "allow_dynamodb_lambda" {
  version = "2012-10-17"

  statement {
    sid = ""

    actions = ["dynamodb:*"]

    resources = [
      aws_dynamodb_table.translate.arn
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.role_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_api_gateway_rest_api" "gateway_api" {
  name = "gateway_api"
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "{proxy+}"
  parent_id   = aws_api_gateway_rest_api.gateway_api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.gateway_api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.gateway_api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_lambda_permission" "allow_api" {
  statement_id  = "permitLambdaInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translate.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.gateway_api.execution_arn}/*/*/*"
}

resource "aws_sqs_queue" "write_queue" {
  name                    = "sentence"
  sqs_managed_sse_enabled = true
}

resource "aws_dynamodb_table" "translate" {
  name         = "translate"
  hash_key     = "translate_id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "translate_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}

output "base_url" {
  description = "Base URL for API Gateway"

  value = aws_api_gateway_stage.lambda.invoke_url
}

resource "aws_api_gateway_stage" "lambda" {
  deployment_id = aws_api_gateway_deployment.lambda.id
  rest_api_id   = aws_api_gateway_rest_api.gateway_api.id
  stage_name    = "lambda"
}

resource "aws_api_gateway_deployment" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.gateway_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.gateway_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration
  ]
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.gateway_api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.translate.invoke_arn
}
