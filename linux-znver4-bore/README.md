# linux-znver4-bore

Kernel personalizado para **AMD Ryzen 7 255 (Zen 4) + Radeon 780M**, basado en
el paquete oficial `linux` de Arch (7.0.13.arch1) con:

- **Scheduler BORE** (CachyOS 7.0) — mejor responsividad en escritorio.
- **Parche cgroup-vram** (CachyOS 7.0) — útil para gestionar VRAM de la iGPU.
- **`-march=znver4 -mtune=znver4`** — optimización para Zen 4.

Se instala EN PARALELO a tu kernel `linux` stock (pkgbase distinto). Si algo
falla, arrancas con el kernel normal desde el menú de systemd-boot.

## Cómo aplicarlo

```bash
# 1. Dependencias de compilación (una vez)
sudo pacman -S --needed base-devel

# 2. Copia el preset UKI ANTES de instalar (clave para systemd-boot)
sudo cp linux-znver4-bore.preset /etc/mkinitcpio.d/linux-znver4-bore.preset

# 3. Compila (descarga ~150 MB de fuentes; tarda ~30-90 min)
cd ~/linux-znver4-bore
makepkg -s

# 4. Instala kernel + headers
sudo pacman -U linux-znver4-bore-*.pkg.tar.zst

# 5. (sólo si makepkg generó el UKI con preset por defecto) regenera el UKI
sudo mkinitcpio -p linux-znver4-bore

# 6. Reinicia y elige "arch-linux-znver4-bore" en el menú de systemd-boot
```

## Desinstalar / volver atrás

```bash
sudo pacman -R linux-znver4-bore linux-znver4-bore-headers
sudo rm -f /boot/EFI/Linux/arch-linux-znver4-bore.efi
sudo rm -f /etc/mkinitcpio.d/linux-znver4-bore.preset
```

Tu kernel stock `linux` nunca se toca, así que siempre tienes arranque seguro.
