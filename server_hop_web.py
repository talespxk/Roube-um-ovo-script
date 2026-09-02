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

# Cache para evitar rate-limits
cache_data = {"timestamp": 0, "servers": []}
CACHE_TTL = 3.0  # segundos

def fetch_roblox_servers():
    global cache_data
    now = time.time()
    if now - cache_data["timestamp"] < CACHE_TTL and cache_data["servers"]:
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
        with urllib.request.urlopen(req, timeout=8) as resp:
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
        return {"error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        if cache_data["servers"]:
            return cache_data["servers"]
        return {"error": str(e)}

HTML_PAGE = r'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Steal An Egg - Real-Time Server Hopper</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #090b11;
            --surface: #121522;
            --surface-hover: #191e30;
            --card: #161a2b;
            --card-border: #232840;
            --accent: #6366f1;
            --accent-hover: #4f46e5;
            --accent-glow: rgba(99, 102, 241, 0.25);
            --green: #10b981;
            --green-glow: rgba(16, 185, 129, 0.2);
            --yellow: #f59e0b;
            --red: #ef4444;
            --gold: #fbbf24;
            --silver: #cbd5e1;
            --bronze: #d97706;
            --text: #f8fafc;
            --text-muted: #94a3b8;
            --text-dim: #64748b;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Plus Jakarta Sans', -apple-system, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            background-image: 
                radial-gradient(ellipse 80% 50% at 50% -20%, rgba(99, 102, 241, 0.15), transparent),
                radial-gradient(ellipse 60% 40% at 100% 100%, rgba(16, 185, 129, 0.08), transparent);
            background-attachment: fixed;
        }

        .container {
            max-width: 1200px;
            width: 100%;
            margin: 0 auto;
            padding: 24px 20px;
            flex: 1;
        }

        /* HEADER */
        header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding-bottom: 24px;
            border-bottom: 1px solid var(--card-border);
            margin-bottom: 28px;
            flex-wrap: wrap;
            gap: 16px;
        }

        .brand {
            display: flex;
            align-items: center;
            gap: 14px;
        }

        .brand-icon {
            width: 44px;
            height: 44px;
            background: linear-gradient(135deg, var(--accent), #818cf8);
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 22px;
            box-shadow: 0 0 24px var(--accent-glow);
        }

        .brand-text h1 {
            font-size: 22px;
            font-weight: 800;
            letter-spacing: -0.5px;
            background: linear-gradient(90deg, #fff, #cbd5e1);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .brand-text p {
            font-size: 13px;
            color: var(--text-muted);
            margin-top: 2px;
        }

        .header-actions {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .status-pill {
            display: flex;
            align-items: center;
            gap: 8px;
            background: var(--surface);
            border: 1px solid var(--card-border);
            padding: 8px 14px;
            border-radius: 999px;
            font-size: 12px;
            font-weight: 600;
            color: var(--text-muted);
        }

        .dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--green);
            box-shadow: 0 0 10px var(--green);
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.8; }
            50% { transform: scale(1.2); opacity: 1; box-shadow: 0 0 14px var(--green); }
            100% { transform: scale(0.95); opacity: 0.8; }
        }

        /* HERO CARD */
        .hero {
            background: linear-gradient(135deg, rgba(22, 26, 43, 0.9), rgba(30, 36, 60, 0.8));
            border: 1px solid rgba(99, 102, 241, 0.35);
            border-radius: 20px;
            padding: 28px;
            margin-bottom: 28px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 24px;
            box-shadow: 0 12px 36px rgba(0, 0, 0, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.05);
            backdrop-filter: blur(12px);
            flex-wrap: wrap;
        }

        .hero-content h2 {
            font-size: 20px;
            font-weight: 700;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .hero-content p {
            color: var(--text-muted);
            font-size: 14px;
            margin-top: 6px;
            max-width: 580px;
            line-height: 1.5;
        }

        .btn-hero {
            background: linear-gradient(135deg, var(--green), #059669);
            color: white;
            font-weight: 700;
            font-size: 15px;
            padding: 14px 28px;
            border-radius: 12px;
            border: none;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 10px;
            box-shadow: 0 4px 20px var(--green-glow);
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            text-decoration: none;
        }

        .btn-hero:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 28px rgba(16, 185, 129, 0.35);
            filter: brightness(1.08);
        }

        .btn-hero:active {
            transform: translateY(0);
        }

        /* FILTERS & CONTROLS */
        .controls {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 14px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }

        .filter-group {
            display: flex;
            align-items: center;
            gap: 8px;
            background: var(--surface);
            border: 1px solid var(--card-border);
            padding: 4px;
            border-radius: 12px;
        }

        .filter-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            font-weight: 600;
            font-size: 13px;
            padding: 8px 14px;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.15s;
        }

        .filter-btn:hover {
            color: var(--text);
            background: rgba(255, 255, 255, 0.04);
        }

        .filter-btn.active {
            background: var(--card);
            color: var(--text);
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.25);
            border: 1px solid var(--card-border);
        }

        .stats-summary {
            display: flex;
            align-items: center;
            gap: 16px;
            font-size: 13px;
            color: var(--text-muted);
        }

        .stat-badge {
            color: var(--green);
            font-weight: 700;
        }

        /* SERVER GRID */
        .servers-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 14px;
        }

        .server-card {
            background: var(--card);
            border: 1px solid var(--card-border);
            border-radius: 14px;
            padding: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
        }

        .server-card:hover {
            border-color: rgba(99, 102, 241, 0.4);
            transform: translateY(-2px);
            background: var(--surface-hover);
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
        }

        .card-top {
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .rank-badge {
            font-size: 12px;
            font-weight: 800;
            padding: 4px 10px;
            border-radius: 6px;
            display: inline-flex;
            align-items: center;
            gap: 4px;
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-dim);
        }

        .rank-1 { background: rgba(251, 191, 36, 0.15); color: var(--gold); border: 1px solid rgba(251, 191, 36, 0.3); }
        .rank-2 { background: rgba(203, 213, 225, 0.15); color: var(--silver); border: 1px solid rgba(203, 213, 225, 0.3); }
        .rank-3 { background: rgba(217, 119, 6, 0.15); color: var(--bronze); border: 1px solid rgba(217, 119, 6, 0.3); }

        .players-pill {
            font-size: 13px;
            font-weight: 800;
            padding: 4px 10px;
            border-radius: 999px;
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .players-1 {
            background: rgba(16, 185, 129, 0.15);
            color: var(--green);
            border: 1px solid rgba(16, 185, 129, 0.3);
        }

        .players-low {
            background: rgba(245, 158, 11, 0.15);
            color: var(--yellow);
            border: 1px solid rgba(245, 158, 11, 0.3);
        }

        .card-meta {
            display: flex;
            align-items: center;
            gap: 14px;
            font-size: 12px;
            color: var(--text-muted);
        }

        .meta-item {
            display: flex;
            align-items: center;
            gap: 5px;
        }

        .meta-item span {
            font-weight: 600;
            color: var(--text);
        }

        .job-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: rgba(0, 0, 0, 0.25);
            padding: 6px 10px;
            border-radius: 8px;
            border: 1px solid rgba(255, 255, 255, 0.03);
            font-family: 'JetBrains Mono', monospace;
            font-size: 11px;
            color: var(--text-dim);
        }

        .btn-copy {
            background: transparent;
            border: none;
            color: var(--accent);
            cursor: pointer;
            font-size: 11px;
            font-weight: 600;
            padding: 2px 6px;
            border-radius: 4px;
            transition: all 0.15s;
        }

        .btn-copy:hover {
            background: var(--accent-glow);
            color: #fff;
        }

        .card-actions {
            margin-top: 4px;
        }

        .btn-join {
            width: 100%;
            background: linear-gradient(135deg, var(--accent), var(--accent-hover));
            color: white;
            font-weight: 700;
            font-size: 13px;
            padding: 10px 16px;
            border-radius: 9px;
            border: none;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            transition: all 0.15s cubic-bezier(0.4, 0, 0.2, 1);
            text-decoration: none;
        }

        .btn-join:hover {
            filter: brightness(1.12);
            box-shadow: 0 4px 16px var(--accent-glow);
        }

        .btn-join:active {
            transform: scale(0.98);
        }

        /* LOADING & EMPTY */
        .loading-state, .empty-state {
            grid-column: 1 / -1;
            text-align: center;
            padding: 60px 20px;
            color: var(--text-muted);
        }

        .spinner {
            width: 36px;
            height: 36px;
            border: 3px solid var(--card-border);
            border-top-color: var(--accent);
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            margin: 0 auto 16px;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* TOAST */
        .toast {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: var(--surface);
            border: 1px solid var(--accent);
            color: #fff;
            padding: 12px 20px;
            border-radius: 12px;
            font-size: 13px;
            font-weight: 600;
            box-shadow: 0 8px 30px rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            gap: 10px;
            transform: translateY(100px);
            opacity: 0;
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
            z-index: 1000;
        }

        .toast.show {
            transform: translateY(0);
            opacity: 1;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="brand">
                <div class="brand-icon">🥚</div>
                <div class="brand-text">
                    <h1>Steal An Egg — Server Hopper</h1>
                    <p>Monitoramento e conexão instantânea em servidores de 1 player</p>
                </div>
            </div>
            <div class="header-actions">
                <div class="status-pill">
                    <span class="dot"></span>
                    <span id="refresh-status">Atualizando a cada 8s</span>
                </div>
                <button class="filter-btn active" id="manual-refresh-btn" onclick="loadServers()">🔄 Atualizar</button>
            </div>
        </header>

        <section class="hero" id="hero-section">
            <div class="hero-content">
                <h2>⚡ Conexão Rápida: Servidor Mais Vazio</h2>
                <p>Clique no botão ao lado para iniciar o Roblox diretamente no servidor com a menor quantidade de jogadores disponível agora.</p>
            </div>
            <button class="btn-hero" id="best-server-btn" onclick="joinBestServer()">
                <span>🚀 Entrar no Menor (#1)</span>
            </button>
        </section>

        <div class="controls">
            <div class="filter-group">
                <button class="filter-btn active" onclick="setFilter('1', this)">Apenas 1 Player</button>
                <button class="filter-btn" onclick="setFilter('low', this)">≤ 3 Players</button>
                <button class="filter-btn" onclick="setFilter('all', this)">Todos</button>
            </div>
            <div class="stats-summary">
                <span>Servidores encontrados: <strong class="stat-badge" id="total-count">0</strong></span>
                <span>Servidores com 1 player: <strong class="stat-badge" id="one-player-count">0</strong></span>
            </div>
        </div>

        <div class="servers-grid" id="servers-grid">
            <div class="loading-state">
                <div class="spinner"></div>
                <p>Buscando servidores em tempo real na API oficial do Roblox...</p>
            </div>
        </div>
    </div>

    <div class="toast" id="toast"></div>

    <script>
        const PLACE_ID = "107778070777162";
        let allServers = [];
        let currentFilter = '1';
        let refreshInterval = null;

        function showToast(msg, icon = '✓') {
            const t = document.getElementById('toast');
            t.innerHTML = `<span>${icon}</span> <span>${msg}</span>`;
            t.classList.add('show');
            setTimeout(() => t.classList.remove('show'), 2800);
        }

        function launchRoblox(jobId) {
            showToast('Iniciando o Roblox no servidor ' + jobId.substring(0, 8) + '...', '🚀');
            // 1. Aciona protocolo nativo no navegador do usuário
            const uri = `roblox://experiences/start?placeId=${PLACE_ID}&gameInstanceId=${jobId}`;
            window.location.href = uri;

            // 2. Notifica o backend Python para acionar via OS se desejado
            fetch('/api/join', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ jobId: jobId })
            }).catch(() => {});
        }

        function joinBestServer() {
            if (!allServers || allServers.length === 0) {
                showToast('Nenhum servidor carregado ainda. Aguarde...', '⚠️');
                return;
            }
            launchRoblox(allServers[0].id);
        }

        function copyJobId(id) {
            navigator.clipboard.writeText(id).then(() => {
                showToast('Job ID copiado com sucesso!', '📋');
            }).catch(() => {
                showToast('Erro ao copiar', '❌');
            });
        }

        function setFilter(f, btn) {
            currentFilter = f;
            document.querySelectorAll('.filter-group .filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            renderServers();
        }

        async function loadServers() {
            try {
                const res = await fetch('/api/servers');
                const data = await res.json();
                if (data.error) {
                    showToast('Erro na API: ' + data.error, '❌');
                    return;
                }
                allServers = Array.isArray(data) ? data : [];
                renderServers();
            } catch (err) {
                console.error(err);
            }
        }

        function renderServers() {
            const grid = document.getElementById('servers-grid');
            document.getElementById('total-count').textContent = allServers.length;
            
            const oneCount = allServers.filter(s => s.playing === 1).length;
            document.getElementById('one-player-count').textContent = oneCount;

            let filtered = allServers;
            if (currentFilter === '1') {
                filtered = allServers.filter(s => s.playing === 1);
            } else if (currentFilter === 'low') {
                filtered = allServers.filter(s => s.playing <= 3);
            }

            if (filtered.length === 0) {
                grid.innerHTML = `
                    <div class="empty-state">
                        <p>Nenhum servidor corresponde ao filtro selecionado no momento.</p>
                    </div>
                `;
                return;
            }

            grid.innerHTML = filtered.map((s, index) => {
                const rank = index + 1;
                let rankClass = '';
                if (rank === 1) rankClass = 'rank-1';
                else if (rank === 2) rankClass = 'rank-2';
                else if (rank === 3) rankClass = 'rank-3';

                const playerClass = s.playing === 1 ? 'players-1' : (s.playing <= 3 ? 'players-low' : '');

                return `
                    <div class="server-card">
                        <div class="card-top">
                            <span class="rank-badge ${rankClass}">#${rank} RANK</span>
                            <span class="players-pill ${playerClass}">👤 ${s.playing}/${s.maxPlayers} Jogadores</span>
                        </div>
                        <div class="card-meta">
                            <div class="meta-item">FPS: <span>${s.fps}</span></div>
                            <div class="meta-item">Ping: <span>${s.ping}ms</span></div>
                        </div>
                        <div class="job-row">
                            <span>${s.id.substring(0, 16)}...</span>
                            <button class="btn-copy" onclick="copyJobId('${s.id}')">Copiar ID</button>
                        </div>
                        <div class="card-actions">
                            <button class="btn-join" onclick="launchRoblox('${s.id}')">
                                ▶ Conectar Instantâneo
                            </button>
                        </div>
                    </div>
                `;
            }).join('');
        }

        // Início
        loadServers();
        refreshInterval = setInterval(loadServers, 8000);
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
        elif self.path == "/api/servers":
            servers = fetch_roblox_servers()
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
    print(f" Acesse no navegador: http://localhost:{PORT}")
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
