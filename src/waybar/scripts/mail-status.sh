#!/usr/bin/env bash

# Base directory for neomutt accounts
ACCOUNTS_DIR="$HOME/.config/neomutt/accounts"

# Icons
ICON_OPEN="🖂" # Open envelope (has unread)

# Arrays to store account info
declare -a accounts_with_unread
declare -i total_unread=0

# Function to count unread emails via IMAP using curl
count_unread_imap() {
  local config_file="$1"

  # Parse config file
  local imap_user=$(grep 'set imap_user' "$config_file" | sed -E 's/.*"([^"]+)".*/\1/')
  local imap_pass_cmd=$(grep 'set imap_pass' "$config_file" | sed -E 's/.*`([^`]+)`.*/\1/')
  local folder=$(grep 'set folder' "$config_file" | sed -E 's/.*"imaps?:\/\/[^@]+@([^:\/]+):?([0-9]*)\/?".*/\1:\2/')

  [ -z "$imap_user" ] || [ -z "$imap_pass_cmd" ] || [ -z "$folder" ] && echo "0" && return

  local server=$(echo "$folder" | cut -d: -f1)
  local port=$(echo "$folder" | cut -d: -f2)
  [ -z "$port" ] && port=993

  # Get password
  local password=$(eval "$imap_pass_cmd" 2>/dev/null)
  [ -z "$password" ] && echo "0" && return

  # Query IMAP for unseen count using curl
  # Use STATUS command to get the actual count of unseen messages
  # Force LOGIN authentication to avoid GSSAPI/Kerberos issues with Exchange
  local result=$(timeout 10 curl -s --url "imaps://${server}:${port}/INBOX" \
    --user "${imap_user}:${password}" \
    --login-options "AUTH=PLAIN" \
    -X "STATUS INBOX (UNSEEN)" 2>/dev/null)

  # Count the number of unseen messages
  if [ -n "$result" ]; then
    # Extract the number from "* STATUS INBOX (UNSEEN X)"
    local count=$(echo "$result" | grep -oP 'UNSEEN \K\d+')
    echo "${count:-0}"
  else
    echo "0"
  fi
}

# Loop through all account domains and names
for domain_dir in "$ACCOUNTS_DIR"/*; do
  [ -d "$domain_dir" ] || continue

  domain=$(basename "$domain_dir")

  for account_dir in "$domain_dir"/*; do
    [ -d "$account_dir" ] || continue

    account_name=$(basename "$account_dir")
    config_file="$account_dir/config"

    [ -f "$config_file" ] || continue

    # Count unread emails via IMAP
    unread=$(count_unread_imap "$config_file" 2>/dev/null || echo 0)

    # Only add to output if there are unread emails
    if [ "$unread" -gt 0 ]; then
      accounts_with_unread+=("$account_name:$domain ($unread)")
      total_unread=$((total_unread + unread))
    fi
  done
done

# Output in JSON format for Waybar
if [ "$total_unread" -gt 0 ]; then
  # Build tooltip text
  tooltip=""
  for account in "${accounts_with_unread[@]}"; do
    tooltip="${tooltip}${account}\n"
  done
  # Remove trailing newline
  tooltip="${tooltip%\\n}"

  # Output JSON
  echo "{\"text\":\"$ICON_OPEN $total_unread \",\"tooltip\":\"$tooltip\",\"class\":\"unread\"}"
else
  # Show nothing if no unread emails
  echo "{\"text\":\"\",\"tooltip\":\"No unread emails\",\"class\":\"empty\"}"
fi
