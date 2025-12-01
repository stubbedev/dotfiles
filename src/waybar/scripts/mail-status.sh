#!/usr/bin/env bash

# Base directory for aerc accounts
ACCOUNTS_CONF="$HOME/.config/aerc/accounts.conf"
STATE_FILE="/tmp/mail-status-$USER.state"
SEEN_UIDS_DIR="/tmp/mail-status-uids-$USER"

# Icons
# ICON_OPEN="🖂" # Open envelope (has unread)
ICON_OPEN="" # Open envelope (has unread)

# Arrays to store account info
declare -a accounts_with_unread
declare -i total_unread=0
declare -A current_counts
declare -A previous_counts

# Create directory for tracking seen UIDs
mkdir -p "$SEEN_UIDS_DIR"

# Load previous state
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r account count; do
    previous_counts["$account"]="$count"
  done <"$STATE_FILE"
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

# Function to get unseen email UIDs
get_unseen_uids() {
  local server="$1"
  local port="$2"
  local user="$3"
  local password="$4"

  local result
  result=$(timeout 10 curl -s --url "imaps://${server}:${port}/INBOX" \
    --user "${user}:${password}" \
    --login-options "AUTH=PLAIN" \
    -X "SEARCH UNSEEN" 2>/dev/null)

  # Extract UIDs from "* SEARCH uid1 uid2 uid3..."
  echo "$result" | grep -oP '\* SEARCH \K.*' | tr ' ' '\n' | grep -E '^[0-9]+$'
}

# Function to fetch email headers (PEEK to not mark as read)
fetch_email_headers() {
  local server="$1"
  local port="$2"
  local user="$3"
  local password="$4"
  local uid="$5"

  # Use BODY.PEEK to fetch without marking as read
  local result
  result=$(timeout 10 curl -s --url "imaps://${server}:${port}/INBOX;UID=${uid};SECTION=HEADER" \
    --user "${user}:${password}" \
    --login-options "AUTH=PLAIN" \
    --request "FETCH ${uid} (BODY.PEEK[HEADER] BODY.PEEK[TEXT]<0.500>)" 2>/dev/null)

  echo "$result"
}

# Function to parse email subject and sender from headers
parse_email_info() {
  local headers="$1"
  local subject=""
  local sender=""
  local body_preview=""
  local in_body=0
  local body_char_count=0
  local max_body_chars=200

  while IFS= read -r line; do
    # Remove carriage return
    line="${line%$'\r'}"

    # Check if we've reached the body
    if [ -z "$line" ] && [ $in_body -eq 0 ]; then
      in_body=1
      continue
    fi

    # Extract subject (handle multi-line headers)
    if [[ "$line" =~ ^Subject:\ (.+)$ ]]; then
      subject="${BASH_REMATCH[1]}"
    elif [ -n "$subject" ] && [[ "$line" =~ ^[[:space:]]+(.+)$ ]]; then
      subject="${subject} ${BASH_REMATCH[1]}"
    fi

    # Extract sender
    if [[ "$line" =~ ^From:\ (.+)$ ]]; then
      sender="${BASH_REMATCH[1]}"
    fi

    # Get body preview (up to max_body_chars characters)
    if [ $in_body -eq 1 ] && [ $body_char_count -lt $max_body_chars ]; then
      # Skip empty lines at start of body
      if [ -z "$body_preview" ] && [ -z "$line" ]; then
        continue
      fi

      # Skip HTML tags and common MIME markers
      if [[ "$line" =~ ^[[:space:]]*\<.*\>[[:space:]]*$ ]] ||
        [[ "$line" =~ ^Content-Type: ]] ||
        [[ "$line" =~ ^Content-Transfer-Encoding: ]] ||
        [[ "$line" =~ ^--.*--$ ]]; then
        continue
      fi

      if [ -n "$line" ]; then
        local remaining=$((max_body_chars - body_char_count))
        if [ ${#line} -gt $remaining ]; then
          body_preview="${body_preview}${line:0:$remaining}"
          body_char_count=$max_body_chars
        else
          body_preview="${body_preview}${line} "
          body_char_count=$((body_char_count + ${#line} + 1))
        fi
      fi
    fi
  done <<<"$headers"

  # Clean up subject - remove extra whitespace
  subject=$(echo "$subject" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Decode MIME encoded subjects
  if [[ "$subject" =~ =\?.*\?= ]]; then
    subject=$(echo "$subject" | perl -CS -MEncode -ne 'print decode("MIME-Header", $_)' 2>/dev/null || echo "$subject")
  fi

  # Clean up body preview
  body_preview=$(echo "$body_preview" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  echo "${subject}|${sender}|${body_preview}"
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

# Send notification for each new email
if [ "$total_new_emails" -gt 0 ]; then
  for account_name in "${!new_emails_per_account[@]}"; do
    email="${email_addresses[$account_name]}"
    server="${account_servers[$account_name]}"
    port="${account_ports[$account_name]}"
    user="${account_users[$account_name]}"
    password="${account_passwords[$account_name]}"

    # Get UIDs of unseen emails
    seen_file="${SEEN_UIDS_DIR}/${account_name}.seen"

    # Load previously seen UIDs
    declare -A seen_uids
    if [ -f "$seen_file" ]; then
      while IFS= read -r uid; do
        seen_uids["$uid"]=1
      done <"$seen_file"
    fi

    # Get current unseen UIDs
    mapfile -t unseen_uids < <(get_unseen_uids "$server" "$port" "$user" "$password")

    # Send notification for each new (previously unseen) email
    for uid in "${unseen_uids[@]}"; do
      if [ -z "${seen_uids[$uid]}" ] && [ -n "$uid" ]; then
        # Fetch email headers and body preview (PEEK to not mark as read)
        headers=$(fetch_email_headers "$server" "$port" "$user" "$password" "$uid")

        if [ -n "$headers" ]; then
          # Parse email info
          email_info=$(parse_email_info "$headers")
          subject=$(echo "$email_info" | cut -d'|' -f1)
          sender=$(echo "$email_info" | cut -d'|' -f2)
          body_preview=$(echo "$email_info" | cut -d'|' -f3-)

          # Truncate subject if too long
          if [ ${#subject} -gt 60 ]; then
            subject="${subject:0:57}..."
          fi

          # Body is already truncated to 200 chars in parse_email_info
          # Add ellipsis if it looks truncated
          if [ ${#body_preview} -ge 200 ]; then
            body_preview="${body_preview}..."
          fi

          # Default values if parsing failed
          subject="${subject:-No Subject}"
          sender="${sender:-Unknown Sender}"
          body_preview="${body_preview:-}"

          # Send notification
          if [ -n "$body_preview" ]; then
            notify-send -u normal -i mail-unread \
              "${email}: ${subject}" \
              "From: ${sender}\n\n${body_preview}"
          else
            notify-send -u normal -i mail-unread \
              "${email}: ${subject}" \
              "From: ${sender}"
          fi

          # Mark UID as seen locally (does NOT mark as read on server)
          echo "$uid" >>"$seen_file"
        fi
      fi
    done

    unset seen_uids
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
