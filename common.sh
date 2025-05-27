#!/bin/bash
# -*- coding: utf-8 -*-

# Set encoding
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# === SETTINGS ===
DISK="/dev/sda"   # Change if needed
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"

# Variables to be set by user
USERNAME=""
HOSTNAME=""
USERPASS=""
ROOTPASS=""
WIFI_SSID=""
WIFI_PASS=""

# Load configuration if exists
if [ -f /root/install_config ]; then
    source /root/install_config
fi

# === FUNCTION: Disk Selection ===
select_disk() {
    echo "=== Available Disks ==="
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
    echo
    read -p "Enter disk name (e.g., sda): " DISK
    DISK="/dev/$DISK"
    
    # Check if disk exists
    if [ ! -b "$DISK" ]; then
        echo "Error: Disk $DISK not found!"
        exit 1
    fi
    
    # Check disk size (minimum 20GB)
    DISK_SIZE=$(lsblk -b -d -o SIZE "$DISK" | tail -n1)
    MIN_SIZE=$((20*1024*1024*1024)) # 20GB in bytes
    
    if [ "$DISK_SIZE" -lt "$MIN_SIZE" ]; then
        echo "Error: Disk too small! Minimum 20GB required"
        exit 1
    fi
    
    echo "Selected disk: $DISK"
    echo "Size: $((DISK_SIZE/1024/1024/1024))GB"
}

# === FUNCTION: Disk Partitioning and Formatting ===
partition_and_format_disk() {
    echo "WARNING! All data on $DISK will be deleted!"
    sleep 3
    
    # Partitioning: EFI (512M), swap (2G), root (rest)
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary linux-swap 513MiB 2561MiB
    parted -s "$DISK" mkpart primary ext4 2561MiB 100%

    # Formatting
    mkfs.fat -F32 ${DISK}1
    mkswap ${DISK}2
    mkfs.ext4 ${DISK}3

    # Mounting
    mount ${DISK}3 /mnt
    mkdir -p /mnt/boot/efi
    mount ${DISK}1 /mnt/boot/efi
    swapon ${DISK}2
}

# Root check
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# === FUNCTION: System and Package Installation ===
install_base_system() {
    pacstrap /mnt base linux linux-firmware
    genfstab -U /mnt >> /mnt/etc/fstab
    cp packages.txt /mnt/root/packages.txt
}

# === FUNCTION: Wi-Fi Setup ===
setup_wifi() {
    if [ -z "$WIFI_SSID" ]; then
        read -p "Enter Wi-Fi network name: " WIFI_SSID
        read -s -p "Enter Wi-Fi password: " WIFI_PASS
        echo
    fi
    
    # Save Wi-Fi settings
    echo "WIFI_SSID=\"$WIFI_SSID\"" >> /tmp/install_config
    echo "WIFI_PASS=\"$WIFI_PASS\"" >> /tmp/install_config
    
    # Configure Wi-Fi
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"
}

# === FUNCTION: zsh Setup with oh-my-zsh ===
setup_zsh() {
    # Install oh-my-zsh
    arch-chroot /mnt sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    # Install plugins
    arch-chroot /mnt git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-/home/$USERNAME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    arch-chroot /mnt git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-/home/$USERNAME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    
    # Configure .zshrc
    cat > /mnt/home/$USERNAME/.zshrc << EOF
export ZSH="/home/$USERNAME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh
EOF
    
    # Set permissions
    arch-chroot /mnt chown -R $USERNAME:$USERNAME /home/$USERNAME/.oh-my-zsh
    arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/.zshrc
}

# === FUNCTION: Final User and Environment Setup ===
final_setup() {
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt systemctl enable pipewire pipewire-pulse wireplumber
    arch-chroot /mnt usermod -aG audio,video,network,wheel $USERNAME
    arch-chroot /mnt xdg-user-dirs-update
    arch-chroot /mnt chsh -s /bin/zsh $USERNAME
    
    # Setup Wi-Fi
    setup_wifi
    
    # Setup zsh
    setup_zsh
}

# === FUNCTIONS: Autorun and Continuation ===
add_autorun() {
    echo "/root/install.sh" >> /mnt/root/.bash_profile
}
remove_autorun() {
    arch-chroot /mnt sed -i '/install.sh/d' /root/.bash_profile
}

# === FUNCTION: System and Package Installation ===
install_all_packages() {
    # Increase parallel downloads
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf
    
    # Update system
    arch-chroot /mnt pacman -Sy --noconfirm
    
    # Install packages in parallel
    local packages=($(cat /mnt/root/packages.txt))
    local total=${#packages[@]}
    local current=0
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        echo -ne "\rInstalling packages: [$current/$total] ($((current*100/total))%)"
        arch-chroot /mnt pacman -S --noconfirm "$pkg" > /dev/null 2>&1
    done
    echo
}

# === FUNCTION: Basic System Setup ===
setup_system() {
    # Locale and encoding setup
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "LC_ALL=en_US.UTF-8" >> /mnt/etc/locale.conf
    
    # Other settings
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    echo "$HOSTNAME" > /mnt/etc/hostname
    echo "127.0.0.1   localhost" > /mnt/etc/hosts
    echo "::1         localhost" >> /mnt/etc/hosts
    echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /mnt/etc/hosts
    echo -e "$ROOTPASS\n$ROOTPASS" | arch-chroot /mnt passwd
    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh $USERNAME
    echo -e "$USERPASS\n$USERPASS" | arch-chroot /mnt passwd $USERNAME
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
}

# === FUNCTION: Bootloader Installation ===
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
