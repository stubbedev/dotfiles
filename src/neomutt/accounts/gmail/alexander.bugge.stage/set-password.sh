#!/usr/bin/env bash

echo "Setting New Password:"
read -srp "Password: " password
echo "$password" | gpg --symmetric --cipher-algo AES256 -o "$(pwd)/password.gpg"
