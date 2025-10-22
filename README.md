# PMAgate 🔒

**Automated MySQL & phpMyAdmin installer with token-based security for Ubuntu servers**

## Features

- 🚀 One-command installation of MySQL + phpMyAdmin + nginx
- 🔐 Secure token-based URL access with 1-hour auto-expiration
- 🌐 Custom domain support
- 🔄 Automatic rollback on errors
- 🔑 Auto-generated strong passwords
- 🔧 Built-in token regeneration tool

## Requirements

- Ubuntu 20.04+ or Debian-based system
- PHP 8.3 (pre-installed)
- Root access
- Domain pointed to your server IP

## Quick Install

```bash
# Download and run
wget https://github.com/sharrpas/pmagate/pmagate.sh
chmod +x pmagate.sh
sudo ./pmagate.sh

# Enter your domain when prompted
Domain: pma.yourdomain.com
```

## Usage

### Access phpMyAdmin
```
http://pma.yourdomain.com/?token=YOUR_GENERATED_TOKEN
```

### View Credentials
```bash
sudo cat /root/.mysql_pma_credentials
```

### Regenerate Token or Password
```bash
sudo regenerate-pma-token
```

Choose from:
1. Regenerate phpMyAdmin token only
2. Regenerate MySQL root password only
3. Regenerate both

## File Locations

| Path | Description |
|------|-------------|
| `/usr/share/phpmyadmin/` | phpMyAdmin files |
| `/root/.mysql_pma_credentials` | Your credentials |
| `/var/log/mysql_pma_install.log` | Installation log |
| `/usr/local/bin/regenerate-pma-token` | Token tool |

## Security Features

- **Token Authentication**: Secure cookie-based access with auto-expiration
- **Strong Passwords**: 25-character auto-generated credentials
- **MySQL Hardening**: Removes test DBs, anonymous users, remote root access
- **Protected Files**: Proper permissions on all config files

## Troubleshooting

**Check Services:**
```bash
sudo systemctl status nginx
sudo systemctl status mysql
sudo systemctl status php8.3-fpm
```

**View Logs:**
```bash
sudo cat /var/log/mysql_pma_install.log
```

**Token Expired:** Clear browser cookies and use token URL again

## Configuration

### Change Token Timeout
Edit `/usr/share/phpmyadmin/config.inc.php`:
```php
$token_timeout = 3600; // seconds (default: 1 hour)
```

### Change Port
Edit `/etc/nginx/sites-available/phpmyadmin`:
```nginx
listen 80; // Change to desired port
```

Then restart: `sudo systemctl restart nginx`

## Uninstall

```bash
sudo systemctl stop mysql nginx php8.3-fpm
sudo apt-get purge -y mysql-server mysql-client
sudo rm -rf /usr/share/phpmyadmin /var/lib/mysql /etc/mysql
sudo rm /etc/nginx/sites-{enabled,available}/phpmyadmin
sudo rm /usr/local/bin/regenerate-pma-token
sudo rm /root/.mysql_pma_credentials
```

## Architecture

```
Browser → nginx (Port 80) → PHP-FPM 8.3 → MySQL
          ↓
    Token Validation (Cookie)
          ↓
      phpMyAdmin
```

## Security Recommendations

- ✅ Use HTTPS with Let's Encrypt SSL
- ✅ Configure firewall (UFW/iptables)



.# pmagate
