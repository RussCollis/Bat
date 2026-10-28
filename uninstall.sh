#!/usr/bin/env bash
#
# uninstall.sh - Completely removes bat, man pages, shell completions, and .pkg receipts
#
set -euo pipefail

DRY_RUN=0
FORCE=0
PURGE=0

# Formatting
BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
CYAN="$(tput setaf 6 2>/dev/null || printf '')"
RESET="$(tput sgr0 2>/dev/null || printf '')"

log_info() {
    printf "${CYAN}→${RESET} %s\n" "$1"
}

log_success() {
    printf "${GREEN}✔${RESET} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}⚠${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}✘${RESET} %s\n" "$1" >&2
}

display_path() {
    echo "$1" | sed "s|^$HOME|~|"
}

usage() {
    printf "%sbat Uninstaller (macOS)%s\n" "${BOLD}" "${RESET}"
    printf "Removes all bat installations, man pages, completions, and package receipts.\n\n"
    printf "%sUSAGE:%s\n" "${BOLD}" "${RESET}"
    printf "    ./uninstall.sh [OPTIONS]\n\n"
    printf "%sOPTIONS:%s\n" "${BOLD}" "${RESET}"
    printf "    -p, --purge     Also remove user config (~/.config/bat) and cache (~/.cache/bat).\n"
    printf "    -y, --yes       Skip confirmation prompt.\n"
    printf "    --dry-run       Show files that would be removed without deleting them.\n"
    printf "    -h, --help      Show this help message.\n\n"
    printf "%sEXAMPLES:%s\n" "${BOLD}" "${RESET}"
    printf "    ./uninstall.sh\n"
    printf "    ./uninstall.sh --purge\n"
    printf "    ./uninstall.sh --dry-run\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--purge)
            PURGE=1
            shift
            ;;
        -y|--yes)
            FORCE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run './uninstall.sh --help' for usage."
            exit 1
            ;;
    esac
done

printf "${BOLD}🦇 bat Uninstaller${RESET}\n"
printf "===================\n"

# Collect potential paths
FILES_TO_REMOVE=()
PKG_RECEIPTS=()

CANDIDATES=(
    # Binaries
    "$HOME/.local/bin/bat"
    "/usr/local/bin/bat"

    # Man pages
    "$HOME/.local/share/man/man1/bat.1"
    "/usr/local/share/man/man1/bat.1"

    # Shell Completions
    "$HOME/.zfunc/_bat"
    "/usr/local/share/zsh/site-functions/_bat"
    "$HOME/.config/fish/completions/bat.fish"
    "/usr/local/share/fish/vendor_completions.d/bat.fish"
    "$HOME/.local/share/bash-completion/completions/bat"
    "/usr/local/etc/bash_completion.d/bat"
)

if [[ "$PURGE" -eq 1 ]]; then
    CANDIDATES+=(
        "$HOME/.config/bat"
        "$HOME/.cache/bat"
    )
fi

# Check which candidates exist
for item in "${CANDIDATES[@]}"; do
    if [[ -e "$item" ]]; then
        FILES_TO_REMOVE+=("$item")
    fi
done

# Check if pkgutil receipt exists
if pkgutil --pkgs=io.github.sharkdp.bat >/dev/null 2>&1; then
    PKG_RECEIPTS+=("io.github.sharkdp.bat")
fi

if [[ ${#FILES_TO_REMOVE[@]} -eq 0 && ${#PKG_RECEIPTS[@]} -eq 0 ]]; then
    printf "${YELLOW}No installed 'bat' files or package receipts found.${RESET}\n"
    exit 0
fi

printf "Found the following components to remove:\n"
if [[ ${#FILES_TO_REMOVE[@]} -gt 0 ]]; then
    for f in "${FILES_TO_REMOVE[@]}"; do
        printf "  • %s\n" "$(display_path "$f")"
    done
fi

if [[ ${#PKG_RECEIPTS[@]} -gt 0 ]]; then
    for r in "${PKG_RECEIPTS[@]}"; do
        printf "  • Package receipt: %s\n" "$r"
    done
fi
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "${YELLOW}[DRY RUN] No files were removed.${RESET}\n"
    exit 0
fi

# Confirmation prompt unless -y / --yes
if [[ "$FORCE" -ne 1 ]]; then
    read -r -p "Are you sure you want to remove these files? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Uninstallation cancelled.\n"
            exit 0
            ;;
    esac
fi

# Remove files
if [[ ${#FILES_TO_REMOVE[@]} -gt 0 ]]; then
    for f in "${FILES_TO_REMOVE[@]}"; do
        if [[ -w "$(dirname "$f")" && (-w "$f" || ! -e "$f") ]]; then
            rm -rf "$f"
            log_success "Removed: $(display_path "$f")"
        else
            log_info "Elevated permissions required for $(display_path "$f")..."
            sudo rm -rf "$f"
            log_success "Removed (sudo): $(display_path "$f")"
        fi
    done
fi

# Forget pkg receipts
if [[ ${#PKG_RECEIPTS[@]} -gt 0 ]]; then
    for r in "${PKG_RECEIPTS[@]}"; do
        log_info "Forgetting package receipt $r..."
        sudo pkgutil --forget "$r" >/dev/null 2>&1 || true
        log_success "Forgot package receipt: $r"
    done
fi

printf "\n${GREEN}${BOLD}✔ bat has been completely removed from your system.${RESET}\n"
