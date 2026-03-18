#!/usr/bin/env python3

import argparse
import html
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_DIR = ROOT / "infra" / "terraform"
DEFAULT_DEMO_USERNAME = "demo-user"
DEFAULT_DEMO_PASSWORD = "DemoPassw0rd!"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def parse_args():
    parser = argparse.ArgumentParser(description="Run the live AWS demo flow against the deployed stack.")
    parser.add_argument(
        "--username",
        default=os.environ.get("AWS_DEMO_USERNAME", DEFAULT_DEMO_USERNAME),
        help="Cognito username",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("AWS_DEMO_PASSWORD", DEFAULT_DEMO_PASSWORD),
        help="Cognito password",
    )
    parser.add_argument("--product-number", default="PROD001", help="Product number to query and order")
    parser.add_argument("--quantity", type=int, default=2, help="Order quantity")
    parser.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION", "us-east-2"), help="AWS region for the Cognito hosted UI")
    parser.add_argument("--correlation-id", default=f"aws-demo-{uuid4()}", help="Correlation ID to attach to the demo request")
    parser.add_argument(
        "--skip-product-check",
        action="store_true",
        help="Skip the initial GET /product call and only execute order creation plus order lookup",
    )
    return parser.parse_args()


def terraform_outputs():
    result = subprocess.run(
        ["terraform", f"-chdir={TERRAFORM_DIR}", "output", "-json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    raw_outputs = json.loads(result.stdout)
    return {name: value["value"] for name, value in raw_outputs.items()}


def read(opener, request):
    try:
        with opener.open(request) as response:
            return response.geturl(), response.read().decode(), dict(response.headers), getattr(response, "status", 200)
    except urllib.error.HTTPError as error:
        return error.geturl(), error.read().decode(), dict(error.headers), error.code


def hosted_ui_login(base_url, client_id, redirect_uri, username, password, scopes):
    cookie_jar = CookieJar()
    normal = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
    no_redirect = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar), NoRedirect)

    authorize_query = urllib.parse.urlencode(
        {
            "response_type": "code",
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "scope": " ".join(scopes),
        }
    )
    authorize_request = urllib.request.Request(f"{base_url}/oauth2/authorize?{authorize_query}")
    _, page, _, status = read(normal, authorize_request)
    if status != 200:
        raise RuntimeError(f"Hosted UI authorize page failed with HTTP {status}")

    form_action_match = re.search(r'<form[^>]+action="([^"]+)"', page)
    csrf_match = re.search(r'name="_csrf" value="([^"]+)"', page)
    if not form_action_match or not csrf_match:
        raise RuntimeError("Could not parse Cognito hosted UI login form")

    form_body = urllib.parse.urlencode(
        {
            "_csrf": csrf_match.group(1),
            "username": username,
            "password": password,
            "cognitoAsfData": "",
            "signInSubmitButton": "Sign in",
        }
    ).encode()
    login_request = urllib.request.Request(
        urllib.parse.urljoin(base_url, html.unescape(form_action_match.group(1))),
        data=form_body,
        method="POST",
    )
    login_request.add_header("Content-Type", "application/x-www-form-urlencoded")
    _, _, headers, status = read(no_redirect, login_request)
    if status not in (302, 303):
        raise RuntimeError(f"Cognito hosted UI login failed with HTTP {status}")

    redirect_url = headers.get("Location", "")
    code = urllib.parse.parse_qs(urllib.parse.urlparse(redirect_url).query).get("code", [None])[0]
    if not code:
        raise RuntimeError("Cognito hosted UI login did not return an authorization code")

    token_request = urllib.request.Request(
        f"{base_url}/oauth2/token",
        data=urllib.parse.urlencode(
            {
                "grant_type": "authorization_code",
                "client_id": client_id,
                "redirect_uri": redirect_uri,
                "code": code,
            }
        ).encode(),
        method="POST",
    )
    token_request.add_header("Content-Type", "application/x-www-form-urlencoded")
    _, payload, _, status = read(normal, token_request)
    if status != 200:
        raise RuntimeError(f"Token exchange failed with HTTP {status}: {payload}")

    token_response = json.loads(payload)
    return token_response["access_token"]


def api_call(api_base_url, access_token, correlation_id, method, path, payload=None):
    request = urllib.request.Request(
        f"{api_base_url}{path}",
        data=None if payload is None else json.dumps(payload).encode(),
        method=method,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "X-Correlation-Id": correlation_id,
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        body = error.read().decode()
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = body
        return error.code, parsed


def main():
    args = parse_args()

    outputs = terraform_outputs()
    redirect_uri = "https://example.com/callback"
    hosted_ui_base_url = outputs.get("cognito_hosted_ui_base_url")
    if not hosted_ui_base_url:
        hosted_ui_base_url = f"https://{outputs['cognito_user_pool_domain']}.auth.{args.region}.amazoncognito.com"

    access_token = hosted_ui_login(
        hosted_ui_base_url,
        outputs["cognito_app_client_id"],
        redirect_uri,
        args.username,
        args.password,
        ["openid", "email", "profile", "orders/read", "orders/write"],
    )

    product_status = None
    product_body = None
    if not args.skip_product_check:
        product_status, product_body = api_call(
            outputs["api_gateway_endpoint"],
            access_token,
            args.correlation_id,
            "GET",
            f"/product/{args.product_number}",
        )

    order_status, order_body = api_call(
        outputs["api_gateway_endpoint"],
        access_token,
        args.correlation_id,
        "POST",
        "/orders",
        {"productNumber": args.product_number, "quantity": args.quantity},
    )

    order_lookup = None
    if order_status == 201 and isinstance(order_body, dict) and order_body.get("orderId"):
        lookup_status, lookup_body = api_call(
            outputs["api_gateway_endpoint"],
            access_token,
            args.correlation_id,
            "GET",
            f"/orders/{order_body['orderId']}",
        )
        order_lookup = {"status": lookup_status, "body": lookup_body}

    print(
        json.dumps(
            {
                "apiGatewayEndpoint": outputs["api_gateway_endpoint"],
                "correlationId": args.correlation_id,
                "productCheck": None if args.skip_product_check else {"status": product_status, "body": product_body},
                "orderCreate": {"status": order_status, "body": order_body},
                "orderLookup": order_lookup,
            },
            indent=2,
        )
    )
    if args.skip_product_check:
        return 0 if order_status == 201 else 1
    return 0 if product_status == 200 and order_status == 201 else 1


if __name__ == "__main__":
    raise SystemExit(main())
