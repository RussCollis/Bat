# bat Standalone macOS Installer & Packaging Tools

A complete set of tools to install, package, and manage [sharkdp/bat](https://github.com/sharkdp/bat) on macOS **without Homebrew (`brew`)**.

---

## Tool Overview

| Script / Tool | Purpose |
| :--- | :--- |
| [`install.sh`](file:///Users/russellcollis/Desktop/Bat/install.sh) | Zero-dependency shell script to download and install `bat` to `~/.local/bin` or `/usr/local/bin`. |
| [`build_pkg.sh`](file:///Users/russellcollis/Desktop/Bat/build_pkg.sh) | Builds a standalone Apple `.pkg` installer (Universal 2: `arm64` + `x86_64`). |
| [`uninstall.sh`](file:///Users/russellcollis/Desktop/Bat/uninstall.sh) | Completely removes all `bat` binaries, man pages, shell completions, and `.pkg` receipts. |
| **Swift CLI (`bat-installer`)** | Swift 6 CLI tool supporting `install`, `status`, `pkg`, and `uninstall` commands. |

---

## 1. Quick Installation

### Standalone Shell Script:
```bash
./install.sh
```
*(Preview changes first: `./install.sh --dry-run`)*

### Or Install via the macOS `.pkg` Package:
A ready-to-run package has been generated at:
```bash
~/Desktop/bat-0.26.1-universal.pkg
```
Double-click it in Finder, or install from the terminal:
```bash
sudo installer -pkg ~/Desktop/bat-0.26.1-universal.pkg -target /
```

---

## 2. Generating a Newer `.pkg` Installer

Whenever a new `bat` release is published on GitHub, you can generate a new Universal `.pkg` with:

```bash
./build_pkg.sh --output-dir ~/Desktop
```
*(Optionally sign it: `./build_pkg.sh --sign "Developer ID Installer: ..."`)*

---

## 3. Complete Uninstallation

To cleanly remove `bat` and all its associated files from your system:

```bash
./uninstall.sh
```

### Uninstaller Options:
| Flag | Description |
| :--- | :--- |
| `-p, --purge` | Also remove configuration (`~/.config/bat`) and cache (`~/.cache/bat`). |
| `-y, --yes` | Skip confirmation prompt. |
| `--dry-run` | Display what files would be deleted without removing them. |
| `-h, --help` | Show usage information. |

---

## 4. Swift CLI Tool (`bat-installer`)

```bash
# Install bat
swift run bat-installer

# Check installation status & available updates
swift run bat-installer status

# Build a Universal .pkg package
swift run bat-installer pkg -o ~/Desktop

# Uninstall bat
swift run bat-installer uninstall
```

---

## What Gets Installed

| Component | Standard Path |
| :--- | :--- |
| **Binary** | `/usr/local/bin/bat` (via `.pkg` / `--system`) or `~/.local/bin/bat` |
| **Man Page** | `/usr/local/share/man/man1/bat.1` or `~/.local/share/man/man1/bat.1` |
| **Zsh Completions** | `/usr/local/share/zsh/site-functions/_bat` or `~/.zfunc/_bat` |
| **Fish Completions** | `/usr/local/share/fish/vendor_completions.d/bat.fish` |
| **Bash Completions** | `/usr/local/etc/bash_completion.d/bat` |
