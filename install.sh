#!/bin/bash
# -*- coding: utf-8 -*-

# Import common functions
source common.sh

# Check if running as root
check_root

# Get user input
echo "=== Installation Setup ==="
read -p "Enter username: " USERNAME
read -p "Enter computer name (hostname): " HOSTNAME
read -s -p "Enter user password: " USERPASS
echo
read -s -p "Enter root password: " ROOTPASS
echo

# Save input data
echo "USERNAME=\"$USERNAME\"" > /tmp/install_config
echo "HOSTNAME=\"$HOSTNAME\"" >> /tmp/install_config
echo "USERPASS=\"$USERPASS\"" >> /tmp/install_config
echo "ROOTPASS=\"$ROOTPASS\"" >> /tmp/install_config

if [ -f /mnt/step2 ]; then
    echo "[2/2] Continuing installation after reboot..."
    # Load saved data
    source /tmp/install_config
    install_all_packages
    setup_system
    install_bootloader
    final_setup
    remove_autorun
    rm /mnt/step2
    rm /tmp/install_config
    echo "Installation complete! Reboot and login as $USERNAME."
    exit 0
fi

# [1/2] First part: disk partitioning, base installation, reboot
echo "=== Select Installation Disk ==="
select_disk

partition_and_format_disk
install_base_system
cp /tmp/install_config /mnt/root/install_config
touch /mnt/step2
add_autorun
echo "Rebooting... Installation will continue automatically after reboot."
reboot

# Устанавливаем Hyprland и необходимые пакеты
echo "Установка Hyprland и дополнительных пакетов..."
install_hyprland

# Настраиваем систему
echo "Настройка системы..."
configure_system

# Устанавливаем dotfiles
echo "Установка конфигурационных файлов..."
install_dotfiles

# Выполняем пост-установочные настройки
echo "Выполнение пост-установочных настроек..."
post_setup

echo "Установка завершена! Перезагрузите систему." 
