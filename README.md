# WordPress Server Optimisation (Enterprise)

Production tuning for **WordPress on Ubuntu**: **Apache (event MPM)**, **PHP 8.3 FPM**, **MySQL 8**. One script applies everything; docs explain scaling and architecture.

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange)]()
[![PHP](https://img.shields.io/badge/PHP-8.3%20(FPM)-777BB4)]()
[![Apache](https://img.shields.io/badge/Apache-2.4%20(event)-D22128)]()
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1)]()

---

## Quick start (one command)

On a **new Ubuntu server**, clone the repo and run:

```bash
git clone <your-repo-url>
cd wordpress_server_optimisation_enterprise
sudo ./setup.sh --domain example.com --email admin@example.com
```

Other tiers (RAM class):

```bash
sudo ./setup.sh --tier 32 --domain example.com --email admin@example.com
sudo ./setup.sh --tier 16 --domain example.com --email admin@example.com
sudo ./setup.sh --tier 8  --skip-certbot   # HTTP only / no DNS yet
```

After every WordPress or code deploy:

```bash
sudo systemctl reload php8.3-fpm
```

---

## What `setup.sh` does

1. Installs PHP 8.3 (Ondřej PPA), Apache, MySQL, Certbot, fail2ban, mod_security  
2. Enables event MPM + PHP-FPM (disables mod_php)  
3. Applies tuned configs from `configs/` for your `--tier`  
4. Optionally runs Certbot and applies hardened SSL vhost  
5. Backs up replaced files under `/root/wp-opt-backup-*`

```bash
sudo ./setup.sh --help
```

| Flag | Description |
|------|-------------|
| `--domain` | Primary domain (required for SSL) |
| `--email` | Let's Encrypt email |
| `--tier` | `64` (default), `32`, `16`, or `8` |
| `--skip-certbot` | Skip SSL (HTTP only) |
| `--skip-ufw` | Skip firewall |
| `--reset-mysql-logs` | Remove `ib_logfile*` if InnoDB log resize fails |
| `--dry-run` | Print steps only |

---

## Repository layout

```
wordpress_server_optimisation_enterprise/
├── setup.sh                 ← One-shot installer (start here on server)
├── configs/
│   ├── mysqld.cnf
│   ├── php.ini
│   ├── opcache.ini
│   ├── php-fpm-www.conf
│   ├── apache-mpm.conf
│   ├── apache-vhost-http.conf
│   └── apache-vhost-ssl.conf
├── docs/
│   ├── SETUP.md             ← Manual steps / troubleshooting
│   ├── SCALING.md           ← Tier tables & capacity
│   └── DOCUMENT-FLOW.md     ← Architecture & install order
└── README.md
```

---

## Capacity by server size

WordPress, typical plugins, **no** full-page cache. See [docs/SCALING.md](docs/SCALING.md).

| Tier | `--tier` | RAM | CPUs | Sustained concurrent | Brief spike |
|------|----------|-----|------|---------------------|-------------|
| XL | `64` | 64 GB | 8 | **150–200** | ~250 |
| L | `32` | 32 GB | 4 | **80–100** | ~130 |
| M | `16` | 16 GB | 4 | **35–50** | ~65 |
| S | `8` | 8 GB | 4 | **15–25** | ~35 |

With object/page caching, sustained load is often **2–3×** higher.

---

## Documentation

| Doc | Use when |
|-----|----------|
| [docs/SETUP.md](docs/SETUP.md) | Manual install or debugging the script |
| [docs/SCALING.md](docs/SCALING.md) | Understanding tier values |
| [docs/DOCUMENT-FLOW.md](docs/DOCUMENT-FLOW.md) | How configs connect at runtime |

---

## Requirements

- Ubuntu 22.04 or 24.04 LTS  
- Root / sudo  
- DNS pointing to the server before Certbot (unless `--skip-certbot`)  
- WordPress in `/var/www/html` (default vhost)

---

## License

Configuration snippets are provided as-is. Add a license file if you publish publicly.
