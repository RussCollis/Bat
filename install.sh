#!/usr/bin/env bash
#
# Standalone macOS Installer for sharkdp/bat (No Homebrew required)
# https://github.com/sharkdp/bat
#
set -euo pipefail

REPO="sharkdp/bat"
DEFAULT_INSTALL_DIR="$HOME/.local/bin"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
VERSION=""
INSTALL_MAN=1
INSTALL_COMPLETIONS=1
DRY_RUN=0
UNINSTALL=0

# Text formatting
BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
CYAN="$(tput setaf 6 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
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
    printf "%sbat Standalone Installer (macOS)%s\n" "${BOLD}" "${RESET}"
    printf "Install sharkdp/bat directly from official GitHub releases without Homebrew.\n\n"
    printf "%sUSAGE:%s\n" "${BOLD}" "${RESET}"
    printf "    ./install.sh [OPTIONS]\n\n"
    printf "%sOPTIONS:%s\n" "${BOLD}" "${RESET}"
    printf "    -v, --version <TAG>     Install a specific release version (e.g. 'v0.26.1' or '0.26.1').\n"
    printf "                            Defaults to the latest stable release.\n"
    printf "    -d, --dir <PATH>        Target directory for the 'bat' binary (default: ~/.local/bin).\n"
    printf "    --system                Install system-wide to /usr/local/bin (may require sudo).\n"
    printf "    --no-man                Skip installing man page (bat.1).\n"
    printf "    --no-completions        Skip installing shell completions (zsh, fish, bash).\n"
    printf "    --dry-run               Show what would be installed without making changes.\n"
    printf "    --uninstall             Uninstall bat binary, man pages, and completions.\n"
    printf "    -h, --help              Show this help message.\n\n"
    printf "%sEXAMPLES:%s\n" "${BOLD}" "${RESET}"
    printf "    ./install.sh\n"
    printf "    ./install.sh --version v0.26.1\n"
    printf "    ./install.sh --system\n"
    printf "    ./install.sh --uninstall\n"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --system)
            INSTALL_DIR="/usr/local/bin"
            shift
            ;;
        --no-man)
            INSTALL_MAN=0
            shift
            ;;
        --no-completions)
            INSTALL_COMPLETIONS=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run './install.sh --help' for usage."
            exit 1
            ;;
    esac
done

# Expand tilde in install directory if present
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# Handle Uninstallation
if [[ "$UNINSTALL" -eq 1 ]]; then
    printf "${BOLD}🦇 bat Uninstaller${RESET}\n"
    printf "===================\n"

    BINARY_PATH="$INSTALL_DIR/bat"
    if [[ -f "$BINARY_PATH" ]]; then
        rm -f "$BINARY_PATH"
        log_success "Removed binary: $(display_path "$BINARY_PATH")"
    else
        log_warn "Binary not found at $(display_path "$BINARY_PATH")"
    fi

    # Remove man page
    if [[ "$INSTALL_DIR" == "/usr/local/bin" ]]; then
        MAN_FILE="/usr/local/share/man/man1/bat.1"
    else
        MAN_FILE="$HOME/.local/share/man/man1/bat.1"
    fi
    if [[ -f "$MAN_FILE" ]]; then
        rm -f "$MAN_FILE"
        log_success "Removed manpage: $(display_path "$MAN_FILE")"
    fi

    # Remove completions
    for comp in "$HOME/.zfunc/_bat" "$HOME/.config/fish/completions/bat.fish" "$HOME/.local/share/bash-completion/completions/bat"; do
        if [[ -f "$comp" ]]; then
            rm -f "$comp"
            log_success "Removed completion: $(display_path "$comp")"
        fi
    done

    printf "\n${GREEN}Uninstallation complete.${RESET}\n"
    exit 0
fi

printf "${BOLD}🦇 bat Standalone Installer${RESET}\n"
printf "============================\n"

# Verify OS
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
    log_error "This installer is configured for macOS (Darwin). Detected: $OS"
    exit 1
fi

# Detect Architecture
ARCH="$(uname -m)"
case "$ARCH" in
    arm64|aarch64)
        TARGET_ARCH="aarch64"
        ARCH_NAME="Apple Silicon (arm64)"
        ;;
    x86_64)
        TARGET_ARCH="x86_64"
        ARCH_NAME="Intel (x86_64)"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
log_info "Detected platform: macOS ($ARCH_NAME)"

# Resolve Release Version Tag
if [[ -z "$VERSION" ]]; then
    log_info "Querying latest release from $REPO..."
    # Try GitHub API first
    TAG=$(curl -sSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)

    # Fallback to redirect inspection if API failed or rate-limited
    if [[ -z "$TAG" ]]; then
        TAG=$(curl -sI "https://github.com/$REPO/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n')
    fi

    if [[ -z "$TAG" ]]; then
        log_error "Could not determine latest release version from GitHub."
        echo "Please specify a version explicitly using: ./install.sh --version <tag>"
        exit 1
    fi
else
    # Ensure tag starts with 'v' if needed
    if [[ "$VERSION" != v* ]]; then
        TAG="v$VERSION"
    else
        TAG="$VERSION"
    fi
fi

ASSET_NAME="bat-${TAG}-${TARGET_ARCH}-apple-darwin.tar.gz"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/${TAG}/${ASSET_NAME}"
log_info "Target release: $TAG"

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "\n${YELLOW}[DRY RUN]${RESET} Would perform the following:\n"
    printf "  • Download URL: %s\n" "$DOWNLOAD_URL"
    printf "  • Install binary to: %s/bat\n" "$(display_path "$INSTALL_DIR")"
    if [[ "$INSTALL_MAN" -eq 1 ]]; then
        printf "  • Install manpage to: %s\n" "$(display_path "$HOME/.local/share/man/man1/bat.1")"
    fi
    if [[ "$INSTALL_COMPLETIONS" -eq 1 ]]; then
        printf "  • Install shell completions (zsh, fish, bash)\n"
    fi
    exit 0
fi

# Create temporary directory for download and extraction
TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Download Asset
log_info "Downloading $ASSET_NAME..."
HTTP_STATUS=$(curl -sSL -w "%{http_code}" -o "$TMP_DIR/$ASSET_NAME" "$DOWNLOAD_URL")
if [[ "$HTTP_STATUS" -ne 200 ]]; then
    log_error "Download failed with HTTP status $HTTP_STATUS"
    exit 1
fi

# Extract
log_info "Extracting archive..."
tar -xzf "$TMP_DIR/$ASSET_NAME" -C "$TMP_DIR"

EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "bat-*" | head -n 1)
if [[ -z "$EXTRACTED_DIR" || ! -f "$EXTRACTED_DIR/bat" ]]; then
    log_error "Failed to locate extracted 'bat' binary in release archive."
    exit 1
fi

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# Install binary
TARGET_BIN="$INSTALL_DIR/bat"
log_info "Installing binary to $(display_path "$TARGET_BIN")..."
cp "$EXTRACTED_DIR/bat" "$TARGET_BIN"
chmod 755 "$TARGET_BIN"

# Remove quarantine attribute so Gatekeeper allows immediate execution
xattr -d com.apple.quarantine "$TARGET_BIN" 2>/dev/null || true

# Verify executable
log_info "Verifying binary..."
INSTALLED_VER=$("$TARGET_BIN" --version 2>/dev/null || true)
if [[ -z "$INSTALLED_VER" ]]; then
    log_error "Binary verification failed."
    exit 1
fi
log_success "Verified: $INSTALLED_VER"

# Install man page
if [[ "$INSTALL_MAN" -eq 1 && -f "$EXTRACTED_DIR/bat.1" ]]; then
    if [[ "$INSTALL_DIR" == "/usr/local/bin" ]]; then
        MAN_DIR="/usr/local/share/man/man1"
    else
        MAN_DIR="$HOME/.local/share/man/man1"
    fi
    mkdir -p "$MAN_DIR"
    cp "$EXTRACTED_DIR/bat.1" "$MAN_DIR/bat.1"
    log_success "Installed man page to $(display_path "$MAN_DIR/bat.1")"
fi

# Install shell completions
if [[ "$INSTALL_COMPLETIONS" -eq 1 ]]; then
    # ZSH
    if [[ -f "$EXTRACTED_DIR/autocomplete/bat.zsh" ]]; then
        ZFUNC_DIR="$HOME/.zfunc"
        mkdir -p "$ZFUNC_DIR"
        cp "$EXTRACTED_DIR/autocomplete/bat.zsh" "$ZFUNC_DIR/_bat"
        log_success "Installed zsh completions to $(display_path "$ZFUNC_DIR/_bat")"
    fi

    # Fish
    if [[ -f "$EXTRACTED_DIR/autocomplete/bat.fish" ]]; then
        FISH_DIR="$HOME/.config/fish/completions"
        mkdir -p "$FISH_DIR"
        cp "$EXTRACTED_DIR/autocomplete/bat.fish" "$FISH_DIR/bat.fish"
        log_success "Installed fish completions to $(display_path "$FISH_DIR/bat.fish")"
    fi

    # Bash
    if [[ -f "$EXTRACTED_DIR/autocomplete/bat.bash" ]]; then
        BASH_DIR="$HOME/.local/share/bash-completion/completions"
        mkdir -p "$BASH_DIR"
        cp "$EXTRACTED_DIR/autocomplete/bat.bash" "$BASH_DIR/bat"
        log_success "Installed bash completions to $(display_path "$BASH_DIR/bat")"
    fi
fi

printf "\n${GREEN}${BOLD}🎉 Installation Complete!${RESET}\n"

# Check if target directory is in PATH
case ":$PATH:" in
    *":$INSTALL_DIR:"*)
        printf "Run %sbat --help%s to get started.\n" "${BOLD}" "${RESET}"
        ;;
    *)
        log_warn "$(display_path "$INSTALL_DIR") is not in your \$PATH."
        printf "To access 'bat' globally, add this to your ~/.zshrc:\n\n"
        printf "    ${CYAN}export PATH=\"%s:\$PATH\"${RESET}\n\n" "$(display_path "$INSTALL_DIR")"
        printf "Then restart your terminal or run: ${CYAN}source ~/.zshrc${RESET}\n"
        ;;
esac
