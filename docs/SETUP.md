# Server setup guide (Debian / Ubuntu)

**Tested stack:** MySQL **8.x**, Apache **2.4**, PHP **8.3** FPM (Ondřej PPA).

To use another PHP version, edit `PHP_VERSION` at the top of `setup.sh` (e.g. `8.2` or `8.4`), then run the script again.

## Automated (recommended)

**Interactive** — detects RAM/CPUs and calculates tuning:

```bash
git clone <your-repo-url>
cd wordpress_server_optimisation_enterprise
sudo ./auto_setup.sh
```

**Fixed tier:**

```bash
sudo ./setup.sh --domain YOUR_DOMAIN --email you@example.com
sudo ./setup.sh --tier 128 --domain YOUR_DOMAIN --email you@example.com
```

Tier examples:

```bash
sudo ./setup.sh --tier 128 --domain YOUR_DOMAIN --email you@example.com
sudo ./setup.sh --tier 64  --domain YOUR_DOMAIN --email you@example.com
sudo ./setup.sh --tier 32  --domain YOUR_DOMAIN --email you@example.com
sudo ./setup.sh --tier 8   --skip-certbot
```

The script installs packages, deploys `configs/`, restarts services, and runs Certbot unless `--skip-certbot` is set.

---

## Manual install

Use this if you need to debug or run steps separately. Configs live in `configs/`.

### 1. Packages

Same as `setup.sh`: Ondřej PHP PPA, PHP 8.3 FPM, Apache, MySQL, Certbot, fail2ban, mod_security.

### 2. Apache modules

```bash
sudo a2dismod mpm_prefork php8.1 php8.2 php8.3 2>/dev/null || true
sudo a2enmod mpm_event ssl rewrite headers proxy proxy_fcgi setenvif \
  http2 expires deflate remoteip security2
sudo a2enconf php8.3-fpm
```

### 3. Deploy configs

| Source | Destination |
|--------|-------------|
| `configs/apache-mpm.conf` | `/etc/apache2/mods-available/mpm_event.conf` |
| `configs/apache-vhost-http.conf` | `/etc/apache2/sites-available/000-default.conf` |
| `configs/mysqld.cnf` | `/etc/mysql/mysql.conf.d/mysqld.cnf` |
| `configs/php.ini` | `/etc/php/8.3/fpm/php.ini` |
| `configs/opcache.ini` | `/etc/php/8.3/fpm/conf.d/10-opcache-custom.ini` |
| `configs/php-fpm-www.conf` | `/etc/php/8.3/fpm/pool.d/www.conf` |

Replace `YOUR_DOMAIN` in vhosts. Adjust values per [SCALING.md](SCALING.md) if not 64 GB.

### 4. Restart

```bash
sudo mysqld --validate-config
sudo apachectl configtest
sudo systemctl restart mysql php8.3-fpm apache2
```

### 5. SSL

```bash
sudo certbot --apache -d YOUR_DOMAIN -d www.YOUR_DOMAIN --email you@example.com --agree-tos
```

Optional: copy `configs/apache-vhost-ssl.conf` over `*-le-ssl.conf` after Certbot (replace domain first).

### 6. WordPress database

```bash
sudo mysql -e "CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';"
sudo mysql -e "GRANT ALL ON wordpress.* TO 'wpuser'@'localhost'; FLUSH PRIVILEGES;"
```

### 7. After deploys

```bash
sudo systemctl reload php8.3-fpm
```

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| MySQL won't start after tuning | `sudo ./setup.sh --reset-mysql-logs` or stop mysql, remove `ib_logfile*`, start |
| Certbot fails | Check DNS; use `--skip-certbot` and fix DNS first |
| High swap | Lower tier or edit `pm.max_children` in `configs/php-fpm-www.conf` |
| 502 Bad Gateway | `systemctl status php8.3-fpm`; check socket `/run/php/php8.3-fpm.sock` |

```bash
systemctl status apache2 php8.3-fpm mysql
free -h
sudo tail -f /var/log/mysql/mysql-slow.log
```
