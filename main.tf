terraform {
  /*
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
  }
  */

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

variable "app_prefix" {
  default = "ev-charging"
}

provider "aws" {
  region = "eu-west-1"
}

resource "aws_kinesis_stream" "outlet-events-kinesis-stream" {
  name        = "${var.app_prefix}_charging-events_stream"
  shard_count = 4
}

resource "aws_kinesis_stream" "dead-letters-kinesis-stream" {
  name        = "${var.app_prefix}_charging-events-dead-letters_stream"
  shard_count = 1
}


resource "aws_dynamodb_table" "app-backend-checkpoints-dynamodb-table" {
  name           = "${var.app_prefix}_charging-event-checkpoints-app-backend_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 4
  write_capacity = 4
  hash_key       = "leaseKey"

  attribute {
    name = "leaseKey"
    type = "S"
  }
}

resource "aws_dynamodb_table" "outlet-backend-checkpoints-dynamodb-table" {
  name           = "${var.app_prefix}_charging-event-checkpoints-outlet-backend_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 4
  write_capacity = 4
  hash_key       = "leaseKey"

  attribute {
    name = "leaseKey"
    type = "S"
  }
}

resource "aws_dynamodb_table" "customer-dynamodb-table" {
  name           = "${var.app_prefix}_customer_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 100
  write_capacity = 100
  hash_key       = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  attribute {
    name = "rfidTag"
    type = "S"
  }

  global_secondary_index {
    name               = "${var.app_prefix}_customer-rfidTag_index"
    hash_key           = "rfidTag"
    write_capacity     = 100
    read_capacity      = 100
    projection_type    = "INCLUDE"
    non_key_attributes = ["customerId"]
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }
}

resource "aws_dynamodb_table" "charger-outlet-dynamodb-table" {
  name           = "${var.app_prefix}_charger-outlet_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 100
  write_capacity = 100
  hash_key       = "outletId"

  attribute {
    name = "outletId"
    type = "S"
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }
}

resource "aws_dynamodb_table" "charging-session-dynamodb-table" {
  name           = "${var.app_prefix}_charging-session_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 100
  write_capacity = 100
  hash_key       = "sessionId"

  attribute {
    name = "sessionId"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  global_secondary_index {
    name               = "${var.app_prefix}_active-charging-sessions_index"
    hash_key           = "customerId"
    write_capacity     = 100
    read_capacity      = 100
    projection_type    = "INCLUDE"
    non_key_attributes = ["outletId", "outletState", "startTime", "sessionId"]
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }
}

resource "aws_sqs_queue" "device_to_backend_queue" {
  name                       = "ev-charging_device-to-outlet-backend_queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 60 * 60 * 24
  receive_wait_time_seconds  = 10
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.device_to_backend_deadletter.arn
    maxReceiveCount     = 1000
  })
}

resource "aws_sqs_queue" "device_to_backend_deadletter" {
  name = "ev-charging_device-to-outlet-backend_dead-letters_queue"
}

resource "aws_sqs_queue" "backend_to_device_queue" {
  name                       = "ev-charging_outlet-backend-to-device_queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 60 * 60 * 24
  receive_wait_time_seconds  = 10
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.backend_to_device_deadletter.arn
    maxReceiveCount     = 1000
  })
}

resource "aws_sqs_queue" "backend_to_device_deadletter" {
  name = "ev-charging_outlet-backend-to-device_dead-letters_queue"
}
