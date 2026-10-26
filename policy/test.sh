#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
POLICY_DIR="$ROOT_DIR/policy/terraform"

if command -v opa >/dev/null 2>&1; then
  OPA_BIN=$(command -v opa)
  TEMP_DIR=""
else
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aws-opa-tests.XXXXXX")
  trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    arm64|aarch64) OPA_ARCH="arm64" ;;
    x86_64|amd64) OPA_ARCH="amd64" ;;
    *)
      echo "Unsupported architecture: $ARCH" >&2
      exit 1
      ;;
  esac

  case "$OS" in
    darwin|linux) ;;
    *)
      echo "Unsupported operating system: $OS" >&2
      exit 1
      ;;
  esac

  OPA_BIN="$TEMP_DIR/opa"
  OPA_VERSION="v1.4.2"
  OPA_URL="https://openpolicyagent.org/downloads/${OPA_VERSION}/opa_${OS}_${OPA_ARCH}_static"

  echo "OPA is not installed; downloading ${OPA_VERSION} temporarily..."
  curl --fail --location --silent --show-error "$OPA_URL" --output "$OPA_BIN"
  chmod +x "$OPA_BIN"
fi

echo "Checking Rego formatting..."
"$OPA_BIN" fmt --fail --list "$POLICY_DIR"

echo "Running Rego unit tests..."
"$OPA_BIN" test --verbose "$POLICY_DIR"
