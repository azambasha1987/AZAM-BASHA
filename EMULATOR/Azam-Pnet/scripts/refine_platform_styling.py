import paramiko
import sys
import time

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

def refine():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect('192.168.1.29', port=22, username='root', password='azam', look_for_keys=False, allow_agent=False)
    sftp = client.open_sftp()
    
    # 1. Update login/index.html to display the user's complete circular logo image
    LOGIN_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Azam Basha — Next-Gen Platform</title>
	<link rel="icon" href="/branding/api.php?action=logo">
	<link rel="preconnect" href="https://fonts.googleapis.com">
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
	<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
	<link rel="stylesheet" href="/login/login.css?v=""" + str(int(time.time())) + """">
</head>
<body>
	<div class="cyber-bg">
		<div class="cyber-grid"></div>
		<div class="cyber-scanlines"></div>
		<div class="glow-orb orb-1"></div>
		<div class="glow-orb orb-2"></div>
		<div class="glow-orb orb-3"></div>
	</div>

	<main class="login-wrap">
		<div class="brand-container">
			<div class="avatar-hero-unit" id="avatar-hero-unit">
				<img class="brand-logo" id="brand-logo" data-brand-logo src="/branding/api.php?action=logo" alt="Azam Basha">
				<span class="brand-mark" id="brand-mark" hidden>AB</span>
				<div class="podium-container">
					<div class="podium-shadow"></div>
					<div class="podium-light-ring"></div>
				</div>
			</div>
			
			<h1 class="brand-title">
				<span class="brand-name" data-brand-name>Azam Basha</span>
			</h1>
			<div class="cyber-divider"></div>
			
			<p class="login-header" id="login-header" hidden></p>
			
			<div class="status-badge-container">
				<div class="status-pill">
					<span class="pulse-dot"></span>
					<span class="status-text">NETWORK EMULATION PLATFORM</span>
					<span class="version-tag" id="version-line">v<span id="version-value">1.0.0</span></span>
				</div>
			</div>

			<div class="default-account-pill" id="default-account">
				<span class="acc-icon">⚡</span>
				<span>Default: <strong class="glow-text">admin</strong> / <strong class="glow-text">azam</strong></span>
			</div>
		</div>

		<form class="login-card" id="login-form" autocomplete="on">
			<div class="card-glow-top"></div>
			<div class="card-corner corner-tl"></div>
			<div class="card-corner corner-tr"></div>
			
			<div class="field">
				<label for="username">
					<span class="field-label-text">USERNAME</span>
				</label>
				<div class="input-wrapper">
					<input id="username" name="username" type="text" autocomplete="username"
						autocapitalize="none" autocorrect="off" spellcheck="false" placeholder="Enter username" required autofocus>
					<div class="input-focus-border"></div>
				</div>
			</div>

			<div class="field">
				<label for="password">
					<span class="field-label-text">PASSWORD</span>
				</label>
				<div class="input-wrapper">
					<input id="password" name="password" type="password" autocomplete="current-password" placeholder="••••••••" required>
					<div class="input-focus-border"></div>
				</div>
			</div>

			<div class="field">
				<label for="console-pref">
					<span class="field-label-text">CONSOLE ENGINE</span>
				</label>
				<div class="select-wrapper">
					<select id="console-pref" name="console-pref">
						<option value="native" selected>Default Console (Native Client)</option>
						<option value="html5">HTML5 Web Console (In-Browser)</option>
					</select>
					<div class="select-arrow"></div>
				</div>
			</div>

			<div class="alert" id="alert" role="alert" hidden></div>

			<button class="btn-submit" id="submit" type="submit">
				<span class="btn-shine"></span>
				<span class="btn-label">AUTHENTICATE &amp; LAUNCH</span>
				<span class="btn-spin" aria-hidden="true"></span>
			</button>
		</form>
	</main>

	<script src="/assets-common/js/pnq-branding.js?v=5c1fac93"></script>
	<script src="/login/login.js?v=ac9a7d35"></script>
</body>
</html>
"""

    LOGIN_CSS = """/* ============================================================================
   Azam Basha Next-Gen Futuristic Cyber-Glass Design System
   ============================================================================ */

:root {
	--bg-deep: #040711;
	--bg-surface: #0a0f1d;
	--card-bg: rgba(11, 19, 38, 0.76);
	--card-border: rgba(0, 242, 254, 0.24);
	--card-border-hover: rgba(0, 242, 254, 0.55);
	
	--cyan-neon: #00f2fe;
	--blue-neon: #38bdf8;
	--purple-neon: #8b5cf6;
	--magenta-neon: #d946ef;
	--emerald-glow: #10b981;
	
	--text-main: #f8fafc;
	--text-muted: #94a3b8;
	--text-dim: #64748b;
	
	--field-bg: rgba(6, 11, 24, 0.88);
	--field-border: rgba(148, 163, 184, 0.22);
	--field-focus-border: #00f2fe;
	
	--font-sans: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
	--font-mono: 'JetBrains Mono', monospace;
}

* {
	box-sizing: border-box;
	margin: 0;
	padding: 0;
}

html, body {
	height: 100%;
	width: 100%;
	overflow-x: hidden;
}

body {
	font-family: var(--font-sans);
	background-color: var(--bg-deep);
	color: var(--text-main);
	display: flex;
	align-items: center;
	justify-content: center;
	min-height: 100vh;
	position: relative;
	-webkit-font-smoothing: antialiased;
	text-rendering: optimizeLegibility;
}

/* Background Canvas */
.cyber-bg {
	position: fixed;
	top: 0; left: 0; right: 0; bottom: 0;
	z-index: 0;
	overflow: hidden;
	background: radial-gradient(circle at 50% 15%, #0e1b38 0%, #060b17 55%, #020409 100%);
}

.cyber-grid {
	position: absolute;
	inset: 0;
	background-image: 
		linear-gradient(rgba(0, 242, 254, 0.04) 1px, transparent 1px),
		linear-gradient(90deg, rgba(0, 242, 254, 0.04) 1px, transparent 1px);
	background-size: 44px 44px;
	background-position: center center;
	mask-image: radial-gradient(circle at 50% 40%, rgba(0,0,0,0.9) 0%, rgba(0,0,0,0.2) 65%, transparent 90%);
	-webkit-mask-image: radial-gradient(circle at 50% 40%, rgba(0,0,0,0.9) 0%, rgba(0,0,0,0.2) 65%, transparent 90%);
}

.cyber-scanlines {
	position: absolute;
	inset: 0;
	background: linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.25) 50%);
	background-size: 100% 4px;
	pointer-events: none;
	opacity: 0.35;
}

.glow-orb {
	position: absolute;
	border-radius: 50%;
	filter: blur(110px);
	opacity: 0.4;
	pointer-events: none;
	animation: floatOrb 18s ease-in-out infinite alternate;
}

.orb-1 {
	top: 10%; left: 50%;
	transform: translate(-50%, -50%);
	width: 550px; height: 550px;
	background: radial-gradient(circle, rgba(0, 242, 254, 0.25) 0%, rgba(56, 189, 248, 0.12) 60%, transparent 100%);
}

.orb-2 {
	bottom: 8%; left: 18%;
	width: 420px; height: 420px;
	background: radial-gradient(circle, rgba(139, 92, 246, 0.22) 0%, transparent 70%);
	animation-delay: -6s;
}

.orb-3 {
	top: 35%; right: 12%;
	width: 380px; height: 380px;
	background: radial-gradient(circle, rgba(0, 242, 254, 0.18) 0%, transparent 70%);
	animation-delay: -11s;
}

@keyframes floatOrb {
	0% { transform: translate(-50%, -50%) scale(1); }
	50% { transform: translate(-46%, -42%) scale(1.15); }
	100% { transform: translate(-54%, -58%) scale(0.92); }
}

.login-wrap {
	position: relative;
	z-index: 10;
	width: 100%;
	max-width: 470px;
	padding: 20px 20px 32px;
	display: flex;
	flex-direction: column;
	align-items: center;
}

.brand-container {
	display: flex;
	flex-direction: column;
	align-items: center;
	margin-bottom: 18px;
	text-align: center;
	width: 100%;
}

/* Jumping Avatar Unit with the complete circular logo */
.avatar-hero-unit {
	position: relative;
	width: 140px;
	height: 140px;
	margin-bottom: 8px;
	display: flex;
	align-items: center;
	justify-content: center;
	animation: avatarUnifiedJump 4.2s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite;
	cursor: pointer;
}

@keyframes avatarUnifiedJump {
	0%, 100% {
		transform: translateY(0px) scale(1);
	}
	40% {
		transform: translateY(-14px) scale(1.03);
	}
	50% {
		transform: translateY(-15px) scale(1.035);
	}
	70% {
		transform: translateY(-5px) scale(0.995);
	}
}

.brand-logo {
	width: 136px;
	height: 136px;
	object-fit: contain;
	display: block;
	filter: drop-shadow(0 0 20px rgba(0, 242, 254, 0.55));
	transition: transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.avatar-hero-unit:hover .brand-logo {
	transform: scale(1.12);
	filter: drop-shadow(0 0 28px rgba(0, 242, 254, 0.85));
}

.brand-mark {
	display: none;
}

/* Grounding Levitation Shadow */
.podium-container {
	position: absolute;
	bottom: -12px;
	left: 50%;
	transform: translateX(-50%);
	width: 100px;
	height: 16px;
	display: flex;
	align-items: center;
	justify-content: center;
	pointer-events: none;
	z-index: 0;
}

.podium-shadow {
	position: absolute;
	width: 96px;
	height: 12px;
	border-radius: 50%;
	background: radial-gradient(ellipse, rgba(0, 242, 254, 0.5) 0%, rgba(0, 0, 0, 0.85) 60%, transparent 85%);
	filter: blur(6px);
	animation: podiumShadowScale 4.2s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite;
}

.podium-light-ring {
	position: absolute;
	width: 80px;
	height: 8px;
	border-radius: 50%;
	border: 1px solid rgba(0, 242, 254, 0.35);
	opacity: 0.6;
	animation: podiumRingPulse 4.2s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite;
}

@keyframes podiumShadowScale {
	0%, 100% { transform: scale(1); opacity: 0.9; }
	40%, 50% { transform: scale(0.68); opacity: 0.35; }
	70% { transform: scale(0.92); opacity: 0.75; }
}

@keyframes podiumRingPulse {
	0%, 100% { transform: scale(1); opacity: 0.7; }
	40%, 50% { transform: scale(0.7); opacity: 0.2; }
}

/* Brand Typography */
.brand-title {
	margin-top: 4px;
	margin-bottom: 4px;
	z-index: 2;
}

.brand-name {
	font-size: 32px;
	font-weight: 800;
	letter-spacing: 0.5px;
	background: linear-gradient(135deg, #ffffff 30%, #bae6fd 70%, #38bdf8 100%);
	-webkit-background-clip: text;
	-webkit-text-fill-color: transparent;
	filter: drop-shadow(0 0 18px rgba(0, 242, 254, 0.35));
}

.cyber-divider {
	width: 56px;
	height: 3px;
	background: linear-gradient(90deg, transparent, var(--cyan-neon), transparent);
	border-radius: 2px;
	margin-bottom: 8px;
	box-shadow: 0 0 12px var(--cyan-neon);
}

.login-header {
	font-size: 13.5px;
	color: var(--text-muted);
	margin-bottom: 8px;
	font-weight: 500;
	max-width: 340px;
	letter-spacing: 0.3px;
}

.login-header[hidden] {
	display: none !important;
}

/* Status Pill */
.status-badge-container {
	margin-bottom: 8px;
}

.status-pill {
	display: inline-flex;
	align-items: center;
	gap: 8px;
	padding: 5px 14px;
	background: rgba(15, 23, 42, 0.85);
	border: 1px solid rgba(0, 242, 254, 0.28);
	border-radius: 100px;
	font-size: 11px;
	font-family: var(--font-mono);
	letter-spacing: 0.6px;
	backdrop-filter: blur(10px);
	box-shadow: 0 4px 15px rgba(0,0,0,0.4), 0 0 14px rgba(0, 242, 254, 0.12);
}

.pulse-dot {
	width: 7px;
	height: 7px;
	border-radius: 50%;
	background-color: var(--emerald-glow);
	box-shadow: 0 0 10px var(--emerald-glow);
	animation: pulseGreen 2s infinite ease-in-out;
}

@keyframes pulseGreen {
	0%, 100% { opacity: 1; transform: scale(1); }
	50% { opacity: 0.4; transform: scale(1.3); }
}

.status-text {
	color: #cbd5e1;
	font-weight: 600;
}

.version-tag {
	color: var(--cyan-neon);
	font-weight: 700;
}

.default-account-pill {
	display: inline-flex;
	align-items: center;
	gap: 6px;
	margin-top: 2px;
	padding: 4px 14px;
	background: rgba(30, 41, 59, 0.45);
	border: 1px solid rgba(148, 163, 184, 0.2);
	border-radius: 6px;
	font-size: 12px;
	color: var(--text-muted);
}

.default-account-pill[hidden] {
	display: none !important;
}

.acc-icon { color: var(--cyan-neon); }
.glow-text { color: #38bdf8; font-weight: 600; }

/* Login Card */
.login-card {
	position: relative;
	width: 100%;
	background: var(--card-bg);
	border: 1px solid var(--card-border);
	border-radius: 22px;
	padding: 30px 30px 26px;
	backdrop-filter: blur(30px);
	-webkit-backdrop-filter: blur(30px);
	box-shadow: 
		0 25px 50px -12px rgba(0, 0, 0, 0.78),
		0 0 40px rgba(0, 242, 254, 0.09),
		inset 0 1px 1px rgba(255, 255, 255, 0.12);
	transition: border-color 0.3s ease, box-shadow 0.3s ease;
	overflow: hidden;
}

.login-card:hover {
	border-color: var(--card-border-hover);
	box-shadow: 
		0 30px 60px -12px rgba(0, 0, 0, 0.88),
		0 0 50px rgba(0, 242, 254, 0.16),
		inset 0 1px 2px rgba(255, 255, 255, 0.18);
}

.card-glow-top {
	position: absolute;
	top: 0; left: 8%; right: 8%; height: 2px;
	background: linear-gradient(90deg, transparent, var(--cyan-neon), var(--blue-neon), transparent);
	opacity: 0.85;
}

.card-corner {
	position: absolute; width: 8px; height: 8px;
	border: 2px solid var(--cyan-neon); opacity: 0.65; pointer-events: none;
}
.corner-tl { top: 8px; left: 8px; border-right: none; border-bottom: none; }
.corner-tr { top: 8px; right: 8px; border-left: none; border-bottom: none; }

.field { margin-bottom: 18px; }
.field label { display: block; margin-bottom: 7px; }
.field-label-text {
	font-size: 11px; font-family: var(--font-mono);
	font-weight: 600; letter-spacing: 1.1px; color: var(--text-muted);
}
.input-wrapper, .select-wrapper { position: relative; width: 100%; }

.field input {
	width: 100%; height: 46px; padding: 0 16px;
	background: var(--field-bg); border: 1px solid var(--field-border);
	border-radius: 12px; color: var(--text-main); font-size: 14.5px;
	outline: none; transition: all 0.25s ease;
}
.field input::placeholder { color: var(--text-dim); font-size: 13.5px; }
.field input:focus {
	border-color: var(--field-focus-border);
	background: rgba(10, 18, 38, 0.95);
	box-shadow: 0 0 0 3px rgba(0, 242, 254, 0.22), 0 0 22px rgba(0, 242, 254, 0.16);
}

.field select {
	width: 100%; height: 46px; padding: 0 40px 0 16px;
	background: var(--field-bg); border: 1px solid var(--field-border);
	border-radius: 12px; color: var(--text-main); font-size: 14px;
	outline: none; appearance: none; -webkit-appearance: none; cursor: pointer;
	transition: all 0.25s ease;
}
.select-arrow {
	position: absolute; right: 16px; top: 50%; width: 8px; height: 8px;
	border-right: 2px solid var(--text-muted); border-bottom: 2px solid var(--text-muted);
	transform: translateY(-70%) rotate(45deg); pointer-events: none;
}
.field select:focus {
	border-color: var(--field-focus-border);
	background: rgba(10, 18, 38, 0.95);
	box-shadow: 0 0 0 3px rgba(0, 242, 254, 0.22), 0 0 22px rgba(0, 242, 254, 0.16);
}
.field select:focus + .select-arrow { border-color: var(--cyan-neon); }
.field select option { background: #0b1329; color: #f8fafc; padding: 10px; }

.alert {
	margin-bottom: 16px; padding: 12px 14px;
	background: rgba(239, 68, 68, 0.15); border: 1px solid rgba(239, 68, 68, 0.38);
	border-radius: 10px; color: #fca5a5; font-size: 13px;
	backdrop-filter: blur(8px); display: flex; align-items: center; gap: 8px;
}
.alert[hidden] { display: none !important; }

.btn-submit {
	position: relative; width: 100%; height: 48px; margin-top: 6px;
	background: linear-gradient(135deg, #0284c7 0%, #0369a1 40%, #2563eb 100%);
	border: 1px solid rgba(56, 189, 248, 0.45); border-radius: 12px;
	color: #ffffff; font-size: 13.5px; font-family: var(--font-mono);
	font-weight: 700; letter-spacing: 1px; cursor: pointer;
	overflow: hidden; display: inline-flex; align-items: center; justify-content: center;
	gap: 10px; box-shadow: 0 4px 20px rgba(2, 132, 199, 0.38), 0 0 25px rgba(0, 242, 254, 0.16);
	transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}
.btn-shine {
	position: absolute; top: 0; left: -100%; width: 60%; height: 100%;
	background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.28), transparent);
	transform: skewX(-25deg); transition: all 0.75s ease;
}
.btn-submit:hover .btn-shine { left: 150%; }
.btn-submit:hover {
	transform: translateY(-2px);
	background: linear-gradient(135deg, #0ea5e9 0%, #0284c7 40%, #3b82f6 100%);
	box-shadow: 0 8px 30px rgba(14, 165, 233, 0.55), 0 0 35px rgba(0, 242, 254, 0.32);
	border-color: rgba(56, 189, 248, 0.85);
}
.btn-submit:active { transform: translateY(1px); }
.btn-submit:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
.btn-spin {
	width: 16px; height: 16px; border: 2px solid rgba(255, 255, 255, 0.3);
	border-top-color: #ffffff; border-radius: 50%; display: none;
	animation: spin 0.6s linear infinite;
}
.btn-submit.is-busy .btn-spin { display: inline-block; }
@keyframes spin { to { transform: rotate(360deg); } }

@media (max-width: 480px) {
	.login-wrap { padding: 16px 14px; }
	.login-card { padding: 22px 18px 20px; border-radius: 16px; }
	.avatar-hero-unit { width: 110px; height: 110px; }
	.brand-logo { width: 106px; height: 106px; }
	.brand-name { font-size: 28px; }
}
"""

    print("[*] Writing /opt/unetlab/html/login/index.html and login.css...")
    with sftp.open('/opt/unetlab/html/login/index.html', 'w') as f:
        f.write(LOGIN_HTML.encode('utf-8'))
    with sftp.open('/opt/unetlab/html/login/login.css', 'w') as f:
        f.write(LOGIN_CSS.encode('utf-8'))

    # 2. Update render.js for sidebar logo
    RENDER_JS_SNIPPET = """                    <div class="logo_img">
                        <img data-brand-logo src='${brandLogoUrl()}' class="sidebar-avatar-img" alt="Azam Basha" style="width:54px; height:54px; object-fit:contain; display:block; margin:0 auto; filter:drop-shadow(0 0 10px rgba(0,242,254,0.6));"></img>
                    </div>"""

    with sftp.open('/opt/unetlab/html/themes/default/js/functions/status/render.js', 'r') as f:
        r_js = f.read().decode('utf-8')

    import re
    r_js = re.sub(
        r'<div class="logo_img">.*?</div>\s*</div>\s*</div>',
        RENDER_JS_SNIPPET,
        r_js,
        flags=re.DOTALL
    )
    with sftp.open('/opt/unetlab/html/themes/default/js/functions/status/render.js', 'w') as f:
        f.write(r_js.encode('utf-8'))

    # 3. Update pnq-branding-avatar.js (Top Right Widget)
    AVATAR_WIDGET_JS = """/* ============================================================================
   pnq-branding-avatar.js — Dynamic Interactive Top-Right Circular Avatar Widget
   ============================================================================ */
(function () {
	'use strict';

	var WIDGET_ID = 'pnq-topright-avatar';
	var PILL_ID = 'pnq-nh-pill';
	var PANEL_ID = 'pnq-nh-panel';

	var isCustomMoved = false;
	var isDragging = false;
	var startX = 0, startY = 0;
	var initialLeft = 0, initialTop = 0;

	function createWidget() {
		if (document.getElementById(WIDGET_ID)) return document.getElementById(WIDGET_ID);

		var el = document.createElement('div');
		el.id = WIDGET_ID;
		el.title = 'Azam Basha (Drag to reposition • Double-click to reset)';
		el.setAttribute('aria-label', 'Azam Basha Interactive Avatar');

		el.innerHTML = 
			'<div class="avatar-hero-unit-mini">' +
				'<img class="brand-logo-mini" id="brand-logo-mini" data-brand-logo src="/branding/api.php?action=logo" alt="Azam Basha">' +
			'</div>' +
			'<div class="brand-name-mini-container">' +
				'<span class="brand-name-mini" data-brand-name>Azam Basha</span>' +
				'<div class="cyber-divider-mini"></div>' +
			'</div>';

		function onPointerDown(e) {
			if (e.button && e.button !== 0) return;
			var clientX = e.clientX || (e.touches && e.touches[0] && e.touches[0].clientX) || 0;
			var clientY = e.clientY || (e.touches && e.touches[0] && e.touches[0].clientY) || 0;

			isDragging = true;
			startX = clientX;
			startY = clientY;

			var rect = el.getBoundingClientRect();
			initialLeft = rect.left;
			initialTop = rect.top;

			el.classList.add('is-dragging');

			window.addEventListener('mousemove', onPointerMove, { passive: false });
			window.addEventListener('touchmove', onPointerMove, { passive: false });
			window.addEventListener('mouseup', onPointerUp);
			window.addEventListener('touchend', onPointerUp);
		}

		function onPointerMove(e) {
			if (!isDragging) return;
			var clientX = e.clientX || (e.touches && e.touches[0] && e.touches[0].clientX) || 0;
			var clientY = e.clientY || (e.touches && e.touches[0] && e.touches[0].clientY) || 0;

			var dx = clientX - startX;
			var dy = clientY - startY;

			if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
				isCustomMoved = true;
				el.classList.add('is-custom-pos');

				var newLeft = Math.max(10, Math.min(window.innerWidth - el.offsetWidth - 10, initialLeft + dx));
				var newTop = Math.max(10, Math.min(window.innerHeight - el.offsetHeight - 10, initialTop + dy));

				el.style.left = newLeft + 'px';
				el.style.top = newTop + 'px';
				el.style.right = 'auto';
			}

			if (e.cancelable) e.preventDefault();
		}

		function onPointerUp() {
			isDragging = false;
			el.classList.remove('is-dragging');
			window.removeEventListener('mousemove', onPointerMove);
			window.removeEventListener('touchmove', onPointerMove);
			window.removeEventListener('mouseup', onPointerUp);
			window.removeEventListener('touchend', onPointerUp);
		}

		el.addEventListener('mousedown', onPointerDown);
		el.addEventListener('touchstart', onPointerDown, { passive: true });

		el.addEventListener('dblclick', function (e) {
			e.stopPropagation();
			isCustomMoved = false;
			el.classList.remove('is-custom-pos');
			el.style.left = 'auto';
			el.classList.add('is-snapping');
			setTimeout(function () { el.classList.remove('is-snapping'); }, 400);
			updatePosition();
		});

		document.body.appendChild(el);

		if (window.PnqBranding && window.PnqBranding.apply) {
			window.PnqBranding.load().then(function (cfg) {
				window.PnqBranding.apply(cfg);
			});
		}

		return el;
	}

	function updatePosition() {
		var el = document.getElementById(WIDGET_ID);
		if (!el) return;
		if (isCustomMoved || isDragging) return;

		var panel = document.getElementById(PANEL_ID);
		var pill = document.getElementById(PILL_ID);

		var isPanelOpen = panel && panel.style.display !== 'none' && panel.offsetHeight > 0;

		if (isPanelOpen) {
			var panelRect = panel.getBoundingClientRect();
			var targetTop = Math.round(panelRect.bottom + 18);
			var targetRight = Math.max(16, Math.round(window.innerWidth - panelRect.right));

			el.style.top = targetTop + 'px';
			el.style.right = targetRight + 'px';
			el.style.left = 'auto';
		} else if (pill && pill.offsetHeight > 0) {
			var pillRect = pill.getBoundingClientRect();
			var targetTop = Math.round(pillRect.bottom + 10);
			var targetRight = Math.max(14, Math.round(window.innerWidth - pillRect.right));

			el.style.top = targetTop + 'px';
			el.style.right = targetRight + 'px';
			el.style.left = 'auto';
		} else {
			el.style.top = '68px';
			el.style.right = '24px';
			el.style.left = 'auto';
		}
	}

	function init() {
		createWidget();
		updatePosition();

		var observer = new MutationObserver(function () {
			updatePosition();
		});

		observer.observe(document.body, {
			childList: true,
			subtree: true,
			attributes: true,
			attributeFilter: ['style', 'class']
		});

		window.addEventListener('resize', updatePosition);
		setInterval(updatePosition, 350);
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
"""

    with sftp.open('/opt/unetlab/html/assets-common/js/pnq-branding-avatar.js', 'w') as f:
        f.write(AVATAR_WIDGET_JS.encode('utf-8'))

    # 4. Update pnq-branding-avatar.css
    AVATAR_CSS_CLEAN = """/* ============================================================================
   Azam Basha Dynamic Interactive Holographic Avatar Badge for Labs & Dashboard
   ============================================================================ */

#pnq-topright-avatar {
	position: fixed;
	top: 54px;
	right: 14px;
	z-index: 100045;
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	cursor: grab;
	user-select: none;
	-webkit-user-select: none;
	touch-action: none;
	transition: top 0.42s cubic-bezier(0.34, 1.25, 0.64, 1), right 0.35s ease, transform 0.25s ease;
	filter: drop-shadow(0 8px 24px rgba(0, 0, 0, 0.7));
}

#pnq-topright-avatar.is-dragging {
	cursor: grabbing !important;
	transition: none !important;
	filter: drop-shadow(0 12px 32px rgba(0, 242, 254, 0.6));
}

.avatar-hero-unit-mini {
	position: relative;
	width: 72px;
	height: 72px;
	display: flex;
	align-items: center;
	justify-content: center;
	animation: avatarMiniFloat 4.2s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite;
}

@keyframes avatarMiniFloat {
	0%, 100% { transform: translateY(0px) scale(1); }
	40% { transform: translateY(-6px) scale(1.025); }
	50% { transform: translateY(-7px) scale(1.03); }
	75% { transform: translateY(-2px) scale(0.99); }
}

.brand-logo-mini {
	width: 70px;
	height: 70px;
	object-fit: contain;
	display: block;
	filter: drop-shadow(0 0 12px rgba(0, 242, 254, 0.65));
	transition: transform 0.3s ease;
}

#pnq-topright-avatar:hover .brand-logo-mini {
	transform: scale(1.12);
	filter: drop-shadow(0 0 18px rgba(0, 242, 254, 0.9));
}

.brand-name-mini-container {
	display: flex;
	flex-direction: column;
	align-items: center;
	margin-top: 3px;
	pointer-events: none;
}

.brand-name-mini {
	font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
	font-size: 11px;
	font-weight: 800;
	letter-spacing: 0.5px;
	background: linear-gradient(135deg, #ffffff 30%, #bae6fd 70%, #38bdf8 100%);
	-webkit-background-clip: text;
	-webkit-text-fill-color: transparent;
	filter: drop-shadow(0 0 10px rgba(0, 242, 254, 0.4));
	white-space: nowrap;
}

.cyber-divider-mini {
	width: 32px;
	height: 2px;
	background: linear-gradient(90deg, transparent, #00f2fe, transparent);
	border-radius: 1px;
	margin-top: 2px;
	box-shadow: 0 0 8px #00f2fe;
}

@keyframes snapBackPulse {
	0% { transform: scale(1); }
	50% { transform: scale(1.12); }
	100% { transform: scale(1); }
}

#pnq-topright-avatar.is-snapping {
	animation: snapBackPulse 0.4s ease-out;
}

/* Sidebar Logo Styling */
#lab-sidebar .logo_img {
	margin: 14px auto 10px;
	padding: 0;
	display: flex;
	justify-content: center;
	align-items: center;
	text-align: center;
}

#lab-sidebar .logo_img img {
	width: 52px !important;
	height: 52px !important;
	object-fit: contain !important;
	display: block !important;
	margin: 0 auto !important;
	filter: drop-shadow(0 0 10px rgba(0, 242, 254, 0.6)) !important;
	transition: transform 0.25s ease;
}

#lab-sidebar .logo_img img:hover {
	transform: scale(1.12) !important;
}

/* Topbar Logo Styling */
.topbar-logo {
	width: 34px !important;
	height: 34px !important;
	object-fit: contain !important;
	display: block !important;
	flex-shrink: 0 !important;
	filter: drop-shadow(0 0 8px rgba(0, 242, 254, 0.5)) !important;
	transition: transform 0.2s ease !important;
}

.topbar-logo:hover {
	transform: scale(1.12) !important;
}
"""

    with sftp.open('/opt/unetlab/html/assets-common/css/pnq-branding-avatar.css', 'w') as f:
        f.write(AVATAR_CSS_CLEAN.encode('utf-8'))

    sftp.close()
    client.exec_command('chmod 644 /opt/unetlab/html/login/index.html /opt/unetlab/html/login/login.css /opt/unetlab/html/themes/default/js/functions/status/render.js /opt/unetlab/html/assets-common/js/pnq-branding-avatar.js /opt/unetlab/html/assets-common/css/pnq-branding-avatar.css')
    client.close()
    print("[+] Refined platform styling deployed successfully!")

if __name__ == "__main__":
    refine()
