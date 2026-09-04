# Azam Basha Permanent Session & Never-Logout Guide

**Complete Fix for Session Timeouts, Cookie Expiry, and Auto-Logout**
- **Applicable:** Azam Basha Virtual Appliances
- **Target OS:** Ubuntu 18.04 - 26.04

---

## 1. Executive Summary & Root Cause Analysis

By default, strict idle and session timeout mechanisms can cause frequent logouts. In personal or dedicated virtualization environments, this fix ensures uninterrupted sessions.

| Layer / Component | Default Constraint | Applied Permanent Fix |
| :--- | :--- | :--- |
| **PHP Backend (`init.php`)** | `SESSION = 3600` (1 hour timeout) | Overridden to `315360000` (10 years) in `config.php` |
| **MySQL Database (`azambasha_db`)** | `ctrl_session_timeout` (1 - 24 hrs max) | Database value set to 10 years; accounts set to never expire |
| **Browser Token Cookie** | Fixed expiry stamped only once at login | Extended to 10 years + dynamic sliding renewal on each request |
| **PHP Engine Configuration** | `session.gc_maxlifetime = 1440` (24m) | Updated to 10 years across all installed PHP versions |
| **Frontend Client (UI)** | 412/401 triggers instant redirect to `/login/` | Background heartbeat ping keeps sessions alive indefinitely |

---

## 2. Quick Deployment

### Method A: Run Pre-Packaged Script (Recommended)
Copy [`scripts/azambasha-disable-logout.sh`](../scripts/azambasha-disable-logout.sh) to the VM via SCP/SSH or git and run:

```bash
chmod +x azambasha-disable-logout.sh
sudo ./azambasha-disable-logout.sh
```

### Method B: Standalone Script Execution
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/.../scripts/azambasha-disable-logout.sh || cat /opt/unetlab/scripts/azambasha-disable-logout.sh)"
```

> [!NOTE]
> The script is completely idempotent and safe to re-run anytime. It creates timestamped backups (`*.bak.TIMESTAMP`) for every file it modifies before making changes.

---

## 3. Detailed Actions Performed by the Script

1. **`config.php` Override**: Defines `SESSION = 315360000` and configures session garbage collection and cookie lifetime to 10 years.
2. **Database Session & Expiration Update**: Inserts `ctrl_session_timeout = 315360000` into table `control` and updates table `users` to set expiration to `-1` (never expires).
3. **`status/api.php` Patching**: Modifies the `$seconds > 86400` constraint to allow extended session checks.
4. **`functions.php` Sliding Cookie Renewal**: Modifies `updateUserCookie()` to stamp a 10-year sliding cookie on every active API request.
5. **PHP INI Files Configuration**: Updates `session.gc_maxlifetime`, `session.cookie_lifetime`, and `session.cache_expire` across `/etc/php/*/apache2/`, `/etc/php/*/fpm/`, and `/etc/php/*/cli/`.
6. **Background Keepalive Heartbeat**: Injects `/opt/unetlab/html/themes/default/js/azambasha-keepalive.js` into `/opt/unetlab/html/main/index.html` to ping `/api/auth` every 3 minutes.
7. **Service Reloads**: Restarts Apache and all running PHP-FPM daemons.

---

## 4. Verification & Validation Steps

1. **Log into Azam Basha Web Interface**: Open your browser, navigate to `https://<azambasha-ip>/` and log in.
2. **Check Cookie Expiry**:
   - Press `F12` to open Developer Tools.
   - Navigate to **Application** (Chrome/Edge) or **Storage** (Firefox) &rarr; **Cookies** &rarr; `https://<azambasha-ip>`.
   - Inspect the `token` cookie. Its **Expires / Max-Age** timestamp will now show a date **10 years in the future**.
3. **Check Database Values**: Run this terminal command on the VM to verify:
   ```bash
   mysql -u azambasha -pazambasha azambasha_db -e "SELECT control_name, control_value FROM control WHERE control_name='ctrl_session_timeout'; SELECT username, FROM_UNIXTIME(session) AS session_expiry FROM users WHERE username='admin';"
   ```
4. **Long Inactivity Test**: Leave the browser tab open overnight or sleep your laptop. On resume, refresh or click any lab node—you will remain authenticated with zero interruptions.

---

## 5. Important Note on Single-Session Concurrency

Azam Basha stores a single active authentication token per user account in the `users.cookie` table column. If you log into the **same user account** (e.g. `admin`) from a different computer or private window, the previous device's token is rotated.

> [!TIP]
> **Best Practice**: To keep multiple browser windows or devices open simultaneously without conflict, create separate sub-accounts in **System &rarr; User Management** (e.g. `admin2`, `laptop`, `desktop`) and grant them Admin roles.
