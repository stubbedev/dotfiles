#!/usr/bin/env bash

# Base directory for aerc accounts
ACCOUNTS_CONF="$HOME/.config/aerc/accounts.conf"
STATE_FILE="/tmp/mail-status-$USER.state"

# Icons
ICON_OPEN="" # Open envelope (has unread)

# Arrays to store account info
declare -a accounts_with_unread
declare -i total_unread=0
declare -A current_counts
declare -A previous_counts

# Load previous state (unread counts)
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r account count; do
    previous_counts["$account"]="$count"
  done <"$STATE_FILE"
fi

# Load last check times
if [ -f "$LAST_CHECK_FILE" ]; then
  while IFS='=' read -r account timestamp; do
    last_check_times["$account"]="$timestamp"
  done <"$LAST_CHECK_FILE"
fi

# Function to parse aerc accounts.conf and extract account info
parse_aerc_account() {
  local account_name="$1"
  local in_section=0
  local source="" source_cred_cmd="" from=""

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
      elif [[ "$line" =~ ^from=(.+)$ ]]; then
        from="${BASH_REMATCH[1]}"
      fi
    fi
  done <"$ACCOUNTS_CONF"

  echo "$source|$source_cred_cmd|$from"
}

# Function to count unread emails via IMAP using curl
count_unread_imap() {
  local account_name="$1"

  # Parse account configuration
  local account_info
  account_info=$(parse_aerc_account "$account_name")
  local source
  source=$(echo "$account_info" | cut -d'|' -f1)
  local source_cred_cmd
  source_cred_cmd=$(echo "$account_info" | cut -d'|' -f2)
  local from
  from=$(echo "$account_info" | cut -d'|' -f3)

  [ -z "$source" ] || [ -z "$source_cred_cmd" ] && echo "0|" && return

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
  local password
  password=$(eval "$source_cred_cmd" 2>/dev/null)
  [ -z "$password" ] && echo "0|$from" && return

  # Query IMAP for unseen count using curl
  # Reduced timeout to 5 seconds for faster response
  local result
  result=$(timeout 5 curl -s --url "imaps://${server}:${port}/INBOX" \
    --user "${imap_user}:${password}" \
    --login-options "AUTH=PLAIN" \
    -X "STATUS INBOX (UNSEEN)" 2>/dev/null)

  # Count the number of unseen messages
  if [ -n "$result" ]; then
    # Extract the number from "* STATUS INBOX (UNSEEN X)"
    local count
    count=$(echo "$result" | grep -oP 'UNSEEN \K\d+')
    echo "${count:-0}|$from|${server}|${port}|${imap_user}|${password}"
  else
    echo "0|$from|${server}|${port}|${imap_user}|${password}"
  fi
}

# Function to get new unseen emails since last check
get_new_unseen_emails() {
  local server="$1"
  local port="$2"
  local user="$3"
  local password="$4"
  local prev_count="$5"
  local current_count="$6"

  # Calculate how many new emails we should fetch
  local new_count=$((current_count - prev_count))

  if [ "$new_count" -le 0 ]; then
    return
  fi

  # Get all unseen emails sorted by arrival date (most recent first)
  # Then take only the newest ones that represent the new emails
  local result
  result=$(timeout 10 curl -s --url "imaps://${server}:${port}/INBOX" \
    --user "${user}:${password}" \
    --login-options "AUTH=PLAIN" \
    -X "SEARCH UNSEEN" 2>/dev/null)

  # Extract UIDs from "* SEARCH uid1 uid2 uid3..." (remove \r\n)
  # The UIDs are returned in ascending order (oldest first)
  # We want the last N UIDs (newest emails)
  local all_uids
  all_uids=$(echo "$result" | tr -d '\r' | grep -oP '\* SEARCH \K.*' | tr ' ' '\n' | grep -E '^[0-9]+$')

  # Take only the last N UIDs (the newest ones)
  echo "$all_uids" | tail -n "$new_count"
}

# Function to fetch email headers (PEEK to not mark as read)
fetch_email_headers() {
  local server="$1"
  local port="$2"
  local user="$3"
  local password="$4"
  local uid="$5"

  # Fetch the entire email but we'll only parse headers
  local result
  result=$(timeout 10 curl -s --url "imaps://${server}:${port}/INBOX;UID=${uid}/;SECTION=HEADER" \
    --user "${user}:${password}" \
    --login-options "AUTH=PLAIN" 2>/dev/null)

  echo "$result"
}

# Function to parse email subject and sender from headers
parse_email_info() {
  local headers="$1"
  local subject=""
  local sender=""
  local date=""
  local in_headers=0
  local current_field=""

  while IFS= read -r line; do
    # Remove carriage return
    line="${line%$'\r'}"

    # Skip IMAP protocol lines (starting with * or containing only braces/parens)
    if [[ "$line" =~ ^\*.*FETCH ]] || [[ "$line" =~ ^[\)\}\{].*$ ]]; then
      continue
    fi

    # Skip lines that look like IMAP size indicators
    if [[ "$line" =~ ^\{[0-9]+\}$ ]]; then
      in_headers=1
      continue
    fi

    # Check if we've reached the body (empty line after headers)
    if [ -z "$line" ] && [ $in_headers -eq 1 ]; then
      break
    fi

    # Check if this is a new header field (starts with non-whitespace followed by colon)
    if [[ "$line" =~ ^([A-Za-z-]+):[[:space:]]*(.*)$ ]]; then
      in_headers=1
      current_field="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      case "$current_field" in
      Subject)
        subject="$value"
        ;;
      From)
        sender="$value"
        ;;
      Date)
        date="$value"
        ;;
      esac
    # Handle continuation lines (only for the current field we're tracking)
    elif [ -n "$current_field" ] && [[ "$line" =~ ^[[:space:]]+(.+)$ ]]; then
      local continuation="${BASH_REMATCH[1]}"
      case "$current_field" in
      Subject)
        subject="${subject} ${continuation}"
        ;;
      From)
        sender="${sender} ${continuation}"
        ;;
      Date)
        date="${date} ${continuation}"
        ;;
      esac
    else
      # Not a header line we recognize, reset current field
      current_field=""
    fi
  done <<<"$headers"

  # Clean up subject - remove extra whitespace
  subject=$(echo "$subject" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Clean up sender
  sender=$(echo "$sender" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Decode MIME encoded subjects
  if [[ "$subject" =~ =\?.*\?= ]]; then
    subject=$(echo "$subject" | perl -CS -MEncode -ne 'print decode("MIME-Header", $_)' 2>/dev/null || echo "$subject")
  fi

  echo "${subject}|${sender}|${date}"
}

# Function to check account in background
check_account() {
  local account_name="$1"
  local result=$(count_unread_imap "$account_name" 2>/dev/null || echo "0|||||")
  local unread=$(echo "$result" | cut -d'|' -f1)
  local from=$(echo "$result" | cut -d'|' -f2)
  local server=$(echo "$result" | cut -d'|' -f3)
  local port=$(echo "$result" | cut -d'|' -f4)
  local user=$(echo "$result" | cut -d'|' -f5)
  local password=$(echo "$result" | cut -d'|' -f6)
  echo "$account_name:$unread:$from:$server:$port:$user:$password"
}

# Collect all account names
account_names=()
while IFS= read -r line; do
  if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
    account_names+=("${BASH_REMATCH[1]}")
  fi
done <"$ACCOUNTS_CONF"

# Check all accounts in parallel for faster response
declare -a pids
declare -a temp_files
for account_name in "${account_names[@]}"; do
  temp_file=$(mktemp)
  temp_files+=("$temp_file")
  check_account "$account_name" >"$temp_file" &
  pids+=($!)
done

# Wait for all background jobs to complete
for pid in "${pids[@]}"; do
  wait "$pid"
done

# Process results from temp files
declare -A new_emails_per_account
declare -A email_addresses
declare -A account_servers
declare -A account_ports
declare -A account_users
declare -A account_passwords
total_new_emails=0

for temp_file in "${temp_files[@]}"; do
  if [ -f "$temp_file" ]; then
    result=$(cat "$temp_file")
    rm -f "$temp_file"

    account_name=$(echo "$result" | cut -d':' -f1)
    unread=$(echo "$result" | cut -d':' -f2)
    from=$(echo "$result" | cut -d':' -f3)
    server=$(echo "$result" | cut -d':' -f4)
    port=$(echo "$result" | cut -d':' -f5)
    user=$(echo "$result" | cut -d':' -f6)
    password=$(echo "$result" | cut -d':' -f7-)

    current_counts["$account_name"]="$unread"
    email_addresses["$account_name"]="$from"
    account_servers["$account_name"]="$server"
    account_ports["$account_name"]="$port"
    account_users["$account_name"]="$user"
    account_passwords["$account_name"]="$password"

    # Only add to output if there are unread emails
    if [ "$unread" -gt 0 ]; then
      accounts_with_unread+=("$from ($unread)")
      total_unread=$((total_unread + unread))

      # Check if this is a new email (count increased)
      prev_count="${previous_counts[$account_name]:-0}"
      if [ "$unread" -gt "$prev_count" ]; then
        new_count=$((unread - prev_count))
        new_emails_per_account["$account_name"]="$new_count"
        total_new_emails=$((total_new_emails + new_count))
      fi
    fi
  fi
done

# Save current state for next run
>"$STATE_FILE"
for account_name in "${!current_counts[@]}"; do
  echo "$account_name=${current_counts[$account_name]}" >>"$STATE_FILE"
done

# Send notification for new emails
if [ "$total_new_emails" -gt 0 ]; then
  for account_name in "${!new_emails_per_account[@]}"; do
    email="${email_addresses[$account_name]}"
    server="${account_servers[$account_name]}"
    port="${account_ports[$account_name]}"
    user="${account_users[$account_name]}"
    password="${account_passwords[$account_name]}"

    # Get the previous count for this account
    prev_count="${previous_counts[$account_name]:-0}"
    current_count="${current_counts[$account_name]}"

    # Only send notifications if we had a previous state (not first run)
    if [ "${previous_counts[$account_name]+isset}" ]; then
      # Get UIDs of the newest unseen emails (the ones that are new since last check)
      mapfile -t new_email_uids < <(get_new_unseen_emails "$server" "$port" "$user" "$password" "$prev_count" "$current_count")

      # Send notification for each new email
      for uid in "${new_email_uids[@]}"; do
        if [ -n "$uid" ]; then
          # Fetch email headers
          headers=$(fetch_email_headers "$server" "$port" "$user" "$password" "$uid")

          if [ -n "$headers" ]; then
            # Parse email info
            email_info=$(parse_email_info "$headers")
            subject=$(echo "$email_info" | cut -d'|' -f1)
            sender=$(echo "$email_info" | cut -d'|' -f2)
            date=$(echo "$email_info" | cut -d'|' -f3)

            # Default values if parsing failed
            subject="${subject:-No Subject}"
            sender="${sender:-Unknown Sender}"
            date="${date:-}"

            # Format the notification body with sender and date
            notification_body="From: ${sender}"
            if [ -n "$date" ]; then
              notification_body="${notification_body}
Date: ${date}"
            fi
            notification_body="${notification_body}
To: ${email}"

            # Send notification
            notify-send -u normal -i mail-unread -a "mail-notification" \
              "${subject}" \
              "${notification_body}"
          fi
        fi
      done
    fi
  done
fi

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
