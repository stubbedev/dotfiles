#!/usr/bin/env bash

echo "Setting New Password:"
read -srp "Password: " password
printf '%s' "$password" | secret-tool store --label="aerc kontainer abs" service aerc account kontainer/abs
unset password
