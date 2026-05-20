# PHP Application Server Optimisation (Enterprise)

Production tuning for **Apache (event MPM)**, **PHP-FPM**, and **MySQL/MariaDB**. Works for **WordPress**, **Laravel**, and **CodeIgniter**.

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange)]()
[![RHEL](https://img.shields.io/badge/RHEL-Rocky%20%7C%20Alma%20%7C%20CentOS-EE0000)]()
[![openSUSE](https://img.shields.io/badge/openSUSE-Leap%20%7C%20SLES-73BA25)]()
[![PHP](https://img.shields.io/badge/PHP-8.x%20(FPM)-777BB4)]()
[![Redis](https://img.shields.io/badge/Redis-optional-D82C20)]()

---

## Supported applications

| App | Works with this stack | Notes |
|-----|----------------------|--------|
| **WordPress** | Yes | Default `DocumentRoot` `/var/www/html`; `.htaccess` enabled |
| **Laravel** | Yes | Point vhost to `public/`; use Redis for cache, session, or queues |
| **CodeIgniter 4** | Yes | Point vhost to `public/` (CI4); CI3 often uses front controller in web root |

All three benefit from the same PHP-FPM, OPcache, and MySQL tuning. Capacity tables in [docs/SCALING.md](docs/SCALING.md) use WordPress as the reference load; Laravel/CodeIgniter with Redis and route caching are often similar or slightly leaner per request.

---

## Choose script for your OS

| OS | Interactive | Non-interactive | Configs |
|----|-------------|-----------------|---------|
| **Debian / Ubuntu** | `auto_setup.sh` | `setup.sh` | `configs/` |
| **RHEL / CentOS / Rocky / Alma** | `auto_setup-rhel.sh` | `setup-rhel.sh` | `configs/rhel/` |
| **openSUSE / SLES** | `auto_setup-opensuse.sh` | `setup-opensuse.sh` | `configs/opensuse/` |

All scripts share the same flags: `--tier`, `--domain`, `--email`, `--with-redis`, `--skip-certbot`, `--help`.

## Quick start

### Debian / Ubuntu

```bash
sudo ./auto_setup.sh
# or
sudo ./setup.sh --domain example.com --email admin@example.com
```

### RHEL family (Rocky, Alma, CentOS Stream, RHEL)

```bash
sudo ./auto_setup-rhel.sh
# or
sudo ./setup-rhel.sh --tier 64 --domain example.com --email you@example.com
```

### openSUSE / SLES

```bash
sudo ./auto_setup-opensuse.sh
# or
sudo ./setup-opensuse.sh --domain example.com --email you@example.com
```

Other tiers:

```bash
sudo ./setup.sh --tier 128 --with-redis --domain example.com --email admin@example.com
sudo ./setup.sh --tier 64  --domain example.com --email admin@example.com
sudo ./setup.sh --tier 32  --with-redis --domain example.com --email admin@example.com
sudo ./setup.sh --tier 8   --skip-certbot
```

After every deploy (OPcache production mode):

```bash
sudo systemctl reload php8.3-fpm
```

---

## Framework setup notes

### WordPress

- Deploy files to `/var/www/html`
- Run installer or `wp-cli`; database created manually (see [docs/SETUP.md](docs/SETUP.md))

### Laravel

1. Clone app to `/var/www/html` (or `/var/www/yourapp`)
2. Set Apache `DocumentRoot` to the app **`public`** folder, e.g. `/var/www/html/public`
3. Configure `.env`: `DB_*`, and if using Redis:

   ```env
   CACHE_DRIVER=redis
   SESSION_DRIVER=redis
   QUEUE_CONNECTION=redis
   REDIS_HOST=127.0.0.1
   REDIS_PORT=6379
   ```

4. Install dependencies and publish:

   ```bash
   cd /var/www/html
   sudo -u www-data composer install --no-dev --optimize-autoloader
   sudo -u www-data php artisan key:generate
   sudo -u www-data php artisan migrate --force
   sudo -u www-data php artisan config:cache
   sudo -u www-data php artisan route:cache
   ```

5. Fix permissions: `storage/` and `bootstrap/cache/` writable by `www-data`

### CodeIgniter 4

1. Point `DocumentRoot` to **`/var/www/html/public`**
2. Copy `env` to `.env` and set `database.default.*`
3. For Redis (optional): configure `Cache` / `Session` handlers in `.env` when `php8.3-redis` is installed

```bash
cd /var/www/html
sudo -u www-data composer install --no-dev
```

---

## Optional dependencies

Installed by **`setup.sh`** by default vs optional add-ons:

| Component | Default (`setup.sh`) | Optional | Typical use |
|-----------|---------------------|----------|-------------|
| PHP 8.3 FPM + extensions | Yes | — | All apps (mysql, xml, mbstring, curl, zip, gd, intl, bcmath, imagick, opcache) |
| Apache, MySQL, Certbot | Yes | — | Web + DB + SSL |
| Git, unzip | Yes | — | Deploy / Composer archives |
| **Redis** | No | `--with-redis` | Laravel/CodeIgniter cache, sessions, queues; WordPress object cache plugins |
| Composer | No | Manual | Laravel, CodeIgniter, modern WP plugins |
| Node.js / npm | No | Manual | Laravel Vite frontend builds |
| Supervisor | No | Manual | Laravel `queue:work` workers |
| Memcached | No | Manual | Alternative to Redis for object cache |

### Install Redis with setup

```bash
sudo ./setup.sh --with-redis --domain example.com --email admin@example.com
```

Installs `redis-server` and `php8.3-redis`, binds to `127.0.0.1:6379`.

### Install other extras manually

```bash
# Composer (Laravel / CodeIgniter)
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Node.js 20 LTS (Laravel assets)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Supervisor (Laravel queues) — example program
sudo apt install -y supervisor
```

| PHP package | When you need it |
|-------------|------------------|
| `php8.3-redis` | Redis cache/session/queue (`--with-redis`) |
| `php8.3-memcached` | Memcached instead of Redis |
| `php8.3-sqlite3` | SQLite testing or small apps |
| `php8.3-readline` | Interactive `artisan tinker` |

```bash
sudo apt install -y php8.3-memcached php8.3-sqlite3 php8.3-readline
```

---

## `auto_setup.sh` vs `setup.sh`

| Script | Use when |
|--------|----------|
| **`auto_setup.sh`** | New server; you want prompts and auto tuning from detected RAM/CPUs |
| **`setup.sh`** | You already know the tier (`--tier 64`) or automating via CI |

**Auto calculation** (option 1 in the wizard):

- MySQL buffer pool ≈ 25% of RAM (cap 32G)
- `pm.max_children` ≈ min(CPUs × 7, 75% of RAM in 256M units)
- OPcache scales with RAM; Apache workers scale with FPM children

**Preset tier** (option 2): picks nearest of 128 / 64 / 32 / 16 / 8 GB from detected RAM.

---

## What `setup.sh` does

1. Installs PHP 8.3 (Ondřej PPA), Apache, MySQL, Certbot, fail2ban, mod_security, git, unzip  
2. Optionally installs **Redis** (`--with-redis`)  
3. Enables event MPM + PHP-FPM (disables mod_php)  
4. Applies tuned configs from `configs/` for your `--tier`  
5. Optionally runs Certbot and applies hardened SSL vhost  
6. Backs up replaced files under `/root/wp-opt-backup-*`

```bash
sudo ./setup.sh --help
```

| Flag | Description |
|------|-------------|
| `--domain` | Primary domain (required for SSL) |
| `--email` | Let's Encrypt email |
| `--tier` | `128`, `64` (default), `32`, `16`, or `8` (aliases: `xxl`, `xl`, `l`, `m`, `s`) |
| `--with-redis` | Redis server + `php8.3-redis` |
| `--skip-certbot` | Skip SSL (HTTP only) |
| `--skip-ufw` | Skip firewall |
| `--reset-mysql-logs` | Remove `ib_logfile*` if InnoDB log resize fails |
| `--dry-run` | Print steps only |

---

## Repository layout

```
wordpress_server_optimisation_enterprise/
├── setup.sh                 ← Debian / Ubuntu
├── auto_setup.sh
├── setup-rhel.sh            ← RHEL, CentOS, Rocky, Alma, Oracle Linux
├── auto_setup-rhel.sh
├── setup-opensuse.sh        ← openSUSE Leap, Tumbleweed, SLES
├── auto_setup-opensuse.sh
├── configs/                 ← Debian/Ubuntu
├── configs/rhel/
├── configs/opensuse/
├── docs/
│   ├── SETUP.md
│   ├── SETUP-RHEL.md
│   ├── SETUP-OPENSUSE.md
│   ├── SCALING.md
│   └── DOCUMENT-FLOW.md
└── README.md
```

---

## Capacity by server size

Reference load: **WordPress**, typical plugins, no full-page cache. Laravel with Redis + `config:cache` is often in the same ballpark. See [docs/SCALING.md](docs/SCALING.md).

| Tier | `--tier` | RAM | CPUs | Sustained concurrent | Brief spike |
|------|----------|-----|------|---------------------|-------------|
| XXL | `128` | 128 GB | 16 | **280–350** | ~450 |
| XL | `64` | 64 GB | 8 | **150–200** | ~250 |
| L | `32` | 32 GB | 4 | **80–100** | ~130 |
| M | `16` | 16 GB | 4 | **35–50** | ~65 |
| S | `8` | 8 GB | 4 | **15–25** | ~35 |

With Redis object cache or full-page cache, sustained load is often **2–3×** higher.

---

## Documentation

| Doc | Use when |
|-----|----------|
| [docs/SETUP.md](docs/SETUP.md) | Manual install or debugging the script |
| [docs/SCALING.md](docs/SCALING.md) | Tier values and capacity |
| [docs/DOCUMENT-FLOW.md](docs/DOCUMENT-FLOW.md) | Config layout and install order |

---

## Requirements

- Root / sudo  
- DNS pointing to the server before Certbot (unless `--skip-certbot`)  
- App files under `/var/www/html` (use `public/` for Laravel / CI4)  

| Distro | Versions | PHP source |
|--------|----------|------------|
| Ubuntu / Debian | 22.04, 24.04 | Ondřej PPA (8.3) |
| Rocky / Alma / RHEL | 8, 9 | Remi (8.3) |
| openSUSE | Leap 15+, Tumbleweed | Distribution `php8-*` |

---

## License

Configuration snippets are provided as-is. Add a license file if you publish publicly.
