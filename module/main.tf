resource "aws_lambda_function" "lambda_function" {
  filename          = "${var.source_file}"
  function_name     = "${var.function_name}"
  role              = "${aws_iam_role.lambda_role.arn}"
  handler           = "${var.handler}"
  runtime           = "${var.runtime}"
  source_code_hash  = "${base64sha256(file("${var.source_file}"))}"
  publish           = true
  timeout           = "${var.function_timeout}"
}

resource "aws_iam_role" "lambda_role" {
  name               = "${coalesce(var.role_name, format("%s-role", var.function_name)) }"
  assume_role_policy = "${var.role_policy}"
}

resource "aws_api_gateway_resource" "api_resource" {
  count       = "${var.use_sub_resource == "true" ? 1 : 0}"
  rest_api_id = "${var.rest_api_id}"
  parent_id   = "${var.parent_id}"
  path_part   = "${var.path_part}"
}

resource "aws_api_gateway_method" "api_method" {
  count         = "${length(var.http_methods)}"
  rest_api_id   = "${var.rest_api_id}"
  resource_id   = "${aws_api_gateway_resource.api_resource.id}"
  http_method   = "${element(var.http_methods, count.index)}"
  authorization = "${var.authorization}"
  authorizer_id = "${var.authorizer_id}"
}

resource "aws_api_gateway_integration" "api_method_integration" {
  count                   = "${length(var.http_methods)}"
  rest_api_id             = "${var.rest_api_id}"
  resource_id             = "${var.use_sub_resource == "true" ? aws_api_gateway_resource.api_resource.id : var.parent_id}"
  http_method             = "${element(aws_api_gateway_method.api_method.*.http_method, count.index)}"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda_function.invoke_arn}"
  integration_http_method = "POST"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    "aws_api_gateway_method.api_method",
    "aws_api_gateway_integration.api_method_integration",
  ]

  rest_api_id = "${var.rest_api_id}"
  stage_name  = "${var.stage_name}"
}

resource "aws_lambda_permission" "apigw_lambda" {

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda_function.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.rest_api_id}/${aws_api_gateway_deployment.deployment.stage_name}/*"
}
