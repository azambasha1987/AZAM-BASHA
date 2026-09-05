#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Enterprise GUI, Smart Alignment, Spotlight & Mini-Map Suite
# 
# Includes:
# 1. Precision Dot-Grid Canvas & Neon Node Status Rings (Emerald, Amber, Crimson)
# 2. Smart Node Alignment & Auto-Layout Engine (Left, Center, Right, Distribute, Snap, Ring)
# 3. Spotlight Command Palette (Ctrl+K / Cmd+K / / fuzzy device search & action runner)
# 4. Floating Radar Mini-Map Viewport Navigator
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "    Applying Azam Basha Enterprise GUI & Alignment Suite    "
echo "============================================================"

HTML_DIR="/opt/unetlab/html"
THEMES_JS="${HTML_DIR}/themes/default/js"
THEMES_CSS="${HTML_DIR}/themes/default/css"

mkdir -p "$THEMES_JS" "$THEMES_CSS"

# --- 1. Smart Node Alignment & Auto-Layout Toolbar ---
echo "[1/4] Installing Smart Alignment & Auto-Layout Engine..."
cat << 'JSEOF' > "${THEMES_JS}/pnetlab-smart-align.js"
/**
 * Azam Basha Smart Node Alignment & Auto-Layout Engine
 * Figma-style precision alignment, distribution, grid snapping, and auto-layout.
 */
(function() {
    'use strict';

    function getSelectedOrAllNodes() {
        var nodeIds = [];
        if (window.freeSelectedNodes && window.freeSelectedNodes.length > 1) {
            nodeIds = window.freeSelectedNodes.map(function(n) { return String(n.path); });
        } else {
            $('.node_frame.ui-selected').each(function() {
                var id = $(this).data('path') || $(this).attr('data-path') || (this.id || '').replace(/^node/, '');
                if (id) nodeIds.push(String(id));
            });
        }
        if (nodeIds.length <= 1 && window.nodes) {
            nodeIds = Object.keys(window.nodes);
        }
        return nodeIds;
    }

    function saveNodePosition(nodeId, left, top) {
        var url = '/api/labs/session/nodes/' + nodeId;
        $.ajax({
            url: url,
            type: 'PUT',
            dataType: 'json',
            contentType: 'application/json',
            data: JSON.stringify({ left: Math.round(left), top: Math.round(top) })
        });
    }

    function applyAlignment(type) {
        var ids = getSelectedOrAllNodes();
        if (!ids || ids.length < 2) {
            if (window.addMessage) addMessage('warning', 'Select 2 or more nodes to align.');
            return;
        }

        var nodeData = [];
        ids.forEach(function(id) {
            var $elem = $('#node' + id);
            if ($elem.length) {
                var pos = $elem.position();
                nodeData.push({
                    id: id,
                    $elem: $elem,
                    left: pos.left,
                    top: pos.top,
                    width: $elem.outerWidth() || 80,
                    height: $elem.outerHeight() || 80
                });
            }
        });

        if (!nodeData.length) return;

        var minLeft = Math.min.apply(null, nodeData.map(function(n) { return n.left; }));
        var maxLeft = Math.max.apply(null, nodeData.map(function(n) { return n.left; }));
        var minTop = Math.min.apply(null, nodeData.map(function(n) { return n.top; }));
        var maxTop = Math.max.apply(null, nodeData.map(function(n) { return n.top; }));
        var avgLeft = nodeData.reduce(function(acc, n) { return acc + n.left; }, 0) / nodeData.length;
        var avgTop = nodeData.reduce(function(acc, n) { return acc + n.top; }, 0) / nodeData.length;

        if (type === 'left') {
            nodeData.forEach(function(n) { n.newLeft = minLeft; n.newTop = n.top; });
        } else if (type === 'center_h') {
            nodeData.forEach(function(n) { n.newLeft = avgLeft; n.newTop = n.top; });
        } else if (type === 'right') {
            nodeData.forEach(function(n) { n.newLeft = maxLeft; n.newTop = n.top; });
        } else if (type === 'top') {
            nodeData.forEach(function(n) { n.newLeft = n.left; n.newTop = minTop; });
        } else if (type === 'middle_v') {
            nodeData.forEach(function(n) { n.newLeft = n.left; n.newTop = avgTop; });
        } else if (type === 'bottom') {
            nodeData.forEach(function(n) { n.newLeft = n.left; n.newTop = maxTop; });
        } else if (type === 'dist_h') {
            nodeData.sort(function(a, b) { return a.left - b.left; });
            var stepH = (maxLeft - minLeft) / (nodeData.length - 1 || 1);
            nodeData.forEach(function(n, idx) { n.newLeft = minLeft + (stepH * idx); n.newTop = n.top; });
        } else if (type === 'dist_v') {
            nodeData.sort(function(a, b) { return a.top - b.top; });
            var stepV = (maxTop - minTop) / (nodeData.length - 1 || 1);
            nodeData.forEach(function(n, idx) { n.newLeft = n.left; n.newTop = minTop + (stepV * idx); });
        } else if (type === 'snap_grid') {
            var gridSize = 30;
            nodeData.forEach(function(n) {
                n.newLeft = Math.round(n.left / gridSize) * gridSize;
                n.newTop = Math.round(n.top / gridSize) * gridSize;
            });
        } else if (type === 'auto_ring') {
            var radius = Math.max(160, nodeData.length * 35);
            var angleStep = (2 * Math.PI) / nodeData.length;
            nodeData.forEach(function(n, idx) {
                n.newLeft = avgLeft + (radius * Math.cos(idx * angleStep));
                n.newTop = avgTop + (radius * Math.sin(idx * angleStep));
            });
        }

        nodeData.forEach(function(n) {
            n.$elem.css({ left: n.newLeft + 'px', top: n.newTop + 'px' });
            if (window.nodes && window.nodes[n.id]) {
                window.nodes[n.id].left = Math.round(n.newLeft);
                window.nodes[n.id].top = Math.round(n.newTop);
            }
            saveNodePosition(n.id, n.newLeft, n.newTop);
        });

        if (window.App && window.App.topology && window.App.topology.printTopology) {
            setTimeout(function() { window.App.topology.printTopology(); }, 50);
        }
        if (window.addMessage) addMessage('success', 'Topology Smart Alignment applied: ' + type);
    }

    function initToolbar() {
        if ($('#pnq-align-toolbar').length) return;

        var toolbarHtml = `
        <div id="pnq-align-toolbar" style="position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:9990;display:flex;align-items:center;gap:4px;padding:6px 12px;background:rgba(15,17,23,0.85);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.12);border-radius:30px;box-shadow:0 8px 32px rgba(0,0,0,0.65);">
            <button class="btn btn-xs pnq-align-btn" data-align="left" title="Align Left" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-align-left"></i></button>
            <button class="btn btn-xs pnq-align-btn" data-align="center_h" title="Align Horizontal Center" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-align-center"></i></button>
            <button class="btn btn-xs pnq-align-btn" data-align="right" title="Align Right" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-align-right"></i></button>
            <span style="width:1px;height:16px;background:rgba(255,255,255,0.15);margin:0 2px;"></span>
            <button class="btn btn-xs pnq-align-btn" data-align="top" title="Align Top" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-arrow-up"></i></button>
            <button class="btn btn-xs pnq-align-btn" data-align="middle_v" title="Align Middle" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-arrows-v"></i></button>
            <button class="btn btn-xs pnq-align-btn" data-align="bottom" title="Align Bottom" style="background:transparent;color:#f8fafc;border:none;padding:4px 8px;"><i class="fa fa-arrow-down"></i></button>
            <span style="width:1px;height:16px;background:rgba(255,255,255,0.15);margin:0 2px;"></span>
            <button class="btn btn-xs pnq-align-btn" data-align="dist_h" title="Distribute Horizontally" style="background:transparent;color:#38bdf8;border:none;padding:4px 8px;"><i class="fa fa-arrows-h"></i> Equal H</button>
            <button class="btn btn-xs pnq-align-btn" data-align="dist_v" title="Distribute Vertically" style="background:transparent;color:#38bdf8;border:none;padding:4px 8px;"><i class="fa fa-arrows-v"></i> Equal V</button>
            <span style="width:1px;height:16px;background:rgba(255,255,255,0.15);margin:0 2px;"></span>
            <button class="btn btn-xs pnq-align-btn" data-align="snap_grid" title="Snap to 30px Grid" style="background:transparent;color:#10b981;border:none;padding:4px 8px;"><i class="fa fa-th"></i> Snap Grid</button>
            <button class="btn btn-xs pnq-align-btn" data-align="auto_ring" title="Circular Mesh Ring" style="background:transparent;color:#f59e0b;border:none;padding:4px 8px;"><i class="fa fa-circle-o-notch"></i> Ring</button>
        </div>`;

        $('body').append(toolbarHtml);

        $(document).on('click', '.pnq-align-btn', function() {
            var alignType = $(this).data('align');
            applyAlignment(alignType);
        });
    }

    $(document).ready(initToolbar);
    window.pnqAlign = applyAlignment;
    console.log('[Azam-Basha] Smart Node Alignment & Auto-Layout Toolbar Active.');
})();
JSEOF

# --- 2. Spotlight Command Palette ---
echo "[2/4] Installing Spotlight Command Palette (Ctrl+K)..."
cat << 'JSEOF' > "${THEMES_JS}/pnetlab-spotlight.js"
/**
 * Azam Basha Spotlight Command Palette (Ctrl+K / Cmd+K / /)
 * Instant device fuzzy-finder and global action runner.
 */
(function() {
    'use strict';

    var selectedIndex = 0;
    var filteredItems = [];

    function renderSpotlightModal() {
        if ($('#pnq-spotlight-modal').length) return;

        var html = `
        <div id="pnq-spotlight-modal" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.75);backdrop-filter:blur(10px);z-index:999999;align-items:flex-start;justify-content:center;padding-top:100px;">
            <div style="width:620px;max-width:92%;background:#0f1117;border:1px solid rgba(255,255,255,0.15);border-radius:12px;box-shadow:0 24px 64px rgba(0,0,0,0.9);overflow:hidden;">
                <div style="display:flex;align-items:center;padding:14px 18px;border-bottom:1px solid rgba(255,255,255,0.08);background:#151822;">
                    <i class="fa fa-search" style="color:#3b82f6;font-size:18px;margin-right:12px;"></i>
                    <input type="text" id="pnq-spotlight-input" placeholder="Search devices or type a command (> Start All, > Heatmap)..." style="width:100%;background:transparent;border:none;color:#f8fafc;font-size:16px;outline:none;" autofocus>
                    <span style="font-size:11px;background:#1e293b;color:#94a3b8;padding:2px 6px;border-radius:4px;margin-left:8px;">ESC to close</span>
                </div>
                <div id="pnq-spotlight-results" style="max-height:360px;overflow-y:auto;padding:8px 0;">
                </div>
                <div style="padding:8px 16px;background:#0d0f16;border-top:1px solid rgba(255,255,255,0.05);display:flex;justify-content:space-between;font-size:11px;color:#64748b;">
                    <span>Navigate: <kbd style="background:#1e293b;color:#94a3b8;">↑</kbd> <kbd style="background:#1e293b;color:#94a3b8;">↓</kbd></span>
                    <span>Select: <kbd style="background:#1e293b;color:#94a3b8;">ENTER</kbd></span>
                </div>
            </div>
        </div>`;

        $('body').append(html);
        attachSpotlightEvents();
    }

    function getAllCommands() {
        var items = [];

        if (window.nodes) {
            for (var id in window.nodes) {
                var node = window.nodes[id];
                items.push({
                    type: 'node',
                    id: id,
                    title: node.name || ('Node ' + id),
                    subtitle: 'Device: ' + (node.template || 'QEMU') + ' | Status: ' + (node.status === 2 ? '🟢 Running' : '⚪ Stopped'),
                    icon: 'fa-server',
                    action: function(nodeId) { jumpToNode(nodeId); }
                });
            }
        }

        items.push({
            type: 'cmd',
            title: 'Start All Lab Nodes',
            subtitle: 'Launches all topology nodes with parallel async engine',
            icon: 'fa-play-circle',
            action: function() { $('.action-nodesstart').trigger('click'); }
        });
        items.push({
            type: 'cmd',
            title: 'Stop All Lab Nodes',
            subtitle: 'Gracefully halts all running nodes',
            icon: 'fa-stop-circle',
            action: function() { $('.action-nodesstop').trigger('click'); }
        });
        items.push({
            type: 'cmd',
            title: 'Toggle Real-Time Telemetry Link Heatmap',
            subtitle: 'Live visual traffic monitor and error heatmap',
            icon: 'fa-bolt',
            action: function() { if (window.pnqToggleHeatmap) window.pnqToggleHeatmap(); }
        });
        items.push({
            type: 'cmd',
            title: 'Open In-Browser Packet Dissector',
            subtitle: 'Wireshark-like live packet inspection modal',
            icon: 'fa-search',
            action: function() { if (window.pnqOpenPacketViewer) window.pnqOpenPacketViewer(); }
        });
        items.push({
            type: 'cmd',
            title: 'Snap All Nodes to 30px Grid',
            subtitle: 'Aligns all device coordinates cleanly',
            icon: 'fa-th',
            action: function() { if (window.pnqAlign) window.pnqAlign('snap_grid'); }
        });
        items.push({
            type: 'cmd',
            title: 'Auto-Layout: Circular Mesh Ring',
            subtitle: 'Arranges topology into an equidistant ring',
            icon: 'fa-circle-o-notch',
            action: function() { if (window.pnqAlign) window.pnqAlign('auto_ring'); }
        });

        return items;
    }

    function jumpToNode(nodeId) {
        var $elem = $('#node' + nodeId);
        if (!$elem.length) return;

        var pos = $elem.position();
        var winW = $(window).width();
        var winH = $(window).height();

        $('html, body, #canvas').animate({
            scrollLeft: Math.max(0, pos.left - (winW / 2) + 40),
            scrollTop: Math.max(0, pos.top - (winH / 2) + 40)
        }, 400);

        $elem.css('transition', 'box-shadow 0.2s ease')
             .css('box-shadow', '0 0 0 6px #38bdf8, 0 0 30px #38bdf8');
        setTimeout(function() {
            $elem.css('box-shadow', '');
        }, 1600);
    }

    function renderResults(query) {
        var allItems = getAllCommands();
        var q = (query || '').toLowerCase().trim();

        filteredItems = allItems.filter(function(item) {
            if (!q) return true;
            return item.title.toLowerCase().indexOf(q) !== -1 || item.subtitle.toLowerCase().indexOf(q) !== -1;
        });

        var $results = $('#pnq-spotlight-results');
        $results.empty();
        selectedIndex = 0;

        if (!filteredItems.length) {
            $results.html('<div style="padding:20px;text-align:center;color:#64748b;">No matching devices or commands found.</div>');
            return;
        }

        filteredItems.slice(0, 10).forEach(function(item, idx) {
            var isSel = (idx === 0);
            var itemHtml = `
            <div class="pnq-spot-item" data-idx="${idx}" style="display:flex;align-items:center;padding:10px 18px;cursor:pointer;background:${isSel ? 'rgba(59,130,246,0.18)' : 'transparent'};border-left:${isSel ? '3px solid #3b82f6' : '3px solid transparent'};">
                <i class="fa ${item.icon}" style="font-size:16px;color:${item.type === 'node' ? '#38bdf8' : '#10b981'};width:26px;"></i>
                <div style="flex:1;">
                    <div style="font-size:14px;font-weight:600;color:#f8fafc;">${item.title}</div>
                    <div style="font-size:12px;color:#94a3b8;">${item.subtitle}</div>
                </div>
                <span style="font-size:11px;color:#64748b;">${item.type === 'node' ? 'Device' : 'Command'}</span>
            </div>`;
            $results.append(itemHtml);
        });
    }

    function openSpotlight() {
        renderSpotlightModal();
        $('#pnq-spotlight-modal').css('display', 'flex');
        $('#pnq-spotlight-input').val('').focus();
        renderResults('');
    }

    function closeSpotlight() {
        $('#pnq-spotlight-modal').hide();
    }

    function attachSpotlightEvents() {
        $('#pnq-spotlight-input').on('input', function() {
            renderResults($(this).val());
        });

        $('#pnq-spotlight-input').on('keydown', function(e) {
            if (e.key === 'ArrowDown') {
                e.preventDefault();
                selectedIndex = Math.min(filteredItems.length - 1, selectedIndex + 1);
                updateSelection();
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                selectedIndex = Math.max(0, selectedIndex - 1);
                updateSelection();
            } else if (e.key === 'Enter') {
                e.preventDefault();
                if (filteredItems[selectedIndex]) {
                    var act = filteredItems[selectedIndex].action;
                    var nId = filteredItems[selectedIndex].id;
                    closeSpotlight();
                    act(nId);
                }
            } else if (e.key === 'Escape') {
                closeSpotlight();
            }
        });

        $(document).on('click', '.pnq-spot-item', function() {
            var idx = $(this).data('idx');
            if (filteredItems[idx]) {
                var act = filteredItems[idx].action;
                var nId = filteredItems[idx].id;
                closeSpotlight();
                act(nId);
            }
        });

        $(document).on('click', '#pnq-spotlight-modal', function(e) {
            if (e.target.id === 'pnq-spotlight-modal') closeSpotlight();
        });
    }

    function updateSelection() {
        $('.pnq-spot-item').each(function(idx) {
            var isSel = (idx === selectedIndex);
            $(this).css({
                background: isSel ? 'rgba(59,130,246,0.18)' : 'transparent',
                borderLeft: isSel ? '3px solid #3b82f6' : '3px solid transparent'
            });
        });
    }

    $(document).on('keydown', function(e) {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
            e.preventDefault();
            openSpotlight();
        } else if (e.key === '/' && !$(e.target).is('input, textarea, select')) {
            e.preventDefault();
            openSpotlight();
        }
    });

    window.pnqOpenSpotlight = openSpotlight;
    console.log('[Azam-Basha] Spotlight Command Palette Ready (Press Ctrl+K).');
})();
JSEOF

# --- 3. Floating Radar Mini-Map ---
echo "[3/4] Installing Floating Radar Mini-Map Viewport Navigator..."
cat << 'JSEOF' > "${THEMES_JS}/pnetlab-minimap.js"
/**
 * Azam Basha Radar Mini-Map Viewport Navigator
 * Live interactive topology thumbnail with draggable viewport radar.
 */
(function() {
    'use strict';

    var mapCanvas = null;
    var ctx = null;

    function initMinimap() {
        if ($('#pnq-minimap-box').length) return;

        var html = `
        <div id="pnq-minimap-box" style="position:fixed;bottom:20px;right:20px;width:190px;height:130px;background:rgba(15,17,23,0.85);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.12);border-radius:10px;box-shadow:0 8px 32px rgba(0,0,0,0.7);z-index:9980;overflow:hidden;">
            <div style="display:flex;align-items:center;justify-content:space-between;padding:4px 8px;background:rgba(21,24,34,0.9);border-bottom:1px solid rgba(255,255,255,0.06);">
                <span style="font-size:11px;font-weight:700;color:#94a3b8;"><i class="fa fa-map-o"></i> Mini-Map</span>
                <a href="javascript:void(0)" id="pnq-minimap-toggle" style="color:#64748b;font-size:12px;"><i class="fa fa-chevron-down"></i></a>
            </div>
            <div id="pnq-minimap-content" style="position:relative;width:100%;height:104px;">
                <canvas id="pnq-minimap-canvas" width="190" height="104" style="display:block;width:100%;height:100%;"></canvas>
                <div id="pnq-minimap-viewport" style="position:absolute;top:0;left:0;width:50px;height:30px;border:1.5px solid #38bdf8;background:rgba(56,189,248,0.15);cursor:move;border-radius:2px;"></div>
            </div>
        </div>`;

        $('body').append(html);
        mapCanvas = document.getElementById('pnq-minimap-canvas');
        if (mapCanvas) ctx = mapCanvas.getContext('2d');

        attachMinimapEvents();
        setInterval(drawMinimap, 2000);
        setTimeout(drawMinimap, 600);
    }

    function drawMinimap() {
        if (!ctx || !mapCanvas || !$('#pnq-minimap-box').is(':visible')) return;

        var w = mapCanvas.width;
        var h = mapCanvas.height;
        ctx.clearRect(0, 0, w, h);

        if (!window.nodes || Object.keys(window.nodes).length === 0) return;

        var maxX = 2000;
        var maxY = 1500;

        for (var id in window.nodes) {
            var n = window.nodes[id];
            if (n.left > maxX) maxX = n.left + 200;
            if (n.top > maxY) maxY = n.top + 200;
        }

        var scaleX = w / maxX;
        var scaleY = h / maxY;

        for (var id in window.nodes) {
            var n = window.nodes[id];
            var nx = (n.left || 0) * scaleX;
            var ny = (n.top || 0) * scaleY;

            ctx.beginPath();
            ctx.arc(nx, ny, 3.5, 0, 2 * Math.PI);
            ctx.fillStyle = (n.status === 2 || n.status === 3) ? '#10b981' : '#64748b';
            ctx.fill();
        }

        var scrollLeft = $(window).scrollLeft();
        var scrollTop = $(window).scrollTop();
        var winW = $(window).width();
        var winH = $(window).height();

        var vpW = Math.max(20, winW * scaleX);
        var vpH = Math.max(15, winH * scaleY);
        var vpX = scrollLeft * scaleX;
        var vpY = scrollTop * scaleY;

        $('#pnq-minimap-viewport').css({
            left: Math.min(w - vpW, Math.max(0, vpX)) + 'px',
            top: Math.min(h - vpH, Math.max(0, vpY)) + 'px',
            width: vpW + 'px',
            height: vpH + 'px'
        });
    }

    function attachMinimapEvents() {
        $(document).on('click', '#pnq-minimap-toggle', function() {
            var $c = $('#pnq-minimap-content');
            $c.slideToggle(150);
            $(this).find('i').toggleClass('fa-chevron-down fa-chevron-up');
        });

        $(document).on('click', '#pnq-minimap-canvas', function(e) {
            var offset = $(this).offset();
            var cx = e.pageX - offset.left;
            var cy = e.pageY - offset.top;
            var w = mapCanvas.width;
            var h = mapCanvas.height;

            var targetX = (cx / w) * 2000 - ($(window).width() / 2);
            var targetY = (cy / h) * 1500 - ($(window).height() / 2);

            $('html, body, #canvas').animate({
                scrollLeft: Math.max(0, targetX),
                scrollTop: Math.max(0, targetY)
            }, 300);
        });

        $(window).on('scroll resize', drawMinimap);
    }

    $(document).ready(initMinimap);
    console.log('[Azam-Basha] Radar Mini-Map Viewport Navigator Active.');
})();
JSEOF

# --- 4. Dot Grid & Status Ring CSS ---
echo "[4/4] Injecting Dot-Grid Canvas and Neon Status Rings into Stylesheets..."
if [ -f "${THEMES_CSS}/azambasha-dark.css" ] && ! grep -q "radial-gradient" "${THEMES_CSS}/azambasha-dark.css"; then
    cat << 'CSSEOF' >> "${THEMES_CSS}/azambasha-dark.css"

/* Precision Dot-Grid Canvas Background */
#canvas, .jtk-surface, .topology-canvas {
  background-color: #07080c !important;
  background-image: radial-gradient(rgba(255, 255, 255, 0.14) 1.2px, transparent 1.2px) !important;
  background-size: 24px 24px !important;
}

/* Neon Node Status Rings */
.node_frame[data-status="2"] .node_icon,
.node_frame[data-status="3"] .node_icon {
  box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.45), 0 0 16px rgba(16, 185, 129, 0.85) !important;
  border-radius: 8px !important;
}

.node_frame[data-status="5"] .node_icon {
  box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.45), 0 0 16px rgba(245, 158, 11, 0.85) !important;
  border-radius: 8px !important;
  animation: pnqPulse 1.2s infinite alternate !important;
}

.node_frame[data-status="7"] .node_icon {
  box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.45), 0 0 16px rgba(239, 68, 68, 0.85) !important;
  border-radius: 8px !important;
}

.node_frame[data-status="0"] .node_icon {
  box-shadow: 0 0 0 1.5px rgba(255, 255, 255, 0.12) !important;
  border-radius: 8px !important;
}
CSSEOF
fi

# Inject scripts into index.html
INDEX_HTML="${HTML_DIR}/themes/default/index.html"
if [ -f "$INDEX_HTML" ]; then
    for js in pnetlab-smart-align.js pnetlab-spotlight.js pnetlab-minimap.js; do
        if ! grep -q "$js" "$INDEX_HTML"; then
            sed -i "/<\/body>/i <script src=\"/themes/default/js/$js\"></script>" "$INDEX_HTML"
        fi
    done
fi

chown -R www-data:www-data "$HTML_DIR"
chmod 755 "$THEMES_JS"/*.js 2>/dev/null || true
systemctl reload apache2 2>/dev/null || true

echo "============================================================"
echo "  [SUCCESS] All Enterprise GUI & Alignment Enhancements Active!"
echo "============================================================"
