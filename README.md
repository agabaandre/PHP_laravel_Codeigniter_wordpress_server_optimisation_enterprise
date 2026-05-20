# PHP Application Server Optimisation (Enterprise)

Production tuning for **Apache 2.4 (event MPM)**, **PHP-FPM**, and **MySQL 8**. Works for **WordPress**, **Laravel**, and **CodeIgniter**.

**Contents:** [Objectives](#project-objectives) · [Why production tuning](#why-configure-for-production) · [Quick start](#quick-start) · [Production recommendations](#production-recommendations) · [Scaling](#capacity-by-server-size) · [Research paper (Africa CDC case study)](docs/research/Scaling-Health-Organisation-Websites.md)

---

## Project objectives

This repository exists to give teams a **repeatable, tested baseline** for PHP application servers—not a generic LAMP install, but a stack tuned and hardened for real traffic.

| Goal | What we provide |
|------|-----------------|
| **Performance** | MySQL, PHP-FPM, OPcache, and Apache sized to your RAM/CPUs (fixed tiers or auto-detect) |
| **Stability** | Predictable concurrent-user limits, slow-query logging, sane timeouts |
| **Security** | TLS, security headers, blocked sensitive files, bot/scraper rules, optional firewall |
| **Consistency** | Same approach on Debian, RHEL, and openSUSE via `setup*.sh` / `auto_setup*.sh` |
| **Speed to deploy** | One script installs packages, applies configs, and optionally runs Certbot |

The configs and scripts reflect how we run **WordPress, Laravel, and CodeIgniter** in production: PHP-FPM (not mod_php), event MPM, MySQL 8, and OPcache tuned for deploy workflows.

---

## Why configure for production?

A fresh VPS with default packages is **not** production-ready. Without tuning and hardening you risk:

- **Out-of-memory kills** — PHP-FPM children and MySQL buffer pool fight for RAM; the kernel kills processes under load.
- **502 / 504 errors** — Too few FPM workers or Apache connections; traffic spikes exhaust the pool.
- **Slow pages and DB meltdown** — Default MySQL settings under-cache InnoDB; every request hits disk.
- **Breaches and abuse** — Default or weak passwords, exposed `wp-config.php` / `.env`, open `xmlrpc.php`, scrapers hammering admin URLs.
- **Wasted hardware** — A 64 GB server behaves like 8 GB if buffer pools and workers are left at defaults.

Production configuration aligns **software limits with your hardware** and **closes common attack paths** before you go live. The setup scripts automate the OS layer; you still must harden application passwords, DNS/CDN, and private URLs (see [Production recommendations](#production-recommendations)).

---

### Tested stack

| Component | Version | Notes |
|-----------|---------|--------|
| **MySQL** | **8.x** | Oracle MySQL or MariaDB 10.x (MySQL 8 compatible) |
| **Apache** | **2.4** | `apache2` (Debian/Ubuntu/SUSE) or `httpd` (RHEL) |
| **PHP** | **8.3** FPM | Default in scripts; **you can change the version** (see below) |

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange)]()
[![RHEL](https://img.shields.io/badge/RHEL-Rocky%20%7C%20Alma%20%7C%20CentOS-EE0000)]()
[![openSUSE](https://img.shields.io/badge/openSUSE-Leap%20%7C%20SLES-73BA25)]()
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1)]()
[![Apache](https://img.shields.io/badge/Apache-2.4-D22128)]()
[![PHP](https://img.shields.io/badge/PHP-8.3%20(FPM)-777BB4)]()
[![Redis](https://img.shields.io/badge/Redis-optional-D82C20)]()

### Change PHP version

Edit the variable at the **top of the setup script** for your OS, then re-run. Vhost sockets and package names are updated automatically on Debian/Ubuntu.

| OS | Script | Variable | Example |
|----|--------|----------|---------|
| Debian / Ubuntu | `setup.sh` | `PHP_VERSION="8.3"` | `8.2`, `8.4` (Ondřej PPA) |
| RHEL family | `setup-rhel.sh` | `PHP_VERSION="8.3"` | Remi module `remi-8.3` |
| openSUSE | `setup-opensuse.sh` | `PHP_MAJOR="8"` | `php8-*` zypper packages |

Or pass at runtime:

```bash
sudo PHP_VERSION=8.4 ./setup.sh --domain example.com --email you@example.com
```

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

## Production recommendations

Use these **in addition to** running the setup scripts. They protect performance, availability, and data on live sites.

### Cloudflare (or similar CDN / WAF)

Put your domain behind **[Cloudflare](https://www.cloudflare.com/)** (or another CDN with WAF) before or right after launch.

| Benefit | Why it matters |
|---------|----------------|
| **DDoS & bad traffic filtering** | Absorbs volumetric attacks and many bots at the edge so your origin never sees them |
| **Caching** | Static assets and full-page cache reduce PHP/MySQL load (often **2–3×** more effective capacity) |
| **TLS at the edge** | Valid HTTPS for visitors; optional “Full (strict)” to origin with Certbot on the server |
| **Hidden origin IP** | Harder to bypass the CDN and hit the server directly—pair with firewall allowing only Cloudflare IPs if needed |
| **Rate limiting & Bot Fight Mode** | Slows credential stuffing, scraping, and brute force on `/wp-login.php`, `/login`, etc. |

**Typical setup:** DNS proxied (orange cloud) → SSL/TLS “Full (strict)” → cache rules for static files → WAF managed rules → optional geographic or IP rules for admin paths.

### Harden passwords and secrets (mandatory)

Default or installer-generated credentials are a leading cause of compromises. **Change everything before go-live:**

| Item | Action |
|------|--------|
| **MySQL `root`** | Set a strong password (`mysql_secure_installation`); disable remote root login |
| **Application DB user** | Dedicated user per app (e.g. `wpuser`) with **long random password**—only privileges needed on one database |
| **WordPress / Laravel / CI admin** | Unique strong passwords; enable 2FA where available |
| **SSH** | Key-based login; disable password auth for root; non-default port optional |
| **`.env` / `wp-config.php`** | Never commit to git; file permissions restrictive; blocked at web server (see below) |
| **Redis** | Bind `127.0.0.1` only (default with our `--with-redis` install); require `requirepass` if exposed |

Use a password manager. Rotate credentials after any team member leaves or repo leak.

### Protect private URLs from bots and crawlers

Admin, staging, and API paths should not be indexed or hammered by scrapers.

**Already in this repo (SSL vhost templates):**

- Blocks common **SEO/scraper bots** and empty User-Agents  
- Denies web access to **`.env`**, **`wp-config.php`**, **`.git`**, **`composer.lock`**  
- Disables **`xmlrpc.php`** (WordPress brute-force amplifier)  
- Security headers: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`  

Configs: `configs/apache-vhost-ssl.conf` (and `configs/rhel/`, `configs/opensuse/` variants).

**You should also:**

| Measure | Purpose |
|---------|---------|
| **Cloudflare WAF / rate limits** on `/wp-admin`, `/wp-login.php`, `/login`, `/admin` | Stops most automated login and scrape attempts |
| **Separate staging subdomain** | e.g. `staging.example.com`—**noindex** (`robots.txt` + meta), HTTP auth or Cloudflare Access; never open to the public internet without protection |
| **`robots.txt`** on production | Disallow admin/cart/checkout paths you do not want indexed (does not stop malicious bots—combine with WAF) |
| **fail2ban** | Installed by setup scripts—protects SSH; add jails for Apache auth failures if needed |
| **Restrict admin by IP** (optional) | Apache `Require ip` for `/wp-admin` or VPN-only access for high-risk sites |

Malicious bots ignore `robots.txt`. **Edge filtering (Cloudflare) + server rules (this repo) + strong auth** is the practical combination.

### Pre-launch checklist

- [ ] Run `auto_setup.sh` or `setup.sh` for your OS and tier  
- [ ] DNS → Cloudflare (or CDN) with SSL  
- [ ] Replace all default DB and admin passwords  
- [ ] Confirm sensitive files return **403** (test `.env`, `wp-config.php`)  
- [ ] Point Laravel/CodeIgniter `DocumentRoot` to `public/`  
- [ ] Enable app-level cache (Redis/object cache/page cache)  
- [ ] `sudo systemctl reload php-fpm` after each deploy (OPcache production mode)  

---

## Documentation

| Doc | Use when |
|-----|----------|
| [docs/SETUP.md](docs/SETUP.md) | Manual install or debugging the script |
| [docs/SCALING.md](docs/SCALING.md) | Tier values and capacity |
| [docs/DOCUMENT-FLOW.md](docs/DOCUMENT-FLOW.md) | Config layout and install order |
| [docs/research/Scaling-Health-Organisation-Websites.md](docs/research/Scaling-Health-Organisation-Websites.md) | Academic case study (Africa CDC); export to PDF |

---

## Requirements

- Root / sudo  
- DNS pointing to the server before Certbot (unless `--skip-certbot`)  
- App files under `/var/www/html` (use `public/` for Laravel / CI4)  

| Distro | Versions | PHP source | Default PHP |
|--------|----------|------------|-------------|
| Ubuntu / Debian | 22.04, 24.04 | Ondřej PPA | **8.3** |
| Rocky / Alma / RHEL | 8, 9 | Remi | **8.3** |
| openSUSE | Leap 15+, Tumbleweed | Distribution repos | **8.3** (`php8-*`) |

MySQL **8.x** and Apache **2.4** are installed from distribution repositories on all platforms.

---

## License

Configuration snippets are provided as-is. Add a license file if you publish publicly.
