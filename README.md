# JPS Server Tools

A comprehensive server management toolkit for Ubuntu 24.04 VPS running OpenLiteSpeed. These tools provide server-level monitoring, auditing, and backup verification that complements application-level tools like MainWP, WPMU DEV, WPVivid, and ManageWP.

## Overview

JPS Server Tools fills the gap between WordPress management plugins and server administration by providing:

- **Server Auditing**: Comprehensive system state capture with drift detection
- **Backup Verification**: Prove your backups can actually restore
- **Site Status**: Quick inventory of all hosted sites with health checks
- **Health Monitoring**: Silent cron monitoring with alerts only on issues
- **Site Lifecycle**: Checkpoint, suspend, archive, and safely delete sites

These are server-level operations that WordPress plugins cannot see or manage.

## Requirements

- **OS**: Ubuntu 24.04 LTS
- **Web Server**: OpenLiteSpeed
- **Database**: MariaDB
- **PHP**: Any version via LiteSpeed SAPI
- **Required Tools**: bash, awk, sed, grep, curl, openssl
- **Optional Tools**: jq (JSON processing), WP-CLI (WordPress operations)

## Installation

### Quick Install

```bash
git clone https://github.com/yourusername/jps-server-tools.git
cd jps-server-tools
sudo ./install.sh
```

### Manual Install

```bash
# Create installation directory
sudo mkdir -p /opt/jps-server-tools/{bin,lib,config,logs/{audit,backup-verify,lifecycle}}

# Copy files
sudo cp bin/* /opt/jps-server-tools/bin/
sudo cp lib/* /opt/jps-server-tools/lib/
sudo cp config/jps-tools.conf /opt/jps-server-tools/config/

# Make executable
sudo chmod +x /opt/jps-server-tools/bin/*

# Create wrapper scripts (more reliable than symlinks)
for cmd in jps-audit jps-backup-verify jps-status jps-monitor jps-checkpoint jps-site-suspend jps-site-archive jps-site-delete; do
    echo '#!/bin/bash' | sudo tee /usr/local/bin/$cmd > /dev/null
    echo "exec /opt/jps-server-tools/bin/$cmd \"\$@\"" | sudo tee -a /usr/local/bin/$cmd > /dev/null
    sudo chmod +x /usr/local/bin/$cmd
done
```

### Check Dependencies

```bash
sudo ./install.sh --check
```

### Uninstall

```bash
sudo ./install.sh --remove
```

## Quick Start

### Run Your First Audit

```bash
# Full server audit with colored output
sudo jps-audit

# Quick summary only
sudo jps-audit --brief

# Save for drift detection
sudo jps-audit --save
```

### Verify a Backup

```bash
# Verify specific site
sudo jps-backup-verify example.com

# Verify all sites
sudo jps-backup-verify --all

# List available backups
sudo jps-backup-verify --list
```

### Check Site Status

```bash
# View all sites in a table
sudo jps-status

# Quick check without HTTP tests
sudo jps-status --no-check

# Details for one site
sudo jps-status --domain example.com
```

### Set Up Monitoring

```bash
# Test monitoring (verbose mode)
sudo jps-monitor --verbose

# Add to cron (silent unless issues)
# */5 * * * * /usr/local/bin/jps-monitor 2>&1 | logger -t jps-monitor
```

### Site Lifecycle Management

```bash
# Create checkpoint before risky change
sudo jps-checkpoint example.com --note "Before WP update"

# Suspend a site (disable without deleting)
sudo jps-site-suspend example.com --note "Client non-payment"

# Resume a suspended site
sudo jps-site-suspend example.com --resume

# Archive a site for long-term storage
sudo jps-site-archive example.com

# Safely delete a site (with confirmations)
sudo jps-site-delete example.com --archive
```

## Tools Reference

### jps-audit

Comprehensive server state capture and drift detection.

```
Usage: jps-audit [OPTIONS]

Options:
  -h, --help     Show help message
  -V, --version  Show version
  -b, --brief    Summary output only
  -j, --json     JSON output format
  -s, --save     Save snapshot for drift detection
  -d, --diff     Compare with previous audit
  -q, --quiet    Suppress non-essential output
  --no-color     Disable colored output
```

**What It Captures:**

| Section | Information |
|---------|-------------|
| System | OS version, kernel, hostname, IP, uptime, timezone |
| Resources | CPU%, memory, swap, disk per partition, disk per site |
| Services | OpenLiteSpeed, MariaDB, Fail2ban, UFW status |
| Security | UFW rules, open ports, SSH attempts, Fail2ban jails |
| Websites | Domain list, disk usage, WordPress version, SSL expiry |
| Databases | MariaDB version, database sizes |
| Checksums | MD5 hashes of config files for drift detection |

**Examples:**

```bash
# Standard audit
sudo jps-audit

# Quick health check
sudo jps-audit --brief

# Automation-friendly JSON
sudo jps-audit --json

# Save snapshot and detect drift
sudo jps-audit --save
sudo jps-audit --diff  # Compare later
```

**Exit Codes:**

- `0` - Healthy, no drift detected
- `1` - Healthy, drift detected
- `2` - Error during audit

### jps-backup-verify

Proves that backups can actually be restored.

```
Usage: jps-backup-verify <domain> [OPTIONS]
       jps-backup-verify --all [OPTIONS]
       jps-backup-verify --report
       jps-backup-verify --list

Options:
  -h, --help     Show help message
  -V, --version  Show version
  -a, --all      Verify all sites
  -r, --report   Show verification history
  -l, --list     List available backups
  -j, --json     JSON output format
  -v, --verbose  Show detailed steps
  --no-db        Skip database verification
  --keep-temp    Keep temp files (debugging)
```

**Verification Checks:**

| Check | Description |
|-------|-------------|
| Extraction | Backup can be extracted successfully |
| wp-config.php | File exists |
| PHP Syntax | wp-config.php is valid PHP |
| wp-content | Directory exists |
| wp-admin | Directory exists |
| wp-includes | Directory exists |
| Database Dump | SQL file exists |
| DB Import | Dump imports to temp database successfully |

**Examples:**

```bash
# Verify single site
sudo jps-backup-verify example.com

# Verify with verbose output
sudo jps-backup-verify example.com --verbose

# Verify all sites
sudo jps-backup-verify --all

# Files only (no database test)
sudo jps-backup-verify example.com --no-db

# Show verification history
sudo jps-backup-verify --report
```

**Exit Codes:**

- `0` - Verification passed
- `1` - Verification failed
- `2` - Error (backup not found, etc.)

### jps-status

Fast overview of all hosted sites in a compact table.

```
Usage: jps-status [OPTIONS]

Options:
  -h, --help              Show help message
  -V, --version           Show version
  -d, --domain DOMAIN     Show details for single domain
  -j, --json              JSON output format
  -n, --no-check          Skip HTTP health checks (faster)
  --no-color              Disable colored output
```

**Output Columns:**

| Column | Description |
|--------|-------------|
| Domain | Website domain name |
| Size | Disk usage (human readable) |
| WP Ver | WordPress version or "Static" |
| SSL | Days until certificate expires (color coded) |
| Status | HTTP health check result (UP/DOWN) |

**Example Output:**

```
JPS Site Status

Domain                         Size      WP Ver     SSL          Status
------------------------------ ---------- ---------- ------------ --------
jpshosting.biz                 3.32 GB   6.7.1      40 days      ✓ UP
jpshosting.net                 66.8 MB   6.7.1      32 days      ✓ UP

Total: 2 sites | WordPress: 2 | All SSL valid | All responding
```

**Examples:**

```bash
# Show all sites
sudo jps-status

# Quick inventory (no HTTP checks)
sudo jps-status --no-check

# Single site details
sudo jps-status --domain example.com

# JSON for scripting
sudo jps-status --json
```

**Exit Codes:**

- `0` - All sites healthy
- `1` - One or more sites have issues
- `2` - Error occurred

### jps-monitor

Silent health monitoring designed for cron. Outputs nothing when healthy.

```
Usage: jps-monitor [OPTIONS]

Options:
  -h, --help      Show help message
  -V, --version   Show version
  -v, --verbose   Show all checks (even passing)
  -e, --email     Send email alert if issues found
  -j, --json      JSON output format
  --no-http       Skip HTTP health checks
  --no-ssl        Skip SSL certificate checks
```

**Checks Performed:**

| Check | Warning | Critical |
|-------|---------|----------|
| Disk usage | 80% | 90% |
| Memory usage | 85% | 95% |
| OpenLiteSpeed | - | Not running |
| MariaDB | - | Not running |
| Website HTTP | - | Not responding |
| SSL certificates | 14 days | 7 days |

**Example Output (only when issues found):**

```
[WARN] Disk usage on / is 82%
[WARN] SSL for example.com expires in 5 days
[CRIT] Site staging.example.com not responding
```

**Cron Examples:**

```bash
# Check every 5 minutes, log to syslog
*/5 * * * * /usr/local/bin/jps-monitor 2>&1 | logger -t jps-monitor

# Check every hour, send email on failure
0 * * * * /usr/local/bin/jps-monitor --email

# Check every 15 minutes, skip HTTP checks
*/15 * * * * /usr/local/bin/jps-monitor --no-http
```

**Exit Codes:**

- `0` - All checks passed (no output)
- `1` - Warnings detected
- `2` - Critical issues detected

### jps-checkpoint

Pre-change backup trigger for quick point-in-time snapshots.

```
Usage: jps-checkpoint <domain> [OPTIONS]

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -v, --verbose       Show detailed progress
  -n, --note NOTE     Add a note describing reason
  -f, --files-only    Only backup files, skip database
  -d, --db-only       Only backup database, skip files
  -l, --list          List existing checkpoints
  -q, --quiet         Suppress non-essential output
```

**Checkpoint Contents:**

| Component | Description |
|-----------|-------------|
| Files | Complete site directory as tarball |
| Database | MySQL dump (WordPress only) |
| Note | Optional description file |

**Examples:**

```bash
# Full checkpoint before update
sudo jps-checkpoint example.com --note "Before WP 6.5 update"

# Quick files-only checkpoint
sudo jps-checkpoint example.com --files-only

# Database checkpoint before migration
sudo jps-checkpoint example.com --db-only --note "Before DB migration"

# List existing checkpoints
sudo jps-checkpoint example.com --list
```

**Exit Codes:**

- `0` - Checkpoint created successfully
- `1` - Error during checkpoint
- `2` - Invalid arguments or domain not found

### jps-site-suspend

Disable a site without deleting files or database.

```
Usage: jps-site-suspend <domain> [OPTIONS]
       jps-site-suspend --list

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -v, --verbose       Show detailed progress
  -r, --resume        Reactivate a suspended site
  -l, --list          List all suspended sites
  -f, --force         Skip confirmation prompt
  -n, --note NOTE     Add a note describing reason
  --no-reload         Don't reload OpenLiteSpeed after change
```

**Suspension Mechanism:**

- Renames `vhconf.conf` to `vhconf.conf.suspended`
- Creates suspension record in logs
- Reloads OpenLiteSpeed to apply changes
- Site files and database remain intact

**Examples:**

```bash
# Suspend a site
sudo jps-site-suspend example.com --note "Client non-payment"

# Resume a suspended site
sudo jps-site-suspend example.com --resume

# List all suspended sites
sudo jps-site-suspend --list

# Force suspend without confirmation
sudo jps-site-suspend example.com --force
```

**Exit Codes:**

- `0` - Operation completed successfully
- `1` - Error during operation
- `2` - Invalid arguments or domain not found

### jps-site-archive

Full site preservation for long-term storage.

```
Usage: jps-site-archive <domain> [OPTIONS]
       jps-site-archive --list

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -v, --verbose       Show detailed progress
  -l, --list          List all archived sites
  -n, --note NOTE     Add a note describing reason
  -e, --encrypt       Encrypt the archive (requires gpg)
  -o, --output DIR    Custom output directory
  --no-db             Skip database backup
  --no-vhost          Skip vhost config backup
```

**Archive Contents:**

| Component | Description |
|-----------|-------------|
| Files | Complete site directory |
| Database | Full MySQL dump with routines/triggers |
| Vhost Config | OpenLiteSpeed configuration |
| SSL Certificates | Let's Encrypt certificates (if local) |
| Metadata | Site info, WP version, archive date |

**Examples:**

```bash
# Create full archive
sudo jps-site-archive example.com --note "Client project completed"

# Encrypted archive
sudo jps-site-archive example.com --encrypt

# List all archives
sudo jps-site-archive --list

# Archive to custom location
sudo jps-site-archive example.com --output /mnt/backup/archives
```

**Exit Codes:**

- `0` - Archive created successfully
- `1` - Error during archive
- `2` - Invalid arguments or domain not found

### jps-site-delete

Safe site deletion with multiple confirmation steps.

```
Usage: jps-site-delete <domain> [OPTIONS]

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -v, --verbose       Show detailed progress
  -a, --archive       Create archive before deletion
  -y, --yes           Skip initial confirmation
  --dry-run           Show what would be deleted
  --no-db             Don't drop the database
  --no-vhost          Don't remove vhost config
  --keep-backups      Don't remove backup files
  -n, --note NOTE     Add a note to the deletion log
```

**Deletion Steps:**

1. Show summary of what will be deleted
2. Ask for initial confirmation
3. Require user to type domain name
4. Optionally create archive
5. Remove site files
6. Drop database (if WordPress)
7. Remove vhost configuration
8. Remove backups (optional)
9. Reload OpenLiteSpeed

**Safety Features:**

- Multiple confirmation prompts
- Must type full domain name to confirm
- Dry-run mode to preview changes
- Optional archive before deletion
- Comprehensive logging

**Examples:**

```bash
# Interactive deletion
sudo jps-site-delete example.com

# Archive before deleting
sudo jps-site-delete example.com --archive

# Preview what would be deleted
sudo jps-site-delete example.com --dry-run

# Delete files only (keep database)
sudo jps-site-delete example.com --no-db
```

**Exit Codes:**

- `0` - Deletion completed successfully
- `1` - Error during deletion
- `2` - Invalid arguments or domain not found
- `3` - User cancelled operation

### jps-install-stack

Install standard WordPress plugin/theme stack for new sites.

```
Usage: jps-install-stack <domain> [OPTIONS]

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -e, --ecomm         Include WooCommerce and ecommerce plugins
  -l, --list          List what would be installed (dry run)
  -q, --quiet         Suppress detailed output
```

**Standard Stack:**

| Type | Items |
|------|-------|
| Free Plugins | wpmudev-updates, mainwp-child, rank-math-seo, elementor, templately, developer-flavor-site-mailer, wpvivid-backuprestore, wpvivid-backup-mainwp, jetoce-developer-flavor-flexible-elementor-panel |
| Premium Plugins | elementor-pro, wpvivid-backup-pro, happyfiles-pro, nexter-pro-extensions-store |
| Themes | nexter (parent), nexter-child-jps (activated) |

**Asset Directory Structure:**

```
/usr/local/jps-assets/
├── plugins/
│   ├── elementor-pro.zip
│   ├── wpvivid-backup-pro.zip
│   ├── happyfiles-pro.zip
│   └── nexter-pro-extensions-store.zip
└── themes/
    └── nexter-child-jps.zip
```

**Examples:**

```bash
# Install standard stack
sudo jps-install-stack example.com

# Include WooCommerce
sudo jps-install-stack example.com --ecomm

# Preview what would be installed
sudo jps-install-stack example.com --list
```

**Exit Codes:**

- `0` - Installation completed (may have warnings)
- `1` - Critical error (missing WordPress, WP-CLI failed)
- `2` - Invalid arguments

### jps-validate-site

Post-migration site validation to ensure everything works correctly.

```
Usage: jps-validate-site <domain> [OPTIONS]

Options:
  -h, --help          Show help message
  -V, --version       Show version
  -q, --quick         Skip external HTTP checks (faster)
  -s, --quiet         Only show failures and warnings
  -j, --json          Output results as JSON
```

**Checks Performed:**

| Category | Checks |
|----------|--------|
| Quick (Local) | Directory exists, WordPress installed, WP-CLI works, Database connected, File permissions, wp-config.php security |
| External (HTTP) | Homepage loads, SSL valid, No mixed content, wp-admin accessible, REST API responding, Permalinks working |
| WordPress (WP-CLI) | No fatal errors, Active plugins, Active theme, Site URL matches, Home URL matches, Search engine visibility |

**Example Output:**

```
JPS Site Validator
==================
Target: example.com
Path: /usr/local/websites/example.com/html/

Quick Checks
  ✓ Directory exists
  ✓ WordPress installed
  ✓ WP-CLI connected (WP 6.7.1)
  ✓ Database connected
  ✓ File permissions OK (nobody:nogroup)
  ✓ wp-config.php secure (permissions 640)

External Checks
  ✓ Homepage loads (HTTP 200, 0.45s)
  ✓ SSL valid (expires in 83 days)
  ✓ No mixed content detected
  ✓ wp-admin accessible (HTTP 302)
  ✓ REST API responding
  ✓ Permalinks working (tested: sample-page)

WordPress Checks
  ✓ No fatal errors
  ✓ Plugins active (12)
  ✓ Theme active (flavor-starter-child)
  ✓ Site URL correct (https://example.com)
  ✓ Home URL correct (https://example.com)
  ⚠ Search engines (BLOCKED, blog_public=0)

==================
Summary
==================
Passed:   17
Warnings: 1
Failed:   0

Site is healthy with warnings.

Elapsed: 2.34s
```

**Examples:**

```bash
# Full validation
sudo jps-validate-site example.com

# Quick checks only (no HTTP requests)
sudo jps-validate-site example.com --quick

# JSON output for scripting
sudo jps-validate-site example.com --json

# Quiet mode - only failures and warnings
sudo jps-validate-site example.com --quiet
```

**Exit Codes:**

- `0` - All checks passed (warnings OK)
- `1` - One or more checks failed
- `2` - Invalid arguments or critical error

## Configuration

Edit `/opt/jps-server-tools/config/jps-tools.conf` to customize settings.

### Key Configuration Options

```bash
# Paths
WEBSITES_ROOT="/usr/local/websites"      # Website document roots
VHOSTS_DIR="/usr/local/lsws/conf/vhosts" # OLS virtual host configs
BACKUP_DIR="/var/backups/jps"            # Backup storage location

# Thresholds
DISK_WARN_PERCENT=80                     # Disk warning threshold
DISK_CRIT_PERCENT=90                     # Disk critical threshold
MEM_WARN_PERCENT=85                      # Memory warning threshold
SSL_WARN_DAYS=14                         # SSL expiry warning
SSL_CRIT_DAYS=7                          # SSL expiry critical

# Retention
AUDIT_RETENTION_DAYS=90                  # Keep audit logs for 90 days

# Lifecycle Management
ARCHIVE_DIR="/var/archives/jps"          # Long-term archive storage
CHECKPOINT_RETENTION_DAYS=30             # Auto-cleanup checkpoints
```

### Expected Directory Structure

The tools expect this server layout:

```
/usr/local/websites/
├── example.com/
│   └── html/
│       ├── wp-config.php
│       ├── wp-content/
│       ├── wp-admin/
│       └── wp-includes/
├── another-site.com/
│   └── html/
└── ...

/usr/local/lsws/conf/
├── httpd_config.conf
└── vhosts/
    ├── example.com/
    │   └── vhconf.conf
    └── another-site.com/
        └── vhconf.conf

/var/backups/jps/
├── example.com/
│   ├── example.com-2024-01-15.tar.gz
│   └── example.com-2024-01-14.tar.gz
└── another-site.com/
    └── another-site.com-2024-01-15.tar.gz
```

## Logs

All logs are stored in `/opt/jps-server-tools/logs/`:

```
logs/
├── audit/
│   ├── 2024-01-15-103045.json
│   └── 2024-01-14-103022.json
├── backup-verify/
│   ├── 2024-01-15.log
│   └── 2024-01-14.log
└── lifecycle/
    ├── checkpoint.log
    ├── suspend.log
    ├── archive.log
    └── delete.log
```

### Audit Logs

JSON snapshots with complete server state. Use for:
- Drift detection
- Historical analysis
- Compliance documentation

### Backup Verification Logs

Plain text logs recording verification results:

```
[2024-01-15 10:30:45] domain=example.com result=pass backup=example.com-2024-01-15.tar.gz
[2024-01-15 10:31:02] domain=another-site.com result=fail backup=another-site.com-2024-01-15.tar.gz
```

## Automation

### Cron Examples

```bash
# Daily audit at 6 AM, save for drift detection
0 6 * * * /usr/local/bin/jps-audit --save --quiet

# Weekly backup verification on Sundays at 3 AM
0 3 * * 0 /usr/local/bin/jps-backup-verify --all --quiet

# Daily brief audit to email
0 7 * * * /usr/local/bin/jps-audit --brief | mail -s "Server Audit" admin@example.com
```

### Integration with Monitoring

```bash
# Output JSON for monitoring systems
jps-audit --json | jq '.resources.memory.percent'

# Check for critical issues
if ! jps-audit --brief --quiet; then
    # Alert on drift
    send_alert "Server drift detected"
fi
```

## Troubleshooting

### Common Issues

**"Cannot find jps-common.sh library"**

The library file is missing. Reinstall:
```bash
sudo ./install.sh
```

**"jq not found" warnings**

Install jq for JSON features:
```bash
sudo apt install jq
```

**"WP-CLI not found"**

Install WP-CLI for WordPress operations:
```bash
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
```

**Database verification fails**

Ensure MySQL socket authentication works:
```bash
sudo mysql -e "SELECT 1"
```

Or configure credentials in `jps-tools.conf`:
```bash
MYSQL_USE_SOCKET=false
MYSQL_USER="root"
MYSQL_PASS="your-password"
```

**Permission denied errors**

Run with sudo:
```bash
sudo jps-audit
sudo jps-backup-verify example.com
```

### Debug Mode

Enable debug output:
```bash
DEBUG=1 jps-audit
DEBUG=1 jps-backup-verify example.com
```

### Verify Installation

```bash
sudo ./install.sh --check
```

## Project Structure

```
jps-server-tools/
├── bin/
│   ├── jps-audit           # Server audit script
│   ├── jps-backup-verify   # Backup verification script
│   ├── jps-status          # Site inventory table
│   ├── jps-monitor         # Health monitoring for cron
│   ├── jps-checkpoint      # Pre-change backup trigger
│   ├── jps-site-suspend    # Disable site without deleting
│   ├── jps-site-archive    # Full site preservation
│   ├── jps-site-delete     # Safe site deletion
│   ├── jps-install-stack   # WordPress plugin/theme installer
│   └── jps-validate-site   # Post-migration validation
├── lib/
│   └── jps-common.sh       # Shared functions library
├── config/
│   └── jps-tools.conf      # Configuration file
├── logs/
│   ├── audit/              # Audit JSON snapshots
│   ├── backup-verify/      # Verification logs
│   └── lifecycle/          # Lifecycle operation logs
├── install.sh              # Installer script
└── README.md               # This file
```

## Future Roadmap

Planned tools for future phases:

- **jps-ssl**: SSL certificate management and renewal
- **jps-security**: Security hardening and vulnerability scanning
- **jps-maintenance**: Automated maintenance tasks
- **jps-migrate**: Site migration between servers

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow the existing code style
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - See LICENSE file for details.

## Support

- **Issues**: https://github.com/yourusername/jps-server-tools/issues
- **Documentation**: This README and --help on each command

---

**JPS Server Tools** - Server-level management for WordPress hosting infrastructure.
