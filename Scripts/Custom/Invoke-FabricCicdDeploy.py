#!/usr/bin/env python3

import argparse
import json
import os
import sys

from azure.identity import ClientSecretCredential
from fabric_cicd import FabricWorkspace, publish_all_items


def _parse_item_types(raw_value: str) -> list[str]:
    value = json.loads(raw_value)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError("items-in-scope must be a JSON array of strings")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Deploy Fabric items using fabric-cicd Python library.")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--workspace-name", required=True)
    parser.add_argument("--source-path", required=True)
    parser.add_argument("--items-in-scope", default='["SemanticModel"]')
    parser.add_argument("--environment", default="N/A")
    args = parser.parse_args()

    tenant_id = args.tenant_id or os.environ.get("TENANT_ID")
    client_id = args.client_id or os.environ.get("CLIENT_ID")
    client_secret = args.client_secret or os.environ.get("CLIENT_SECRET")
    if not tenant_id or not client_id or not client_secret:
        raise ValueError("tenant-id, client-id, and client-secret must be provided via args or environment")

    item_types = _parse_item_types(args.items_in_scope)
    credential = ClientSecretCredential(
        tenant_id=tenant_id,
        client_id=client_id,
        client_secret=client_secret,
    )
    workspace = FabricWorkspace(
        workspace_name=args.workspace_name,
        repository_directory=args.source_path,
        item_type_in_scope=item_types,
        environment=args.environment,
        token_credential=credential,
    )
    publish_all_items(workspace)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"Deployment failed: {exc}", file=sys.stderr)
        sys.exit(1)
