#!/usr/bin/env bash

# Base directory for aerc accounts
ACCOUNTS_DIR="$HOME/.config/aerc/accounts"
ACCOUNTS_CONF="$HOME/.config/aerc/accounts.conf"

# Icons
# ICON_OPEN="🖂" # Open envelope (has unread)
ICON_OPEN="" # Open envelope (has unread)

# Arrays to store account info
declare -a accounts_with_unread
declare -i total_unread=0

# Function to parse aerc accounts.conf and extract account info
parse_aerc_account() {
  local account_name="$1"
  local in_section=0
  local source="" source_cred_cmd=""

  while IFS= read -r line; do
    # Check if we're entering the target account section
    if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
      if [ "${BASH_REMATCH[1]}" = "$account_name" ]; then
        in_section=1
      else
        in_section=0
      fi
      continue
    fi

    # Parse fields if we're in the right section
    if [ $in_section -eq 1 ]; then
      if [[ "$line" =~ ^source=(.+)$ ]]; then
        source="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^source-cred-cmd=(.+)$ ]]; then
        source_cred_cmd="${BASH_REMATCH[1]}"
      fi
    fi
  done <"$ACCOUNTS_CONF"

  echo "$source|$source_cred_cmd"
}

# Function to count unread emails via IMAP using curl
count_unread_imap() {
  local account_name="$1"

  # Parse account configuration
  local account_info=$(parse_aerc_account "$account_name")
  local source=$(echo "$account_info" | cut -d'|' -f1)
  local source_cred_cmd=$(echo "$account_info" | cut -d'|' -f2)

  [ -z "$source" ] || [ -z "$source_cred_cmd" ] && echo "0" && return

  # Parse IMAP URL: imaps://user@domain@server:port
  # Format: imaps://abs@kontainer.com@ex.konformit.com:993
  local url_stripped="${source#imaps://}"
  local imap_user="${url_stripped%%@*}"    # Get first part before @
  local rest="${url_stripped#*@}"          # Remove first part
  local email_domain="${rest%%@*}"         # Get second part before @
  imap_user="${imap_user}@${email_domain}" # Combine user@domain
  local server_port="${rest#*@}"           # Get server:port
  local server="${server_port%%:*}"
  local port="${server_port##*:}"
  [ "$port" = "$server" ] && port=993

  # Expand tilde in credential command
  source_cred_cmd="${source_cred_cmd/#\~/$HOME}"

  # Get password
  local password=$(eval "$source_cred_cmd" 2>/dev/null)
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

# Read account names from accounts.conf
while IFS= read -r line; do
  if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
    account_name="${BASH_REMATCH[1]}"

    # Count unread emails via IMAP
    unread=$(count_unread_imap "$account_name" 2>/dev/null || echo 0)

    # Only add to output if there are unread emails
    if [ "$unread" -gt 0 ]; then
      accounts_with_unread+=("$account_name ($unread)")
      total_unread=$((total_unread + unread))
    fi
  fi
done <"$ACCOUNTS_CONF"

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
