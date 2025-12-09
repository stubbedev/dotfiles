#!/bin/sh
gpg --quiet --batch --decrypt ~/.config/vpn/konform/password.gpg | tr -d ' \n'
