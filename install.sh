#!/usr/bin/env bash
#
# Bootstrap an Arch Linux machine to mirror this setup.
# Idempotent: safe to re-run. Run as your normal user (NOT root); it calls
# sudo where needed.
#
#   git clone <repo> ~/dotfiles && cd ~/dotfiles && ./install.sh
#
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"

log()  { printf '\033[1;32m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SETUP_NVIDIA=0
usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --nvidia    Also configure NVIDIA drivers for boot/Wayland startup: ensure the
              nvidia modules are early-loaded in the initramfs, enable DRM
              modeset on the kernel cmdline, rebuild the initramfs and GRUB
              config, and enable the NVIDIA suspend/resume services. Edits
              /etc/mkinitcpio.conf and /etc/default/grub (timestamped backups
              are made first). Requires GRUB.
  -h, --help  Show this help and exit.
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --nvidia)  SETUP_NVIDIA=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
[ -f /etc/arch-release ] || die "This script targets Arch Linux."
[ "$(id -u)" -ne 0 ]      || die "Run as your normal user, not root."
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || warn "No internet? Continuing anyway."

# ---------------------------------------------------------------------------
# 1. System update + base tooling
# ---------------------------------------------------------------------------
log "Updating system and installing base tooling..."
sudo pacman -Syu --needed --noconfirm base-devel git

# ---------------------------------------------------------------------------
# 2. Bootstrap yay (AUR helper) if missing
# ---------------------------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
  log "Bootstrapping yay from the AUR..."
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  ( cd "$tmp/yay" && makepkg -si --noconfirm )
  rm -rf "$tmp"
else
  log "yay already installed."
fi

# ---------------------------------------------------------------------------
# 3. Install packages
# ---------------------------------------------------------------------------
log "Installing native (pacman) packages..."
sudo pacman -S --needed --noconfirm - < "$DOTFILES/packages/pacman.txt"

log "Installing AUR packages (this can take a while — some build from source)..."
yay -S --needed --noconfirm - < "$DOTFILES/packages/aur.txt"

# ---------------------------------------------------------------------------
# 4. Shell: oh-my-zsh + default shell
# ---------------------------------------------------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing oh-my-zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  log "oh-my-zsh already present."
fi

if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]; then
  log "Setting default shell to zsh..."
  chsh -s /usr/bin/zsh || warn "chsh failed; set your shell to zsh manually."
fi

# ---------------------------------------------------------------------------
# 5. Symlink configs and home dotfiles
# ---------------------------------------------------------------------------
# link SRC -> DEST, backing up an existing real DEST first.
link() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    return 0   # already linked correctly
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mkdir -p "$BACKUP_DIR$(dirname "${dest#"$HOME"}")"
    mv "$dest" "$BACKUP_DIR${dest#"$HOME"}"
    warn "backed up existing $dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  log "linked $dest"
}

log "Linking ~/.config entries..."
mkdir -p "$HOME/.config"
for src in "$DOTFILES"/config/*; do
  link "$src" "$HOME/.config/$(basename "$src")"
done

log "Linking home dotfiles..."
shopt -s dotglob nullglob
for src in "$DOTFILES"/home/*; do
  base="$(basename "$src")"
  case "$base" in .|..) continue;; esac
  link "$src" "$HOME/$base"
done
shopt -u dotglob nullglob

# ---------------------------------------------------------------------------
# 5b. Wallpapers (copied, not symlinked — referenced by hyprland.conf)
# ---------------------------------------------------------------------------
if [ -d "$DOTFILES/assets/wallpapers" ]; then
  log "Installing wallpapers to ~/Pictures/wallpapers..."
  mkdir -p "$HOME/Pictures/wallpapers"
  cp -n "$DOTFILES"/assets/wallpapers/* "$HOME/Pictures/wallpapers/" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 6. Enable services (only those whose unit exists)
# ---------------------------------------------------------------------------
enable_system() {
  if systemctl list-unit-files "$1" >/dev/null 2>&1 && \
     [ -n "$(systemctl list-unit-files "$1" 2>/dev/null | grep "$1")" ]; then
    log "enabling $1"
    sudo systemctl enable "$1" || warn "could not enable $1"
  else
    warn "unit $1 not found — skipping"
  fi
}

log "Enabling system services..."
enable_system NetworkManager.service
enable_system sddm.service
enable_system cups.socket
enable_system tailscaled.service
enable_system docker.service

# ---------------------------------------------------------------------------
# 6b. NVIDIA driver setup (opt-in via --nvidia)
# ---------------------------------------------------------------------------
setup_nvidia() {
  log "Configuring NVIDIA for boot / Wayland startup..."
  local ts mkconf=/etc/mkinitcpio.conf grubdef=/etc/default/grub
  local nv_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
  local regen_grub=0
  ts="$(date +%Y%m%d-%H%M%S)"

  # Ensure the driver userspace is present (normally already from pacman.txt).
  sudo pacman -S --needed --noconfirm nvidia-utils || warn "nvidia-utils install skipped"

  # 1. Early-load the nvidia modules in the initramfs.
  if [ -f "$mkconf" ] && grep -qE '^MODULES=.*nvidia_drm' "$mkconf"; then
    log "mkinitcpio MODULES already include nvidia."
  elif [ -f "$mkconf" ]; then
    sudo cp "$mkconf" "$mkconf.bak.$ts"
    sudo sed -i -E "s/^MODULES=\((.*)\)/MODULES=(\1 $nv_modules)/" "$mkconf"
    # tidy any leading/double spaces the substitution may introduce
    sudo sed -i -E 's/^MODULES=\( +/MODULES=(/; s/  +/ /g' "$mkconf"
    log "added nvidia modules to $mkconf (backup: $mkconf.bak.$ts)"
  else
    warn "$mkconf not found — skipping initramfs module setup"
  fi

  # 2. Enable DRM modeset on the kernel cmdline (canonical Wayland requirement).
  if [ -f "$grubdef" ] && grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*nvidia_drm\.modeset=1' "$grubdef"; then
    log "GRUB cmdline already enables nvidia_drm.modeset."
  elif [ -f "$grubdef" ]; then
    sudo cp "$grubdef" "$grubdef.bak.$ts"
    sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)"/\1\2 nvidia_drm.modeset=1"/' "$grubdef"
    sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=") +/\1/' "$grubdef"
    regen_grub=1
    log "added nvidia_drm.modeset=1 to $grubdef (backup: $grubdef.bak.$ts)"
  else
    warn "$grubdef not found — is this a GRUB system? Skipping cmdline edit."
  fi

  # 3. Rebuild the initramfs so the module changes take effect.
  log "Rebuilding initramfs (mkinitcpio -P)..."
  sudo mkinitcpio -P || warn "mkinitcpio failed — check output above"

  # 4. Regenerate GRUB config if the cmdline changed.
  if [ "$regen_grub" -eq 1 ]; then
    if [ -f /boot/grub/grub.cfg ]; then
      log "Regenerating GRUB config..."
      sudo grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed"
    else
      warn "/boot/grub/grub.cfg not found — apply the cmdline change with your bootloader manually."
    fi
  fi

  # 5. Enable suspend/resume services to avoid black screens on wake.
  enable_system nvidia-suspend.service
  enable_system nvidia-resume.service
  enable_system nvidia-hibernate.service

  log "NVIDIA setup done — changes take effect after a reboot."
}

if [ "$SETUP_NVIDIA" -eq 1 ]; then
  setup_nvidia
fi

# ---------------------------------------------------------------------------
# 7. Done
# ---------------------------------------------------------------------------
cat <<EOF

$(log "Bootstrap complete.")

Backups of any replaced files: $BACKUP_DIR
Next steps (manual — see system/README.md):
  * Reboot to start the display manager (sddm) and load NVIDIA drivers.
$( [ "$SETUP_NVIDIA" -eq 1 ] \
    && echo "  * NVIDIA boot setup was applied (--nvidia); the reboot activates it." \
    || echo "  * NVIDIA boot setup was NOT applied. Re-run with --nvidia, or see system/README.md." )
  * Re-add your secrets: SSH keys, GPG keys, ~/.aws, 1Password, API tokens.
  * Install tools that live outside pacman/AUR if you want them: Claude Code
    (claude.ai/install.sh), zen browser, uv, aws-sam; re-pull Ollama models.
  * Sign into apps (1Password, Chrome, Discord, Steam, etc.).
EOF
