// Steal An Egg - Quick Server Hopper (MAIN World Script)
(function() {
    const PLACE_ID = "107778070777162";

    // Só executa nas páginas deste jogo
    if (!window.location.href.includes(PLACE_ID)) return;

    console.log("[Hopper] Ativado na página de Steal An Egg");

    function joinServer(jobId) {
        console.log("[Hopper] Disparando Roblox.GameLauncher para o JobId:", jobId);
        if (window.Roblox && window.Roblox.GameLauncher && typeof window.Roblox.GameLauncher.joinGameInstance === "function") {
            window.Roblox.GameLauncher.joinGameInstance(PLACE_ID, jobId);
        } else {
            console.warn("[Hopper] Roblox.GameLauncher não encontrado no contexto");
        }
    }

    // 1. Conexão automática vinda de parâmetro na URL (?jobId=...)
    const urlParams = new URLSearchParams(window.location.search);
    const targetJob = urlParams.get("jobId") || urlParams.get("serverJobId");
    if (targetJob) {
        setTimeout(() => {
            joinServer(targetJob);
        }, 1500);
    }

    // 2. Criação do Widget Flutuante (garantido de aparecer em qualquer idioma/tema)
    function createFloatingWidget() {
        if (document.getElementById("hopper-floating-widget")) return;

        const widget = document.createElement("div");
        widget.id = "hopper-floating-widget";
        widget.innerHTML = `
            <button id="hopper-btn-floating" style="
                display: flex;
                align-items: center;
                gap: 10px;
                background: linear-gradient(135deg, #10b981, #059669);
                color: #ffffff;
                border: 1px solid rgba(255, 255, 255, 0.2);
                padding: 12px 20px;
                border-radius: 999px;
                font-family: inherit;
                font-size: 14px;
                font-weight: 700;
                cursor: pointer;
                box-shadow: 0 8px 30px rgba(16, 185, 129, 0.45);
                transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            ">
                <span style="font-size: 16px;">⚡</span>
                <span id="hopper-btn-text">Entrar no Menor Servidor (1 Player)</span>
            </button>
        `;

        widget.style.cssText = `
            position: fixed;
            bottom: 24px;
            right: 24px;
            z-index: 999999;
        `;

        const btn = widget.querySelector("#hopper-btn-floating");
        const txt = widget.querySelector("#hopper-btn-text");

        btn.addEventListener("mouseenter", () => {
            btn.style.transform = "translateY(-2px) scale(1.03)";
            btn.style.filter = "brightness(1.12)";
        });
        btn.addEventListener("mouseleave", () => {
            btn.style.transform = "none";
            btn.style.filter = "none";
        });

        btn.addEventListener("click", async () => {
            txt.textContent = "Buscando servidor com 1 player...";
            btn.style.pointerEvents = "none";

            try {
                const res = await fetch(`https://games.roblox.com/v1/games/${PLACE_ID}/servers/Public?sortOrder=Asc&limit=100`);
                const data = await res.json();
                const servers = (data && data.data) ? data.data : [];

                const valid = servers.filter(s => s.id && s.playing < (s.maxPlayers || 20));
                valid.sort((a, b) => (a.playing - b.playing) || (a.ping - b.ping));

                if (valid.length > 0) {
                    const best = valid[0];
                    txt.textContent = `Conectando (${best.playing} player)...`;
                    joinServer(best.id);
                } else {
                    txt.textContent = "Nenhum servidor vazio encontrado";
                }
            } catch (err) {
                console.error(err);
                txt.textContent = "Erro ao buscar servidor";
            } finally {
                setTimeout(() => {
                    txt.textContent = "Entrar no Menor Servidor (1 Player)";
                    btn.style.pointerEvents = "auto";
                }, 4000);
            }
        });

        document.body.appendChild(widget);
    }

    // Inicia e reinjeta se o usuário navegar entre abas do Roblox (SPA)
    createFloatingWidget();
    setInterval(createFloatingWidget, 2000);
})();
