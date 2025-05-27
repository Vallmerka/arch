#!/bin/bash
set -e

# Клонируем dotfiles
if [ ! -d "$HOME/dots-hyprland" ]; then
  git clone https://github.com/sh1zicus/dots-hyprland.git "$HOME/dots-hyprland"
fi

# Запускаем автоматический установщик из репозитория
test -f "$HOME/dots-hyprland/install.sh" && bash "$HOME/dots-hyprland/install.sh" 