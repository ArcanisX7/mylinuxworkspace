#!/usr/bin/env bash
# Idempotent installer for mylinuxworkspace (Debian 13 + Sway).
# Safe to run repeatedly: every step only changes what is missing or different.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stow packages (directories in the repo root) linked into $HOME.
STOW_PACKAGES=(sway)

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }

check_system() {
    if [[ $EUID -eq 0 ]]; then
        echo "Run as a regular user, not root. sudo is used where needed." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
        echo "This script targets Debian 13, found: ${PRETTY_NAME:-unknown}." >&2
        exit 1
    fi
}

install_packages() {
    log "Installing packages from packages.txt"
    local pkgs
    mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$REPO_DIR/packages.txt" | grep -v '^$')
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}"
}

link_dotfiles() {
    log "Linking dotfiles with stow"
    mkdir -p "$HOME/.config"
    local pkg
    for pkg in "${STOW_PACKAGES[@]}"; do
        stow --no-folding --restow --dir "$REPO_DIR" --target "$HOME" "$pkg"
    done
}

install_system_files() {
    log "Installing system files into /etc"
    local src dest grub_changed=0
    while IFS= read -r -d '' src; do
        dest="${src#"$REPO_DIR/system"}"
        if ! cmp -s "$src" "$dest"; then
            sudo install -D -m 0644 "$src" "$dest"
            echo "    updated $dest"
            if [[ "$dest" == /etc/default/grub* ]]; then
                grub_changed=1
            fi
        fi
    done < <(find "$REPO_DIR/system" -type f -print0)

    if (( grub_changed )); then
        log "Regenerating GRUB configuration"
        sudo update-grub
    fi
}

main() {
    check_system
    install_packages
    link_dotfiles
    install_system_files
    log "Done"
}

main "$@"
