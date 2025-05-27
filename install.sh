#!/bin/bash

# Импортируем общие функции
source common.sh

# Проверяем, запущен ли скрипт от root
check_root

# Запрашиваем данные у пользователя
echo "=== Настройка установки ==="
read -p "Введите имя пользователя: " USERNAME
read -p "Введите имя компьютера (hostname): " HOSTNAME
read -s -p "Введите пароль для пользователя: " USERPASS
echo
read -s -p "Введите пароль для root: " ROOTPASS
echo

# Сохраняем введенные данные
echo "USERNAME=\"$USERNAME\"" > /tmp/install_config
echo "HOSTNAME=\"$HOSTNAME\"" >> /tmp/install_config
echo "USERPASS=\"$USERPASS\"" >> /tmp/install_config
echo "ROOTPASS=\"$ROOTPASS\"" >> /tmp/install_config

if [ -f /mnt/step2 ]; then
    echo "[2/2] Продолжаем установку после перезагрузки..."
    # Загружаем сохраненные данные
    source /tmp/install_config
    install_all_packages
    setup_system
    install_bootloader
    final_setup
    remove_autorun
    rm /mnt/step2
    rm /tmp/install_config
    echo "Установка завершена! Перезагрузите систему и войдите под пользователем $USERNAME."
    exit 0
fi

# [1/2] Первая часть: разметка, базовая установка, перезагрузка
echo "=== Выбор диска для установки ==="
select_disk

partition_and_format_disk
install_base_system
cp /tmp/install_config /mnt/root/install_config
touch /mnt/step2
add_autorun
echo "Перезагрузка... После перезагрузки установка продолжится автоматически."
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