# openSUSE / SLES setup

**Tested stack:** Apache **2.4**, MariaDB **10.x**, PHP **8.3** (`php8-fpm`).

Change PHP: edit `PHP_MAJOR="8"` (and `PHP_VERSION` label) at the top of `setup-opensuse.sh`.

## Scripts

| Script | Mode |
|--------|------|
| `setup-opensuse.sh` | Non-interactive |
| `auto_setup-opensuse.sh` | Interactive |

Configs: `configs/opensuse/`

## Requirements

- openSUSE Leap 15.x / Tumbleweed or SLES 15+
- Packages: **apache2**, **php8-fpm**, **mariadb**

## Quick start

```bash
sudo ./auto_setup-opensuse.sh
```

Or:

```bash
sudo ./setup-opensuse.sh --domain example.com --email you@example.com
```

## Paths

| Component | Path |
|-----------|------|
| Apache vhosts | `/etc/apache2/conf.d/` |
| PHP-FPM | `/etc/php8/fpm/php-fpm.d/www.conf` |
| PHP ini | `/etc/php8/fpm/php.ini` |
| OPcache | `/etc/php8/fpm/conf.d/10-opcache-custom.ini` |
| Socket | `/run/php-fpm/www.sock` |
| Web user | `wwwrun` |
| MySQL | `/etc/my.cnf.d/wp-optimisation.cnf` |

## Services

```bash
systemctl status apache2 php8-fpm mariadb
sudo systemctl reload php8-fpm
```

## Firewall

**firewalld** — same flags as other scripts (`--skip-ufw` to skip).

## Notes

- PHP version is **8.x** from openSUSE repos (package names `php8-*`).
- `a2enmod` / `a2enconf` are used when available (Leap).
