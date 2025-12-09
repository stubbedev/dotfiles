#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
gpg --quiet --batch --decrypt "$SCRIPT_DIR/password.gpg" | tr -d ' \n'
