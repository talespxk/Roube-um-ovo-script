import os
import sys
import json
import time
import urllib.request
import urllib.error
import subprocess
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

PLACE_ID = "107778070777162"
PORT = 5000

cache_data = {"timestamp": 0, "servers": []}
CACHE_TTL = 3.0

def fetch_roblox_servers(force=False):
    global cache_data
    now = time.time()
    if not force and (now - cache_data["timestamp"] < CACHE_TTL) and cache_data["servers"]:
        return cache_data["servers"]

    url = f"https://games.roblox.com/v1/games/{PLACE_ID}/servers/Public?sortOrder=Asc&limit=100"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7",
        "Origin": "https://www.roblox.com",
        "Referer": "https://www.roblox.com/",
    }

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
            items = raw.get("data", [])
            servers = []
            for s in items:
                sid = s.get("id", "")
                playing = s.get("playing", 0)
                max_p = s.get("maxPlayers", 20)
                if sid and playing < max_p:
                    servers.append({
                        "id": sid,
                        "playing": playing,
                        "maxPlayers": max_p,
                        "fps": int(s.get("fps", 60)),
                        "ping": int(s.get("ping", 0)),
                    })
            servers.sort(key=lambda x: (x["playing"], -x["fps"], x["ping"]))
            cache_data = {"timestamp": now, "servers": servers}
            return servers
    except urllib.error.HTTPError as e:
        if cache_data["servers"]:
            return cache_data["servers"]
        return {"error": f"Erro {e.code}: {e.reason}"}
    except Exception as e:
        if cache_data["servers"]:
            return cache_data["servers"]
        return {"error": str(e)}

HTML_PAGE = r'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Steal An Egg — Server Browser</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-base: #090a0d;
            --bg-subtle: #0e1117;
            --bg-surface: #141822;
            --bg-card: #171c28;
            --bg-card-hover: #1c2232;
            --border: #232a3b;
            --border-subtle: #1c2230;
            --border-focus: #3b82f6;

            --text-primary: #f1f5f9;
            --text-secondary: #94a3b8;
            --text-muted: #64748b;
            --text-dim: #475569;

            --green: #10b981;
            --green-subtle: rgba(16, 185, 129, 0.12);
            --green-border: rgba(16, 185, 129, 0.28);

            --amber: #f59e0b;
            --amber-subtle: rgba(245, 158, 11, 0.12);
            
            --blue: #3b82f6;
            --blue-subtle: rgba(59, 130, 246, 0.12);

            --radius-sm: 6px;
            --radius-md: 8px;
            --radius-lg: 12px;
            --radius-xl: 16px;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: var(--bg-base);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }

        /* TOPBAR NAV */
        nav {
            border-bottom: 1px solid var(--border);
            background: var(--bg-subtle);
            position: sticky;
            top: 0;
            z-index: 50;
            backdrop-filter: blur(8px);
        }

        .nav-inner {
            max-width: 1280px;
            margin: 0 auto;
            padding: 12px 24px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
        }

        .nav-brand {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .logo-mark {
            width: 32px;
            height: 32px;
            background: #1e293b;
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--text-primary);
        }

        .nav-title {
            font-size: 14px;
            font-weight: 600;
            color: var(--text-primary);
            letter-spacing: -0.2px;
        }

        .nav-meta {
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 1px;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .tag-pill {
            font-size: 11px;
            font-weight: 500;
            font-family: 'JetBrains Mono', monospace;
            background: #1e293b;
            color: var(--text-secondary);
            padding: 1px 6px;
            border-radius: 4px;
            border: 1px solid var(--border);
        }

        .nav-actions {
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .live-chip {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            font-size: 12px;
            font-weight: 500;
            color: var(--text-secondary);
            background: var(--bg-surface);
            border: 1px solid var(--border);
            padding: 6px 12px;
            border-radius: var(--radius-md);
        }

        .live-dot {
            width: 7px;
            height: 7px;
            background: var(--green);
            border-radius: 50%;
            box-shadow: 0 0 8px var(--green);
        }

        .btn-action {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            background: var(--bg-surface);
            border: 1px solid var(--border);
            color: var(--text-primary);
            font-size: 12px;
            font-weight: 600;
            padding: 7px 13px;
            border-radius: var(--radius-md);
            cursor: pointer;
            transition: all 0.15s ease;
        }

        .btn-action:hover {
            background: var(--bg-card-hover);
            border-color: var(--text-muted);
        }

        .btn-action:active {
            transform: scale(0.98);
        }

        .icon-spin {
            animation: spin 0.7s linear infinite;
        }

        @keyframes spin { 100% { transform: rotate(360deg); } }

        /* MAIN CONTAINER */
        main {
            max-width: 1280px;
            width: 100%;
            margin: 0 auto;
            padding: 24px;
            flex: 1;
        }

        /* QUICK CONNECT HERO BAR */
        .quick-bar {
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            padding: 18px 24px;
            margin-bottom: 24px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 20px;
            flex-wrap: wrap;
        }

        .quick-info {
            display: flex;
            flex-direction: column;
            gap: 4px;
        }

        .quick-label {
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.8px;
            color: var(--green);
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .quick-title {
            font-size: 15px;
            font-weight: 600;
            color: var(--text-primary);
        }

        .quick-desc {
            font-size: 13px;
            color: var(--text-muted);
        }

        .btn-primary {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: #ffffff;
            color: #090a0d;
            font-size: 13px;
            font-weight: 600;
            padding: 10px 20px;
            border-radius: var(--radius-md);
            border: none;
            cursor: pointer;
            transition: all 0.15s ease;
        }

        .btn-primary:hover {
            background: #e2e8f0;
            box-shadow: 0 4px 16px rgba(255, 255, 255, 0.15);
        }

        .btn-primary:active {
            transform: scale(0.98);
        }

        /* CONTROLS STRIP */
        .controls-strip {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 14px;
            margin-bottom: 16px;
            flex-wrap: wrap;
        }

        .filter-tabs {
            display: flex;
            align-items: center;
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            padding: 3px;
            gap: 2px;
        }

        .tab-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            font-size: 12px;
            font-weight: 500;
            padding: 6px 14px;
            border-radius: var(--radius-sm);
            cursor: pointer;
            transition: all 0.15s;
        }

        .tab-btn:hover {
            color: var(--text-primary);
        }

        .tab-btn.active {
            background: var(--bg-surface);
            color: var(--text-primary);
            font-weight: 600;
            border: 1px solid var(--border-subtle);
        }

        .controls-right {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .search-field {
            display: flex;
            align-items: center;
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            padding: 6px 12px;
            gap: 8px;
            width: 260px;
            transition: border-color 0.15s;
        }

        .search-field:focus-within {
            border-color: var(--border-focus);
        }

        .search-field input {
            background: transparent;
            border: none;
            outline: none;
            color: var(--text-primary);
            font-size: 12px;
            width: 100%;
        }

        .search-field input::placeholder {
            color: var(--text-dim);
        }

        .shortcut-badge {
            font-size: 10px;
            font-family: 'JetBrains Mono', monospace;
            background: #1e293b;
            color: var(--text-dim);
            padding: 2px 5px;
            border-radius: 3px;
            border: 1px solid var(--border);
        }

        .view-switcher {
            display: flex;
            align-items: center;
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            padding: 3px;
        }

        .view-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            padding: 5px 8px;
            border-radius: var(--radius-sm);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .view-btn.active {
            background: var(--bg-surface);
            color: var(--text-primary);
        }

        /* METRICS STRIP */
        .metrics-strip {
            display: flex;
            align-items: center;
            gap: 20px;
            padding: 12px 18px;
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            margin-bottom: 20px;
            font-size: 12px;
            color: var(--text-muted);
            flex-wrap: wrap;
        }

        .metric-inline {
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .metric-inline strong {
            font-family: 'JetBrains Mono', monospace;
            font-size: 13px;
            color: var(--text-primary);
        }

        .metric-inline .green { color: var(--green); }

        /* TABLE VIEW (DEFAULT) */
        .table-wrap {
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            overflow: hidden;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 13px;
        }

        thead {
            background: #0b0e14;
            border-bottom: 1px solid var(--border);
        }

        th {
            padding: 12px 16px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.6px;
            color: var(--text-muted);
        }

        tbody tr {
            border-bottom: 1px solid var(--border-subtle);
            transition: background 0.12s ease;
        }

        tbody tr:hover {
            background: var(--bg-card);
        }

        tbody tr:last-child {
            border-bottom: none;
        }

        td {
            padding: 12px 16px;
            vertical-align: middle;
        }

        .rank-cell {
            font-family: 'JetBrains Mono', monospace;
            font-weight: 600;
            font-size: 12px;
            color: var(--text-muted);
            width: 48px;
        }

        .rank-top-1 { color: #f59e0b; }
        .rank-top-2 { color: #94a3b8; }
        .rank-top-3 { color: #d97706; }

        .players-cell {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .status-tag {
            display: inline-flex;
            align-items: center;
            gap: 5px;
            font-size: 12px;
            font-weight: 600;
            font-family: 'JetBrains Mono', monospace;
            padding: 3px 8px;
            border-radius: 4px;
        }

        .tag-1 {
            background: var(--green-subtle);
            color: var(--green);
            border: 1px solid var(--green-border);
        }

        .tag-low {
            background: var(--amber-subtle);
            color: var(--amber);
            border: 1px solid rgba(245, 158, 11, 0.25);
        }

        .mini-bar {
            width: 60px;
            height: 4px;
            background: rgba(255,255,255,0.06);
            border-radius: 2px;
            overflow: hidden;
        }

        .mini-bar-fill {
            height: 100%;
            border-radius: 2px;
        }

        .mono-val {
            font-family: 'JetBrains Mono', monospace;
            font-size: 12px;
            color: var(--text-secondary);
        }

        .job-id-cell {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-family: 'JetBrains Mono', monospace;
            font-size: 11px;
            color: var(--text-dim);
            background: rgba(0,0,0,0.25);
            padding: 3px 7px;
            border-radius: 4px;
            border: 1px solid rgba(255,255,255,0.04);
        }

        .btn-copy {
            background: transparent;
            border: none;
            color: var(--text-muted);
            cursor: pointer;
            font-size: 11px;
            display: flex;
            align-items: center;
            padding: 2px;
        }

        .btn-copy:hover {
            color: var(--text-primary);
        }

        .btn-table-join {
            background: var(--bg-surface);
            border: 1px solid var(--border);
            color: var(--text-primary);
            font-size: 12px;
            font-weight: 600;
            padding: 6px 14px;
            border-radius: var(--radius-sm);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            transition: all 0.15s;
        }

        .btn-table-join:hover {
            background: #ffffff;
            color: #000000;
            border-color: #ffffff;
        }

        .btn-table-join:active {
            transform: scale(0.97);
        }

        /* GRID VIEW */
        .cards-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
            gap: 12px;
        }

        .grid-card {
            background: var(--bg-subtle);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            padding: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
            transition: all 0.15s ease;
        }

        .grid-card:hover {
            border-color: var(--text-muted);
            background: var(--bg-card);
        }

        .card-row-top {
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .card-row-mid {
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 12px;
            color: var(--text-muted);
            padding: 8px 10px;
            background: rgba(0,0,0,0.2);
            border-radius: 6px;
        }

        /* EMPTY & LOADING STATES */
        .empty-wrap {
            padding: 60px 20px;
            text-align: center;
            color: var(--text-muted);
            font-size: 13px;
        }

        .loader-ring {
            width: 28px;
            height: 28px;
            border: 2px solid var(--border);
            border-top-color: var(--text-primary);
            border-radius: 50%;
            animation: spin 0.6s linear infinite;
            margin: 0 auto 12px;
        }

        /* TOAST */
        .toast-bar {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: #181f2f;
            border: 1px solid var(--border);
            color: var(--text-primary);
            font-size: 13px;
            font-weight: 500;
            padding: 10px 16px;
            border-radius: var(--radius-md);
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            display: flex;
            align-items: center;
            gap: 10px;
            transform: translateY(80px);
            opacity: 0;
            transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
            z-index: 100;
        }

        .toast-bar.visible {
            transform: translateY(0);
            opacity: 1;
        }
    </style>
</head>
<body>
    <nav>
        <div class="nav-inner">
            <div class="nav-brand">
                <div class="logo-mark">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                </div>
                <div>
                    <div class="nav-title">Steal An Egg — Server Browser</div>
                    <div class="nav-meta">
                        <span>Place ID: <span class="tag-pill">107778070777162</span></span>
                    </div>
                </div>
            </div>
            <div class="nav-actions">
                <div class="live-chip">
                    <span class="live-dot"></span>
                    <span id="refresh-timer-label">Ao Vivo</span>
                </div>
                <button class="btn-action" id="btn-refresh" onclick="triggerManualRefresh()">
                    <svg class="icon-refresh" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"></polyline><polyline points="1 20 1 14 7 14"></polyline><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path></svg>
                    <span>Atualizar</span>
                </button>
            </div>
        </div>
    </nav>

    <main>
        <!-- QUICK CONNECT -->
        <section class="quick-bar">
            <div class="quick-info">
                <div class="quick-label">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon></svg>
                    Recomendação Instantânea
                </div>
                <div class="quick-title" id="best-server-title">Servidor #1 — 1 Jogador Online</div>
                <div class="quick-desc">Conexão direta através do inicializador oficial do Windows (sem riscos de kick).</div>
            </div>
            <button class="btn-primary" onclick="joinBestServer()">
                <span>Entrar no Menor (#1)</span>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>
            </button>
        </section>

        <!-- METRICS STRIP -->
        <div class="metrics-strip">
            <div class="metric-inline">
                <span>Servidores com 1 player:</span>
                <strong class="green" id="stat-one-player">0</strong>
            </div>
            <div class="metric-inline">
                <span>Total rastreado:</span>
                <strong id="stat-total">0</strong>
            </div>
            <div class="metric-inline">
                <span>Menor latência:</span>
                <strong id="stat-ping">0 ms</strong>
            </div>
            <div class="metric-inline">
                <span>Última sincronização:</span>
                <strong id="stat-time">--:--:--</strong>
            </div>
        </div>

        <!-- CONTROLS & FILTERS -->
        <div class="controls-strip">
            <div class="filter-tabs">
                <button class="tab-btn active" onclick="setFilter('1', this)">1 Jogador</button>
                <button class="tab-btn" onclick="setFilter('low', this)">≤ 3 Jogadores</button>
                <button class="tab-btn" onclick="setFilter('all', this)">Todos os Servidores</button>
            </div>
            <div class="controls-right">
                <div class="search-field">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
                    <input type="text" id="search-box" placeholder="Buscar por ID ou Ping..." oninput="renderContent()">
                    <span class="shortcut-badge">/</span>
                </div>
                <div class="view-switcher">
                    <button class="view-btn active" id="btn-view-table" onclick="setView('table', this)" title="Modo Tabela">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"></line><line x1="8" y1="12" x2="21" y2="12"></line><line x1="8" y1="18" x2="21" y2="18"></line><line x1="3" y1="6" x2="3.01" y2="6"></line><line x1="3" y1="12" x2="3.01" y2="12"></line><line x1="3" y1="18" x2="3.01" y2="18"></line></svg>
                    </button>
                    <button class="view-btn" id="btn-view-cards" onclick="setView('cards', this)" title="Modo Cards">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"></rect><rect x="14" y="3" width="7" height="7"></rect><rect x="14" y="14" width="7" height="7"></rect><rect x="3" y="14" width="7" height="7"></rect></svg>
                    </button>
                </div>
            </div>
        </div>

        <!-- CONTENT VIEW -->
        <div id="content-container">
            <div class="table-wrap">
                <div class="empty-wrap">
                    <div class="loader-ring"></div>
                    <div>Buscando servidores na API oficial do Roblox...</div>
                </div>
            </div>
        </div>
    </main>

    <div class="toast-bar" id="toast"></div>

    <script>
        const PLACE_ID = "107778070777162";
        let servers = [];
        let activeFilter = '1';
        let currentView = 'table';
        let isFetching = false;

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.textContent = msg;
            t.classList.add('visible');
            setTimeout(() => t.classList.remove('visible'), 2600);
        }

        function launchRoblox(jobId) {
            showToast(`Conectando ao servidor ${jobId.substring(0, 8)}...`);
            const uri = `roblox://experiences/start?placeId=${PLACE_ID}&gameInstanceId=${jobId}`;
            window.location.href = uri;

            fetch('/api/join', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ jobId: jobId })
            }).catch(() => {});
        }

        function joinBestServer() {
            if (!servers || servers.length === 0) {
                showToast('Nenhum servidor disponível no momento.');
                return;
            }
            launchRoblox(servers[0].id);
        }

        function copyId(id, btn) {
            navigator.clipboard.writeText(id).then(() => {
                showToast('ID copiado para a área de transferência.');
            });
        }

        function setFilter(f, btn) {
            activeFilter = f;
            document.querySelectorAll('.filter-tabs .tab-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            renderContent();
        }

        function setView(view, btn) {
            currentView = view;
            document.querySelectorAll('.view-switcher .view-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            renderContent();
        }

        async function fetchServers(force = false) {
            if (isFetching) return;
            isFetching = true;

            const btn = document.getElementById('btn-refresh');
            const icon = btn.querySelector('.icon-refresh');
            if (force) icon.classList.add('icon-spin');

            try {
                const url = force ? `/api/servers?force=1&t=${Date.now()}` : `/api/servers?t=${Date.now()}`;
                const res = await fetch(url);
                const data = await res.json();

                if (Array.isArray(data)) {
                    servers = data;
                    renderContent();
                    updateStats();
                    if (force) showToast(`${servers.length} servidores atualizados.`);
                }
            } catch (e) {
                console.error(e);
            } finally {
                isFetching = false;
                if (force) {
                    setTimeout(() => icon.classList.remove('icon-spin'), 350);
                }
            }
        }

        function triggerManualRefresh() {
            fetchServers(true);
        }

        function updateStats() {
            document.getElementById('stat-total').textContent = servers.length;
            const oneCount = servers.filter(s => s.playing === 1).length;
            document.getElementById('stat-one-player').textContent = oneCount;

            if (servers.length > 0) {
                const minPing = Math.min(...servers.map(s => s.ping || 999));
                document.getElementById('stat-ping').textContent = (minPing === 999 ? '0' : minPing) + ' ms';
                document.getElementById('best-server-title').textContent = `Servidor #1 — ${servers[0].playing} Jogador Online (${servers[0].ping}ms)`;
            }

            const now = new Date();
            document.getElementById('stat-time').textContent = now.toTimeString().split(' ')[0];
        }

        function getFilteredServers() {
            const query = (document.getElementById('search-box').value || '').trim().toLowerCase();
            let list = servers;

            if (activeFilter === '1') {
                list = list.filter(s => s.playing === 1);
            } else if (activeFilter === 'low') {
                list = list.filter(s => s.playing <= 3);
            }

            if (query) {
                list = list.filter(s => s.id.toLowerCase().includes(query) || String(s.ping).includes(query));
            }

            return list;
        }

        function renderContent() {
            const container = document.getElementById('content-container');
            const list = getFilteredServers();

            if (list.length === 0) {
                container.innerHTML = `
                    <div class="table-wrap">
                        <div class="empty-wrap">
                            Nenhum servidor encontrado com o filtro atual.
                        </div>
                    </div>
                `;
                return;
            }

            if (currentView === 'table') {
                renderTableView(container, list);
            } else {
                renderCardsView(container, list);
            }
        }

        function renderTableView(container, list) {
            container.innerHTML = `
                <div class="table-wrap">
                    <table>
                        <thead>
                            <tr>
                                <th style="width: 50px;">#</th>
                                <th>Jogadores</th>
                                <th>Latência</th>
                                <th>FPS</th>
                                <th>Job ID</th>
                                <th style="text-align: right; width: 140px;">Ação</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${list.map((s, idx) => {
                                const rank = idx + 1;
                                let rankClass = '';
                                if (rank === 1) rankClass = 'rank-top-1';
                                else if (rank === 2) rankClass = 'rank-top-2';
                                else if (rank === 3) rankClass = 'rank-top-3';

                                const tagClass = s.playing === 1 ? 'tag-1' : 'tag-low';
                                const pct = Math.max(8, Math.min(100, Math.round((s.playing / s.maxPlayers) * 100)));
                                const barColor = s.playing === 1 ? 'var(--green)' : 'var(--amber)';

                                return `
                                    <tr>
                                        <td class="rank-cell ${rankClass}">#${rank}</td>
                                        <td>
                                            <div class="players-cell">
                                                <span class="status-tag ${tagClass}">${s.playing} / ${s.maxPlayers}</span>
                                                <div class="mini-bar">
                                                    <div class="mini-bar-fill" style="width: ${pct}%; background: ${barColor};"></div>
                                                </div>
                                            </div>
                                        </td>
                                        <td class="mono-val" style="color: ${s.ping < 60 ? 'var(--green)' : 'var(--text-secondary)'};">${s.ping} ms</td>
                                        <td class="mono-val">${s.fps}</td>
                                        <td>
                                            <div class="job-id-cell">
                                                <span>${s.id.substring(0, 16)}...</span>
                                                <button class="btn-copy" onclick="copyId('${s.id}', this)" title="Copiar ID">
                                                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                                </button>
                                            </div>
                                        </td>
                                        <td style="text-align: right;">
                                            <button class="btn-table-join" onclick="launchRoblox('${s.id}')">
                                                <span>Conectar</span>
                                                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>
                                            </button>
                                        </td>
                                    </tr>
                                `;
                            }).join('')}
                        </tbody>
                    </table>
                </div>
            `;
        }

        function renderCardsView(container, list) {
            container.innerHTML = `
                <div class="cards-grid">
                    ${list.map((s, idx) => {
                        const rank = idx + 1;
                        const tagClass = s.playing === 1 ? 'tag-1' : 'tag-low';
                        return `
                            <div class="grid-card">
                                <div class="card-row-top">
                                    <span class="rank-cell">#${rank}</span>
                                    <span class="status-tag ${tagClass}">${s.playing} / ${s.maxPlayers} Jogadores</span>
                                </div>
                                <div class="card-row-mid">
                                    <span>Ping: <strong style="color: var(--text-primary); font-family: 'JetBrains Mono';">${s.ping}ms</strong></span>
                                    <span>FPS: <strong style="color: var(--text-primary); font-family: 'JetBrains Mono';">${s.fps}</strong></span>
                                </div>
                                <div class="job-id-cell" style="width: 100%; justify-content: space-between;">
                                    <span>${s.id.substring(0, 20)}...</span>
                                    <button class="btn-copy" onclick="copyId('${s.id}', this)" title="Copiar ID">
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                    </button>
                                </div>
                                <button class="btn-primary" style="width: 100%; justify-content: center;" onclick="launchRoblox('${s.id}')">
                                    Conectar Instantâneo
                                </button>
                            </div>
                        `;
                    }).join('')}
                </div>
            `;
        }

        // Atalho de busca '/'
        window.addEventListener('keydown', (e) => {
            if (e.key === '/' && document.activeElement !== document.getElementById('search-box')) {
                e.preventDefault();
                document.getElementById('search-box').focus();
            }
        });

        // Inicialização
        fetchServers(true);
        setInterval(() => fetchServers(false), 8000);
    </script>
</body>
</html>
'''

def find_roblox_exe():
    appdata = os.environ.get("LOCALAPPDATA", "")
    versions_dir = os.path.join(appdata, "Roblox", "Versions")
    if os.path.exists(versions_dir):
        for root, dirs, files in os.walk(versions_dir):
            if "RobloxPlayerBeta.exe" in files:
                return os.path.join(root, "RobloxPlayerBeta.exe")
    return None

class ServerHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode("utf-8"))
        elif self.path.startswith("/api/servers"):
            force = ("force=1" in self.path) or ("force=true" in self.path)
            servers = fetch_roblox_servers(force=force)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(servers).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/join":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
            try:
                data = json.loads(raw)
                job_id = data.get("jobId", "")
                if job_id:
                    uri = f"roblox://experiences/start?placeId={PLACE_ID}&gameInstanceId={job_id}"
                    subprocess.run("taskkill /f /im RobloxPlayerBeta.exe", shell=True, capture_output=True)
                    time.sleep(0.3)
                    exe = find_roblox_exe()
                    if exe and os.path.isfile(exe):
                        subprocess.Popen([exe, uri])
                    else:
                        subprocess.Popen(f'start "" "{uri}"', shell=True)
            except Exception:
                pass
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            self.send_response(404)
            self.end_headers()

def run_server():
    server = HTTPServer(("127.0.0.1", PORT), ServerHandler)
    print(f"\n=======================================================")
    print(f" [OK] SERVER BROWSER - STEAL AN EGG INICIADO")
    print(f" Acesse no navegador: http://localhost:{PORT}")
    print(f"=======================================================\n")
    try:
        webbrowser.open(f"http://localhost:{PORT}")
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

if __name__ == "__main__":
    run_server()
