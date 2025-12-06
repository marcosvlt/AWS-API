#!/usr/bin/env bash
set -euo pipefail

# Usage/help function: prints how to call the script and exits.
usage() {
  cat <<EOF
Usage: $(basename "$0") -p USER_POOL_ID -e USER_EMAIL [-w PASSWORD] [-h]

Creates a Cognito user and sets a permanent password.
If PASSWORD is omitted the script will prompt (hidden).
EOF
  exit 1
}

# Variables to hold parsed arguments
POOL_ID=""
EMAIL=""
PASSWORD=""

# Parse command-line options:
# -p USER_POOL_ID : Cognito user pool id
# -e USER_EMAIL   : username / email to create
# -w PASSWORD     : optional password (if omitted the script will prompt)
# -h              : show help/usage
while getopts "p:e:w:h" opt; do
  case $opt in
    p) POOL_ID="$OPTARG" ;;
    e) EMAIL="$OPTARG" ;;
    w) PASSWORD="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Ensure required options were provided; if not, show usage and exit.
if [[ -z "$POOL_ID" || -z "$EMAIL" ]]; then
  usage
fi

# If password not provided on command line, prompt interactively (hidden input).
if [[ -z "${PASSWORD:-}" ]]; then
  # -s hides input, -p prints prompt on the same line
  read -s -p "Enter password for ${EMAIL}: " PASSWORD
  echo
  read -s -p "Confirm password: " PASSWORD2
  echo
  # Verify confirmation matches
  if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
    echo "Passwords do not match" >&2
    exit 2
  fi
fi

# Ensure the AWS CLI is available before proceeding.
command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 3; }

# Create the user in the specified Cognito user pool.
# --message-action SUPPRESS prevents Cognito from sending the welcome email.
# Also sets the email attribute and marks it verified.
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "$EMAIL" \
  --message-action SUPPRESS \
  --user-attributes Name="email",Value="$EMAIL" Name="email_verified",Value="true"

# Set the user's password and mark it as permanent (so user is not required to change it).
aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL_ID" \
  --username "$EMAIL" \
  --password "$PASSWORD" \
  --permanent

# Final status message
echo "User $EMAIL created and password set."
