# Scaling guide

Baseline configs in `configs/` match **`--tier 64`** (64 GB RAM / 8 CPUs). Use `setup.sh --tier` for any size, or edit the four knob files manually.

## Capacity (WordPress, typical plugins, no full-page cache)

| Tier | `--tier` | RAM | CPUs (typical) | Sustained concurrent* | Brief spike |
|------|----------|-----|----------------|----------------------|-------------|
| **XXL** | `128` | 128 GB | 16 | 280–350 | ~450 |
| **XL** | `64` | 64 GB | 8 | 150–200 | ~250 |
| **L** | `32` | 32 GB | 4 | 80–100 | ~130 |
| **M** | `16` | 16 GB | 4 | 35–50 | ~65 |
| **S** | `8` | 8 GB | 4 | 15–25 | ~35 |

\*Active PHP requests at once, not daily visitors. With object/page cache (Redis, etc.), often **2–3×** higher.

**Rule of thumb:** sustained users ≈ `pm.max_children` × 2–3 when `memory_limit` is 256M.

**Aliases:** `--tier xxl` = 128, `--tier xl` = 64, `--tier l` = 32, `--tier m` = 16, `--tier s` = 8.

---

## Four knobs (all tiers)

| Knob | File |
|------|------|
| MySQL buffer pool & connections | `configs/mysqld.cnf` |
| PHP concurrency | `configs/php-fpm-www.conf` |
| OPcache RAM | `configs/opcache.ini` |
| Apache workers | `configs/apache-mpm.conf` |

**Automated examples:**

```bash
sudo ./setup.sh --tier 128 --domain example.com --email you@example.com
sudo ./setup.sh --tier 64  --domain example.com --email you@example.com
sudo ./setup.sh --tier 32  --domain example.com --email you@example.com
```

---

## 128 GB RAM / 16 CPUs (XXL)

| Setting | Value |
|---------|--------|
| `innodb_buffer_pool_size` | `32G` |
| `innodb_buffer_pool_instances` | `16` |
| `max_connections` | `400` |
| `tmp_table_size` / `max_heap_table_size` | `768M` |
| `opcache.memory_consumption` | `2048` |
| `opcache.interned_strings_buffer` | `192` |
| `pm.max_children` | `96` |
| `pm.start_servers` / `pm.min_spare_servers` | `12` / `12` |
| `pm.max_spare_servers` | `24` |
| `ServerLimit` | `28` |
| `MaxRequestWorkers` | `700` |

---

## 64 GB RAM / 8 CPUs (XL)

| Setting | Value |
|---------|--------|
| `innodb_buffer_pool_size` | `16G` |
| `innodb_buffer_pool_instances` | `8` |
| `max_connections` | `300` |
| `tmp_table_size` / `max_heap_table_size` | `512M` |
| `opcache.memory_consumption` | `1024` |
| `opcache.interned_strings_buffer` | `128` |
| `pm.max_children` | `56` |
| `pm.start_servers` / `pm.min_spare_servers` | `8` / `8` |
| `pm.max_spare_servers` | `16` |
| `ServerLimit` | `16` |
| `MaxRequestWorkers` | `400` |

---

## 32 GB RAM / 4 CPUs (L)

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

## 16 GB RAM / 4 CPUs (M)

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

## 8 GB RAM / 4 CPUs (S)

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
