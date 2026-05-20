# RHEL-family setup (CentOS, Rocky, Alma, RHEL, Oracle Linux)

## Scripts

| Script | Mode |
|--------|------|
| `setup-rhel.sh` | Non-interactive (`--tier`, `--domain`, …) |
| `auto_setup-rhel.sh` | Interactive detect + calculate |

Configs: `configs/rhel/`

## Requirements

- EL 8 or 9 (or compatible) with `dnf`
- PHP **8.3** via [Remi repository](https://rpms.remirepo.net/)
- MariaDB/MySQL, **httpd**, **php-fpm**

## Quick start

```bash
sudo ./auto_setup-rhel.sh
```

Or:

```bash
sudo ./setup-rhel.sh --tier 64 --domain example.com --email you@example.com
sudo ./setup-rhel.sh --with-redis --domain example.com --email you@example.com
```

## Paths (differ from Debian)

| Component | Path |
|-----------|------|
| Apache | `/etc/httpd/conf.d/` |
| PHP ini | `/etc/php.ini` |
| OPcache drop-in | `/etc/php.d/10-opcache-custom.ini` |
| PHP-FPM pool | `/etc/php-fpm.d/www.conf` |
| Socket | `/run/php-fpm/www.sock` |
| Web user | `apache` |
| MySQL tuning | `/etc/my.cnf.d/wp-optimisation.cnf` |

## Services

```bash
systemctl status httpd php-fpm mariadb
sudo systemctl reload php-fpm
```

## SELinux

On enforcing systems the script runs:

```bash
setsebool -P httpd_can_network_connect 1
restorecon -Rv /var/www/html
```

Laravel queues or Redis over TCP may need additional booleans (`httpd_can_network_connect_db`, etc.).

## Firewall

Uses **firewalld** (not UFW). Skip with `--skip-ufw`.

## Laravel `public/` docroot

Point `DocumentRoot` in `/etc/httpd/conf.d/wp-vhost.conf` to `/var/www/html/public` after install.
