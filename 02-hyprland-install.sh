#!/bin/bash
set -e

sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm git base-devel

# Установка Hyprland и Wayland-окружения
sudo pacman -S --noconfirm hyprland waybar rofi alacritty thunar \
  pipewire wireplumber networkmanager fuzzel \
  xdg-desktop-portal-hyprland xdg-user-dirs

# Установка AGS (GTK widget system)
sudo pacman -S --noconfirm gtk3 gtk4

# Включение NetworkManager
sudo systemctl enable --now NetworkManager 