#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Enterprise Pure Slate & Black Dark Theme Engine
# Provides a 100% unified, seamless, modern dark design system across all pages:
# Dashboard (/main/), Lab Canvas (/themes/default/), Login (/login/), & Overlays.
# ==============================================================================
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/opt/unetlab/scripts")"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd || echo "/opt/azambasha")"

echo "============================================================"
echo "    Applying Azam Basha Unified Pure Dark Design System     "
echo "============================================================"

# Ensure Target CSS Directories exist
mkdir -p /opt/unetlab/html/themes/default/css \
         /opt/unetlab/html/main/css \
         /opt/unetlab/html/assets-common/css \
         /opt/unetlab/html/login 2>/dev/null || true

DARK_CSS="/opt/unetlab/html/themes/default/css/azambasha-dark.css"

cat > "$DARK_CSS" << 'EOF'
/* ==========================================================================
   Azam Basha Enterprise Unified High-Contrast Dark Theme
   Seamless obsidian & deep-slate palette with electric blue accents
   ========================================================================== */

/* 1. Universal Design Tokens — Completely overrides all legacy/greenish vars */
:root,
:root[data-theme="dark"],
:root[data-theme="light"],
html,
body {
  /* Topbar & Sidebar Chrome */
  --pnq-primary:        #0a0c10 !important;
  --pnq-primary-light:  #181c28 !important;
  --pnq-primary-hover:  #131620 !important;
  --pnq-on-primary:     #f8fafc !important;
  --pnq-on-primary-dim: #94a3b8 !important;

  /* App Surfaces & Backgrounds (No green/olive tints) */
  --pnq-bg:             #07080c !important;
  --pnq-surface:        #0f1117 !important;
  --pnq-surface-2:      #151822 !important;
  --pnq-text:           #f8fafc !important;
  --pnq-text-muted:     #94a3b8 !important;

  /* Brand Accents */
  --pnq-accent:         #3b82f6 !important;
  --pnq-accent-hover:   #2563eb !important;
  --pnq-accent-soft:    rgba(59, 130, 246, 0.15) !important;
  --pnq-on-accent:      #ffffff !important;

  /* Status Colors */
  --pnq-danger:         #ef4444 !important;
  --pnq-danger-soft:    rgba(239, 68, 68, 0.14) !important;
  --pnq-ok:             #10b981 !important;
  --pnq-warn:           #f59e0b !important;

  /* Sleek Minimal Borders & Elevation */
  --pnq-border:         rgba(255, 255, 255, 0.08) !important;
  --pnq-border-strong:  rgba(255, 255, 255, 0.16) !important;
  --pnq-shadow:         0 4px 20px rgba(0, 0, 0, 0.55) !important;

  /* Media & Canvas Previews */
  --pnq-folder:         #fbbf24 !important;
  --pnq-preview-from:   #0d0f16 !important;
  --pnq-preview-to:     #07080c !important;
  --pnq-preview-live-from: #0c1420 !important;
  --pnq-preview-live-to:   #07080c !important;
  --pnq-overlay-chip:   rgba(21, 24, 34, 0.92) !important;
  --pnq-card-btn:       rgba(21, 24, 34, 0.95) !important;
  --pnq-card-btn-hover: #222636 !important;
  --pnq-perm-hover:     #1a1d28 !important;
  --pnq-hover-veil:     rgba(255, 255, 255, 0.04) !important;
  --pnq-overlay-veil:   rgba(7, 8, 12, 0.75) !important;

  color-scheme: dark !important;
}

/* 2. Global Document Reset */
html, body {
  background-color: #07080c !important;
  color: #f8fafc !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Inter", Oxygen, Ubuntu, Cantarell, "Helvetica Neue", sans-serif !important;
}

/* 3. Top Navigation Bar */
.topbar, header.topbar, .navbar, .navbar-default, .navbar-inverse {
  background-color: #0a0c10 !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.6) !important;
}
.topbar-brand-text, .navbar-brand {
  color: #ffffff !important;
  font-weight: 600 !important;
  letter-spacing: 0.3px !important;
}
.topbar-user {
  color: #94a3b8 !important;
}
.topbar-user span {
  color: #f1f5f9 !important;
  font-weight: 500 !important;
}
.topbar-logout {
  color: #94a3b8 !important;
  border: 1px solid transparent !important;
  border-radius: 6px !important;
}
.topbar-logout:hover {
  background-color: #151822 !important;
  color: #ffffff !important;
  border-color: rgba(255, 255, 255, 0.1) !important;
}

/* 4. Left Sidebar Navigation */
.sidebar, nav.sidebar, .main-sidebar, .left-side, #sidebar {
  background-color: #0a0c10 !important;
  border-right: 1px solid rgba(255, 255, 255, 0.08) !important;
}
.nav-item {
  color: #94a3b8 !important;
  background-color: transparent !important;
  border-radius: 6px !important;
  margin: 1px 0 !important;
  transition: all 0.15s ease !important;
}
.nav-item:hover {
  background-color: #151822 !important;
  color: #ffffff !important;
}
.nav-item.active, .nav-item.is-active, .sidebar .active > a {
  background-color: #181c28 !important;
  color: #ffffff !important;
  font-weight: 600 !important;
  box-shadow: inset 3px 0 0 #3b82f6 !important;
  border-left: none !important;
}
.nav-item.active .fa, .nav-item.is-active .fa {
  color: #3b82f6 !important;
}
.sidebar-version {
  background-color: #10121a !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 6px !important;
  color: #94a3b8 !important;
  padding: 8px 10px !important;
}
.sidebar-version strong {
  color: #ffffff !important;
}

/* 5. Main Content Area & Panels */
.content, main.content, #view {
  background-color: #07080c !important;
  color: #f8fafc !important;
}
.view-title {
  color: #ffffff !important;
}

/* Workspace Panels & Split Views (Eliminates green panels) */
.fm-split__list,
.fm-split__preview,
.card,
.panel,
.panel-default,
.box,
.content-wrapper,
.dropdown-menu {
  background-color: #0f1117 !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 8px !important;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4) !important;
  color: #f8fafc !important;
}

/* Preview Stage & Viewport */
.lab-preview__stage {
  background: #0a0c12 !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  background-image: radial-gradient(circle, #181c28 1px, transparent 1px) !important;
  background-size: 20px 20px !important;
}
.lab-preview__info {
  background-color: #131620 !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 6px !important;
}
.lab-preview__row {
  border-bottom: 1px solid rgba(255, 255, 255, 0.06) !important;
}
.lab-preview__row > b {
  color: #94a3b8 !important;
}
.lab-preview__row > span, .lab-preview__row > div {
  color: #e2e8f0 !important;
}
.lab-preview__zoom {
  background-color: #131620 !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}
.lab-preview__zoom-stop, .lab-preview__zoom-auto {
  color: #94a3b8 !important;
  background-color: transparent !important;
}
.lab-preview__zoom-stop:hover, .lab-preview__zoom-auto:hover {
  background-color: #1a1e2c !important;
  color: #ffffff !important;
}
.lab-preview__zoom-stop.is-active, .lab-preview__zoom-auto.is-active {
  background-color: rgba(59, 130, 246, 0.2) !important;
  color: #3b82f6 !important;
}

/* 6. Buttons & Interactive Controls */
.btn {
  background-color: #151822 !important;
  border: 1px solid rgba(255, 255, 255, 0.12) !important;
  color: #e2e8f0 !important;
  border-radius: 6px !important;
  font-weight: 500 !important;
  transition: all 0.15s ease !important;
}
.btn:hover {
  background-color: #202434 !important;
  color: #ffffff !important;
  border-color: rgba(255, 255, 255, 0.2) !important;
}
.btn:disabled, .btn[disabled] {
  opacity: 0.4 !important;
  background-color: #11131a !important;
  color: #64748b !important;
  border-color: rgba(255, 255, 255, 0.05) !important;
}
.btn-primary, .btn-accent {
  background-color: #2563eb !important;
  border-color: #3b82f6 !important;
  color: #ffffff !important;
}
.btn-primary:hover, .btn-accent:hover {
  background-color: #1d4ed8 !important;
  border-color: #2563eb !important;
  box-shadow: 0 0 12px rgba(37, 99, 235, 0.4) !important;
}
.btn-danger {
  background-color: rgba(239, 68, 68, 0.12) !important;
  border-color: rgba(239, 68, 68, 0.35) !important;
  color: #ef4444 !important;
}
.btn-danger:hover {
  background-color: #ef4444 !important;
  color: #ffffff !important;
}
.btn-ghost {
  background-color: transparent !important;
  border-color: transparent !important;
  color: #94a3b8 !important;
}
.btn-ghost:hover {
  background-color: #151822 !important;
  color: #ffffff !important;
}

/* 7. Forms, Inputs, Search Bars */
.input, select.input, textarea.input, input[type="text"], input[type="password"], input[type="search"], select, textarea, .form-control {
  background-color: #131620 !important;
  color: #f8fafc !important;
  border: 1px solid rgba(255, 255, 255, 0.12) !important;
  border-radius: 6px !important;
}
.input:focus, select.input:focus, textarea.input:focus, input:focus, select:focus, textarea:focus, .form-control:focus {
  border-color: #3b82f6 !important;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2) !important;
  outline: none !important;
}
.input::placeholder, input::placeholder {
  color: #64748b !important;
}

/* 8. Tables & Lists */
.table, .fm-table, table {
  background-color: #0f1117 !important;
  color: #f8fafc !important;
}
.table th, .fm-table th, table th {
  background-color: #131620 !important;
  color: #94a3b8 !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
  font-weight: 600 !important;
}
.table td, .fm-table td, table td {
  border-bottom: 1px solid rgba(255, 255, 255, 0.06) !important;
  color: #e2e8f0 !important;
}
.table tbody tr:hover, .fm-table tbody tr:hover, table tbody tr:hover {
  background-color: #151822 !important;
}
.fm-row.is-selected, .fm-table tbody tr.fm-row.is-selected > td {
  background-color: rgba(59, 130, 246, 0.15) !important;
}
.fm-table tbody tr.fm-row.is-selected > td:first-child {
  box-shadow: inset 3px 0 0 #3b82f6 !important;
}
.fm-name {
  color: #f1f5f9 !important;
}
.fm-name:hover {
  color: #3b82f6 !important;
}
.fm-name .fa-folder, .fm-name .fa-folder-open-o {
  color: #fbbf24 !important;
}
.fm-name .fa-file-o, .fm-name .fa-flask {
  color: #3b82f6 !important;
}

/* 9. Empty States & Breadcrumbs */
.empty {
  color: #64748b !important;
}
.empty .fa {
  color: #475569 !important;
}
.crumb {
  color: #3b82f6 !important;
}
.crumb:hover {
  background-color: rgba(59, 130, 246, 0.15) !important;
}
.crumb.is-current {
  color: #f8fafc !important;
}

/* 10. Topology Lab Canvas & Workbench View */
#lab-viewport, #viewport, .canvas, .topology-canvas, #topology-body, .workspace {
  background-color: #07080c !important;
  background-image: radial-gradient(circle, #1a1e2c 1px, transparent 1px) !important;
  background-size: 24px 24px !important;
}
.pnq-quickbar, #pnetlab-quickbar {
  background-color: #0a0c10 !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.6) !important;
}
.pnq-quickbar .pnq-btn {
  background-color: #131620 !important;
  color: #e2e8f0 !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}
.pnq-quickbar .pnq-btn:hover {
  background-color: #202434 !important;
  color: #ffffff !important;
}

/* 11. Modals & Dialogs */
.modal-backdrop {
  background: rgba(4, 5, 8, 0.8) !important;
  backdrop-filter: blur(4px) !important;
}
.modal, .modal-content {
  background-color: #0f1117 !important;
  border: 1px solid rgba(255, 255, 255, 0.12) !important;
  border-radius: 8px !important;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.7) !important;
  color: #f8fafc !important;
}
.modal-head, .modal-header {
  background-color: #131620 !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
  color: #ffffff !important;
}
.modal-foot, .modal-footer {
  background-color: #131620 !important;
  border-top: 1px solid rgba(255, 255, 255, 0.08) !important;
}

/* 12. Login Screen Unified Styling */
.login-wrap {
  background-color: #07080c !important;
}
.login-card {
  background-color: #0f1117 !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  border-radius: 10px !important;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6) !important;
}
.brand-text {
  color: #ffffff !important;
  font-weight: 600 !important;
}
EOF

# Copy stylesheet to all html directories
cp -f "$DARK_CSS" /opt/unetlab/html/main/css/azambasha-dark.css 2>/dev/null || true
cp -f "$DARK_CSS" /opt/unetlab/html/assets-common/css/azambasha-dark.css 2>/dev/null || true
cp -f "$DARK_CSS" /opt/unetlab/html/login/azambasha-dark.css 2>/dev/null || true
chmod 0644 /opt/unetlab/html/themes/default/css/azambasha-dark.css \
           /opt/unetlab/html/main/css/azambasha-dark.css \
           /opt/unetlab/html/assets-common/css/azambasha-dark.css \
           /opt/unetlab/html/login/azambasha-dark.css 2>/dev/null || true

# 2. Inject stylesheet link into UI HTML templates
INJECT_TAG='<link rel="stylesheet" id="azambasha-dark-theme" href="/themes/default/css/azambasha-dark.css">'

for html_file in \
    "/opt/unetlab/html/themes/default/index.html" \
    "/opt/unetlab/html/main/index.html" \
    "/opt/unetlab/html/index.html" \
    "/opt/unetlab/html/login/index.html"; do
    if [ -f "$html_file" ]; then
        # Remove any duplicate link tags first
        sed -i '/id="azambasha-dark-theme"/d' "$html_file" 2>/dev/null || true
        # Append before </head>
        if grep -q "</head>" "$html_file"; then
            sed -i -E "s|</head>|  ${INJECT_TAG}\n</head>|I" "$html_file"
        else
            echo "$INJECT_TAG" >> "$html_file"
        fi
        echo "  [✔] Unified dark theme injected into $html_file"
    fi
done

# 3. Deploy Logo & UI Branding Assets
if [ -f "${SCRIPT_DIR}/azambasha-apply-branding.sh" ]; then
    bash "${SCRIPT_DIR}/azambasha-apply-branding.sh" || true
elif [ -d "${PARENT_DIR}/assets" ]; then
    cp -f "${PARENT_DIR}/assets/logo.png" "/opt/unetlab/html/themes/default/images/logo.png" 2>/dev/null || true
    cp -f "${PARENT_DIR}/assets/logo.png" "/opt/unetlab/html/images/logo.png" 2>/dev/null || true
    cp -f "${PARENT_DIR}/assets/favicon.png" "/opt/unetlab/html/themes/default/images/favicon.ico" 2>/dev/null || true
    echo "  [✔] Azam Basha logo and favicon deployed"
fi

# 4. Refresh Web Server & Cache
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload apache2 2>/dev/null || true
fi

echo "============================================================"
echo "  [SUCCESS] Azam Basha Unified Dark Theme Applied Globally! "
echo "============================================================"
