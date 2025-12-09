#!/usr/bin/env bash

echo "Setting Konform VPN Password:"
read -srp "Password: " password
echo "$password" | gpg --symmetric --cipher-algo AES256 -o "$(pwd)/password.gpg"
echo ""
echo "Password stored in $(pwd)/password.gpg"
