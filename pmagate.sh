#!/bin/bash

# MySQL and phpMyAdmin Installation Script with Token-Based Access
# Ubuntu Server with PHP 8.3, nginx
# Author: Auto-generated script
# Date: 2025-10-21

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOGFILE="/var/log/mysql_pma_install.log"
CREDENTIAL_FILE="/root/.mysql_pma_credentials"

# Track installed components for rollback
INSTALLED_PACKAGES=()
CREATED_FILES=()
CREATED_DIRS=()
MYSQL_INSTALLED=false
NGINX_CONFIGURED=false

# Function to log messages
log_message() {
    echo -e "${2}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOGFILE"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to generate random token
generate_token() {
    openssl rand -hex 32
}

# Cleanup function for rollback
cleanup_on_error() {
    log_message "ERROR DETECTED! Starting rollback process..." "$RED"
    
    # Stop services
    systemctl stop mysql 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    
    # Remove nginx configuration
    if [ "$NGINX_CONFIGURED" = true ]; then
        log_message "Removing nginx configuration..." "$YELLOW"
        rm -f /etc/nginx/sites-enabled/phpmyadmin
        rm -f /etc/nginx/sites-available/phpmyadmin
        systemctl restart nginx 2>/dev/null || true
    fi
    
    # Remove created directories
    for dir in "${CREATED_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            log_message "Removing directory: $dir" "$YELLOW"
            rm -rf "$dir"
        fi
    done
    
    # Remove created files
    for file in "${CREATED_FILES[@]}"; do
        if [ -f "$file" ]; then
            log_message "Removing file: $file" "$YELLOW"
            rm -f "$file"
        fi
    done
    
    # Remove MySQL if installed
    if [ "$MYSQL_INSTALLED" = true ]; then
        log_message "Removing MySQL..." "$YELLOW"
        systemctl stop mysql 2>/dev/null || true
        apt-get purge -y mysql-server mysql-client mysql-common 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /var/lib/mysql
        rm -rf /etc/mysql
    fi
    
    # Remove other installed packages
    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        log_message "Removing installed packages..." "$YELLOW"
        apt-get purge -y "${INSTALLED_PACKAGES[@]}" 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi
    
    log_message "Rollback completed. System restored to previous state." "$RED"
    exit 1
}

# Set trap for errors
trap cleanup_on_error ERR

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_message "Please run as root" "$RED"
    exit 1
fi

log_message "Starting MySQL and phpMyAdmin installation..." "$GREEN"

# Ask for domain name
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Domain Configuration${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${GREEN}Please enter your domain for phpMyAdmin${NC}"
echo -e "${YELLOW}Example: pma.gomjoo.ir${NC}"
echo -e "${YELLOW}Note: Make sure this domain points to your server IP${NC}"
echo ""
read -p "Domain: " PMA_DOMAIN

# Validate domain input
if [ -z "$PMA_DOMAIN" ]; then
    log_message "Domain cannot be empty!" "$RED"
    exit 1
fi

# Remove http:// or https:// if user included it
PMA_DOMAIN=$(echo "$PMA_DOMAIN" | sed 's~http[s]*://~~g' | sed 's~/.*~~g')

log_message "Domain set to: $PMA_DOMAIN" "$GREEN"
echo ""

# Check system requirements
log_message "Checking system requirements..." "$YELLOW"

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    log_message "Installing wget..." "$YELLOW"
    apt-get install -y wget
    INSTALLED_PACKAGES+=("wget")
fi

# Check if openssl is installed
if ! command -v openssl &> /dev/null; then
    log_message "Installing openssl..." "$YELLOW"
    apt-get install -y openssl
    INSTALLED_PACKAGES+=("openssl")
fi

# Check nginx
log_message "Checking nginx installation..." "$YELLOW"
if ! command -v nginx &> /dev/null; then
    log_message "nginx not found! Installing nginx..." "$YELLOW"
    apt-get update
    apt-get install -y nginx
    INSTALLED_PACKAGES+=("nginx")
    systemctl start nginx
    systemctl enable nginx
    log_message "nginx installed successfully" "$GREEN"
else
    log_message "nginx is already installed" "$GREEN"
fi

# Check if PHP 8.3 FPM is installed
log_message "Checking PHP 8.3 installation..." "$YELLOW"
if ! command -v php &> /dev/null; then
    log_message "PHP not found! Please install PHP 8.3 first." "$RED"
    exit 1
fi

PHP_VERSION=$(php -r 'echo PHP_VERSION;' | cut -d. -f1,2)
if [ "$PHP_VERSION" != "8.3" ]; then
    log_message "PHP version is $PHP_VERSION but 8.3 is required!" "$RED"
    exit 1
fi
log_message "PHP 8.3 detected" "$GREEN"

# Check and install PHP-FPM
if ! systemctl is-active --quiet php8.3-fpm 2>/dev/null; then
    log_message "PHP-FPM not running. Checking installation..." "$YELLOW"
    if ! dpkg -l | grep -q php8.3-fpm; then
        log_message "Installing PHP 8.3 FPM..." "$YELLOW"
        apt-get install -y php8.3-fpm
        INSTALLED_PACKAGES+=("php8.3-fpm")
    fi
    systemctl start php8.3-fpm
    systemctl enable php8.3-fpm
    log_message "PHP-FPM started successfully" "$GREEN"
else
    log_message "PHP-FPM is already running" "$GREEN"
fi

# Update package list
log_message "Updating package list..." "$YELLOW"
apt-get update

# Generate passwords
MYSQL_ROOT_PASSWORD=$(generate_password)
PMA_TOKEN=$(generate_token)

log_message "Generated secure credentials" "$GREEN"

# Install MySQL Server
log_message "Installing MySQL Server..." "$YELLOW"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y mysql-server
INSTALLED_PACKAGES+=("mysql-server")
MYSQL_INSTALLED=true

# Start MySQL service
log_message "Starting MySQL service..." "$YELLOW"
systemctl start mysql
systemctl enable mysql

# Wait for MySQL to be ready
log_message "Waiting for MySQL to be ready..." "$YELLOW"
sleep 5

# Secure MySQL installation and set root password
log_message "Configuring MySQL security..." "$YELLOW"

# Check current MySQL authentication method
log_message "Checking MySQL authentication..." "$YELLOW"

# Try connecting without password first (fresh install)
if mysql -e "SELECT 1;" 2>/dev/null; then
    log_message "MySQL accessible without password (fresh install)" "$GREEN"
    # Set root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';"
elif sudo mysql -e "SELECT 1;" 2>/dev/null; then
    log_message "MySQL requires sudo (unix_socket auth)" "$YELLOW"
    # Set root password using sudo
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';"
else
    log_message "Trying alternative authentication method..." "$YELLOW"
    # Try with debian-sys-maint credentials
    if [ -f /etc/mysql/debian.cnf ]; then
        DEBIAN_USER=$(grep user /etc/mysql/debian.cnf | head -n1 | awk '{print $3}')
        DEBIAN_PASS=$(grep password /etc/mysql/debian.cnf | head -n1 | awk '{print $3}')
        mysql -u "$DEBIAN_USER" -p"$DEBIAN_PASS" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null || true
    fi
fi

# Verify password was set
if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>/dev/null; then
    log_message "Failed to set MySQL root password!" "$RED"
    cleanup_on_error
fi

log_message "MySQL root password set successfully" "$GREEN"

# Secure MySQL installation
log_message "Securing MySQL installation..." "$YELLOW"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

log_message "MySQL secured successfully" "$GREEN"

# Install required PHP extensions for phpMyAdmin
log_message "Installing PHP extensions..." "$YELLOW"

# List of PHP extensions to install (excluding php8.3-json as it's built-in for PHP 8.3)
PHP_EXTENSIONS=(
    "php8.3-mbstring"
    "php8.3-zip"
    "php8.3-gd"
    "php8.3-curl"
    "php8.3-mysql"
    "php8.3-xml"
)

# Install each extension
for ext in "${PHP_EXTENSIONS[@]}"; do
    if ! dpkg -l | grep -q "^ii  $ext"; then
        log_message "Installing $ext..." "$YELLOW"
        if apt-get install -y "$ext" 2>/dev/null; then
            INSTALLED_PACKAGES+=("$ext")
            log_message "$ext installed successfully" "$GREEN"
        else
            log_message "Warning: Could not install $ext (may not be needed)" "$YELLOW"
        fi
    else
        log_message "$ext is already installed" "$GREEN"
    fi
done

# Restart PHP-FPM to load new extensions
systemctl restart php8.3-fpm

log_message "PHP extensions installation completed" "$GREEN"

# Download and install phpMyAdmin
log_message "Downloading phpMyAdmin..." "$YELLOW"
PMA_VERSION="5.2.1"
PMA_DIR="/usr/share/phpmyadmin"
PMA_DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"

cd /tmp
if wget -q "${PMA_DOWNLOAD_URL}" -O phpmyadmin.tar.gz; then
    log_message "phpMyAdmin downloaded successfully" "$GREEN"
else
    log_message "Failed to download phpMyAdmin!" "$RED"
    cleanup_on_error
fi

tar xzf phpmyadmin.tar.gz
mkdir -p "$PMA_DIR"
CREATED_DIRS+=("$PMA_DIR")
mv phpMyAdmin-${PMA_VERSION}-all-languages/* "$PMA_DIR/"
rm -rf phpMyAdmin-${PMA_VERSION}-all-languages phpmyadmin.tar.gz

# Create phpMyAdmin tmp directory
mkdir -p "$PMA_DIR/tmp"
chmod 777 "$PMA_DIR/tmp"

# Create phpMyAdmin configuration
log_message "Configuring phpMyAdmin..." "$YELLOW"
PMA_CONFIG="$PMA_DIR/config.inc.php"
BLOWFISH_SECRET=$(generate_password)

cat > "$PMA_CONFIG" << EOF
<?php
// phpMyAdmin configuration with token-based access

\$cfg['blowfish_secret'] = '${BLOWFISH_SECRET}';

// Token-based access configuration (using cookies instead of session)
\$valid_token = '${PMA_TOKEN}';
\$token_timeout = 3600; // 1 hour timeout
\$cookie_name = 'pma_token_auth';

// Check if token is provided in URL
if (isset(\$_GET['token']) && \$_GET['token'] === \$valid_token) {
    // Valid token provided, set cookie
    setcookie(\$cookie_name, \$valid_token, time() + \$token_timeout, '/', '', false, true);
    setcookie(\$cookie_name . '_time', time(), time() + \$token_timeout, '/', '', false, true);
    // Redirect to remove token from URL
    header('Location: ' . strtok(\$_SERVER['REQUEST_URI'], '?'));
    exit;
}

// Check if token cookie is valid
if (!isset(\$_COOKIE[\$cookie_name]) || \$_COOKIE[\$cookie_name] !== \$valid_token) {
    http_response_code(403);
    die('<html><head><title>Access Denied</title></head><body><h1>Access Denied</h1><p>Invalid or missing token. Please use the URL with token parameter.</p></body></html>');
}

// Check token timeout
if (isset(\$_COOKIE[\$cookie_name . '_time'])) {
    if (time() - \$_COOKIE[\$cookie_name . '_time'] > \$token_timeout) {
        // Token expired, clear cookies
        setcookie(\$cookie_name, '', time() - 3600, '/', '', false, true);
        setcookie(\$cookie_name . '_time', '', time() - 3600, '/', '', false, true);
        http_response_code(403);
        die('<html><head><title>Token Expired</title></head><body><h1>Token Expired</h1><p>Your token has expired. Please access with a valid token.</p></body></html>');
    }
    // Update last activity time
    setcookie(\$cookie_name . '_time', time(), time() + \$token_timeout, '/', '', false, true);
}

\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;

\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
\$cfg['TempDir'] = '/usr/share/phpmyadmin/tmp';

\$cfg['DefaultLang'] = 'en';
\$cfg['ServerDefault'] = 1;
\$cfg['VersionCheck'] = false;

\$cfg['LoginCookieValidity'] = 3600; // 1 hour
EOF

CREATED_FILES+=("$PMA_CONFIG")
chmod 640 "$PMA_CONFIG"
chown -R www-data:www-data "$PMA_DIR"

log_message "phpMyAdmin configured successfully" "$GREEN"

# Configure nginx
log_message "Configuring nginx..." "$YELLOW"
NGINX_CONFIG="/etc/nginx/sites-available/phpmyadmin"

cat > "$NGINX_CONFIG" << EOF
server {
    listen 80;
    server_name ${PMA_DOMAIN};
    
    root /usr/share/phpmyadmin;
    index index.php;
    
    access_log /var/log/nginx/phpmyadmin-access.log;
    error_log /var/log/nginx/phpmyadmin-error.log;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /(libraries|setup/frames|setup/libs) {
        deny all;
        return 404;
    }
}
EOF

CREATED_FILES+=("$NGINX_CONFIG")

# Enable nginx site
ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/phpmyadmin
NGINX_CONFIGURED=true

# Test nginx configuration
log_message "Testing nginx configuration..." "$YELLOW"
if nginx -t 2>&1 | tee -a "$LOGFILE"; then
    log_message "nginx configuration is valid" "$GREEN"
else
    log_message "nginx configuration test failed!" "$RED"
    cleanup_on_error
fi

# Restart services
log_message "Restarting services..." "$YELLOW"
systemctl restart php8.3-fpm
systemctl restart nginx

# Verify services are running
if ! systemctl is-active --quiet mysql; then
    log_message "MySQL failed to start!" "$RED"
    cleanup_on_error
fi

if ! systemctl is-active --quiet nginx; then
    log_message "nginx failed to start!" "$RED"
    cleanup_on_error
fi

if ! systemctl is-active --quiet php8.3-fpm; then
    log_message "PHP-FPM failed to start!" "$RED"
    cleanup_on_error
fi

log_message "All services are running" "$GREEN"

# Save credentials to file
log_message "Saving credentials..." "$YELLOW"
cat > "$CREDENTIAL_FILE" << EOF
========================================
MySQL & phpMyAdmin Installation Complete
========================================
Date: $(date)

Domain: ${PMA_DOMAIN}

MySQL Root Password: ${MYSQL_ROOT_PASSWORD}

phpMyAdmin Access URL:
http://${PMA_DOMAIN}/?token=${PMA_TOKEN}

phpMyAdmin Token: ${PMA_TOKEN}
Token Timeout: 1 hour (3600 seconds)

Login Credentials:
Username: root
Password: ${MYSQL_ROOT_PASSWORD}

IMPORTANT NOTES:
1. Make sure ${PMA_DOMAIN} points to your server IP
2. The token will expire after 1 hour of inactivity
3. Access phpMyAdmin using the URL with the token parameter
4. Store these credentials securely
5. To generate a new token, run: /usr/local/bin/regenerate-pma-token

To change token timeout, edit:
${PMA_CONFIG}

========================================
EOF

chmod 600 "$CREDENTIAL_FILE"

# Create token regeneration script
log_message "Creating token regeneration script..." "$YELLOW"
REGEN_SCRIPT="/usr/local/bin/regenerate-pma-token"

cat > "$REGEN_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash

# Token Regeneration Script for phpMyAdmin
# Generates new access token and optionally new MySQL root password

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CREDENTIAL_FILE="/root/.mysql_pma_credentials"
PMA_CONFIG="/usr/share/phpmyadmin/config.inc.php"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to generate random token
generate_token() {
    openssl rand -hex 32
}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}phpMyAdmin Token Regeneration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Read current domain from config
CURRENT_DOMAIN=$(grep "server_name" /etc/nginx/sites-available/phpmyadmin | awk '{print $2}' | tr -d ';')

# Ask what to regenerate
echo -e "${YELLOW}What would you like to regenerate?${NC}"
echo "1) phpMyAdmin token only"
echo "2) MySQL root password only"
echo "3) Both token and MySQL password"
echo ""
read -p "Choice (1/2/3): " CHOICE

case $CHOICE in
    1)
        # Regenerate token only
        NEW_TOKEN=$(generate_token)
        
        # Update config file
        sed -i "s/\$valid_token = '.*';/\$valid_token = '$NEW_TOKEN';/" "$PMA_CONFIG"
        
        echo ""
        echo -e "${GREEN}Token regenerated successfully!${NC}"
        echo ""
        echo -e "${YELLOW}New phpMyAdmin Access URL:${NC}"
        echo "http://${CURRENT_DOMAIN}/?token=${NEW_TOKEN}"
        echo ""
        echo -e "${YELLOW}New Token:${NC} ${NEW_TOKEN}"
        
        # Update credentials file
        sed -i "s|http://.*/?token=.*|http://${CURRENT_DOMAIN}/?token=${NEW_TOKEN}|" "$CREDENTIAL_FILE"
        sed -i "s/phpMyAdmin Token: .*/phpMyAdmin Token: ${NEW_TOKEN}/" "$CREDENTIAL_FILE"
        ;;
        
    2)
        # Regenerate MySQL password only
        echo ""
        read -sp "Enter current MySQL root password: " CURRENT_PASS
        echo ""
        
        # Test current password
        if ! mysql -u root -p"${CURRENT_PASS}" -e "SELECT 1;" 2>/dev/null; then
            echo -e "${RED}Invalid current password!${NC}"
            exit 1
        fi
        
        NEW_PASS=$(generate_password)
        
        # Update MySQL password
        mysql -u root -p"${CURRENT_PASS}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASS}';"
        
        echo ""
        echo -e "${GREEN}MySQL root password changed successfully!${NC}"
        echo ""
        echo -e "${YELLOW}New MySQL Root Password:${NC} ${NEW_PASS}"
        
        # Update credentials file
        sed -i "s/MySQL Root Password: .*/MySQL Root Password: ${NEW_PASS}/" "$CREDENTIAL_FILE"
        sed -i "/^Password: /s/Password: .*/Password: ${NEW_PASS}/" "$CREDENTIAL_FILE"
        ;;
        
    3)
        # Regenerate both
        echo ""
        read -sp "Enter current MySQL root password: " CURRENT_PASS
        echo ""
        
        # Test current password
        if ! mysql -u root -p"${CURRENT_PASS}" -e "SELECT 1;" 2>/dev/null; then
            echo -e "${RED}Invalid current password!${NC}"
            exit 1
        fi
        
        NEW_TOKEN=$(generate_token)
        NEW_PASS=$(generate_password)
        
        # Update config file
        sed -i "s/\$valid_token = '.*';/\$valid_token = '$NEW_TOKEN';/" "$PMA_CONFIG"
        
        # Update MySQL password
        mysql -u root -p"${CURRENT_PASS}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASS}';"
        
        echo ""
        echo -e "${GREEN}Token and password regenerated successfully!${NC}"
        echo ""
        echo -e "${YELLOW}New phpMyAdmin Access URL:${NC}"
        echo "http://${CURRENT_DOMAIN}/?token=${NEW_TOKEN}"
        echo ""
        echo -e "${YELLOW}New Token:${NC} ${NEW_TOKEN}"
        echo -e "${YELLOW}New MySQL Root Password:${NC} ${NEW_PASS}"
        
        # Update credentials file
        sed -i "s|http://.*/?token=.*|http://${CURRENT_DOMAIN}/?token=${NEW_TOKEN}|" "$CREDENTIAL_FILE"
        sed -i "s/phpMyAdmin Token: .*/phpMyAdmin Token: ${NEW_TOKEN}/" "$CREDENTIAL_FILE"
        sed -i "s/MySQL Root Password: .*/MySQL Root Password: ${NEW_PASS}/" "$CREDENTIAL_FILE"
        sed -i "/^Password: /s/Password: .*/Password: ${NEW_PASS}/" "$CREDENTIAL_FILE"
        ;;
        
    *)
        echo -e "${RED}Invalid choice!${NC}"
        exit 1
        ;;
esac

# Update date in credentials file
sed -i "s/Date: .*/Date: $(date)/" "$CREDENTIAL_FILE"

echo ""
echo -e "${GREEN}Credentials updated in: ${CREDENTIAL_FILE}${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Clear your browser cookies for the domain to use the new token${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
EOFSCRIPT

chmod +x "$REGEN_SCRIPT"
CREATED_FILES+=("$REGEN_SCRIPT")

log_message "Token regeneration script created at: $REGEN_SCRIPT" "$GREEN"

# Display credentials
log_message "Installation completed successfully!" "$GREEN"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MySQL & phpMyAdmin Installed Successfully${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}MySQL Root Password:${NC} ${MYSQL_ROOT_PASSWORD}"
echo ""
echo -e "${YELLOW}phpMyAdmin Access URL:${NC}"
echo "http://${SERVER_IP}:8080/?token=${PMA_TOKEN}"
echo ""
echo -e "${YELLOW}phpMyAdmin Token:${NC} ${PMA_TOKEN}"
echo -e "${YELLOW}Token Timeout:${NC} 1 hour"
echo ""
echo -e "${YELLOW}Login Credentials:${NC}"
echo "Username: root"
echo "Password: ${MYSQL_ROOT_PASSWORD}"
echo ""
echo -e "${GREEN}Credentials saved to:${NC} ${CREDENTIAL_FILE}"
echo -e "${GREEN}Installation log:${NC} ${LOGFILE}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "1. The token will expire after 1 hour of inactivity"
echo "2. Store these credentials securely"
echo "3. Consider setting up firewall rules for port 8080"
echo "4. You can view saved credentials anytime: cat ${CREDENTIAL_FILE}"
echo ""
echo -e "${GREEN}========================================${NC}"

log_message "All operations completed successfully!" "$GREEN"
