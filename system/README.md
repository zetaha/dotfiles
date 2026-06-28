# System-level notes (apply manually)

`install.sh` deliberately does **not** touch bootloader, initramfs, or kernel
parameters — these are machine-specific and dangerous to apply blindly. This
machine has an NVIDIA GPU running Hyprland (Wayland) on `nvidia-open`. Replicate
the bits below by hand on a fresh install.

## NVIDIA + Wayland

Packages (already in `packages/pacman.txt`): `nvidia-open`, `nvidia-open-lts`,
`nvidia-utils`, `lib32-nvidia-utils`, `nvidia-settings`, plus the `vulkan` /
`lib32` libs.

1. **Early KMS** — add the NVIDIA modules to `/etc/mkinitcpio.conf`:
   ```
   MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
   ```
   Then rebuild: `sudo mkinitcpio -P`.

2. **DRM modeset** — required for Wayland. Add to the kernel cmdline in
   `/etc/default/grub` (`GRUB_CMDLINE_LINUX_DEFAULT`):
   ```
   nvidia_drm.modeset=1
   ```
   Then: `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

3. **Environment** — Hyprland already exports the usual NVIDIA env vars in
   `config/hypr/hyprland.conf` if present; otherwise see the Hyprland wiki
   "NVIDIA" page for `LIBVA_DRIVER_NAME`, `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`.

## Display manager

`sddm.service` is enabled by `install.sh`. It launches the Hyprland session.

## mDNS / `.local` resolution (`nss-mdns`)

`nss-mdns` is installed. To resolve `.local` hostnames, edit `/etc/nsswitch.conf`
so the `hosts:` line reads (per the Arch wiki):
```
hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns
```

## Printing

`cups.socket` is enabled. Add printers via `system-config-printer` or the CUPS
web UI at <http://localhost:631>.

## Bootloader

This machine uses GRUB (`grub`, `efibootmgr`, `os-prober`). On a fresh install
configure GRUB per the Arch wiki for your firmware (UEFI vs BIOS). Not scripted.
