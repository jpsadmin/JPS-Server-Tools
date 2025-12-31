#!/bin/bash
#===============================================================================
# JPS Server Tools - Optimization Library
# Shared functions for WordPress site optimization
#===============================================================================

# Prevent multiple sourcing
[[ -n "${_JPS_OPTIMIZE_LOADED:-}" ]] && return 0
readonly _JPS_OPTIMIZE_LOADED=1

# Source common library if not already loaded
OPTIMIZE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jps-common.sh
source "${OPTIMIZE_SCRIPT_DIR}/jps-common.sh" 2>/dev/null || {
    echo "ERROR: Cannot load jps-common.sh" >&2
    exit 1
}

#===============================================================================
# YAML PARSING
# Simple YAML parser for preset configuration files
#===============================================================================

# parse_yaml() - Parse a YAML file and output shell variable assignments
# Usage: eval "$(parse_yaml /path/to/preset.yaml "PRESET_")"
# Supports simple key: value pairs and nested structures (one level)
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-}"

    if [[ ! -f "$yaml_file" ]]; then
        error "YAML file not found: $yaml_file"
        return 1
    fi

    local line key value section=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check if this is a section header (no leading spaces, ends with colon)
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):$ ]]; then
            section="${BASH_REMATCH[1]}_"
            continue
        fi

        # Check if this is a section header with value (key: value)
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            # Trim whitespace
            value="$(echo "$value" | xargs)"
            echo "${prefix}${key}='${value}'"
            section=""
            continue
        fi

        # Check for indented key: value (nested under section)
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):?[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            # Trim whitespace
            value="$(echo "$value" | xargs)"

            # Use section prefix if we're in a section
            if [[ -n "$section" ]]; then
                echo "${prefix}${section}${key}='${value}'"
            else
                echo "${prefix}${key}='${value}'"
            fi
        fi
    done < "$yaml_file"
}

# get_yaml_value() - Get a specific value from a YAML file
# Usage: value=$(get_yaml_value /path/to/preset.yaml "php.memory_limit")
get_yaml_value() {
    local yaml_file="$1"
    local key_path="$2"

    if [[ ! -f "$yaml_file" ]]; then
        return 1
    fi

    # Convert dot notation to section_key format
    local section=""
    local key="$key_path"

    if [[ "$key_path" == *"."* ]]; then
        section="${key_path%%.*}"
        key="${key_path#*.}"
    fi

    local in_section=false
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for section header
        if [[ -n "$section" ]] && [[ "$line" =~ ^${section}:$ ]]; then
            in_section=true
            continue
        fi

        # If we're in the right section, look for the key
        if [[ "$in_section" == true ]] && [[ "$line" =~ ^[[:space:]]+${key}:[[:space:]]*(.+)$ ]]; then
            local value="${BASH_REMATCH[1]}"
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            echo "$(echo "$value" | xargs)"
            return 0
        fi

        # If no section specified, look for top-level key
        if [[ -z "$section" ]] && [[ "$line" =~ ^${key}:[[:space:]]*(.+)$ ]]; then
            local value="${BASH_REMATCH[1]}"
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            echo "$(echo "$value" | xargs)"
            return 0
        fi

        # If line is not indented and we were in a section, exit section
        if [[ "$in_section" == true ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_section=false
        fi
    done < "$yaml_file"

    return 1
}

# list_yaml_keys() - List all keys under a section in a YAML file
# Usage: keys=$(list_yaml_keys /path/to/preset.yaml "php")
list_yaml_keys() {
    local yaml_file="$1"
    local section="$2"

    if [[ ! -f "$yaml_file" ]]; then
        return 1
    fi

    local in_section=false
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for section header
        if [[ "$line" =~ ^${section}:$ ]]; then
            in_section=true
            continue
        fi

        # If we're in the right section, extract keys
        if [[ "$in_section" == true ]] && [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]* ]]; then
            echo "${BASH_REMATCH[1]}"
        fi

        # If line is not indented and we were in a section, exit
        if [[ "$in_section" == true ]] && [[ ! "$line" =~ ^[[:space:]] ]] && [[ ! -z "$line" ]]; then
            break
        fi
    done < "$yaml_file"
}

#===============================================================================
# VHOST CONFIGURATION
# Functions for modifying OpenLiteSpeed vhost configuration
#===============================================================================

# update_vhconf_php() - Modify phpIniOverride section in vhconf.conf
# Usage: update_vhconf_php "/usr/local/lsws/conf/vhosts/example.com/vhconf.conf" "memory_limit" "512M"
update_vhconf_php() {
    local vhconf_file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$vhconf_file" ]]; then
        error "vhconf.conf not found: $vhconf_file"
        return 1
    fi

    # Backup original file
    cp "$vhconf_file" "${vhconf_file}.bak.$(date +%Y%m%d%H%M%S)"

    # Check if phpIniOverride section exists
    if grep -q "phpIniOverride" "$vhconf_file"; then
        # Check if the key already exists in phpIniOverride
        if grep -qP "^\s*php_value\s+${key}\s+" "$vhconf_file"; then
            # Update existing value
            sed -i "s/^\(\s*php_value\s\+${key}\s\+\).*/\1${value}/" "$vhconf_file"
            debug "Updated ${key} = ${value} in phpIniOverride"
        else
            # Add new key to existing phpIniOverride section
            # Insert before the closing brace of phpIniOverride
            awk -v key="$key" -v val="$value" '
            /phpIniOverride/ { in_section=1 }
            in_section && /^}/ {
                print "  php_value " key " " val
                in_section=0
            }
            { print }
            ' "$vhconf_file" > "${vhconf_file}.tmp" && mv "${vhconf_file}.tmp" "$vhconf_file"
            debug "Added ${key} = ${value} to phpIniOverride"
        fi
    else
        # Create phpIniOverride section
        cat >> "$vhconf_file" << EOF

phpIniOverride  {
  php_value ${key} ${value}
}
EOF
        debug "Created phpIniOverride section with ${key} = ${value}"
    fi

    return 0
}

# set_vhconf_php_values() - Set multiple PHP values in vhconf.conf
# Usage: set_vhconf_php_values "/path/to/vhconf.conf" "memory_limit=512M" "max_execution_time=300"
set_vhconf_php_values() {
    local vhconf_file="$1"
    shift
    local settings=("$@")

    for setting in "${settings[@]}"; do
        local key="${setting%%=*}"
        local value="${setting#*=}"
        update_vhconf_php "$vhconf_file" "$key" "$value" || return 1
    done

    return 0
}

# get_vhconf_php_value() - Get current PHP value from vhconf.conf
# Usage: value=$(get_vhconf_php_value "/path/to/vhconf.conf" "memory_limit")
get_vhconf_php_value() {
    local vhconf_file="$1"
    local key="$2"

    if [[ ! -f "$vhconf_file" ]]; then
        return 1
    fi

    grep -oP "^\s*php_value\s+${key}\s+\K\S+" "$vhconf_file" 2>/dev/null
}

# remove_vhconf_php_value() - Remove a PHP value from vhconf.conf
# Usage: remove_vhconf_php_value "/path/to/vhconf.conf" "memory_limit"
remove_vhconf_php_value() {
    local vhconf_file="$1"
    local key="$2"

    if [[ ! -f "$vhconf_file" ]]; then
        return 1
    fi

    sed -i "/^\s*php_value\s\+${key}\s\+/d" "$vhconf_file"
    debug "Removed ${key} from phpIniOverride"
}

#===============================================================================
# LITESPEED CACHE CONFIGURATION
# Functions for configuring LiteSpeed Cache WordPress plugin
#===============================================================================

# apply_lscache_settings() - Configure LiteSpeed Cache plugin via WP-CLI
# Usage: apply_lscache_settings "/usr/local/websites/example.com/html" "preset_name" "/path/to/preset.yaml"
apply_lscache_settings() {
    local site_path="$1"
    local preset_name="$2"
    local preset_file="$3"

    # Verify WordPress installation
    if [[ ! -f "${site_path}/wp-config.php" ]]; then
        error "WordPress not found at: $site_path"
        return 1
    fi

    # Check if LiteSpeed Cache plugin is active
    local lscache_active
    lscache_active=$(wp_cli "$site_path" plugin is-active litespeed-cache 2>/dev/null && echo "yes" || echo "no")

    if [[ "$lscache_active" != "yes" ]]; then
        warn "LiteSpeed Cache plugin is not active"
        info "Attempting to activate LiteSpeed Cache plugin..."
        wp_cli "$site_path" plugin activate litespeed-cache 2>/dev/null || {
            error "Failed to activate LiteSpeed Cache plugin"
            return 1
        }
    fi

    # Load preset settings
    if [[ ! -f "$preset_file" ]]; then
        error "Preset file not found: $preset_file"
        return 1
    fi

    # Apply cache settings based on preset
    local cache_browser cache_mobile cache_logged_in cache_ttl_pub cache_ttl_priv

    cache_browser=$(get_yaml_value "$preset_file" "lscache.browser_cache")
    cache_mobile=$(get_yaml_value "$preset_file" "lscache.mobile_cache")
    cache_logged_in=$(get_yaml_value "$preset_file" "lscache.cache_logged_in")
    cache_ttl_pub=$(get_yaml_value "$preset_file" "lscache.ttl_public")
    cache_ttl_priv=$(get_yaml_value "$preset_file" "lscache.ttl_private")

    # Apply settings via WP-CLI litespeed-option
    local options_set=0

    if [[ -n "$cache_browser" ]]; then
        local browser_val=$([[ "$cache_browser" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set cache-browser "$browser_val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$cache_mobile" ]]; then
        local mobile_val=$([[ "$cache_mobile" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set cache-mobile "$mobile_val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$cache_logged_in" ]]; then
        local logged_val=$([[ "$cache_logged_in" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set cache-priv "$logged_val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$cache_ttl_pub" ]]; then
        wp_cli "$site_path" litespeed-option set cache-ttl_pub "$cache_ttl_pub" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$cache_ttl_priv" ]]; then
        wp_cli "$site_path" litespeed-option set cache-ttl_priv "$cache_ttl_priv" 2>/dev/null && ((options_set++))
    fi

    # Apply optimization settings
    local opt_css_minify opt_js_minify opt_html_minify opt_css_combine opt_js_combine

    opt_css_minify=$(get_yaml_value "$preset_file" "lscache.css_minify")
    opt_js_minify=$(get_yaml_value "$preset_file" "lscache.js_minify")
    opt_html_minify=$(get_yaml_value "$preset_file" "lscache.html_minify")
    opt_css_combine=$(get_yaml_value "$preset_file" "lscache.css_combine")
    opt_js_combine=$(get_yaml_value "$preset_file" "lscache.js_combine")

    if [[ -n "$opt_css_minify" ]]; then
        local val=$([[ "$opt_css_minify" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set optm-css_min "$val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$opt_js_minify" ]]; then
        local val=$([[ "$opt_js_minify" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set optm-js_min "$val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$opt_html_minify" ]]; then
        local val=$([[ "$opt_html_minify" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set optm-html_min "$val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$opt_css_combine" ]]; then
        local val=$([[ "$opt_css_combine" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set optm-css_comb "$val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$opt_js_combine" ]]; then
        local val=$([[ "$opt_js_combine" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set optm-js_comb "$val" 2>/dev/null && ((options_set++))
    fi

    # Apply image optimization settings
    local img_lazyload img_webp

    img_lazyload=$(get_yaml_value "$preset_file" "lscache.lazy_load")
    img_webp=$(get_yaml_value "$preset_file" "lscache.webp")

    if [[ -n "$img_lazyload" ]]; then
        local val=$([[ "$img_lazyload" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set media-lazy "$val" 2>/dev/null && ((options_set++))
    fi

    if [[ -n "$img_webp" ]]; then
        local val=$([[ "$img_webp" == "true" ]] && echo 1 || echo 0)
        wp_cli "$site_path" litespeed-option set img_optm-webp "$val" 2>/dev/null && ((options_set++))
    fi

    # Flush cache after applying settings
    wp_cli "$site_path" litespeed-purge all 2>/dev/null

    info "Applied ${options_set} LiteSpeed Cache settings from preset: ${preset_name}"
    return 0
}

# purge_lscache() - Purge all LiteSpeed Cache for a site
# Usage: purge_lscache "/usr/local/websites/example.com/html"
purge_lscache() {
    local site_path="$1"

    if [[ ! -f "${site_path}/wp-config.php" ]]; then
        return 1
    fi

    wp_cli "$site_path" litespeed-purge all 2>/dev/null
}

# get_lscache_status() - Get LiteSpeed Cache status for a site
# Usage: get_lscache_status "/usr/local/websites/example.com/html"
get_lscache_status() {
    local site_path="$1"

    if [[ ! -f "${site_path}/wp-config.php" ]]; then
        echo "no_wp"
        return 1
    fi

    # Check if plugin exists
    if ! wp_cli "$site_path" plugin is-installed litespeed-cache 2>/dev/null; then
        echo "not_installed"
        return 0
    fi

    # Check if plugin is active
    if wp_cli "$site_path" plugin is-active litespeed-cache 2>/dev/null; then
        echo "active"
    else
        echo "inactive"
    fi
}

#===============================================================================
# VALIDATION
# Functions for validating optimization changes
#===============================================================================

# validate_optimization() - Verify that optimization settings were applied correctly
# Usage: validate_optimization "/usr/local/websites/example.com" "woo" "/path/to/preset.yaml"
validate_optimization() {
    local domain="$1"
    local preset_name="$2"
    local preset_file="$3"

    local websites_root="${WEBSITES_ROOT:-/usr/local/websites}"
    local vhosts_dir="${VHOSTS_DIR:-/usr/local/lsws/conf/vhosts}"
    local site_path="${websites_root}/${domain}/html"
    local vhconf_file="${vhosts_dir}/${domain}/vhconf.conf"

    local errors=0
    local warnings=0
    local results=()

    # Validate vhconf.conf exists
    if [[ ! -f "$vhconf_file" ]]; then
        results+=("ERROR: vhconf.conf not found")
        ((errors++))
    else
        # Validate PHP settings
        local expected_memory expected_exec_time expected_upload
        expected_memory=$(get_yaml_value "$preset_file" "php.memory_limit")
        expected_exec_time=$(get_yaml_value "$preset_file" "php.max_execution_time")
        expected_upload=$(get_yaml_value "$preset_file" "php.upload_max_filesize")

        if [[ -n "$expected_memory" ]]; then
            local actual_memory
            actual_memory=$(get_vhconf_php_value "$vhconf_file" "memory_limit")
            if [[ "$actual_memory" == "$expected_memory" ]]; then
                results+=("OK: memory_limit = ${actual_memory}")
            else
                results+=("WARN: memory_limit expected ${expected_memory}, got ${actual_memory:-'not set'}")
                ((warnings++))
            fi
        fi

        if [[ -n "$expected_exec_time" ]]; then
            local actual_exec
            actual_exec=$(get_vhconf_php_value "$vhconf_file" "max_execution_time")
            if [[ "$actual_exec" == "$expected_exec_time" ]]; then
                results+=("OK: max_execution_time = ${actual_exec}")
            else
                results+=("WARN: max_execution_time expected ${expected_exec_time}, got ${actual_exec:-'not set'}")
                ((warnings++))
            fi
        fi

        if [[ -n "$expected_upload" ]]; then
            local actual_upload
            actual_upload=$(get_vhconf_php_value "$vhconf_file" "upload_max_filesize")
            if [[ "$actual_upload" == "$expected_upload" ]]; then
                results+=("OK: upload_max_filesize = ${actual_upload}")
            else
                results+=("WARN: upload_max_filesize expected ${expected_upload}, got ${actual_upload:-'not set'}")
                ((warnings++))
            fi
        fi
    fi

    # Validate WordPress/LiteSpeed Cache
    if [[ -f "${site_path}/wp-config.php" ]]; then
        local lscache_status
        lscache_status=$(get_lscache_status "$site_path")

        case "$lscache_status" in
            active)
                results+=("OK: LiteSpeed Cache is active")
                ;;
            inactive)
                results+=("WARN: LiteSpeed Cache is installed but inactive")
                ((warnings++))
                ;;
            not_installed)
                results+=("ERROR: LiteSpeed Cache is not installed")
                ((errors++))
                ;;
        esac
    else
        results+=("INFO: Not a WordPress site, skipping LSCache validation")
    fi

    # Output results
    for result in "${results[@]}"; do
        echo "$result"
    done

    # Return status
    if ((errors > 0)); then
        return 2
    elif ((warnings > 0)); then
        return 1
    else
        return 0
    fi
}

# generate_optimization_report() - Generate a JSON report of optimization status
# Usage: report=$(generate_optimization_report "example.com" "woo")
generate_optimization_report() {
    local domain="$1"
    local preset_name="$2"

    local websites_root="${WEBSITES_ROOT:-/usr/local/websites}"
    local vhosts_dir="${VHOSTS_DIR:-/usr/local/lsws/conf/vhosts}"
    local site_path="${websites_root}/${domain}/html"
    local vhconf_file="${vhosts_dir}/${domain}/vhconf.conf"

    local timestamp
    timestamp=$(date -Iseconds)

    # Collect PHP settings
    local memory_limit max_exec_time upload_size post_size
    memory_limit=$(get_vhconf_php_value "$vhconf_file" "memory_limit" 2>/dev/null || echo "default")
    max_exec_time=$(get_vhconf_php_value "$vhconf_file" "max_execution_time" 2>/dev/null || echo "default")
    upload_size=$(get_vhconf_php_value "$vhconf_file" "upload_max_filesize" 2>/dev/null || echo "default")
    post_size=$(get_vhconf_php_value "$vhconf_file" "post_max_size" 2>/dev/null || echo "default")

    # Collect LiteSpeed Cache status
    local lscache_status="n/a"
    if [[ -f "${site_path}/wp-config.php" ]]; then
        lscache_status=$(get_lscache_status "$site_path")
    fi

    # Build JSON report
    cat << EOF
{
  "domain": "${domain}",
  "preset": "${preset_name}",
  "timestamp": "${timestamp}",
  "php": {
    "memory_limit": "${memory_limit}",
    "max_execution_time": "${max_exec_time}",
    "upload_max_filesize": "${upload_size}",
    "post_max_size": "${post_size}"
  },
  "lscache": {
    "status": "${lscache_status}"
  }
}
EOF
}

#===============================================================================
# PRESET MANAGEMENT
# Functions for managing optimization presets
#===============================================================================

# list_presets() - List available optimization presets
# Usage: list_presets
list_presets() {
    local presets_dir="${JPS_INSTALL_DIR:-/opt/jps-server-tools}/config/presets"

    if [[ ! -d "$presets_dir" ]]; then
        error "Presets directory not found: $presets_dir"
        return 1
    fi

    local preset_file
    for preset_file in "${presets_dir}"/*.yaml; do
        if [[ -f "$preset_file" ]]; then
            local name description
            name=$(basename "$preset_file" .yaml)
            description=$(get_yaml_value "$preset_file" "description" 2>/dev/null || echo "No description")
            printf "%-12s  %s\n" "$name" "$description"
        fi
    done
}

# get_preset_path() - Get the full path to a preset file
# Usage: preset_path=$(get_preset_path "woo")
get_preset_path() {
    local preset_name="$1"
    local presets_dir="${JPS_INSTALL_DIR:-/opt/jps-server-tools}/config/presets"
    local preset_file="${presets_dir}/${preset_name}.yaml"

    if [[ -f "$preset_file" ]]; then
        echo "$preset_file"
        return 0
    fi

    return 1
}

# validate_preset() - Check if a preset file is valid
# Usage: validate_preset "/path/to/preset.yaml"
validate_preset() {
    local preset_file="$1"

    if [[ ! -f "$preset_file" ]]; then
        error "Preset file not found: $preset_file"
        return 1
    fi

    # Check for required sections
    local has_name has_php
    has_name=$(get_yaml_value "$preset_file" "name" 2>/dev/null)

    if [[ -z "$has_name" ]]; then
        error "Preset missing 'name' field"
        return 1
    fi

    # Check for at least one setting section
    if ! grep -qE "^(php|lscache):" "$preset_file"; then
        error "Preset must have at least one of: php, lscache sections"
        return 1
    fi

    return 0
}
