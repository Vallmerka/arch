#!/bin/bash
set -e

# Пример: дополнительные пакеты
sudo pacman -S --noconfirm firefox neovim

# Пример: автозапуск Wayland-сессии
echo 'exec Hyprland' > ~/.xinitrc

# Информация по хоткеям
echo 'Смотри ~/.config/hypr/hyprland.conf для настройки хоткеев (Super+/ — список по умолчанию)' 