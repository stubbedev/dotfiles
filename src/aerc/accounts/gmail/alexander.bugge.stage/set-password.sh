#!/usr/bin/env bash

echo "Setting New Password:"
read -srp "Password: " password
printf '%s' "$password" | secret-tool store --label="aerc gmail alexander.bugge.stage" service aerc account gmail/alexander.bugge.stage
unset password
