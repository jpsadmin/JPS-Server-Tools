#!/bin/bash
#===============================================================================
# JPS Server Tools - Installer
#
# Installs the JPS Server Tools suite to /opt/jps-server-tools/
# and creates symlinks in /usr/local/bin/ for easy access.
#
# Usage:
#   sudo ./install.sh          # Standard install
#   sudo ./install.sh --check  # Check dependencies only
#   sudo ./install.sh --remove # Uninstall
#
# Requirements:
#   - Root privileges
#   - Ubuntu 24.04 LTS (or compatible)
#   - jq (for JSON processing)
#   - WP-CLI (for WordPress operations)
#===============================================================================

set -euo pipefail

#===============================================================================
# CONFIGURATION
#===============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly INSTALL_DIR="/opt/jps-server-tools"
readonly BIN_LINKS_DIR="/usr/local/bin"

# Colors (inline since we can't source common.sh yet)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly BOLD='\033[1m'
    readonly RESET='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly BOLD=''
    readonly RESET=''
fi

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

success() {
    echo -e "${GREEN}[OK]${RESET} $*"
}

header() {
    echo ""
    echo -e "${BOLD}=== $* ===${RESET}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

#===============================================================================
# DEPENDENCY CHECKS
#===============================================================================

# List of required commands
REQUIRED_COMMANDS=(
    "bash:Shell interpreter"
    "awk:Text processing"
    "sed:Text transformation"
    "grep:Pattern matching"
    "curl:HTTP client"
    "openssl:SSL/TLS operations"
    "md5sum:Checksum calculation"
    "df:Disk usage"
    "free:Memory information"
    "ss:Socket statistics"
    "tar:Archive extraction"
)

# Optional but recommended commands
OPTIONAL_COMMANDS=(
    "jq:JSON processing (required for --json output)"
    "wp:WP-CLI (required for WordPress operations)"
    "fail2ban-client:Fail2ban status"
    "ufw:Firewall status"
    "unzip:ZIP archive extraction"
)

# Check dependencies
check_dependencies() {
    header "Checking Dependencies"

    local missing_required=()
    local missing_optional=()

    # Check required commands
    echo "Required commands:"
    for item in "${REQUIRED_COMMANDS[@]}"; do
        local cmd="${item%%:*}"
        local desc="${item#*:}"

        if command_exists "$cmd"; then
            echo -e "  ${GREEN}✓${RESET} $cmd - $desc"
        else
            echo -e "  ${RED}✗${RESET} $cmd - $desc"
            missing_required+=("$cmd")
        fi
    done

    echo ""
    echo "Optional commands:"
    for item in "${OPTIONAL_COMMANDS[@]}"; do
        local cmd="${item%%:*}"
        local desc="${item#*:}"

        if command_exists "$cmd"; then
            echo -e "  ${GREEN}✓${RESET} $cmd - $desc"
        else
            echo -e "  ${YELLOW}○${RESET} $cmd - $desc (not installed)"
            missing_optional+=("$cmd")
        fi
    done

    echo ""

    # Report missing dependencies
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_required[*]}"
        echo "Install with: apt install ${missing_required[*]}"
        return 1
    fi

    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        warn "Some optional dependencies are missing"
        echo ""
        echo "To install optional dependencies:"

        # Check for jq
        if [[ " ${missing_optional[*]} " =~ " jq " ]]; then
            echo "  apt install jq"
        fi

        # Check for WP-CLI
        if [[ " ${missing_optional[*]} " =~ " wp " ]]; then
            echo "  # Install WP-CLI:"
            echo "  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
            echo "  chmod +x wp-cli.phar"
            echo "  mv wp-cli.phar /usr/local/bin/wp"
        fi

        echo ""
    fi

    success "Dependency check passed"
    return 0
}

#===============================================================================
# INSTALLATION FUNCTIONS
#===============================================================================

# Get the source directory (where the installer is located)
get_source_dir() {
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_path"
}

# Install files
install_files() {
    header "Installing Files"

    local source_dir
    source_dir=$(get_source_dir)

    # Create installation directory
    info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"/{bin,lib,config,logs/{audit,backup-verify}}

    # Copy bin scripts
    info "Installing scripts..."
    if [[ -d "${source_dir}/bin" ]]; then
        cp -v "${source_dir}/bin/"* "$INSTALL_DIR/bin/" 2>/dev/null || true
    fi

    # Copy lib files
    info "Installing libraries..."
    if [[ -d "${source_dir}/lib" ]]; then
        cp -v "${source_dir}/lib/"* "$INSTALL_DIR/lib/" 2>/dev/null || true
    fi

    # Copy config (only if doesn't exist)
    if [[ ! -f "$INSTALL_DIR/config/jps-tools.conf" ]]; then
        info "Installing default configuration..."
        if [[ -f "${source_dir}/config/jps-tools.conf" ]]; then
            cp -v "${source_dir}/config/jps-tools.conf" "$INSTALL_DIR/config/"
        fi
    else
        info "Configuration file already exists, not overwriting"
        # Copy as example for reference
        if [[ -f "${source_dir}/config/jps-tools.conf" ]]; then
            cp -v "${source_dir}/config/jps-tools.conf" "$INSTALL_DIR/config/jps-tools.conf.example"
        fi
    fi

    # Make scripts executable
    info "Setting permissions..."
    chmod +x "$INSTALL_DIR/bin/"* 2>/dev/null || true
    chmod +x "$INSTALL_DIR/lib/"* 2>/dev/null || true

    success "Files installed to $INSTALL_DIR"
}

# Create symlinks
create_symlinks() {
    header "Creating Symlinks"

    local scripts=(
        "jps-audit"
        "jps-backup-verify"
        "jps-status"
        "jps-monitor"
    )

    for script in "${scripts[@]}"; do
        local source_path="$INSTALL_DIR/bin/$script"
        local link_path="$BIN_LINKS_DIR/$script"

        if [[ -f "$source_path" ]]; then
            # Remove existing symlink if present
            if [[ -L "$link_path" ]]; then
                rm -f "$link_path"
            fi

            # Create symlink
            ln -sf "$source_path" "$link_path"
            success "Created symlink: $link_path -> $source_path"
        else
            warn "Script not found: $source_path"
        fi
    done
}

# Create log directories with proper permissions
setup_logs() {
    header "Setting Up Log Directories"

    local log_dirs=(
        "$INSTALL_DIR/logs"
        "$INSTALL_DIR/logs/audit"
        "$INSTALL_DIR/logs/backup-verify"
    )

    for dir in "${log_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            info "Created: $dir"
        fi
    done

    # Set permissions
    chmod 755 "$INSTALL_DIR/logs"
    chmod 755 "$INSTALL_DIR/logs/"*

    success "Log directories configured"
}

# Verify installation
verify_installation() {
    header "Verifying Installation"

    local errors=0

    # Check directories
    local required_dirs=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/bin"
        "$INSTALL_DIR/lib"
        "$INSTALL_DIR/config"
        "$INSTALL_DIR/logs"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo -e "  ${GREEN}✓${RESET} Directory exists: $dir"
        else
            echo -e "  ${RED}✗${RESET} Directory missing: $dir"
            ((errors++))
        fi
    done

    # Check files
    local required_files=(
        "$INSTALL_DIR/bin/jps-audit"
        "$INSTALL_DIR/bin/jps-backup-verify"
        "$INSTALL_DIR/bin/jps-status"
        "$INSTALL_DIR/bin/jps-monitor"
        "$INSTALL_DIR/lib/jps-common.sh"
        "$INSTALL_DIR/config/jps-tools.conf"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "  ${GREEN}✓${RESET} File exists: $file"
        else
            echo -e "  ${RED}✗${RESET} File missing: $file"
            ((errors++))
        fi
    done

    # Check symlinks
    local symlinks=(
        "$BIN_LINKS_DIR/jps-audit"
        "$BIN_LINKS_DIR/jps-backup-verify"
        "$BIN_LINKS_DIR/jps-status"
        "$BIN_LINKS_DIR/jps-monitor"
    )

    for link in "${symlinks[@]}"; do
        if [[ -L "$link" ]]; then
            echo -e "  ${GREEN}✓${RESET} Symlink exists: $link"
        else
            echo -e "  ${RED}✗${RESET} Symlink missing: $link"
            ((errors++))
        fi
    done

    echo ""

    if [[ $errors -eq 0 ]]; then
        success "Installation verified successfully"
        return 0
    else
        error "Verification found $errors error(s)"
        return 1
    fi
}

# Show post-install instructions
show_instructions() {
    header "Installation Complete!"

    cat << EOF
${BOLD}Quick Start:${RESET}

  1. Edit the configuration file:
     ${BLUE}nano $INSTALL_DIR/config/jps-tools.conf${RESET}

  2. Run a server audit:
     ${BLUE}jps-audit${RESET}

  3. Verify a site backup:
     ${BLUE}jps-backup-verify example.com${RESET}

${BOLD}Available Commands:${RESET}

  ${GREEN}jps-audit${RESET}
    Comprehensive server state capture and drift detection.
    Options: --help, --brief, --json, --save, --diff

  ${GREEN}jps-backup-verify${RESET}
    Verify backup restoration integrity.
    Options: --help, --all, --report, --list

  ${GREEN}jps-status${RESET}
    Quick site inventory table.
    Options: --help, --json, --no-check, --domain

  ${GREEN}jps-monitor${RESET}
    Health monitoring for cron (silent when healthy).
    Options: --help, --verbose, --email, --json

${BOLD}Configuration:${RESET}

  Config file: $INSTALL_DIR/config/jps-tools.conf
  Log files:   $INSTALL_DIR/logs/

${BOLD}Documentation:${RESET}

  See README.md for full documentation
  Report issues: https://github.com/yourusername/jps-server-tools/issues

EOF
}

#===============================================================================
# UNINSTALL FUNCTION
#===============================================================================

uninstall() {
    header "Uninstalling JPS Server Tools"

    # Confirm
    read -rp "This will remove all JPS Server Tools. Continue? [y/N] " response
    if [[ ! "$response" =~ ^[yY]$ ]]; then
        echo "Uninstall cancelled"
        exit 0
    fi

    # Remove symlinks
    info "Removing symlinks..."
    rm -f "$BIN_LINKS_DIR/jps-audit"
    rm -f "$BIN_LINKS_DIR/jps-backup-verify"
    rm -f "$BIN_LINKS_DIR/jps-status"
    rm -f "$BIN_LINKS_DIR/jps-monitor"

    # Ask about logs
    read -rp "Remove log files as well? [y/N] " response
    if [[ "$response" =~ ^[yY]$ ]]; then
        info "Removing installation directory including logs..."
        rm -rf "$INSTALL_DIR"
    else
        info "Removing installation directory, preserving logs..."
        rm -rf "$INSTALL_DIR/bin"
        rm -rf "$INSTALL_DIR/lib"
        rm -f "$INSTALL_DIR/config/jps-tools.conf.example"
        # Keep config and logs
    fi

    success "JPS Server Tools has been uninstalled"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo -e "${BOLD}JPS Server Tools Installer v${SCRIPT_VERSION}${RESET}"
    echo "========================================"

    # Parse arguments
    case "${1:-}" in
        --check|-c)
            check_root
            check_dependencies
            exit $?
            ;;
        --remove|--uninstall|-r)
            check_root
            uninstall
            exit 0
            ;;
        --help|-h)
            cat << EOF
JPS Server Tools Installer

Usage:
  sudo ./install.sh           Install JPS Server Tools
  sudo ./install.sh --check   Check dependencies only
  sudo ./install.sh --remove  Uninstall JPS Server Tools
  sudo ./install.sh --help    Show this help message

Installation directory: $INSTALL_DIR
EOF
            exit 0
            ;;
        "")
            # Normal installation
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac

    # Run installation
    check_root
    check_dependencies || exit 1
    install_files
    create_symlinks
    setup_logs
    verify_installation || exit 1
    show_instructions
}

main "$@"
