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
# 7. Done
# ---------------------------------------------------------------------------
cat <<EOF

$(log "Bootstrap complete.")

Backups of any replaced files: $BACKUP_DIR
Next steps (manual — see system/README.md):
  * Reboot to start the display manager (sddm) and load NVIDIA drivers.
  * Review system/README.md for NVIDIA / Wayland / mkinitcpio notes (NOT applied automatically).
  * Re-add your secrets: SSH keys, GPG keys, ~/.aws, 1Password, API tokens.
  * Drop a wallpaper at ~/Pictures/wallpapers/jinx.jpg (referenced by hyprland.conf).
  * Sign into apps (1Password, Chrome, Discord, Steam, etc.).
EOF
