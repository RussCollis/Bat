#!/usr/bin/env bash
#
# build_pkg.sh - Builds a standalone macOS .pkg installer for sharkdp/bat
# Creates a Universal 2 (Apple Silicon + Intel) macOS Installer package (.pkg)
#
set -euo pipefail

REPO="sharkdp/bat"
VERSION=""
OUTPUT_DIR="."
SIGN_IDENTITY=""
INSTALL_AFTER_BUILD=0

# Formatting
BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
CYAN="$(tput setaf 6 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
RESET="$(tput sgr0 2>/dev/null || printf '')"

log_info() {
    printf "${CYAN}→${RESET} %s\n" "$1"
}

log_success() {
    printf "${GREEN}✔${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}✘${RESET} %s\n" "$1" >&2
}

usage() {
    printf "%sbat macOS .pkg Builder%s\n" "${BOLD}" "${RESET}"
    printf "Generates a standalone Universal macOS Installer package (.pkg) for sharkdp/bat.\n\n"
    printf "%sUSAGE:%s\n" "${BOLD}" "${RESET}"
    printf "    ./build_pkg.sh [OPTIONS]\n\n"
    printf "%sOPTIONS:%s\n" "${BOLD}" "${RESET}"
    printf "    -v, --version <TAG>     Target release version (e.g. 'v0.26.1' or '0.26.1').\n"
    printf "                            Defaults to the latest GitHub release.\n"
    printf "    -o, --output-dir <DIR>  Directory to save the built .pkg (default: current directory).\n"
    printf "    -s, --sign <IDENTITY>   Developer ID Installer identity for code signing.\n"
    printf "    -i, --install           Install the built package immediately with 'installer'.\n"
    printf "    -h, --help              Show this help message.\n\n"
    printf "%sEXAMPLES:%s\n" "${BOLD}" "${RESET}"
    printf "    ./build_pkg.sh\n"
    printf "    ./build_pkg.sh --output-dir ~/Desktop\n"
    printf "    ./build_pkg.sh --sign \"Developer ID Installer: ACME Inc (ABC123XYZ)\"\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -i|--install)
            INSTALL_AFTER_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run './build_pkg.sh --help' for usage."
            exit 1
            ;;
    esac
done

OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
mkdir -p "$OUTPUT_DIR"

printf "${BOLD}🦇 bat macOS .pkg Builder${RESET}\n"
printf "=========================\n"

# Resolve version
if [[ -z "$VERSION" ]]; then
    log_info "Querying latest release from $REPO..."
    TAG=$(curl -sSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)
    if [[ -z "$TAG" ]]; then
        TAG=$(curl -sI "https://github.com/$REPO/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n')
    fi
    if [[ -z "$TAG" ]]; then
        log_error "Failed to resolve latest release tag from GitHub."
        exit 1
    fi
else
    if [[ "$VERSION" != v* ]]; then
        TAG="v$VERSION"
    else
        TAG="$VERSION"
    fi
fi

RAW_VERSION="${TAG#v}"
log_info "Building package for bat ${TAG}..."

# Setup temporary working environment
WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARM64_ASSET="bat-${TAG}-aarch64-apple-darwin.tar.gz"
X86_64_ASSET="bat-${TAG}-x86_64-apple-darwin.tar.gz"

log_info "Downloading Apple Silicon (arm64) binary..."
curl -sSL -o "$WORK_DIR/$ARM64_ASSET" "https://github.com/$REPO/releases/download/${TAG}/${ARM64_ASSET}"

log_info "Downloading Intel (x86_64) binary..."
curl -sSL -o "$WORK_DIR/$X86_64_ASSET" "https://github.com/$REPO/releases/download/${TAG}/${X86_64_ASSET}"

# Extract both architectures
mkdir -p "$WORK_DIR/arm64" "$WORK_DIR/x86_64"
tar -xzf "$WORK_DIR/$ARM64_ASSET" -C "$WORK_DIR/arm64"
tar -xzf "$WORK_DIR/$X86_64_ASSET" -C "$WORK_DIR/x86_64"

ARM64_DIR=$(find "$WORK_DIR/arm64" -maxdepth 1 -type d -name "bat-*" | head -n 1)
X86_64_DIR=$(find "$WORK_DIR/x86_64" -maxdepth 1 -type d -name "bat-*" | head -n 1)

# Build Payload root hierarchy
PAYLOAD_DIR="$WORK_DIR/payload"
mkdir -p "$PAYLOAD_DIR/usr/local/bin"
mkdir -p "$PAYLOAD_DIR/usr/local/share/man/man1"
mkdir -p "$PAYLOAD_DIR/usr/local/share/zsh/site-functions"
mkdir -p "$PAYLOAD_DIR/usr/local/share/fish/vendor_completions.d"
mkdir -p "$PAYLOAD_DIR/usr/local/etc/bash_completion.d"

# Create Universal 2 binary with lipo
log_info "Creating Universal 2 binary with lipo (arm64 + x86_64)..."
lipo -create \
    "$ARM64_DIR/bat" \
    "$X86_64_DIR/bat" \
    -output "$PAYLOAD_DIR/usr/local/bin/bat"

chmod 755 "$PAYLOAD_DIR/usr/local/bin/bat"

# Copy man page
if [[ -f "$ARM64_DIR/bat.1" ]]; then
    cp "$ARM64_DIR/bat.1" "$PAYLOAD_DIR/usr/local/share/man/man1/bat.1"
fi

# Copy shell completions
if [[ -f "$ARM64_DIR/autocomplete/bat.zsh" ]]; then
    cp "$ARM64_DIR/autocomplete/bat.zsh" "$PAYLOAD_DIR/usr/local/share/zsh/site-functions/_bat"
fi
if [[ -f "$ARM64_DIR/autocomplete/bat.fish" ]]; then
    cp "$ARM64_DIR/autocomplete/bat.fish" "$PAYLOAD_DIR/usr/local/share/fish/vendor_completions.d/bat.fish"
fi
if [[ -f "$ARM64_DIR/autocomplete/bat.bash" ]]; then
    cp "$ARM64_DIR/autocomplete/bat.bash" "$PAYLOAD_DIR/usr/local/etc/bash_completion.d/bat"
fi

# Prepare postinstall script
SCRIPTS_DIR="$WORK_DIR/scripts"
mkdir -p "$SCRIPTS_DIR"
cat << 'EOF' > "$SCRIPTS_DIR/postinstall"
#!/bin/sh
# Ensure permissions
chown -R root:admin /usr/local/bin/bat
chmod 755 /usr/local/bin/bat

# Clear Gatekeeper quarantine attribute
xattr -d com.apple.quarantine /usr/local/bin/bat 2>/dev/null || true

# Test execution
if /usr/local/bin/bat --version >/dev/null 2>&1; then
    exit 0
else
    echo "bat installation test failed" >&2
    exit 1
fi
EOF
chmod 755 "$SCRIPTS_DIR/postinstall"

# Prepare Resources (Welcome HTML, License)
RESOURCES_DIR="$WORK_DIR/resources"
mkdir -p "$RESOURCES_DIR"

if [[ -f "$ARM64_DIR/LICENSE-MIT" ]]; then
    cp "$ARM64_DIR/LICENSE-MIT" "$RESOURCES_DIR/LICENSE.txt"
fi

cat << EOF > "$RESOURCES_DIR/welcome.html"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.6; }
h1 { font-size: 18px; margin-bottom: 6px; }
.badge { background: #333; color: #fff; padding: 2px 6px; border-radius: 4px; font-size: 11px; }
ul { padding-left: 20px; }
code { background: #f0f0f0; padding: 2px 4px; border-radius: 3px; font-family: ui-monospace, Menlo, Monaco, monospace; }
</style>
</head>
<body>
<h1>bat <span class="badge">v${RAW_VERSION}</span></h1>
<p><strong>A cat clone with syntax highlighting and Git integration.</strong></p>
<p>This package installs the official precompiled Universal binary (Apple Silicon and Intel) directly into macOS without requiring Homebrew:</p>
<ul>
    <li>Executable: <code>/usr/local/bin/bat</code></li>
    <li>Man page: <code>/usr/local/share/man/man1/bat.1</code></li>
    <li>Shell completions for Zsh, Fish, and Bash</li>
</ul>
<p>Project homepage: <a href="https://github.com/sharkdp/bat">https://github.com/sharkdp/bat</a></p>
</body>
</html>
EOF

# Build component package with pkgbuild
log_info "Building component package with pkgbuild..."
COMPONENT_PKG="$WORK_DIR/bat-component.pkg"
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "io.github.sharkdp.bat" \
    --version "$RAW_VERSION" \
    --install-location "/" \
    "$COMPONENT_PKG"

# Build distribution XML
DIST_XML="$WORK_DIR/Distribution.xml"
cat << EOF > "$DIST_XML"
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>bat ${TAG}</title>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="LICENSE.txt" mime-type="text/plain"/>
    <choices-outline>
        <line choice="default">
            <line choice="io.github.sharkdp.bat"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="io.github.sharkdp.bat" visible="false">
        <pkg-ref id="io.github.sharkdp.bat"/>
    </choice>
    <pkg-ref id="io.github.sharkdp.bat" version="${RAW_VERSION}" onConclusion="none">bat-component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Build final distribution package with productbuild
OUTPUT_PKG_NAME="bat-${RAW_VERSION}-universal.pkg"
FINAL_PKG="$OUTPUT_DIR/$OUTPUT_PKG_NAME"

log_info "Synthesizing distribution package with productbuild..."
if [[ -n "$SIGN_IDENTITY" ]]; then
    log_info "Signing package with identity: $SIGN_IDENTITY"
    productbuild \
        --distribution "$DIST_XML" \
        --package-path "$WORK_DIR" \
        --resources "$RESOURCES_DIR" \
        --sign "$SIGN_IDENTITY" \
        "$FINAL_PKG"
else
    productbuild \
        --distribution "$DIST_XML" \
        --package-path "$WORK_DIR" \
        --resources "$RESOURCES_DIR" \
        "$FINAL_PKG"
fi

PKG_SIZE="$(du -h "$FINAL_PKG" | awk '{print $1}')"
printf "\n${GREEN}${BOLD}✔ Successfully created macOS Installer Package!${RESET}\n"
printf "  Package: %s\n" "$FINAL_PKG"
printf "  Version: %s\n" "$TAG"
printf "  Arch:    Universal 2 (arm64 + x86_64)\n"
printf "  Size:    %s\n\n" "$PKG_SIZE"

if [[ "$INSTALL_AFTER_BUILD" -eq 1 ]]; then
    log_info "Installing package to /..."
    sudo installer -pkg "$FINAL_PKG" -target /
    log_success "bat installed successfully to /usr/local/bin/bat"
    /usr/local/bin/bat --version
fi
