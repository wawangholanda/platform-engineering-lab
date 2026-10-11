#!/usr/bin/env python3

import argparse
import os
import re
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent

TEMPLATES = {
    ROOT_DIR / "templates/domain/argocd-route.yaml.tmpl": (
        ROOT_DIR / "environments/dev/kubernetes/gateway/argocd-route.yaml"
    ),
    ROOT_DIR / "templates/domain/grafana-route.yaml.tmpl": (
        ROOT_DIR / "environments/dev/kubernetes/gateway/grafana-route.yaml"
    ),
    ROOT_DIR / "templates/domain/monitoring-values.yaml.tmpl": (
        ROOT_DIR
        / "environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml"
    ),
}

HOSTNAME_PATTERN = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"
)


def validate_hostname(name: str, value: str) -> str:
    hostname = value.strip().rstrip(".")
    if not hostname or len(hostname) > 253:
        raise ValueError(f"{name} is missing or has an invalid length")
    if not HOSTNAME_PATTERN.fullmatch(hostname):
        raise ValueError(
            f"{name} must be a valid hostname without a scheme or path"
        )
    return hostname.lower()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate and render domain-based GitOps configuration."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write rendered content to the three generated GitOps files.",
    )
    args = parser.parse_args()

    try:
        domains = {
            "ARGOCD_DOMAIN": validate_hostname(
                "ARGOCD_DOMAIN", os.environ.get("ARGOCD_DOMAIN", "")
            ),
            "GRAFANA_DOMAIN": validate_hostname(
                "GRAFANA_DOMAIN", os.environ.get("GRAFANA_DOMAIN", "")
            ),
        }

        rendered_files = []

        for template_path, output_path in TEMPLATES.items():
            if not template_path.is_file():
                raise FileNotFoundError(
                    f"Template not found: {template_path.relative_to(ROOT_DIR)}"
                )

            content = template_path.read_text(encoding="utf-8")

            for key, value in domains.items():
                content = content.replace("{{" + key + "}}", value)

            if re.search(r"\{\{[A-Z][A-Z0-9_]*\}\}", content):
                raise ValueError(
                    "Unresolved domain placeholder in "
                    f"{template_path.relative_to(ROOT_DIR)}"
                )

            rendered_files.append((template_path, output_path, content))

        for template_path, output_path, content in rendered_files:
            template_name = template_path.relative_to(ROOT_DIR)
            output_name = output_path.relative_to(ROOT_DIR)

            if args.write:
                output_path.write_text(content, encoding="utf-8")
                print(f"Wrote: {output_name}")
            else:
                print(f"Validated: {template_name} -> {output_name}")

        if args.write:
            print("Domain configuration rendered successfully.")
        else:
            print("Validation successful; no files were modified.")
            print("Use --write to write the generated manifests.")

        return 0

    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
