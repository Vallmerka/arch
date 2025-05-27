#!/bin/bash

# === НАСТРОЙКИ ===
DISK="/dev/sda"   # Измените, если диск другой
TIMEZONE="Europe/Moscow"
LOCALE="ru_RU.UTF-8"

# Переменные, которые будут установлены пользователем
USERNAME=""
HOSTNAME=""
USERPASS=""
ROOTPASS=""
WIFI_SSID=""
WIFI_PASS=""

# Загружаем конфигурацию, если она есть
if [ -f /root/install_config ]; then
    source /root/install_config
fi

# === ФУНКЦИЯ: Полная разметка и форматирование диска ===
partition_and_format_disk() {
    echo "ВНИМАНИЕ! Все данные на $DISK будут удалены!"
    sleep 3
    
    # Разметка: EFI (512M), swap (2G), root (остальное)
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary linux-swap 513MiB 2561MiB
    parted -s "$DISK" mkpart primary ext4 2561MiB 100%

    # Форматирование
    mkfs.fat -F32 ${DISK}1
    mkswap ${DISK}2
    mkfs.ext4 ${DISK}3

    # Монтирование
    mount ${DISK}3 /mnt
    mkdir -p /mnt/boot/efi
    mount ${DISK}1 /mnt/boot/efi
    swapon ${DISK}2
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# === ФУНКЦИЯ: Установка системы и пакетов ===
install_base_system() {
    pacstrap /mnt base linux linux-firmware
    genfstab -U /mnt >> /mnt/etc/fstab
    cp packages.txt /mnt/root/packages.txt
}

# === ФУНКЦИЯ: Выбор диска ===
select_disk() {
    echo "=== Доступные диски ==="
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
    echo
    read -p "Введите имя диска (например, sda): " DISK
    DISK="/dev/$DISK"
    
    # Проверка существования диска
    if [ ! -b "$DISK" ]; then
        echo "Ошибка: Диск $DISK не найден!"
        exit 1
    fi
    
    # Проверка размера диска (минимум 20GB)
    DISK_SIZE=$(lsblk -b -d -o SIZE "$DISK" | tail -n1)
    MIN_SIZE=$((20*1024*1024*1024)) # 20GB в байтах
    
    if [ "$DISK_SIZE" -lt "$MIN_SIZE" ]; then
        echo "Ошибка: Диск слишком маленький! Требуется минимум 20GB"
        exit 1
    fi
    
    echo "Выбран диск: $DISK"
    echo "Размер: $((DISK_SIZE/1024/1024/1024))GB"
}

# === ФУНКЦИЯ: Настройка Wi-Fi ===
setup_wifi() {
    if [ -z "$WIFI_SSID" ]; then
        read -p "Введите имя Wi-Fi сети: " WIFI_SSID
        read -s -p "Введите пароль Wi-Fi: " WIFI_PASS
        echo
    fi
    
    # Сохраняем настройки Wi-Fi
    echo "WIFI_SSID=\"$WIFI_SSID\"" >> /tmp/install_config
    echo "WIFI_PASS=\"$WIFI_PASS\"" >> /tmp/install_config
    
    # Настраиваем Wi-Fi
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"
}

# === ФУНКЦИЯ: Параллельная установка пакетов ===
install_all_packages() {
    # Увеличиваем количество параллельных загрузок
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf
    
    # Обновляем систему
    arch-chroot /mnt pacman -Sy --noconfirm
    
    # Устанавливаем пакеты параллельно
    local packages=($(cat /mnt/root/packages.txt))
    local total=${#packages[@]}
    local current=0
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        echo -ne "\rУстановка пакетов: [$current/$total] ($((current*100/total))%)"
        arch-chroot /mnt pacman -S --noconfirm "$pkg" > /dev/null 2>&1
    done
    echo
}

# === ФУНКЦИЯ: Базовые настройки системы ===
setup_system() {
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    echo "$LOCALE UTF-8" > /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    echo "$HOSTNAME" > /mnt/etc/hostname
    echo "127.0.0.1   localhost" > /mnt/etc/hosts
    echo "::1         localhost" >> /mnt/etc/hosts
    echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /mnt/etc/hosts
    echo -e "$ROOTPASS\n$ROOTPASS" | arch-chroot /mnt passwd
    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh $USERNAME
    echo -e "$USERPASS\n$USERPASS" | arch-chroot /mnt passwd $USERNAME
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
}

# === ФУНКЦИЯ: Установка загрузчика ===
install_bootloader() {
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# Установка Hyprland и необходимых пакетов
install_hyprland() {
    # Установка Hyprland и зависимостей
    pacman -S --noconfirm \
        hyprland \
        waybar \
        rofi \
        dunst \
        swaybg \
        swaylock \
        wl-clipboard \
        xdg-desktop-portal-hyprland \
        qt5-wayland \
        qt6-wayland \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        pipewire-jack \
        wireplumber \
        pavucontrol \
        brightnessctl \
        playerctl \
        grim \
        slurp \
        wf-recorder \
        thunar \
        thunar-archive-plugin \
        thunar-volman \
        gvfs \
        gvfs-mtp \
        gvfs-gphoto2 \
        ffmpegthumbnailer \
        tumbler \
        xdg-user-dirs \
        xdg-utils \
        gtk3 \
        gtk4 \
        qt5 \
        qt6 \
        adwaita-qt5 \
        adwaita-qt6 \
        adwaita-icon-theme \
        papirus-icon-theme \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        ttf-font-awesome \
        ttf-jetbrains-mono-nerd \
        ttf-nerd-fonts-symbols \
        ttf-nerd-fonts-symbols-common \
        ttf-nerd-fonts-symbols-mono
}

# Настройка системы
configure_system() {
    # Включаем NetworkManager
    systemctl enable NetworkManager

    # Включаем PipeWire
    systemctl enable --user pipewire
    systemctl enable --user pipewire-pulse
    systemctl enable --user wireplumber

    # Создаем необходимые директории
    mkdir -p /etc/skel/.config
    mkdir -p /etc/skel/.local/share
}

# Установка dotfiles
install_dotfiles() {
    # Создаем директории для конфигурации
    mkdir -p /etc/skel/.config/hypr
    mkdir -p /etc/skel/.config/waybar
    mkdir -p /etc/skel/.config/rofi
    mkdir -p /etc/skel/.config/dunst

    # Копируем конфигурационные файлы
    cp -r config/hypr/* /etc/skel/.config/hypr/
    cp -r config/waybar/* /etc/skel/.config/waybar/
    cp -r config/rofi/* /etc/skel/.config/rofi/
    cp -r config/dunst/* /etc/skel/.config/dunst/
}

# Пост-установочные настройки
post_setup() {
    # Устанавливаем zsh как оболочку по умолчанию
    chsh -s /bin/zsh

    # Создаем пользовательские директории
    xdg-user-dirs-update

    # Устанавливаем разрешения
    chmod +x /etc/skel/.config/waybar/launch.sh
    chmod +x /etc/skel/.config/rofi/launcher.sh
}

# === ФУНКЦИИ: Автозапуск и автопродолжение ===
add_autorun() {
    echo "/root/install.sh" >> /mnt/root/.bash_profile
}
remove_autorun() {
    arch-chroot /mnt sed -i '/install.sh/d' /root/.bash_profile
}

# === ФУНКЦИЯ: Настройка zsh с oh-my-zsh ===
setup_zsh() {
    # Устанавливаем oh-my-zsh
    arch-chroot /mnt sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    # Устанавливаем плагины
    arch-chroot /mnt git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-/home/$USERNAME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    arch-chroot /mnt git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-/home/$USERNAME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    
    # Настраиваем .zshrc
    cat > /mnt/home/$USERNAME/.zshrc << EOF
export ZSH="/home/$USERNAME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh
EOF
    
    # Устанавливаем права
    arch-chroot /mnt chown -R $USERNAME:$USERNAME /home/$USERNAME/.oh-my-zsh
    arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/.zshrc
}

# === ФУНКЦИЯ: Финальная настройка пользователя и окружения ===
final_setup() {
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt systemctl enable pipewire pipewire-pulse wireplumber
    arch-chroot /mnt usermod -aG audio,video,network,wheel $USERNAME
    arch-chroot /mnt xdg-user-dirs-update
    arch-chroot /mnt chsh -s /bin/zsh $USERNAME
    
    # Настраиваем Wi-Fi
    setup_wifi
    
    # Настраиваем zsh
    setup_zsh
} 