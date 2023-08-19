#!/usr/bin/env bash

CONFIG="$HOME/.config/dunst/config"

if [[ ! $(pidof dunst) ]]; then
	dunst --config ${CONFIG}
fi
