#!/bin/bash

# ==============================================================================
# ENTERPRISE SIGNOZ AGENT PROVISIONER (Self-Contained / Binary Mode)
# Features:
# - Downloads Official Binary directly (Bypasses broken external scripts)
# - Auto-detects OS/Arch (AMD64/ARM64)
# - Creates Systemd Service automatically
# - Configures MySQL/PHP monitoring
#
# Environment Variables (for non-interactive mode):
#   SIGNOZ_ENDPOINT     - Required. SigNoz endpoint (e.g., signoz.5lab.co:443)
#   ENABLE_MYSQL        - Optional. "y" to enable MySQL monitoring
#   MYSQL_USER          - MySQL username (required if ENABLE_MYSQL=y)
#   MYSQL_PASS          - MySQL password (required if ENABLE_MYSQL=y)
#   MYSQL_HOST          - MySQL host (default: 127.0.0.1:3306)
#   ENABLE_PHPFPM       - Optional. "y" to enable PHP-FPM monitoring
#   ENABLE_PHP_OTEL     - Optional. "y" to install OpenTelemetry PHP extensions
# ==============================================================================

set -e

# --- Visuals ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# --- Detect Interactive Mode ---
INTERACTIVE=false
if [[ -t 0 ]]; then
    INTERACTIVE=true
fi

prompt_user() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "$prompt" user_input
        eval "$var_name=\"\${user_input:-$default}\""
    else
        eval "$var_name=\"$default\""
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local env_var="$2"
    
    # Check if env var is already set
    local current_val="${!env_var}"
    if [[ -n "$current_val" ]]; then
        [[ "$current_val" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "$prompt" user_input
        [[ "$user_input" =~ ^[Yy]$ ]] && return 0 || return 1
    else
        return 1  # Default to no in non-interactive mode
    fi
}

# --- 1. Root Check ---
if [[ $EUID -ne 0 ]]; then
   log_err "This script must be run as root (sudo)." 
   exit 1
fi

# --- 2. Endpoint & Pre-checks ---
log_info "Phase 1: Connectivity Checks"

if [ -z "$SIGNOZ_ENDPOINT" ]; then
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo "Please enter your SigNoz Endpoint (e.g., signoz.5lab.co:443):"
        read -r USER_ENDPOINT
        [ -z "$USER_ENDPOINT" ] && { log_err "Endpoint cannot be empty."; exit 1; }
        SIGNOZ_ENDPOINT="$USER_ENDPOINT"
    else
        log_err "SIGNOZ_ENDPOINT environment variable is required in non-interactive mode."
        echo "Usage: SIGNOZ_ENDPOINT=\"host:port\" bash install.sh"
        exit 1
    fi
fi

HOST=$(echo $SIGNOZ_ENDPOINT | cut -d: -f1)
PORT=$(echo $SIGNOZ_ENDPOINT | cut -d: -f2)

# Determine TLS Mode
TLS_INSECURE="true"
[[ "$PORT" == "443" ]] && TLS_INSECURE="false"

# --- 3. Workload Detection ---
log_info "Phase 2: Workload Detection"

MODULES_CONFIG=""
ACTIVE_RECEIVERS="[hostmetrics, otlp]"

add_module() {
    local name=$1
    local config=$2
    MODULES_CONFIG="$MODULES_CONFIG
$config"
    ACTIVE_RECEIVERS="${ACTIVE_RECEIVERS%,*}, $name]"
}

# MySQL Detection
if pgrep -x "mysqld" >/dev/null || pgrep -x "mariadbd" >/dev/null; then
    echo ""
    log_info "MySQL/MariaDB detected."
    if prompt_yes_no "   Enable MySQL Monitoring? (y/n): " "ENABLE_MYSQL"; then
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "   MySQL User: " MYSQL_USER
            read -s -p "   MySQL Password: " MYSQL_PASS
            echo ""
            read -p "   MySQL Host (Default: 127.0.0.1:3306): " input_host
            MYSQL_HOST=${input_host:-127.0.0.1:3306}
        else
            # Non-interactive: require env vars
            if [[ -z "$MYSQL_USER" || -z "$MYSQL_PASS" ]]; then
                log_err "MYSQL_USER and MYSQL_PASS required when ENABLE_MYSQL=y"
                exit 1
            fi
            MYSQL_HOST=${MYSQL_HOST:-127.0.0.1:3306}
        fi
        
        add_module "mysql" "  mysql:
    endpoint: \"$MYSQL_HOST\"
    username: \"$MYSQL_USER\"
    password: \"$MYSQL_PASS\"
    collection_interval: 30s
    transport: tcp"
    fi
fi

# PHP-FPM Metrics Detection
if pgrep "php-fpm" >/dev/null; then
    echo ""
    log_info "PHP-FPM detected."
    if prompt_yes_no "   Enable PHP-FPM Monitoring? (y/n): " "ENABLE_PHPFPM"; then
        
        # Find PHP-FPM pool config
        PHP_FPM_POOL=""
        for pool_path in /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/www.conf /etc/php/fpm/pool.d/www.conf; do
            if [[ -f "$pool_path" ]]; then
                PHP_FPM_POOL="$pool_path"
                break
            fi
        done
        
        STATUS_PATH="/signoz-status"
        
        if [[ -n "$PHP_FPM_POOL" ]]; then
            log_info "Found pool config: $PHP_FPM_POOL"
            
            # Check if status_path already enabled
            if grep -q "^pm.status_path" "$PHP_FPM_POOL"; then
                CURRENT_STATUS=$(grep "^pm.status_path" "$PHP_FPM_POOL" | cut -d= -f2 | tr -d ' ')
                log_info "Status path already configured: $CURRENT_STATUS"
                STATUS_PATH="$CURRENT_STATUS"
            else
                # In non-interactive mode, auto-configure
                SHOULD_CONFIGURE=false
                if [[ "$INTERACTIVE" == "true" ]]; then
                    read -p "   Configure pm.status_path = $STATUS_PATH in PHP-FPM? (y/n): " CONFIGURE_STATUS
                    [[ "$CONFIGURE_STATUS" =~ ^[Yy]$ ]] && SHOULD_CONFIGURE=true
                else
                    SHOULD_CONFIGURE=true  # Auto-configure in non-interactive
                fi
                
                if [[ "$SHOULD_CONFIGURE" == "true" ]]; then
                    # Backup original
                    cp "$PHP_FPM_POOL" "${PHP_FPM_POOL}.bak.$(date +%s)"
                    
                    # Add status_path config
                    echo "" >> "$PHP_FPM_POOL"
                    echo "; SigNoz PHP-FPM monitoring" >> "$PHP_FPM_POOL"
                    echo "pm.status_path = $STATUS_PATH" >> "$PHP_FPM_POOL"
                    echo "pm.status_listen = 127.0.0.1:9001" >> "$PHP_FPM_POOL"
                    
                    log_success "Added pm.status_path to $PHP_FPM_POOL"
                    
                    # Restart PHP-FPM (auto in non-interactive)
                    SHOULD_RESTART=false
                    if [[ "$INTERACTIVE" == "true" ]]; then
                        read -p "   Restart PHP-FPM to apply changes? (y/n): " RESTART_FPM
                        [[ "$RESTART_FPM" =~ ^[Yy]$ ]] && SHOULD_RESTART=true
                    else
                        SHOULD_RESTART=true
                    fi
                    
                    if [[ "$SHOULD_RESTART" == "true" ]]; then
                        systemctl restart php*-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || log_err "Could not restart PHP-FPM"
                        log_success "PHP-FPM restarted"
                    fi
                fi
            fi
            
            # Show web server config needed
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}Web Server Configuration Required${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "Add this to your Nginx config (inside server block):"
            echo -e "${YELLOW}location = $STATUS_PATH {"
            echo "    access_log off;"
            echo "    allow 127.0.0.1;"
            echo "    deny all;"
            echo "    include fastcgi_params;"
            echo "    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;"
            echo "    fastcgi_pass unix:/run/php/php-fpm.sock;  # or 127.0.0.1:9000"
            echo -e "}${NC}"
            echo ""
            echo "Or for Apache (in VirtualHost):"
            echo -e "${YELLOW}<Location $STATUS_PATH>"
            echo "    Require local"
            echo "    SetHandler \"proxy:fcgi://127.0.0.1:9000\""
            echo -e "</Location>${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            PHP_URL="http://127.0.0.1${STATUS_PATH}"
        else
            log_info "Could not find PHP-FPM pool config."
            echo "   Make sure pm.status_path is enabled in your www.conf"
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "   Status URL (Default: http://127.0.0.1/status): " PHP_URL
            fi
            PHP_URL=${PHP_URL:-http://127.0.0.1/status}
        fi
        
        add_module "phpfpm" "  phpfpm:
    endpoint: \"$PHP_URL\"
    collection_interval: 30s"
        
        log_success "PHP-FPM monitoring configured for: $PHP_URL"
    fi
fi

# PHP Tracing (OpenTelemetry) Detection
if command -v php &>/dev/null; then
    echo ""
    log_info "PHP detected. Checking OpenTelemetry tracing support..."
    
    OTEL_EXT=$(php -m 2>/dev/null | grep -i "^opentelemetry$" || true)
    PROTOBUF_EXT=$(php -m 2>/dev/null | grep -i "^protobuf$" || true)
    
    if [[ -n "$OTEL_EXT" && -n "$PROTOBUF_EXT" ]]; then
        log_success "OpenTelemetry PHP extensions already installed."
    else
        echo -e "   ${YELLOW}Missing extensions:${NC}"
        [[ -z "$OTEL_EXT" ]] && echo "     - opentelemetry"
        [[ -z "$PROTOBUF_EXT" ]] && echo "     - protobuf"
        echo ""
        if prompt_yes_no "   Install OpenTelemetry PHP extensions via PECL? (y/n): " "ENABLE_PHP_OTEL"; then
            # Check for PECL
            if ! command -v pecl &>/dev/null; then
                log_err "PECL not found. Install php-pear first:"
                echo "   Ubuntu/Debian: sudo apt install php-pear php-dev"
                echo "   RHEL/CentOS:   sudo yum install php-pear php-devel"
            else
                log_info "Installing OpenTelemetry PHP extensions..."
                pecl install opentelemetry || log_err "Failed to install opentelemetry extension"
                pecl install protobuf || log_err "Failed to install protobuf extension"
                
                # Find php.ini path
                PHP_INI=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
                if [[ -n "$PHP_INI" && -f "$PHP_INI" ]]; then
                    if ! grep -q "extension=opentelemetry" "$PHP_INI"; then
                        echo -e "\n[opentelemetry]\nextension=opentelemetry.so\nextension=protobuf.so" >> "$PHP_INI"
                        log_success "Extensions added to $PHP_INI"
                    fi
                else
                    log_info "Add these lines to your php.ini manually:"
                    echo "   extension=opentelemetry.so"
                    echo "   extension=protobuf.so"
                fi
            fi
        fi
    fi
    
    # Always show environment variable guide
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}PHP Tracing Guide${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "To send traces from PHP apps, run with these environment variables:"
    echo ""
    echo -e "${YELLOW}OTEL_PHP_AUTOLOAD_ENABLED=true \\\\${NC}"
    echo -e "${YELLOW}OTEL_SERVICE_NAME=my-php-app \\\\${NC}"
    echo -e "${YELLOW}OTEL_TRACES_EXPORTER=otlp \\\\${NC}"
    echo -e "${YELLOW}OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \\\\${NC}"
    echo -e "${YELLOW}OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \\\\${NC}"
    echo -e "${YELLOW}OTEL_PROPAGATORS=baggage,tracecontext \\\\${NC}"
    echo -e "${YELLOW}php -S localhost:8080 app.php${NC}"
    echo ""
    echo "Or add to your PHP-FPM pool config (www.conf):"
    echo "   env[OTEL_PHP_AUTOLOAD_ENABLED] = true"
    echo "   env[OTEL_SERVICE_NAME] = my-php-app"
    echo "   env[OTEL_TRACES_EXPORTER] = otlp"
    echo "   env[OTEL_EXPORTER_OTLP_PROTOCOL] = http/protobuf"
    echo "   env[OTEL_EXPORTER_OTLP_ENDPOINT] = http://localhost:4318"
    echo ""
    echo "Composer dependencies (run in your PHP project):"
    echo -e "   ${YELLOW}composer require open-telemetry/sdk open-telemetry/exporter-otlp php-http/guzzle7-adapter${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# --- 4. Manual Installation (The Fix) ---
log_info "Phase 3: Installing Binary"

# Determine Arch
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) log_err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Define Paths
INSTALL_DIR="/opt/signoz-otel-collector"
CONFIG_DIR="/etc/signoz-otel-collector"
BINARY_URL="https://github.com/SigNoz/signoz-otel-collector/releases/latest/download/signoz-otel-collector_linux_${ARCH}.tar.gz"

# Create Users & Dirs
id -u signoz-otel-collector &>/dev/null || useradd -r -s /bin/false signoz-otel-collector
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
chown -R signoz-otel-collector:signoz-otel-collector "$INSTALL_DIR" "$CONFIG_DIR"

# Download & Extract
log_info "Downloading from: $BINARY_URL"
curl -L -o /tmp/signoz-collector.tar.gz "$BINARY_URL"
tar -xzf /tmp/signoz-collector.tar.gz -C "$INSTALL_DIR"
# Move binary to root of install dir if nested
find "$INSTALL_DIR" -type f -name "signoz-otel-collector" -exec mv {} "$INSTALL_DIR/" \;
chmod +x "$INSTALL_DIR/signoz-otel-collector"

# --- 5. Generate Systemd Service ---
log_info "Phase 4: Creating Service"

cat <<EOF > /etc/systemd/system/signoz-otel-collector.service
[Unit]
Description=SigNoz OpenTelemetry Collector
After=network.target

[Service]
User=signoz-otel-collector
Group=signoz-otel-collector
ExecStart=$INSTALL_DIR/signoz-otel-collector --config $CONFIG_DIR/config.yaml
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# --- 6. Generate Config ---
log_info "Phase 5: Writing Configuration"

cat <<EOF > "$CONFIG_DIR/config.yaml"
receivers:
  otlp:
    protocols:
      grpc:
      http:
  hostmetrics:
    collection_interval: 30s
    scrapers:
      cpu:
      load:
      memory:
      disk:
      filesystem:
      paging:
      network:
  filelog/syslog:
    include: [ /var/log/**/*.log ]

$MODULES_CONFIG

processors:
  batch:
    send_batch_size: 1000
    timeout: 10s
  resourcedetection:
    detectors: [env, system]
    timeout: 2s
    override: false

exporters:
  otlp:
    endpoint: "$SIGNOZ_ENDPOINT"
    tls:
      insecure: $TLS_INSECURE

service:
  pipelines:
    metrics:
      receivers: $ACTIVE_RECEIVERS
      processors: [resourcedetection, batch]
      exporters: [otlp]
    logs:
      receivers: [filelog/syslog]
      processors: [resourcedetection, batch]
      exporters: [otlp]
    traces:
      receivers: [otlp]
      processors: [resourcedetection, batch]
      exporters: [otlp]
EOF

chown signoz-otel-collector:signoz-otel-collector "$CONFIG_DIR/config.yaml"

# --- 7. Start ---
log_info "Phase 6: Launching"
systemctl enable --now signoz-otel-collector
sleep 3

if systemctl is-active --quiet signoz-otel-collector; then
    log_success "Installation Complete! Agent is running."
else
    log_err "Service failed to start. Logs:"
    journalctl -u signoz-otel-collector -n 20 --no-pager
    exit 1
fi