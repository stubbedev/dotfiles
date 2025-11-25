#!/bin/sh
gpg --quiet --batch --decrypt ~/.config/aerc/accounts/gmail/alexander.bugge.stage/password.gpg | tr -d ' \n'
