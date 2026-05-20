---
title: "Scaling Health Organisation Websites for Public-Health Emergencies: A Production-Stack Optimisation Case Study of the Africa CDC Web Platform"
author: "Agaba Andrew"
affiliation: "Africa Centres for Disease Control and Prevention (Africa CDC), Division of Digital Health and Information Systems"
date: "May 2026"
keywords: "public health informatics, web scalability, WordPress, PHP-FPM, MySQL, Africa CDC, health emergency communication, web security"
---

# Scaling Health Organisation Websites for Public-Health Emergencies: A Production-Stack Optimisation Case Study of the Africa CDC Web Platform

**Agaba Andrew**  
Software Engineer, Division of Digital Health and Information Systems  
Africa Centres for Disease Control and Prevention (Africa CDC)  
Addis Ababa, Ethiopia  
*Correspondence: practitioner documentation accompanying the WordPress Server Optimisation (Enterprise) open-source project.*

---

## Abstract

Health organisations increasingly depend on web platforms to disseminate time-sensitive guidance during outbreaks and public-health emergencies. When traffic surges coincide with news alerts or media coverage, websites running default operating-system and application stacks frequently become unavailable—undermining trust and access to evidence-based information. This paper documents a practitioner-led optimisation initiative motivated by operational failures observed on the Africa Centres for Disease Control and Prevention (Africa CDC) website (*africacdc.org*) during heightened demand associated with the 2026 Congo and Uganda Ebola virus disease communications period (11–19 May 2026). We describe the technical baseline (default Apache, PHP, and MySQL configurations), the production-oriented tuning methodology applied, and the open-source automation framework developed to generalise the approach across Debian/Ubuntu, RHEL, and openSUSE environments. The work addresses performance sizing (PHP-FPM, OPcache, InnoDB buffer pool), transport and application security (TLS, headers, bot mitigation, credential hygiene), and edge-protection recommendations (CDN/WAF). We conclude that health-sector digital teams require repeatable, evidence-informed server baselines—not ad hoc tuning—to sustain availability when populations seek information under crisis conditions.

**Keywords:** public health informatics; web scalability; WordPress; PHP-FPM; MySQL 8; health emergency communication; web application security; Africa CDC

---

## 1. Introduction

### 1.1 Context

Digital channels are now primary interfaces between health agencies and the public during emergencies. The World Health Organization and regional bodies routinely direct populations to institutional websites for situation reports, prevention guidance, and press materials (WHO, 2024). In the African context, the Africa CDC coordinates continental public-health intelligence and outbreak communication; its website functions as an authoritative source during events such as viral haemorrhagic fever outbreaks (Africa CDC, 2026).

Unlike commercial e-commerce platforms, health information sites experience **extreme burstiness**: traffic may remain moderate for weeks, then increase by orders of magnitude within minutes when (a) a news alert is distributed, (b) social media amplifies a link, or (c) international media covers an outbreak. If the hosting stack is provisioned for average load but not configured for concurrency, users perceive “the site is down” precisely when information is most critical.

### 1.2 Problem statement

Many organisations deploy common content-management and application frameworks—**WordPress**, **Laravel**, **CodeIgniter**, Drupal, and others—on virtual private servers with **default package configurations**. Defaults prioritise compatibility over throughput: Apache `prefork` with embedded `mod_php`, conservative MySQL buffer pools, unbounded or mis-sized PHP-FPM pools, and minimal hardening. Under spike conditions, symptoms include HTTP 502/504 errors, database connection exhaustion, swap thrashing, and slow page times (Allspaw, 2012; Heward, 2018).

The present work was motivated by firsthand operational experience of the author as a software engineer within Africa CDC’s Division of Digital Health and Information Systems: **the Africa CDC website** (*africacdc.org*), running on a capable server but **default software tuning**, exhibited instability during the May 2026 Congo and Uganda Ebola emergency communication window (11–19 May 2026), particularly when access surged following public health alerts and news cycles. That experience demonstrated a gap between **hardware capacity** and **effective capacity**—a distinction well documented in web operations literature but rarely addressed systematically in health-sector IT practice—and led the author to codify tuning practice in an open repository for the wider health informatics community.

### 1.3 Objectives

This documentation and the accompanying open-source project pursue four objectives:

1. **Establish a reproducible production baseline** for PHP-centric health web properties (Apache 2.4 event MPM, PHP 8.3 FPM, MySQL 8).
2. **Quantify resource sizing** across server tiers (8 GB–128 GB RAM) to support capacity planning.
3. **Integrate security controls** appropriate for public-facing health sites (TLS, HTTP security headers, blocking of sensitive paths, bot/scraper mitigation).
4. **Lower barriers to adoption** through scripted installation (`setup.sh`, `auto_setup.sh`, and distribution-specific variants).

### 1.4 Author’s role and declaration

This paper is written from a **practitioner-researcher** perspective. The author led or contributed substantially to the server optimisation described for the Africa CDC web platform and developed the accompanying automation tooling. Views expressed regarding generalisability to other institutions are offered in a technical capacity and do not necessarily represent official policy positions of the Africa Union or Africa CDC unless separately communicated through institutional channels.

### 1.5 Structure of the paper

Section 2 reviews relevant literature. Section 3 outlines the technical stack and optimisation parameters. Section 4 presents the Africa CDC case narrative. Section 5 describes the methodology and automation artefacts. Section 6 discusses security and governance. Section 7 provides recommendations for health organisations. Section 8 concludes and identifies future work.

---

## 2. Literature review and conceptual background

### 2.1 Web performance and scalability

Web performance research distinguishes **capacity** (maximum sustainable load) from **demand** (arrival rate of requests). For dynamic PHP applications, the bound is often the **worker pool**: each concurrent request consumes a PHP-FPM process with memory footprint proportional to `memory_limit` and application complexity (Zend by Perforce, 2023). When the pool is exhausted, queues form at the web server or reverse proxy, manifesting as timeouts (Allspaw, 2012).

**Opportunistic caching**—OPcache for bytecode, object caches (Redis), and full-page caches (CDN or plugins)—shifts the bottleneck from PHP execution to cache hit ratio. Health sites that serve largely read-heavy content during outbreaks are strong candidates for edge caching, provided content freshness policies respect scientific update cycles (Fielding & Reschke, 2014).

### 2.2 LAMP/LEMP stacks in the public sector

Government and NGO digital teams frequently adopt **LAMP** (Linux, Apache, MySQL, PHP) or **LEMP** variants due to procurement familiarity and large contractor ecosystems. WordPress dominates health communication microsites and institutional blogs because of editorial workflows and plugin availability (WordPress Foundation, 2025). Laravel and CodeIgniter appear in custom surveillance dashboards, registration systems, and API-backed portals requiring structured engineering (Taylor, 2024; Ellis, 2013).

Default distribution packages on Ubuntu, RHEL, and openSUSE ship generic configurations. Academic and industry guidance recommends **separating PHP execution from Apache** via PHP-FPM and **event-driven MPMs** to improve concurrency on modern hardware (Apache Software Foundation, 2024).

### 2.3 Security in health web properties

Health websites are high-value targets for defacement, SEO spam, and credential stuffing. The OWASP Top Ten highlights broken access control, cryptographic failures, and security misconfiguration as prevalent risks (OWASP Foundation, 2021). WordPress-specific exposures include `xmlrpc.php` brute-force amplification and exposed `wp-config.php` (Wordfence, 2023).

During emergencies, **availability itself is a security property**: denial of service—whether malicious or accidental—reduces access to prophylactic guidance. Defence in depth combines **edge protection** (CDN, WAF, rate limiting), **host hardening** (firewall, SELinux, patched runtimes), and **application hygiene** (strong passwords, least-privilege database accounts, disabled unused endpoints) (Cloudflare, 2024; NIST, 2022).

### 2.4 Crisis informatics and information access

Crisis informatics literature emphasises that information needs spike asymmetrically during hazards; infrastructure must be designed for **surge** rather than mean load (Palen et al., 2007). For health agencies, ethical obligations to provide timely information align with technical requirements for resilient digital service delivery (WHO, 2021). This paper contributes a **practitioner-facing** complement to theoretical crisis-communication models by documenting stack-level interventions.

---

## 3. Technical framework: production PHP application hosting

### 3.1 Reference architecture

The optimised architecture adheres to contemporary best practice:

| Layer | Component | Role |
|-------|-----------|------|
| Edge (recommended) | CDN/WAF (e.g. Cloudflare) | Caching, DDoS mitigation, bot control, TLS termination |
| Web | Apache 2.4 (event MPM) | Static assets, TLS, reverse proxy to PHP-FPM |
| Application runtime | PHP 8.3 FPM | Isolated worker processes per request |
| Bytecode cache | OPcache | Reduced PHP parse/compile overhead |
| Data | MySQL 8 / MariaDB 10.x | Content, users, telemetry |
| Optional | Redis | Object cache, sessions, queues (Laravel) |

**Tested versions** in the automation project: **MySQL 8.x**, **Apache 2.4**, **PHP 8.3** FPM, with parameterised PHP version selection for maintainability.

### 3.2 Key optimisation parameters

**MySQL / InnoDB.** The `innodb_buffer_pool_size` should approximate 20–30% of RAM on dedicated web/database co-hosted nodes, subject to PHP worker reservations. Undersized pools increase disk I/O during read-heavy CMS queries; oversized pools induce memory pressure (Oracle, 2024).

**PHP-FPM.** `pm.max_children` must satisfy  
\(\text{max\_children} \times \text{memory\_limit} \lesssim \text{RAM available to PHP}\).  
Dynamic process management (`pm = dynamic`) balances latency and memory (PHP Project, 2024).

**OPcache.** Production deployments benefit from `opcache.validate_timestamps=0` with explicit FPM reload after deploys—reducing filesystem stat overhead at the cost of operational discipline.

**Apache.** Event MPM with elevated `MaxRequestWorkers` (within RAM constraints) supports concurrent keep-alive connections while PHP executes in separate pools.

Tiered presets in the project (8 GB–128 GB RAM) map hardware to these parameters; an auto-detection script derives suggestions from `MemTotal` and CPU count.

### 3.3 Framework-specific considerations

| Framework | Deployment note | Surge behaviour |
|-----------|-----------------|-----------------|
| **WordPress** | `.htaccess`, `xmlrpc.php`, plugin overhead | Highly cacheable public pages; admin/login paths uncached |
| **Laravel** | `public/` docroot, `config:cache`, queues | Heavier per-request bootstrap; Redis strongly recommended |
| **CodeIgniter 4** | `public/` docroot | Moderate footprint; similar FPM sizing to WordPress |
| **Drupal / Joomla** | Comparable PHP stacks | Module ecosystems affect memory per worker |

The Africa CDC property referenced in this study operates in the **WordPress/CMS class** of workloads; optimisations described herein transfer to analogous PHP stacks with configuration path adjustments.

---

## 4. Case study: Africa CDC website under emergency-driven demand

### 4.1 Institutional background

The Africa CDC is the public health agency of the African Union, mandated to strengthen preparedness and response. Its website publishes outbreak updates, press releases, and technical guidance—materials heavily accessed when new events are announced (Africa CDC, 2026).

### 4.2 Baseline configuration (pre-optimisation)

Prior to intervention, the site operated on a **high-capacity server** (64 GB RAM class) but with **stock software tuning**:

- Apache **prefork** or suboptimal MPM pairing with PHP integration patterns not sized for burst traffic.
- **Default MySQL** buffer and connection settings relative to available memory.
- **PHP-FPM pool defaults** not aligned with concurrent reader load during alerts.
- **OPcache** not tuned for production CMS deploy workflows.
- **Security controls** present but not systematically consolidated (TLS via Let’s Encrypt, partial hardening).

This configuration class is common: procurement secures hardware, while software tuning remains “installer defaults.”

### 4.3 Incident window: 11–19 May 2026

During the **Congo and Uganda Ebola virus disease** public communication period (11–19 May 2026), several demand drivers coincided:

1. **Situational updates** published on the Africa CDC site and mirrored by news agencies.
2. **Email and newsletter alerts** directing subscribers to specific URLs in near-simultaneous waves.
3. **Social amplification** producing sharp, short-lived request peaks.

**Observed symptoms** during spikes included intermittent unavailability, elevated time-to-first-byte on uncached pages, and occasional gateway errors—consistent with PHP worker or database connection saturation rather than pure bandwidth limits.

Qualitatively, failures mapped to **emergency information seeking behaviour** described in crisis informatics: punctuated equilibria of attention (Palen et al., 2007). The operational lesson is unambiguous: **a 64 GB server behaving like a default 8 GB configured host** cannot fulfil its institutional mission under surge.

### 4.4 Intervention summary

A structured optimisation programme was applied:

| Domain | Intervention |
|--------|----------------|
| Web server | Migration to **Apache event MPM**; PHP served via **PHP 8.3 FPM** socket proxy |
| Database | InnoDB buffer pool and connection limits sized to ~25% RAM class; slow query logging |
| PHP runtime | OPcache memory uplift; production validation settings; FPM `max_children` aligned to RAM |
| Security | Consolidated TLS vhost; security headers; bot/scraper blocking; denial of `xmlrpc.php` and sensitive dotfiles |
| Operations | Documented reload procedures post-deploy; capacity tables for future tier planning |

Post-intervention, the same hardware class exhibited **materially improved headroom** for concurrent readers—consistent with industry expectations when worker pools and buffer pools match resources (see project tier tables: approximately 150–200 sustained concurrent dynamic requests at 64 GB / 8 vCPU with full tuning, higher with edge caching).

### 4.5 Generalisability

The Africa CDC experience is not unique. Regional health ministries, WHO country offices, and NGOs deploying WordPress or Laravel on VPS infrastructure report analogous patterns during COVID-19, Ebola, and cholera communication peaks (WHO, 2021). The case substantiates the **motivation for an open, repeatable tuning repository** rather than bespoke consultant engagements per outbreak.

---

## 5. Methodology and open-source artefacts

### 5.1 Design principles

The **WordPress Server Optimisation (Enterprise)** repository encodes:

1. **Separation of concerns** — OS-specific install scripts; shared tuning logic.
2. **Tiered and auto-calculated sizing** — `setup.sh --tier` or `auto_setup.sh` interactive detection.
3. **Multi-distribution support** — Debian/Ubuntu (`setup.sh`), RHEL family (`setup-rhel.sh`), openSUSE (`setup-opensuse.sh`).
4. **Documented capacity expectations** — sustained concurrent user estimates per RAM tier.

### 5.2 Installation pipeline

Automated pipelines perform: package installation (Ondřej PPA or Remi PHP 8.3), module enablement, config staging, validation (`apachectl configtest`, `mysqld --validate-config`), service restart, optional Certbot SSL, and hardened vhost deployment.

### 5.3 Evaluation approach

Rigorous pre/post controlled experimentation was not feasible in the operational context (ethical and logistical constraints during an active emergency). Evaluation therefore combines:

- **Operational metrics** (error rates, subjective availability during subsequent alerts).
- **Theoretical capacity models** (FPM child limits, buffer pool sizing).
- **Configuration conformance audits** against documented baselines.

Future work should incorporate longitudinal monitoring (Prometheus, Apache server-status, MySQL performance_schema) to publish quantitative availability statistics.

---

## 6. Security architecture and governance

### 6.1 Transport and application layer

Mandatory **HTTPS** (Let’s Encrypt / Certbot) protects confidentiality of user interactions—relevant where forms collect professional inquiries or newsletter subscriptions. HTTP security headers reduce clickjacking and MIME confusion attacks (OWASP Foundation, 2021).

### 6.2 Attack surface reduction

Server templates block:

- Automated **SEO scrapers** and empty User-Agent requests (reducing noise during spikes).
- Direct web access to **`.env`**, **`wp-config.php`**, and version-control metadata.
- **WordPress `xmlrpc.php`** brute-force vectors.

### 6.3 Credential and secrets management

Production governance requires:

- Rotation of database and CMS administrator passwords from installer defaults.
- Dedicated least-privilege database accounts per application.
- SSH key-based administration; optional VPN or IP allowlists for `/wp-admin` and staging hosts.

### 6.4 Edge services

**Cloudflare** (or equivalent) is recommended to absorb volumetric traffic, apply WAF rules to login endpoints, and cache static and cacheable HTML. Edge caching is particularly effective for health communication pages with infrequent content updates during a 24–72 hour outbreak news cycle.

### 6.5 Compliance and data protection

Health sites may process personal data (newsletter emails, contact forms). Optimisation does not substitute for privacy impact assessments or compliance with applicable data protection law (African Union Convention on Cyber Security and Personal Data Protection, 2014). Security controls described here support **availability** and **baseline confidentiality** but must integrate with organisational policy.

---

## 7. Recommendations for health organisations

### 7.1 Before the next emergency

1. **Benchmark** current `pm.max_children`, InnoDB buffer pool, and observed peak concurrency.
2. **Implement** PHP-FPM + event MPM if still on legacy prefork/mod_php.
3. **Place** public sites behind a CDN with caching rules for anonymous readers.
4. **Harden** credentials; enforce MFA on CMS admin interfaces.
5. **Maintain** staging environments that are not indexable and not exposed without authentication.

### 7.2 During surge events

1. **Purge/warm CDN cache** after publishing critical updates.
2. **Monitor** PHP slow logs and MySQL slow query logs.
3. **Defer** non-essential plugin updates and batch jobs.
4. **Communicate** via multiple channels (email, social) aware that web spikes follow alerts by minutes.

### 7.3 Framework selection guidance

- **WordPress:** prioritise page caching plugins or edge cache; minimise admin-plugin bloat.
- **Laravel:** Redis for cache/session; `config:cache` and `route:cache` in production.
- **CodeIgniter:** similar cache/session strategy; strict `public/` docroot.

---

## 8. Conclusion

Public-health emergencies convert institutional websites into critical infrastructure. The Africa CDC case during the May 2026 Congo and Uganda Ebola communication window illustrates how **default server configurations can neutralise substantial hardware investments** at the moment of greatest public need. Structured tuning of Apache, PHP-FPM, MySQL, and OPcache—combined with edge protection and credential hygiene—restores effective capacity and aligns technical posture with organisational mandates for timely information.

The open-source automation framework accompanying this research translates practitioner knowledge into **repeatable scripts and documentation**, addressing a widespread skills gap among health-sector digital teams. Future empirical work should quantify availability improvements through controlled monitoring and report multi-institutional deployments.

---

## References

Africa CDC. (2026). *Disease outbreaks and health emergencies*. Africa Centres for Disease Control and Prevention. https://africacdc.org/

Allspaw, J. (2012). *The art of capacity planning* (2nd ed.). O’Reilly Media.

Apache Software Foundation. (2024). *Apache HTTP Server Version 2.4 Documentation: Multi-Processing Modules*. https://httpd.apache.org/docs/2.4/mpm.html

Cloudflare. (2024). *Web application firewall (WAF)*. Cloudflare Documentation. https://developers.cloudflare.com/waf/

Ellis, J. (2013). *CodeIgniter framework*. British Columbia Institute of Technology.

Fielding, R. T., & Reschke, J. (Eds.). (2014). *Hypertext Transfer Protocol (HTTP/1.1): Conditional requests* (RFC 7232). IETF.

Heward, M. (2018). *High performance PHP*. php[architect].

NIST. (2022). *Cybersecurity Framework v1.1*. National Institute of Standards and Technology.

Oracle. (2024). *MySQL 8.0 Reference Manual: InnoDB buffer pool*. Oracle Corporation.

OWASP Foundation. (2021). *OWASP Top Ten 2021*. Open Worldwide Application Security Project.

Palen, L., Anderson, K. M., Mark, G., Martin, J., Rotolo, D., & Torkington, S. (2007). Crisis informatics: Studying crisis in a networked world. *Proceedings of the Third International Conference on e-Social Science*.

PHP Project. (2024). *PHP-FPM configuration*. PHP Manual. https://www.php.net/manual/en/install.fpm.configuration.php

Taylor, O. (2024). *Laravel framework documentation*. Laravel LLC.

Wordfence. (2023). *WordPress security: XML-RPC vulnerabilities*. Wordfence Labs.

WordPress Foundation. (2025). *WordPress*. https://wordpress.org/

WHO. (2021). *Digital health*. World Health Organization. https://www.who.int/health-topics/digital-health

WHO. (2024). *Infodemic management*. World Health Organization.

Zend by Perforce. (2023). *PHP OPcache documentation*. https://www.php.net/manual/en/book.opcache.php

African Union. (2014). *Convention on Cyber Security and Personal Data Protection (Malabo Convention)*. African Union Commission.

---

## Appendix A: Tier capacity reference (project documentation)

| RAM tier | Sustained concurrent PHP requests (indicative) | Primary use case |
|----------|-----------------------------------------------|------------------|
| 8 GB | 15–25 | Small ministry microsites |
| 16 GB | 35–50 | Regional programmes |
| 32 GB | 80–100 | National agency sites |
| 64 GB | 150–200 | Continental agencies (Africa CDC class) |
| 128 GB | 280–350 | High-traffic multi-property hosts |

*Values assume tuned stack without full-page edge cache; CDN caching may multiply effective capacity.*

---

## Appendix B: Repository artefacts

| Artefact | Function |
|----------|----------|
| `setup.sh` / `auto_setup.sh` | Debian/Ubuntu automated install |
| `setup-rhel.sh` / `auto_setup-rhel.sh` | RHEL-family install |
| `setup-opensuse.sh` / `auto_setup-opensuse.sh` | openSUSE install |
| `configs/` | MySQL, PHP, OPcache, FPM, Apache vhost templates |
| `docs/SCALING.md` | Tier parameter tables |

---

*Document version: 1.0 — May 2026.*  
*Author: **Agaba Andrew**, Software Engineer, Division of Digital Health and Information Systems, Africa CDC.*  
*Prepared in conjunction with the WordPress Server Optimisation (Enterprise) open-source project.*
