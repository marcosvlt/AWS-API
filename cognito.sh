#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -p USER_POOL_ID -e USER_EMAIL [-w PASSWORD] [-h]

Creates a Cognito user and sets a permanent password.
If PASSWORD is omitted the script will prompt (hidden).
EOF
  exit 1
}

POOL_ID=""
EMAIL=""
PASSWORD=""

while getopts "p:e:w:h" opt; do
  case $opt in
    p) POOL_ID="$OPTARG" ;;
    e) EMAIL="$OPTARG" ;;
    w) PASSWORD="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$POOL_ID" || -z "$EMAIL" ]]; then
  usage
fi

if [[ -z "${PASSWORD:-}" ]]; then
  read -s -p "Enter password for ${EMAIL}: " PASSWORD
  echo
  read -s -p "Confirm password: " PASSWORD2
  echo
  if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
    echo "Passwords do not match" >&2
    exit 2
  fi
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 3; }

# Create the user (suppress email/message)
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "$EMAIL" \
  --message-action SUPPRESS \
  --user-attributes Name="email",Value="$EMAIL" Name="email_verified",Value="true"

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL_ID" \
  --username "$EMAIL" \
  --password "$PASSWORD" \
  --permanent

echo "User $EMAIL created and password set."
