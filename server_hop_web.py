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
CACHE_TTL = 4.0  # segundos de cache normal

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
    <title>Steal An Egg — Pro Server Hopper</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #07090e;
            --surface: #0f1422;
            --surface-glass: rgba(15, 20, 34, 0.75);
            --card: #141b2d;
            --card-glass: rgba(20, 27, 45, 0.7);
            --card-hover: #1a233a;
            --border: #222c46;
            --border-glow: rgba(99, 102, 241, 0.35);
            
            --accent: #6366f1;
            --accent-light: #818cf8;
            --accent-glow: rgba(99, 102, 241, 0.35);
            
            --emerald: #10b981;
            --emerald-glow: rgba(16, 185, 129, 0.3);
            
            --amber: #f59e0b;
            --rose: #f43f5e;
            
            --gold: #fbbf24;
            --silver: #cbd5e1;
            --bronze: #d97706;
            
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --text-dim: #64748b;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            user-select: none;
        }

        body {
            font-family: 'Plus Jakarta Sans', sans-serif;
            background-color: var(--bg);
            color: var(--text-main);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            overflow-x: hidden;
            background-image: 
                radial-gradient(circle at 50% 0%, rgba(99, 102, 241, 0.18), transparent 45%),
                radial-gradient(circle at 90% 90%, rgba(16, 185, 129, 0.12), transparent 40%),
                radial-gradient(circle at 10% 80%, rgba(244, 63, 94, 0.08), transparent 40%);
            background-attachment: fixed;
        }

        /* AMBIENT MESH */
        .ambient-glow {
            position: fixed;
            top: 0;
            left: 50%;
            transform: translateX(-50%);
            width: 100vw;
            height: 100vh;
            background-image: 
                linear-gradient(to right, rgba(255,255,255,0.015) 1px, transparent 1px),
                linear-gradient(to bottom, rgba(255,255,255,0.015) 1px, transparent 1px);
            background-size: 40px 40px;
            pointer-events: none;
            z-index: 0;
        }

        .container {
            max-width: 1280px;
            width: 100%;
            margin: 0 auto;
            padding: 32px 24px;
            position: relative;
            z-index: 1;
            flex: 1;
        }

        /* HEADER */
        header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding-bottom: 24px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 28px;
            flex-wrap: wrap;
            gap: 20px;
        }

        .brand {
            display: flex;
            align-items: center;
            gap: 16px;
        }

        .brand-logo {
            width: 52px;
            height: 52px;
            background: linear-gradient(135deg, #4338ca, #6366f1);
            border-radius: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 26px;
            box-shadow: 0 0 30px var(--accent-glow);
            border: 1px solid rgba(255, 255, 255, 0.15);
        }

        .brand-meta h1 {
            font-family: 'Space Grotesk', sans-serif;
            font-size: 24px;
            font-weight: 700;
            letter-spacing: -0.5px;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .brand-badge {
            font-size: 11px;
            font-weight: 800;
            background: rgba(99, 102, 241, 0.2);
            color: var(--accent-light);
            border: 1px solid rgba(99, 102, 241, 0.4);
            padding: 2px 8px;
            border-radius: 6px;
            letter-spacing: 0.5px;
        }

        .brand-meta p {
            font-size: 13px;
            color: var(--text-muted);
            margin-top: 4px;
        }

        .header-controls {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .live-status {
            display: flex;
            align-items: center;
            gap: 10px;
            background: var(--surface-glass);
            border: 1px solid var(--border);
            padding: 10px 16px;
            border-radius: 999px;
            font-size: 13px;
            font-weight: 600;
            color: var(--text-muted);
            backdrop-filter: blur(10px);
        }

        .pulse-dot {
            width: 9px;
            height: 9px;
            background: var(--emerald);
            border-radius: 50%;
            box-shadow: 0 0 12px var(--emerald);
            animation: pulse-ring 2s infinite ease-out;
        }

        @keyframes pulse-ring {
            0% { transform: scale(0.9); opacity: 0.8; box-shadow: 0 0 6px var(--emerald); }
            50% { transform: scale(1.3); opacity: 1; box-shadow: 0 0 16px var(--emerald); }
            100% { transform: scale(0.9); opacity: 0.8; box-shadow: 0 0 6px var(--emerald); }
        }

        /* REFRESH BUTTON */
        .btn-refresh {
            background: linear-gradient(135deg, var(--card), var(--surface));
            border: 1px solid var(--border);
            color: var(--text-main);
            font-size: 13px;
            font-weight: 700;
            padding: 10px 18px;
            border-radius: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 8px;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
        }

        .btn-refresh:hover {
            border-color: var(--accent);
            background: var(--surface-hover);
            transform: translateY(-2px);
            box-shadow: 0 6px 20px var(--accent-glow);
        }

        .btn-refresh:active {
            transform: translateY(0);
        }

        .btn-refresh .icon-sync {
            display: inline-block;
            transition: transform 0.4s ease;
        }

        .btn-refresh.spinning .icon-sync {
            animation: spin 0.8s linear infinite;
        }

        @keyframes spin {
            100% { transform: rotate(360deg); }
        }

        /* METRICS ROW */
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 28px;
        }

        .metric-card {
            background: var(--card-glass);
            border: 1px solid var(--border);
            border-radius: 18px;
            padding: 18px 22px;
            backdrop-filter: blur(12px);
            display: flex;
            align-items: center;
            gap: 18px;
            position: relative;
            overflow: hidden;
            transition: all 0.25s ease;
        }

        .metric-card:hover {
            border-color: rgba(255, 255, 255, 0.15);
            transform: translateY(-2px);
        }

        .metric-icon {
            width: 48px;
            height: 48px;
            border-radius: 14px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 22px;
        }

        .metric-icon.emerald { background: rgba(16, 185, 129, 0.15); color: var(--emerald); border: 1px solid rgba(16, 185, 129, 0.25); }
        .metric-icon.indigo  { background: rgba(99, 102, 241, 0.15); color: var(--accent-light); border: 1px solid rgba(99, 102, 241, 0.25); }
        .metric-icon.amber   { background: rgba(245, 158, 11, 0.15); color: var(--amber); border: 1px solid rgba(245, 158, 11, 0.25); }
        .metric-icon.rose    { background: rgba(244, 63, 94, 0.15); color: var(--rose); border: 1px solid rgba(244, 63, 94, 0.25); }

        .metric-info h3 {
            font-size: 12px;
            font-weight: 700;
            color: var(--text-dim);
            text-transform: uppercase;
            letter-spacing: 0.8px;
        }

        .metric-info .val {
            font-family: 'Space Grotesk', sans-serif;
            font-size: 24px;
            font-weight: 800;
            color: var(--text-main);
            margin-top: 2px;
        }

        /* HERO CARD */
        .hero-banner {
            background: linear-gradient(135deg, rgba(20, 27, 48, 0.95), rgba(30, 40, 70, 0.85));
            border: 1px solid rgba(99, 102, 241, 0.4);
            border-radius: 22px;
            padding: 30px 34px;
            margin-bottom: 28px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 24px;
            box-shadow: 0 16px 40px rgba(0, 0, 0, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.08);
            position: relative;
            overflow: hidden;
            flex-wrap: wrap;
        }

        .hero-banner::before {
            content: '';
            position: absolute;
            top: -50%;
            left: -30%;
            width: 160%;
            height: 200%;
            background: radial-gradient(circle, rgba(99, 102, 241, 0.12) 0%, transparent 60%);
            pointer-events: none;
        }

        .hero-text {
            max-width: 650px;
            position: relative;
            z-index: 1;
        }

        .hero-text h2 {
            font-family: 'Space Grotesk', sans-serif;
            font-size: 22px;
            font-weight: 700;
            color: #fff;
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .hero-text p {
            color: var(--text-muted);
            font-size: 14px;
            line-height: 1.6;
            margin-top: 8px;
        }

        .hero-action {
            position: relative;
            z-index: 1;
        }

        .btn-hop-hero {
            background: linear-gradient(135deg, #10b981, #059669);
            color: #ffffff;
            font-family: 'Space Grotesk', sans-serif;
            font-weight: 700;
            font-size: 16px;
            padding: 16px 32px;
            border-radius: 14px;
            border: none;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 12px;
            box-shadow: 0 8px 28px var(--emerald-glow);
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .btn-hop-hero:hover {
            transform: translateY(-3px) scale(1.02);
            box-shadow: 0 12px 36px rgba(16, 185, 129, 0.45);
            filter: brightness(1.1);
        }

        .btn-hop-hero:active {
            transform: translateY(0) scale(0.99);
        }

        /* TOOLBAR */
        .toolbar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            margin-bottom: 22px;
            flex-wrap: wrap;
        }

        .filter-pills {
            display: flex;
            align-items: center;
            background: var(--surface);
            border: 1px solid var(--border);
            padding: 4px;
            border-radius: 14px;
            gap: 4px;
        }

        .pill-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            font-size: 13px;
            font-weight: 600;
            padding: 8px 16px;
            border-radius: 10px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .pill-btn:hover {
            color: #fff;
            background: rgba(255, 255, 255, 0.04);
        }

        .pill-btn.active {
            background: var(--card);
            color: #fff;
            border: 1px solid var(--border);
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        }

        .search-box {
            display: flex;
            align-items: center;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 8px 14px;
            gap: 10px;
            min-width: 280px;
            transition: border-color 0.2s;
        }

        .search-box:focus-within {
            border-color: var(--accent);
            box-shadow: 0 0 16px var(--accent-glow);
        }

        .search-box input {
            background: transparent;
            border: none;
            outline: none;
            color: var(--text-main);
            font-size: 13px;
            width: 100%;
        }

        .search-box input::placeholder {
            color: var(--text-dim);
        }

        /* SERVER CARDS */
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
            gap: 16px;
        }

        .server-card {
            background: var(--card-glass);
            border: 1px solid var(--border);
            border-radius: 18px;
            padding: 20px;
            display: flex;
            flex-direction: column;
            gap: 14px;
            position: relative;
            backdrop-filter: blur(12px);
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .server-card:hover {
            border-color: var(--border-glow);
            transform: translateY(-3px);
            background: var(--card-hover);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.4);
        }

        .card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .rank-tag {
            font-family: 'Space Grotesk', sans-serif;
            font-size: 12px;
            font-weight: 800;
            padding: 5px 12px;
            border-radius: 8px;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-dim);
        }

        .rank-gold   { background: rgba(251, 191, 36, 0.18); color: var(--gold); border: 1px solid rgba(251, 191, 36, 0.35); }
        .rank-silver { background: rgba(203, 213, 225, 0.18); color: var(--silver); border: 1px solid rgba(203, 213, 225, 0.35); }
        .rank-bronze { background: rgba(217, 119, 6, 0.18); color: var(--bronze); border: 1px solid rgba(217, 119, 6, 0.35); }

        .player-badge {
            font-size: 13px;
            font-weight: 800;
            padding: 5px 12px;
            border-radius: 999px;
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .p-emerald { background: rgba(16, 185, 129, 0.18); color: var(--emerald); border: 1px solid rgba(16, 185, 129, 0.35); }
        .p-amber   { background: rgba(245, 158, 11, 0.18); color: var(--amber); border: 1px solid rgba(245, 158, 11, 0.35); }

        /* PROGRESS BAR */
        .bar-wrap {
            width: 100%;
            height: 6px;
            background: rgba(255, 255, 255, 0.06);
            border-radius: 999px;
            overflow: hidden;
        }

        .bar-fill {
            height: 100%;
            border-radius: 999px;
            transition: width 0.4s ease;
        }

        .card-stats {
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 12px;
            color: var(--text-muted);
            background: rgba(0, 0, 0, 0.2);
            padding: 8px 12px;
            border-radius: 10px;
        }

        .stat-item {
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .stat-item strong {
            color: var(--text-main);
            font-weight: 700;
        }

        .id-box {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: rgba(0, 0, 0, 0.35);
            border: 1px solid rgba(255, 255, 255, 0.04);
            padding: 8px 12px;
            border-radius: 10px;
            font-family: 'JetBrains Mono', monospace;
            font-size: 11px;
            color: var(--text-dim);
        }

        .btn-copy-id {
            background: transparent;
            border: none;
            color: var(--accent-light);
            font-weight: 700;
            font-size: 11px;
            cursor: pointer;
            padding: 2px 6px;
            border-radius: 4px;
            transition: all 0.15s;
        }

        .btn-copy-id:hover {
            background: var(--accent-glow);
            color: #fff;
        }

        .btn-connect {
            width: 100%;
            background: linear-gradient(135deg, var(--accent), var(--accent-hover, #4f46e5));
            color: white;
            font-family: 'Space Grotesk', sans-serif;
            font-weight: 700;
            font-size: 14px;
            padding: 12px;
            border-radius: 12px;
            border: none;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: 0 4px 16px var(--accent-glow);
        }

        .btn-connect:hover {
            filter: brightness(1.15);
            transform: translateY(-1px);
            box-shadow: 0 6px 22px rgba(99, 102, 241, 0.5);
        }

        .btn-connect:active {
            transform: translateY(0);
        }

        /* LOADING & EMPTY */
        .state-msg {
            grid-column: 1 / -1;
            text-align: center;
            padding: 80px 20px;
            color: var(--text-muted);
        }

        .spinner {
            width: 42px;
            height: 42px;
            border: 3px solid var(--border);
            border-top-color: var(--accent);
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            margin: 0 auto 16px;
        }

        /* TOAST */
        .toast-popup {
            position: fixed;
            bottom: 28px;
            right: 28px;
            background: rgba(15, 20, 34, 0.92);
            border: 1px solid var(--accent);
            color: #fff;
            padding: 14px 22px;
            border-radius: 14px;
            font-size: 14px;
            font-weight: 600;
            box-shadow: 0 12px 36px rgba(0, 0, 0, 0.6);
            display: flex;
            align-items: center;
            gap: 12px;
            transform: translateY(120px);
            opacity: 0;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            backdrop-filter: blur(14px);
            z-index: 9999;
        }

        .toast-popup.visible {
            transform: translateY(0);
            opacity: 1;
        }
    </style>
</head>
<body>
    <div class="ambient-glow"></div>

    <div class="container">
        <header>
            <div class="brand">
                <div class="brand-logo">🥚</div>
                <div class="brand-meta">
                    <h1>
                        Steal An Egg 
                        <span class="brand-badge">PRO HOPPER</span>
                    </h1>
                    <p>Busca ao vivo de servidores com 1 jogador e conexão direta via protocolo oficial</p>
                </div>
            </div>
            <div class="header-controls">
                <div class="live-status">
                    <span class="pulse-dot"></span>
                    <span id="status-label">Online (Tempo Real)</span>
                </div>
                <button class="btn-refresh" id="refresh-btn" onclick="manualRefresh()">
                    <span class="icon-sync">🔄</span>
                    <span id="refresh-text">Atualizar</span>
                </button>
            </div>
        </header>

        <!-- CARDS DE METRICAS -->
        <section class="metrics-grid">
            <div class="metric-card">
                <div class="metric-icon emerald">🎯</div>
                <div class="metric-info">
                    <h3>Servidores 1-Player</h3>
                    <div class="val" id="m-one">0</div>
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-icon indigo">🌐</div>
                <div class="metric-info">
                    <h3>Total Monitorado</h3>
                    <div class="val" id="m-total">0</div>
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-icon amber">⚡</div>
                <div class="metric-info">
                    <h3>Menor Latência</h3>
                    <div class="val" id="m-ping">0 ms</div>
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-icon rose">⏱️</div>
                <div class="metric-info">
                    <h3>Última Leitura</h3>
                    <div class="val" id="m-time">--:--:--</div>
                </div>
            </div>
        </section>

        <!-- BANNER DE CONEXAO RAPIDA -->
        <section class="hero-banner">
            <div class="hero-text">
                <h2>⚡ Conexão Direta: Servidor Mais Vazio (#1)</h2>
                <p>Abra o Roblox de forma legítima e instantânea no servidor com a menor quantidade de pessoas online agora, sem riscos de banimento ou kicks de anti-cheat.</p>
            </div>
            <div class="hero-action">
                <button class="btn-hop-hero" onclick="joinBestServer()">
                    <span>🚀 Entrar no Menor Servidor (#1)</span>
                </button>
            </div>
        </section>

        <!-- BARRA DE CONTROLES & FILTROS -->
        <div class="toolbar">
            <div class="filter-pills">
                <button class="pill-btn active" onclick="setFilter('1', this)">Apenas 1 Player</button>
                <button class="pill-btn" onclick="setFilter('low', this)">≤ 3 Players</button>
                <button class="pill-btn" onclick="setFilter('all', this)">Todos os Servidores</button>
            </div>
            <div class="search-box">
                <span>🔍</span>
                <input type="text" id="search-input" placeholder="Buscar por Job ID ou Ping..." oninput="renderServers()">
            </div>
        </div>

        <!-- GRID DE SERVIDORES -->
        <div class="grid" id="servers-grid">
            <div class="state-msg">
                <div class="spinner"></div>
                <p>Consultando servidores ativos na API oficial do Roblox...</p>
            </div>
        </div>
    </div>

    <div class="toast-popup" id="toast"></div>

    <script>
        const PLACE_ID = "107778070777162";
        let allServers = [];
        let currentFilter = '1';
        let isFetching = false;

        // Feedback sonoro sutil via Web Audio API (opcional)
        function playBeep() {
            try {
                const ctx = new (window.AudioContext || window.webkitAudioContext)();
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(640, ctx.currentTime);
                gain.gain.setValueAtTime(0.04, ctx.currentTime);
                gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.08);
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start();
                osc.stop(ctx.currentTime + 0.08);
            } catch (e) {}
        }

        function showToast(msg, icon = '✓') {
            const t = document.getElementById('toast');
            t.innerHTML = `<span style="font-size: 18px;">${icon}</span> <span>${msg}</span>`;
            t.classList.add('visible');
            setTimeout(() => t.classList.remove('visible'), 3000);
        }

        function launchRoblox(jobId) {
            playBeep();
            showToast('Iniciando o Roblox no servidor ' + jobId.substring(0, 8) + '...', '🚀');
            
            // 1. Aciona protocolo nativo no navegador do usuário
            const uri = `roblox://experiences/start?placeId=${PLACE_ID}&gameInstanceId=${jobId}`;
            window.location.href = uri;

            // 2. Notifica o backend Python para acionar via OS também
            fetch('/api/join', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ jobId: jobId })
            }).catch(() => {});
        }

        function joinBestServer() {
            if (!allServers || allServers.length === 0) {
                showToast('Carregando servidores... tente em 1 segundo.', '⚠️');
                return;
            }
            launchRoblox(allServers[0].id);
        }

        function copyJobId(id) {
            playBeep();
            navigator.clipboard.writeText(id).then(() => {
                showToast('Job ID copiado com sucesso!', '📋');
            }).catch(() => {
                showToast('Erro ao copiar', '❌');
            });
        }

        function setFilter(filter, btn) {
            playBeep();
            currentFilter = filter;
            document.querySelectorAll('.filter-pills .pill-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            renderServers();
        }

        async function fetchServers(force = false) {
            if (isFetching) return;
            isFetching = true;

            const refBtn = document.getElementById('refresh-btn');
            const refTxt = document.getElementById('refresh-text');
            if (force) {
                refBtn.classList.add('spinning');
                refTxt.textContent = 'Buscando...';
            }

            try {
                const url = force ? `/api/servers?force=1&t=${Date.now()}` : `/api/servers?t=${Date.now()}`;
                const res = await fetch(url);
                const data = await res.json();
                
                if (data.error) {
                    showToast('Erro ao buscar: ' + data.error, '❌');
                } else if (Array.isArray(data)) {
                    allServers = data;
                    renderServers();
                    updateMetrics();
                    if (force) {
                        showToast(`${allServers.length} servidores atualizados em tempo real!`, '⚡');
                    }
                }
            } catch (err) {
                console.error(err);
            } finally {
                isFetching = false;
                if (force) {
                    setTimeout(() => {
                        refBtn.classList.remove('spinning');
                        refTxt.textContent = 'Atualizar';
                    }, 400);
                }
            }
        }

        function manualRefresh() {
            playBeep();
            fetchServers(true);
        }

        function updateMetrics() {
            document.getElementById('m-total').textContent = allServers.length;
            const oneCount = allServers.filter(s => s.playing === 1).length;
            document.getElementById('m-one').textContent = oneCount;

            if (allServers.length > 0) {
                const lowestPing = Math.min(...allServers.map(s => s.ping || 999));
                document.getElementById('m-ping').textContent = (lowestPing === 999 ? '0' : lowestPing) + ' ms';
            }

            const now = new Date();
            document.getElementById('m-time').textContent = now.toTimeString().split(' ')[0];
        }

        function renderServers() {
            const grid = document.getElementById('servers-grid');
            const searchVal = (document.getElementById('search-input').value || '').trim().toLowerCase();

            let filtered = allServers;
            if (currentFilter === '1') {
                filtered = allServers.filter(s => s.playing === 1);
            } else if (currentFilter === 'low') {
                filtered = allServers.filter(s => s.playing <= 3);
            }

            if (searchVal) {
                filtered = filtered.filter(s => s.id.toLowerCase().includes(searchVal) || String(s.ping).includes(searchVal));
            }

            if (filtered.length === 0) {
                grid.innerHTML = `
                    <div class="state-msg">
                        <p>Nenhum servidor encontrado para o filtro atual.</p>
                    </div>
                `;
                return;
            }

            grid.innerHTML = filtered.map((s, index) => {
                const rank = index + 1;
                let rankClass = '';
                let rankIcon = '';
                if (rank === 1) { rankClass = 'rank-gold'; rankIcon = '👑 '; }
                else if (rank === 2) { rankClass = 'rank-silver'; rankIcon = '🥈 '; }
                else if (rank === 3) { rankClass = 'rank-bronze'; rankIcon = '🥉 '; }

                const pClass = s.playing === 1 ? 'p-emerald' : 'p-amber';
                const fillPercent = Math.max(10, Math.min(100, Math.round((s.playing / s.maxPlayers) * 100)));
                const barColor = s.playing === 1 ? 'var(--emerald)' : (s.playing <= 3 ? 'var(--amber)' : 'var(--rose)');

                const pingColor = s.ping < 50 ? 'var(--emerald)' : (s.ping < 120 ? 'var(--amber)' : 'var(--rose)');

                return `
                    <div class="server-card">
                        <div class="card-header">
                            <span class="rank-tag ${rankClass}">${rankIcon}#${rank} RANK</span>
                            <span class="player-badge ${pClass}">👤 ${s.playing}/${s.maxPlayers} Jogadores</span>
                        </div>

                        <div class="bar-wrap">
                            <div class="bar-fill" style="width: ${fillPercent}%; background: ${barColor};"></div>
                        </div>

                        <div class="card-stats">
                            <div class="stat-item">
                                <span>Latência:</span>
                                <strong style="color: ${pingColor};">${s.ping}ms</strong>
                            </div>
                            <div class="stat-item">
                                <span>FPS:</span>
                                <strong style="color: var(--emerald);">${s.fps}</strong>
                            </div>
                        </div>

                        <div class="id-box">
                            <span>${s.id.substring(0, 18)}...</span>
                            <button class="btn-copy-id" onclick="copyJobId('${s.id}')">Copiar ID</button>
                        </div>

                        <button class="btn-connect" onclick="launchRoblox('${s.id}')">
                            ▶ Conectar Instantâneo
                        </button>
                    </div>
                `;
            }).join('');
        }

        // Auto-refresh a cada 8 segundos
        fetchServers(true);
        setInterval(() => fetchServers(false), 8000);
    </script>
</body>
</html>
'''

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
                    cmd = f'start "" "roblox://experiences/start?placeId={PLACE_ID}&gameInstanceId={job_id}"'
                    subprocess.Popen(cmd, shell=True)
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
    print(f" [OK] STEAL AN EGG - PAINEL HOPPER EM TEMPO REAL INICIADO")
    print(f" Acesse no seu navegador: http://localhost:{PORT}")
    print(f"=======================================================\n")
    try:
        webbrowser.open(f"http://localhost:{PORT}")
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Encerrando servidor...")
        server.server_close()

if __name__ == "__main__":
    run_server()
