sudo pacman -S --needed mesa vulkan-radeon linux-firmware mesa-utils vulkan-tools libva-utils libva-mesa-driver lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver quickshell qt6-declarative hyprland ttf-jetbrains-mono-nerd cliphist wl-clipboard hyprlock curl procps-ng nano networkmanager bluez bluez-utils pipewire wireplumber pipewire-pulse playerctl upower rtkit hypridle power-profiles-daemon ddcutil xdg-user-dirs hyprshot

getent group i2c || sudo groupadd i2c
sudo usermod -aG i2c $USER

xdg-user-dirs-update
