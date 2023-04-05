terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.61"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }

  required_version = ">= 1.4.0"
}

resource "terraform_data" "lambda_build" {
  triggers_replace = [
    filemd5("./product/main.go")
  ]

  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 go build -o ./bin/aws-lambda-go -C ./product"
    working_dir = path.module
  }
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_lambda_function" "product" {
  function_name    = "product"
  filename         = "aws-lambda-go.zip"
  handler          = "aws-lambda-go"
  source_code_hash = data.archive_file.zip.output_base64sha256
  role             = aws_iam_role.role_lambda.arn
  runtime          = "go1.x"
  memory_size      = 128
  timeout          = 10

  environment {
    variables = {
      PRODUCT_TABLE = aws_dynamodb_table.product.name
    }
  }
}

data "archive_file" "zip" {
  type        = "zip"
  source_file = "bin/aws-lambda-go"
  output_path = "aws-lambda-go.zip"
  depends_on  = [terraform_data.lambda_build]
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
      aws_dynamodb_table.product.arn
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
   role = aws_iam_role.role_lambda.name
   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# resource "aws_api_gateway_rest_api" "api" {
#   name = "time_api"
# }

# resource "aws_api_gateway_resource" "resource" {
#   path_part   = "time"
#   parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
#   rest_api_id = "${aws_api_gateway_rest_api.api.id}"
# }

# resource "aws_api_gateway_method" "method" {
#   rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
#   resource_id   = "${aws_api_gateway_resource.resource.id}"
#   http_method   = "GET"
#   authorization = "NONE"
# }

resource "aws_dynamodb_table" "product" {
  name             = "product"
  hash_key         = "product_id"
  billing_mode     = "PAY_PER_REQUEST"

  attribute {
    name = "product_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}
