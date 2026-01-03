#!/bin/bash
#===============================================================================
# JPS Server Tools - Common Library
# Shared functions used by all JPS server management scripts
#===============================================================================

# Prevent multiple sourcing
[[ -n "${_JPS_COMMON_LOADED:-}" ]] && return 0
readonly _JPS_COMMON_LOADED=1

#===============================================================================
# CONFIGURATION
#===============================================================================

# Default paths (can be overridden by config file)
readonly JPS_INSTALL_DIR="${JPS_INSTALL_DIR:-/opt/jps-server-tools}"
readonly JPS_CONFIG_FILE="${JPS_CONFIG_FILE:-${JPS_INSTALL_DIR}/config/jps-tools.conf}"

# Script identification (set by calling script)
: "${SCRIPT_NAME:=jps-tools}"
: "${SCRIPT_VERSION:=1.0.0}"

#===============================================================================
# COLOR OUTPUT
# Terminal colors for formatted output
# All functions check if stdout is a terminal before using colors
#===============================================================================

# Define colors only if terminal supports them
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_MAGENTA='\033[0;35m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_WHITE='\033[0;37m'
    readonly COLOR_BOLD='\033[1m'
    readonly COLOR_DIM='\033[2m'
else
    readonly COLOR_RESET=''
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_MAGENTA=''
    readonly COLOR_CYAN=''
    readonly COLOR_WHITE=''
    readonly COLOR_BOLD=''
    readonly COLOR_DIM=''
fi

# info() - Display informational message in blue
# Usage: info "Processing files..."
info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

# warn() - Display warning message in yellow
# Usage: warn "Disk usage above 80%"
warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

# error() - Display error message in red
# Usage: error "Failed to connect to database"
error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

# success() - Display success message in green
# Usage: success "Backup completed successfully"
success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
}

# debug() - Display debug message if DEBUG is set
# Usage: DEBUG=1 script.sh  then  debug "Variable value: $var"
debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${COLOR_DIM}[DEBUG]${COLOR_RESET} $*" >&2
    fi
}

# header() - Display a section header
# Usage: header "System Information"
header() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== $* ===${COLOR_RESET}"
    echo ""
}

# subheader() - Display a subsection header
# Usage: subheader "Memory Usage"
subheader() {
    echo -e "${COLOR_BOLD}--- $* ---${COLOR_RESET}"
}

# status_line() - Display a status line with label and value
# Usage: status_line "CPU Usage" "45%"
status_line() {
    local label="$1"
    local value="$2"
    local status="${3:-}"  # Optional: ok, warn, error

    local value_color=""
    case "$status" in
        ok|good|pass)   value_color="$COLOR_GREEN" ;;
        warn|warning)   value_color="$COLOR_YELLOW" ;;
        error|fail|bad) value_color="$COLOR_RED" ;;
        *)              value_color="$COLOR_WHITE" ;;
    esac

    printf "  %-30s ${value_color}%s${COLOR_RESET}\n" "$label:" "$value"
}

#===============================================================================
# LOGGING
# Functions for writing to log files
#===============================================================================

# log_to_file() - Append timestamped message to specified log file
# Usage: log_to_file "/var/log/script.log" "Operation completed"
# Creates parent directories if they don't exist
log_to_file() {
    local log_file="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create log directory if it doesn't exist
    local log_dir
    log_dir=$(dirname "$log_file")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            error "Cannot create log directory: $log_dir"
            return 1
        }
    fi

    # Append timestamped message to log file
    echo "[$timestamp] [$SCRIPT_NAME] $message" >> "$log_file" 2>/dev/null || {
        error "Cannot write to log file: $log_file"
        return 1
    }
}

# log_json() - Write JSON object to log file
# Usage: log_json "/var/log/audit.json" "$json_data"
log_json() {
    local log_file="$1"
    local json_data="$2"

    local log_dir
    log_dir=$(dirname "$log_file")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi

    echo "$json_data" > "$log_file" 2>/dev/null
}

#===============================================================================
# PROMPTS
# Interactive user prompts
#===============================================================================

# confirm() - Ask yes/no question, return 0 for yes, 1 for no
# Usage: if confirm "Proceed with deletion?"; then rm -rf /tmp/data; fi
# Default can be set: confirm "Continue?" "y" or confirm "Delete all?" "n"
confirm() {
    local prompt="$1"
    local default="${2:-}"
    local response

    # Build prompt string with default indicator
    local prompt_str="$prompt"
    case "$default" in
        y|Y) prompt_str="$prompt [Y/n]: " ;;
        n|N) prompt_str="$prompt [y/N]: " ;;
        *)   prompt_str="$prompt [y/n]: " ;;
    esac

    # Read response
    read -r -p "$prompt_str" response

    # Handle empty response (use default)
    if [[ -z "$response" ]]; then
        response="$default"
    fi

    # Return based on response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# prompt_input() - Get text input from user
# Usage: domain=$(prompt_input "Enter domain name" "example.com")
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local response

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -r -p "$prompt: " response
        echo "$response"
    fi
}

#===============================================================================
# VALIDATION
# Input and state validation functions
#===============================================================================

# validate_domain() - Check if domain directory exists in WEBSITES_ROOT
# Usage: if validate_domain "example.com"; then process_site; fi
# Returns 0 if valid, 1 if not
validate_domain() {
    local domain="$1"
    local websites_root="${WEBSITES_ROOT:-/usr/local/websites}"

    # Check for empty domain
    if [[ -z "$domain" ]]; then
        debug "validate_domain: empty domain provided"
        return 1
    fi

    # Check if directory exists
    if [[ -d "${websites_root}/${domain}" ]]; then
        return 0
    else
        debug "validate_domain: directory not found: ${websites_root}/${domain}"
        return 1
    fi
}

# is_wordpress() - Check if directory contains WordPress (wp-config.php exists)
# Usage: if is_wordpress "/usr/local/websites/example.com/html"; then echo "WP site"; fi
# Returns 0 if WordPress, 1 if not
is_wordpress() {
    local path="$1"

    # Check for wp-config.php (primary indicator)
    if [[ -f "${path}/wp-config.php" ]]; then
        return 0
    fi

    # Also check in html subdirectory
    if [[ -f "${path}/html/wp-config.php" ]]; then
        return 0
    fi

    return 1
}

# is_root() - Check if script is running as root
# Usage: is_root || die "This script requires root privileges"
is_root() {
    [[ $EUID -eq 0 ]]
}

# require_root() - Exit with error if not running as root
# Usage: require_root
require_root() {
    if ! is_root; then
        error "This script must be run as root"
        exit 1
    fi
}

# command_exists() - Check if a command is available
# Usage: command_exists "jq" || warn "jq not installed"
command_exists() {
    command -v "$1" &>/dev/null
}

# require_command() - Exit with error if command not available
# Usage: require_command "jq" "JSON processing"
require_command() {
    local cmd="$1"
    local purpose="${2:-required functionality}"

    if ! command_exists "$cmd"; then
        error "Required command '$cmd' not found (needed for $purpose)"
        error "Please install it: apt install $cmd"
        exit 1
    fi
}

#===============================================================================
# WORDPRESS HELPERS
# Functions for working with WordPress installations
#===============================================================================

# Find WP-CLI binary path
_find_wp_cli() {
    local wp_paths=(
        "/usr/local/bin/wp"
        "/usr/bin/wp"
        "$HOME/.wp-cli/bin/wp"
        "/opt/wp-cli/wp"
    )

    for wp_path in "${wp_paths[@]}"; do
        if [[ -x "$wp_path" ]]; then
            echo "$wp_path"
            return 0
        fi
    done

    # Try to find in PATH
    if command_exists wp; then
        command -v wp
        return 0
    fi

    return 1
}

# wp_cli() - Wrapper that handles WP-CLI path and --allow-root
# Usage: wp_cli "/var/www/html" core version
# Returns WP-CLI output or error
wp_cli() {
    local path="$1"
    shift
    local wp_args=("$@")

    local wp_bin
    wp_bin=$(_find_wp_cli) || {
        error "WP-CLI not found"
        return 1
    }

    # Build command with --allow-root if running as root
    local cmd=("$wp_bin" "--path=$path")
    if is_root; then
        cmd+=("--allow-root")
    fi
    cmd+=("${wp_args[@]}")

    # Execute WP-CLI command
    "${cmd[@]}" 2>/dev/null
}

# get_wp_version() - Extract WordPress version using WP-CLI or parsing
# Usage: version=$(get_wp_version "/var/www/html")
# Returns version string or "unknown"
get_wp_version() {
    local path="$1"

    # Resolve html subdirectory if needed
    if [[ -f "${path}/html/wp-config.php" ]]; then
        path="${path}/html"
    fi

    # Method 1: Try WP-CLI (most reliable)
    if wp_bin=$(_find_wp_cli); then
        local version
        version=$(wp_cli "$path" core version 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Method 2: Parse version.php directly
    local version_file="${path}/wp-includes/version.php"
    if [[ -f "$version_file" ]]; then
        local version
        version=$(grep -oP '\$wp_version\s*=\s*['\''\"]\K[^'\''\";]+' "$version_file" 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Failed to determine version
    echo "unknown"
    return 1
}

# get_wp_db_info() - Extract database credentials from wp-config.php
# Usage: eval "$(get_wp_db_info /var/www/html)"
#        echo "Database: $DB_NAME, User: $DB_USER"
get_wp_db_info() {
    local path="$1"

    # Find wp-config.php
    local config_file="${path}/wp-config.php"
    if [[ ! -f "$config_file" ]]; then
        config_file="${path}/html/wp-config.php"
    fi

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # Extract database constants
    local db_name db_user db_pass db_host
    db_name=$(grep -oP "define\s*\(\s*['\"]DB_NAME['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config_file")
    db_user=$(grep -oP "define\s*\(\s*['\"]DB_USER['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config_file")
    db_pass=$(grep -oP "define\s*\(\s*['\"]DB_PASSWORD['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config_file")
    db_host=$(grep -oP "define\s*\(\s*['\"]DB_HOST['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config_file")

    # Output as shell variable assignments
    echo "DB_NAME='$db_name'"
    echo "DB_USER='$db_user'"
    echo "DB_PASSWORD='$db_pass'"
    echo "DB_HOST='${db_host:-localhost}'"
}

#===============================================================================
# CONFIGURATION
# Loading and managing configuration
#===============================================================================

# load_config() - Source the jps-tools.conf file
# Usage: load_config || exit 1
# Sets global variables from config file
load_config() {
    local config_file="${1:-$JPS_CONFIG_FILE}"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        debug "Loaded config from: $config_file"
        return 0
    else
        # Use defaults if config doesn't exist
        debug "Config file not found, using defaults: $config_file"

        # Set default values
        WEBSITES_ROOT="${WEBSITES_ROOT:-/usr/local/websites}"
        VHOSTS_DIR="${VHOSTS_DIR:-/usr/local/lsws/conf/vhosts}"
        OLS_CONFIG="${OLS_CONFIG:-/usr/local/lsws/conf/httpd_config.conf}"
        BACKUP_DIR="${BACKUP_DIR:-/var/backups/jps}"
        LOG_DIR="${LOG_DIR:-/opt/jps-server-tools/logs}"
        VERIFY_TEMP_DIR="${VERIFY_TEMP_DIR:-/tmp/jps-verify}"
        VERIFY_DB_PREFIX="${VERIFY_DB_PREFIX:-jps_verify_}"
        DISK_WARN_PERCENT="${DISK_WARN_PERCENT:-80}"
        DISK_CRIT_PERCENT="${DISK_CRIT_PERCENT:-90}"
        MEM_WARN_PERCENT="${MEM_WARN_PERCENT:-85}"
        MEM_CRIT_PERCENT="${MEM_CRIT_PERCENT:-95}"
        SSL_WARN_DAYS="${SSL_WARN_DAYS:-14}"
        SSL_CRIT_DAYS="${SSL_CRIT_DAYS:-7}"
        ALERT_EMAIL="${ALERT_EMAIL:-}"
        SEND_ALERTS="${SEND_ALERTS:-false}"
        AUDIT_RETENTION_DAYS="${AUDIT_RETENTION_DAYS:-90}"

        # Migration system defaults
        MIGRATION_INCOMING_DIR="${MIGRATION_INCOMING_DIR:-/var/backups/jps/migrations/incoming}"
        MIGRATION_METADATA_DIR="${MIGRATION_METADATA_DIR:-/var/backups/jps/migrations/metadata}"
        MIGRATION_RETENTION_DAYS="${MIGRATION_RETENTION_DAYS:-7}"
        MIGRATION_ALLOW_DEFAULT_SOURCE="${MIGRATION_ALLOW_DEFAULT_SOURCE:-true}"

        return 0
    fi
}

# get_config() - Get a configuration value with default
# Usage: value=$(get_config "WEBSITES_ROOT" "/var/www")
get_config() {
    local key="$1"
    local default="$2"

    # Use indirect expansion to get variable value
    local value="${!key:-$default}"
    echo "$value"
}

#===============================================================================
# UTILITIES
# General utility functions
#===============================================================================

# human_size() - Convert bytes to human readable (KB, MB, GB)
# Usage: human_size 1073741824  # Returns "1.00 GB"
human_size() {
    local bytes="$1"

    # Handle empty or non-numeric input
    if [[ -z "$bytes" ]] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return
    fi

    if (( bytes >= 1099511627776 )); then
        printf "%.2f TB" "$(echo "scale=2; $bytes / 1099511627776" | bc)"
    elif (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    else
        echo "$bytes B"
    fi
}

# days_until() - Calculate days between now and a future date
# Usage: days=$(days_until "2024-12-31")
# Returns negative number if date is in the past
days_until() {
    local future_date="$1"

    # Get current timestamp
    local now
    now=$(date +%s)

    # Parse future date to timestamp
    local future
    future=$(date -d "$future_date" +%s 2>/dev/null) || {
        echo "0"
        return 1
    }

    # Calculate difference in days
    local diff=$(( (future - now) / 86400 ))
    echo "$diff"
}

# days_since() - Calculate days since a past date
# Usage: days=$(days_since "2024-01-01")
days_since() {
    local past_date="$1"

    local now
    now=$(date +%s)

    local past
    past=$(date -d "$past_date" +%s 2>/dev/null) || {
        echo "0"
        return 1
    }

    local diff=$(( (now - past) / 86400 ))
    echo "$diff"
}

# random_string() - Generate a random alphanumeric string
# Usage: token=$(random_string 16)
random_string() {
    local length="${1:-12}"
    openssl rand -base64 48 2>/dev/null | tr -dc a-zA-Z0-9 | head -c "$length"
}

# timestamp() - Get current timestamp in specified format
# Usage: ts=$(timestamp)  or  ts=$(timestamp "%Y-%m-%d")
timestamp() {
    local format="${1:-%Y-%m-%d %H:%M:%S}"
    date +"$format"
}

# file_age_days() - Get file age in days
# Usage: age=$(file_age_days "/var/log/syslog")
file_age_days() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "-1"
        return 1
    fi

    local file_time
    file_time=$(stat -c %Y "$file" 2>/dev/null) || {
        echo "-1"
        return 1
    }

    local now
    now=$(date +%s)

    local diff=$(( (now - file_time) / 86400 ))
    echo "$diff"
}

# trim() - Remove leading and trailing whitespace
# Usage: cleaned=$(trim "  hello world  ")
trim() {
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# json_escape() - Escape string for JSON
# Usage: escaped=$(json_escape "string with \"quotes\"")
json_escape() {
    local string="$1"
    # Escape backslashes, quotes, and control characters
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    string="${string//$'\r'/\\r}"
    string="${string//$'\t'/\\t}"
    echo "$string"
}

# die() - Print error message and exit
# Usage: die "Something went wrong" 2
die() {
    local message="$1"
    local exit_code="${2:-1}"

    error "$message"
    exit "$exit_code"
}

#===============================================================================
# SSL/CERTIFICATE HELPERS
#===============================================================================

# get_ssl_expiry() - Get SSL certificate expiry date for a domain
# Usage: expiry=$(get_ssl_expiry "example.com")
# Returns date in format: "Dec 31 23:59:59 2024 GMT"
get_ssl_expiry() {
    local domain="$1"
    local port="${2:-443}"

    # Try to get certificate expiry via openssl
    local expiry
    expiry=$(echo | openssl s_client -servername "$domain" -connect "${domain}:${port}" 2>/dev/null | \
             openssl x509 -noout -enddate 2>/dev/null | \
             cut -d= -f2)

    if [[ -n "$expiry" ]]; then
        echo "$expiry"
        return 0
    fi

    # Try local certificate file (Let's Encrypt default location)
    local cert_file="/etc/letsencrypt/live/${domain}/cert.pem"
    if [[ -f "$cert_file" ]]; then
        expiry=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            echo "$expiry"
            return 0
        fi
    fi

    return 1
}

# get_ssl_days_remaining() - Get days until SSL certificate expires
# Usage: days=$(get_ssl_days_remaining "example.com")
get_ssl_days_remaining() {
    local domain="$1"

    local expiry
    expiry=$(get_ssl_expiry "$domain") || {
        echo "-1"
        return 1
    }

    # Convert expiry to timestamp
    local expiry_ts
    expiry_ts=$(date -d "$expiry" +%s 2>/dev/null) || {
        echo "-1"
        return 1
    }

    local now
    now=$(date +%s)

    local diff=$(( (expiry_ts - now) / 86400 ))
    echo "$diff"
}

#===============================================================================
# SERVICE HELPERS
#===============================================================================

# service_status() - Check if a service is running
# Usage: if service_status "mysql"; then echo "MySQL is running"; fi
# Returns 0 if running, 1 if stopped/not found
service_status() {
    local service="$1"

    # Try systemctl first (systemd)
    if command_exists systemctl; then
        systemctl is-active --quiet "$service" 2>/dev/null && return 0
    fi

    # Try service command (SysV init)
    if command_exists service; then
        service "$service" status &>/dev/null && return 0
    fi

    # Check if process is running by name
    pgrep -x "$service" &>/dev/null && return 0

    return 1
}

# get_service_status_text() - Get human-readable service status
# Usage: status=$(get_service_status_text "mysql")
get_service_status_text() {
    local service="$1"

    if service_status "$service"; then
        echo "running"
    else
        echo "stopped"
    fi
}

#===============================================================================
# ARRAY/LIST HELPERS
#===============================================================================

# list_dirs() - List directories in a path
# Usage: dirs=$(list_dirs "/usr/local/websites")
list_dirs() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        return 1
    fi

    find "$path" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# count_items() - Count items in newline-separated list
# Usage: count=$(echo "$list" | count_items)
count_items() {
    grep -c . 2>/dev/null || echo "0"
}

#===============================================================================
# CLEANUP/TEMP HELPERS
#===============================================================================

# Trap handler for cleanup on exit
_cleanup_files=()

# register_cleanup() - Register a file/directory for cleanup on exit
# Usage: register_cleanup "/tmp/myfile"
register_cleanup() {
    _cleanup_files+=("$1")
}

# _do_cleanup() - Internal function to clean up registered files
_do_cleanup() {
    for item in "${_cleanup_files[@]}"; do
        if [[ -f "$item" ]]; then
            rm -f "$item" 2>/dev/null
        elif [[ -d "$item" ]]; then
            rm -rf "$item" 2>/dev/null
        fi
    done
}

# Set up cleanup trap
trap _do_cleanup EXIT

# create_temp_dir() - Create a temporary directory and register for cleanup
# Usage: temp_dir=$(create_temp_dir "jps-audit")
create_temp_dir() {
    local prefix="${1:-jps}"
    local temp_dir
    temp_dir=$(mktemp -d -t "${prefix}.XXXXXX")
    register_cleanup "$temp_dir"
    echo "$temp_dir"
}

# create_temp_file() - Create a temporary file and register for cleanup
# Usage: temp_file=$(create_temp_file "jps-output")
create_temp_file() {
    local prefix="${1:-jps}"
    local temp_file
    temp_file=$(mktemp -t "${prefix}.XXXXXX")
    register_cleanup "$temp_file"
    echo "$temp_file"
}

#===============================================================================
# VERSION/HELP HELPERS
#===============================================================================

# show_version() - Display script version
# Usage: show_version
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# Standard help footer
help_footer() {
    echo ""
    echo "Part of JPS Server Tools - https://github.com/yourusername/jps-server-tools"
    echo "Report issues at https://github.com/yourusername/jps-server-tools/issues"
}
