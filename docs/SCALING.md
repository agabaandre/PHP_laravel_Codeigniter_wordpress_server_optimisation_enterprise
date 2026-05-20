# Scaling guide

Baseline configs in `configs/` target **64 GB RAM / 8 CPUs**. For smaller servers, use `setup.sh --tier` or edit the same four areas manually.

## Capacity (WordPress, typical plugins, no full-page cache)

| Tier | RAM | CPUs | Sustained concurrent* | Brief spike |
|------|-----|------|----------------------|-------------|
| **XL** | 64 GB | 8 | 150–200 | ~250 |
| **L** | 32 GB | 4 | 80–100 | ~130 |
| **M** | 16 GB | 4 | 35–50 | ~65 |
| **S** | 8 GB | 4 | 15–25 | ~35 |

\*Active PHP requests at once, not daily visitors. With object/page cache, often **2–3×** higher.

**Rule of thumb:** sustained users ≈ `pm.max_children` × 2–3 when `memory_limit` is 256M.

---

## Four knobs (all tiers)

| Knob | File |
|------|------|
| MySQL buffer pool & connections | `configs/mysqld.cnf` |
| PHP concurrency | `configs/php-fpm-www.conf` |
| OPcache RAM | `configs/opcache.ini` |
| Apache workers (optional) | `configs/apache-mpm.conf` |

**Automated:** `sudo ./setup.sh --tier 32 --domain example.com --email you@example.com`

---

## 32 GB RAM / 4 CPUs

| Setting | Value |
|---------|--------|
| `innodb_buffer_pool_size` | `8G` |
| `innodb_buffer_pool_instances` | `4` |
| `max_connections` | `200` |
| `tmp_table_size` / `max_heap_table_size` | `256M` |
| `opcache.memory_consumption` | `512` |
| `opcache.interned_strings_buffer` | `64` |
| `pm.max_children` | `28` |
| `pm.start_servers` / `pm.min_spare_servers` | `4` / `4` |
| `pm.max_spare_servers` | `8` |
| `MaxRequestWorkers` | `200` |

---

## 16 GB RAM / 4 CPUs

| Setting | Value |
|---------|--------|
| `innodb_buffer_pool_size` | `4G` |
| `innodb_buffer_pool_instances` | `4` |
| `max_connections` | `150` |
| `tmp_table_size` / `max_heap_table_size` | `128M` |
| `opcache.memory_consumption` | `256` |
| `opcache.interned_strings_buffer` | `32` |
| `pm.max_children` | `14` |
| `pm.start_servers` / `pm.min_spare_servers` | `2` / `2` |
| `pm.max_spare_servers` | `4` |
| `MaxRequestWorkers` | `150` |

---

## 8 GB RAM / 4 CPUs

| Setting | Value |
|---------|--------|
| `innodb_buffer_pool_size` | `2G` |
| `innodb_buffer_pool_instances` | `2` |
| `max_connections` | `100` |
| `tmp_table_size` / `max_heap_table_size` | `64M` |
| `opcache.memory_consumption` | `128` |
| `opcache.interned_strings_buffer` | `16` |
| `pm.max_children` | `8` |
| `pm.start_servers` / `pm.min_spare_servers` | `2` / `2` |
| `pm.max_spare_servers` | `3` |
| `MaxRequestWorkers` | `100` |
| `memory_limit` in `configs/php.ini` | `192M` (set automatically by `setup.sh --tier 8`) |

On 8 GB, use a page-cache plugin and consider `opcache.validate_timestamps=1` until you have a deploy reload habit.

---

## After MySQL memory changes

```bash
sudo systemctl stop mysql
sudo rm -f /var/lib/mysql/ib_logfile*
sudo mysqld --validate-config
sudo systemctl start mysql
```

Only required when `innodb_log_file_size` (or related InnoDB log settings) change on an **existing** data directory.

---

## 64 GB baseline (reference)

| Component | Value |
|-----------|--------|
| `innodb_buffer_pool_size` | 16G |
| `memory_limit` | 256M |
| `pm.max_children` | 56 |
| `opcache.memory_consumption` | 1024 |
| `MaxRequestWorkers` | 400 |
