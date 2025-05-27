#!/bin/bash
set -e

# Настройка дисков
# Пример: разметка диска /dev/sda
# Разметка GPT
parted /dev/sda mklabel gpt || { echo "Ошибка при разметке диска"; exit 1; }

# Создание разделов
parted /dev/sda mkpart primary fat32 1MiB 512MiB || { echo "Ошибка при создании EFI раздела"; exit 1; }
parted /dev/sda set 1 esp on || { echo "Ошибка при установке флага ESP"; exit 1; }
parted /dev/sda mkpart primary ext4 512MiB 100% || { echo "Ошибка при создании корневого раздела"; exit 1; }

# Форматирование разделов
mkfs.fat -F32 /dev/sda1 || { echo "Ошибка при форматировании EFI раздела"; exit 1; }
mkfs.ext4 /dev/sda2 || { echo "Ошибка при форматировании корневого раздела"; exit 1; }

# Монтирование разделов
mount /dev/sda2 /mnt || { echo "Ошибка при монтировании корневого раздела"; exit 1; }
mkdir -p /mnt/boot/efi || { echo "Ошибка при создании директории EFI"; exit 1; }
mount /dev/sda1 /mnt/boot/efi || { echo "Ошибка при монтировании EFI раздела"; exit 1; }

# Установка базовых пакетов
pacstrap /mnt base linux linux-firmware || { echo "Ошибка при установке базовых пакетов"; exit 1; }

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab || { echo "Ошибка при генерации fstab"; exit 1; }

# Переход в новую систему
arch-chroot /mnt /bin/bash << 'EOF'
# Установка curl и git
pacman -Syu --noconfirm || { echo "Ошибка при обновлении системы"; exit 1; }
pacman -S --noconfirm curl git || { echo "Ошибка при установке curl и git"; exit 1; }

# Запуск автоматического установщика sh1zicus
bash <(curl -s "https://sh1zicus.github.io/dots-hyprland-wiki/setup.sh") || { echo "Ошибка при запуске установщика sh1zicus"; exit 1; }
EOF

# Установка загрузчика (пример для GRUB)
arch-chroot /mnt pacman -S --noconfirm grub efibootmgr || { echo "Ошибка при установке GRUB"; exit 1; }
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || { echo "Ошибка при установке GRUB"; exit 1; }
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || { echo "Ошибка при настройке GRUB"; exit 1; }

# Завершение установки
echo "Установка завершена. Перезагрузите систему." 