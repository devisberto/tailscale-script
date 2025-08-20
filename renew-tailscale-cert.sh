#!/bin/bash
set -euo pipefail

CERT_DIR="/etc/ssl/tailscale"

# Obtain DNS name for this machine in the tailnet
DNS_NAME=$(tailscale status --json | jq -r '.Self.DNSName')

CERT_FILE="${CERT_DIR}/${DNS_NAME}.crt"
KEY_FILE="${CERT_DIR}/${DNS_NAME}.key"

mkdir -p "$CERT_DIR"

renew_needed=false

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  renew_needed=true
else
  # Extract certificate expiration date and compute remaining days
  if ! END_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2); then
    renew_needed=true
  else
    END_SECS=$(date -d "$END_DATE" +%s)
    NOW_SECS=$(date +%s)
    DAYS_LEFT=$(( (END_SECS - NOW_SECS) / 86400 ))
    if (( DAYS_LEFT < 20 )); then
      renew_needed=true
    fi
  fi
fi

if [ "$renew_needed" = true ]; then
  echo "Generating new certificate for $DNS_NAME"
  tailscale cert --cert-file="$CERT_FILE" --key-file="$KEY_FILE" "$DNS_NAME"
  # Reload Apache to ensure it picks up the new certificate
  if systemctl list-units --full -all | grep -Fq apache2.service; then
    systemctl reload apache2
  elif systemctl list-units --full -all | grep -Fq httpd.service; then
    systemctl reload httpd
  else
    echo "Apache service not found; skipping reload" >&2
  fi
else
  echo "Certificate for $DNS_NAME is valid for $DAYS_LEFT days."
fi
