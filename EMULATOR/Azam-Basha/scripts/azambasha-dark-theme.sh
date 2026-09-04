#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Web GUI Pure Black Dark Mode Theme Engine
# ==============================================================================
# Injects a high-contrast, pure black (#000000) background theme with pure white
# (#ffffff) typography into the Web UI canvas, sidebar, modals, and login screens.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    Applying Azam Basha Web GUI Pure Black Dark Mode        "
echo "============================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

THEME_DIR="/opt/unetlab/html/themes/default"
CSS_DIR="${THEME_DIR}/css"
IMG_DIR="${THEME_DIR}/images"

mkdir -p "$CSS_DIR" "$IMG_DIR" /opt/unetlab/html/images 2>/dev/null || true

# 1. Write the high-contrast Pure Black & White stylesheet
DARK_CSS="${CSS_DIR}/azambasha-dark.css"

cat > "$DARK_CSS" << 'EOF'
/* ==========================================================================
   Azam Basha High-Contrast Pure Black Dark Mode
   ========================================================================== */

:root {
  --ab-bg-pure-black: #000000;
  --ab-bg-dark-panel: #0a0b0e;
  --ab-bg-dark-card: #121318;
  --ab-bg-dark-hover: #1b1c24;
  --ab-text-white: #ffffff;
  --ab-text-muted: #cbd5e1;
  --ab-border-dark: #232530;
  --ab-accent-blue: #3b82f6;
  --ab-accent-cyan: #06b6d4;
  --ab-accent-glow: rgba(59, 130, 246, 0.25);
}

/* Global Background and Typography */
html, body {
  background-color: var(--ab-bg-pure-black) !important;
  color: var(--ab-text-white) !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, "Helvetica Neue", sans-serif !important;
}

/* Top Navbar & Header */
.navbar, .navbar-default, .navbar-inverse, header, .main-header, .top-bar {
  background-color: var(--ab-bg-dark-panel) !important;
  border-bottom: 1px solid var(--ab-border-dark) !important;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.7) !important;
}

.navbar a, .navbar-brand, .nav > li > a {
  color: var(--ab-text-white) !important;
  font-weight: 500 !important;
}

.navbar a:hover, .nav > li > a:hover {
  color: var(--ab-accent-cyan) !important;
  background-color: var(--ab-bg-dark-hover) !important;
}

/* Sidebar & Navigation Panels */
.sidebar, .main-sidebar, .left-side, .side-menu, #sidebar {
  background-color: var(--ab-bg-dark-panel) !important;
  border-right: 1px solid var(--ab-border-dark) !important;
  color: var(--ab-text-white) !important;
}

.sidebar a, .side-menu a {
  color: var(--ab-text-white) !important;
}

.sidebar a:hover, .side-menu a:hover, .sidebar .active > a {
  background-color: var(--ab-bg-dark-hover) !important;
  color: var(--ab-accent-cyan) !important;
  border-left: 3px solid var(--ab-accent-blue) !important;
}

/* Topology Workbench / Lab Canvas */
#lab-viewport, #viewport, .canvas, .topology-canvas, #topology-body, .workspace {
  background-color: var(--ab-bg-pure-black) !important;
  background-image: radial-gradient(circle, #1a1c24 1px, transparent 1px) !important;
  background-size: 24px 24px !important;
}

/* Cards, Panels & Boxes */
.card, .panel, .panel-default, .box, .content-wrapper, .modal-content, .dropdown-menu {
  background-color: var(--ab-bg-dark-card) !important;
  color: var(--ab-text-white) !important;
  border: 1px solid var(--ab-border-dark) !important;
  border-radius: 8px !important;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6) !important;
}

.panel-heading, .card-header, .box-header, .modal-header {
  background-color: var(--ab-bg-dark-panel) !important;
  color: var(--ab-text-white) !important;
  border-bottom: 1px solid var(--ab-border-dark) !important;
  font-weight: 600 !important;
}

.panel-footer, .card-footer, .modal-footer {
  background-color: var(--ab-bg-dark-panel) !important;
  border-top: 1px solid var(--ab-border-dark) !important;
}

/* Tables & Lists */
table, .table, .table-bordered, .table-striped {
  background-color: var(--ab-bg-dark-card) !important;
  color: var(--ab-text-white) !important;
  border-color: var(--ab-border-dark) !important;
}

.table > thead > tr > th, .table > tbody > tr > th, table th {
  background-color: var(--ab-bg-dark-panel) !important;
  color: var(--ab-text-white) !important;
  border-bottom: 2px solid var(--ab-border-dark) !important;
}

.table > tbody > tr > td, table td {
  color: var(--ab-text-white) !important;
  border-top: 1px solid var(--ab-border-dark) !important;
}

.table-striped > tbody > tr:nth-of-type(odd) {
  background-color: rgba(255, 255, 255, 0.03) !important;
}

.table-hover > tbody > tr:hover {
  background-color: var(--ab-bg-dark-hover) !important;
}

/* Forms, Inputs & Textareas */
input[type="text"], input[type="password"], input[type="email"], input[type="search"],
select, textarea, .form-control {
  background-color: #16181f !important;
  color: var(--ab-text-white) !important;
  border: 1px solid var(--ab-border-dark) !important;
  border-radius: 6px !important;
}

input:focus, select:focus, textarea:focus, .form-control:focus {
  border-color: var(--ab-accent-blue) !important;
  box-shadow: 0 0 0 3px var(--ab-accent-glow) !important;
  outline: none !important;
}

/* Buttons */
.btn-primary {
  background-color: var(--ab-accent-blue) !important;
  border-color: var(--ab-accent-blue) !important;
  color: #ffffff !important;
  font-weight: 600 !important;
}

.btn-default, .btn-secondary {
  background-color: #232530 !important;
  border-color: #2f3340 !important;
  color: var(--ab-text-white) !important;
}

.btn-default:hover, .btn-secondary:hover {
  background-color: #2f3340 !important;
  color: #ffffff !important;
}

/* Text Hierarchy */
h1, h2, h3, h4, h5, h6, .h1, .h2, .h3, .h4, .h5, .h6, label, b, strong {
  color: var(--ab-text-white) !important;
}

p, span, small, .text-muted {
  color: var(--ab-text-muted) !important;
}

/* Scrollbars */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}
::-webkit-scrollbar-track {
  background: var(--ab-bg-pure-black);
}
::-webkit-scrollbar-thumb {
  background: #2b2e3b;
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: #3e4354;
}
EOF

chmod 0644 "$DARK_CSS"
echo "  [✔] Pure Black Dark Mode stylesheet created at $DARK_CSS"

# 2. Inject stylesheet link into UI HTML templates
INJECT_TAG='<link rel="stylesheet" id="azambasha-dark-theme" href="/themes/default/css/azambasha-dark.css">'

for html_file in \
    "/opt/unetlab/html/themes/default/index.html" \
    "/opt/unetlab/html/main/index.html" \
    "/opt/unetlab/html/index.html" \
    "/opt/unetlab/html/login/index.html"; do
    if [ -f "$html_file" ]; then
        if ! grep -q "azambasha-dark-theme" "$html_file"; then
            if grep -q "</head>" "$html_file"; then
                sed -i -E "s|</head>|  ${INJECT_TAG}\n</head>|I" "$html_file"
            else
                echo "$INJECT_TAG" >> "$html_file"
            fi
            echo "  [✔] Dark theme injected into $html_file"
        fi
    fi
done

# 3. Deploy Logo & UI Branding Assets
if [ -f "${SCRIPT_DIR}/azambasha-apply-branding.sh" ]; then
    bash "${SCRIPT_DIR}/azambasha-apply-branding.sh" || true
elif [ -d "${PARENT_DIR}/assets" ]; then
    cp -f "${PARENT_DIR}/assets/logo.png" "${IMG_DIR}/logo.png" 2>/dev/null || true
    cp -f "${PARENT_DIR}/assets/logo.png" "/opt/unetlab/html/images/logo.png" 2>/dev/null || true
    cp -f "${PARENT_DIR}/assets/favicon.png" "${IMG_DIR}/favicon.ico" 2>/dev/null || true
    echo "  [✔] Azam Basha logo and favicon deployed"
fi

echo "============================================================"
echo "  [SUCCESS] Azam Basha Pure Black Dark Mode Active!         "
echo "============================================================"
