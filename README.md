# dotfiles

Reproducible Arch Linux setup: packages, configs, and theming for a
Hyprland (Wayland) desktop on NVIDIA.

## What's here

```
install.sh            Idempotent bootstrap script (run on a fresh Arch install)
packages/
  pacman.txt          Native explicitly-installed packages
  aur.txt             AUR packages (installed via yay; yay itself is bootstrapped)
config/               Symlinked into ~/.config/
  hypr/               Hyprland compositor
  waybar/             Status bar
  wofi/               App launcher
  ghostty/ kitty/     Terminals
  btop/               System monitor
  swappy/             Screenshot annotation
  gtk-3.0/ gtk-4.0/   GTK theme (Adwaita-dark)
  xdg-desktop-portal/ Portal routing (dark-mode / prefers-color-scheme)
  nvim/               Neovim config
home/
  .zshrc              Shell config (oh-my-zsh, installed fresh by the script)
system/
  README.md           Manual, machine-specific steps (NVIDIA, mkinitcpio, GRUB)
```

## Usage (fresh machine)

```bash
git clone <this-repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script will:
1. `pacman -Syu` and install `base-devel git`.
2. Bootstrap `yay`.
3. Install everything in `packages/`.
4. Install oh-my-zsh and set zsh as the default shell.
5. Symlink `config/*` → `~/.config/*` and `home/*` → `~/` (existing files are
   backed up to `~/.dotfiles-backup/<timestamp>/`).
6. Enable services that exist: NetworkManager, sddm, cups, tailscaled, docker.

Then read **`system/README.md`** and apply the NVIDIA / bootloader steps by hand,
and reboot.

## Not included (by design)

Secrets are never committed: SSH/GPG keys, `~/.aws`, `~/.1password`,
`~/.claude.json`, Docker creds, shell history, API tokens. Re-add these manually
after install. A defensive `.gitignore` blocks these patterns.

## Updating the repo

Because configs are **symlinked**, editing e.g. `~/.config/hypr/hyprland.conf`
edits the file in this repo directly. Commit and push to capture changes. To
refresh the package lists:

```bash
pacman -Qqen > packages/pacman.txt
pacman -Qqem | grep -vE '^(yay|yay-debug)$' > packages/aur.txt
```
