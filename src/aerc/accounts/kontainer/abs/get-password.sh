#!/bin/sh
gpg --quiet --batch --decrypt ~/.config/aerc/accounts/kontainer/abs/password.gpg | tr -d ' \n'
