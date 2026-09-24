from app.lambda_handler import handler


def _function_url_event(path: str) -> dict:
    """The payload a Lambda function URL sends (format 2.0), trimmed to what Mangum reads."""
    host = "abc.lambda-url.us-east-1.on.aws"
    return {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": path,
        "rawQueryString": "",
        "headers": {"host": host},
        "requestContext": {
            "http": {"method": "GET", "path": path, "protocol": "HTTP/1.1", "sourceIp": "1.2.3.4"},
            "domainName": host,
            "stage": "$default",
            "requestId": "test",
        },
        "isBase64Encoded": False,
    }


def test_function_url_request_reaches_the_app() -> None:
    response = handler(_function_url_event("/health"), None)
    assert response["statusCode"] == 200
    assert response["body"] == '{"status":"ok"}'


def test_handler_survives_repeated_calls() -> None:
    for _ in range(2):
        assert handler(_function_url_event("/health"), None)["statusCode"] == 200
