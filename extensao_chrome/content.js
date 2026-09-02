// Steal An Egg - Quick Server Hopper Content Script
(function() {
    const PLACE_ID = "107778070777162";

    function execInPage(code) {
        const script = document.createElement("script");
        script.textContent = code;
        (document.head || document.documentElement).appendChild(script);
        script.remove();
    }

    function joinServer(jobId) {
        console.log("[Hopper] Conectando ao servidor:", jobId);
        execInPage(`if (window.Roblox && window.Roblox.GameLauncher) { window.Roblox.GameLauncher.joinGameInstance(${PLACE_ID}, "${jobId}"); }`);
    }

    // 1. Checa se veio com parâmetro jobId na URL (vindo do Painel Web)
    const urlParams = new URLSearchParams(window.location.search);
    const targetJob = urlParams.get("jobId") || urlParams.get("serverJobId");
    if (targetJob) {
        setTimeout(() => {
            joinServer(targetJob);
        }, 1200);
    }

    // 2. Injeta botão nativo na página oficial do Roblox
    function injectButton() {
        if (document.getElementById("btn-hop-egg")) return;

        const playContainer = document.querySelector(".game-play-buttons") || document.querySelector(".play-button-container") || document.querySelector("#game-details-play-button-container");
        if (!playContainer) return;

        const btn = document.createElement("button");
        btn.id = "btn-hop-egg";
        btn.innerHTML = `<span>⚡ Menor Servidor (1 Player)</span>`;
        btn.style.cssText = `
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #10b981, #059669);
            color: #ffffff;
            font-family: inherit;
            font-size: 15px;
            font-weight: 700;
            padding: 12px 20px;
            border-radius: 8px;
            border: none;
            cursor: pointer;
            margin-top: 10px;
            width: 100%;
            box-shadow: 0 4px 14px rgba(16, 185, 129, 0.4);
            transition: all 0.2s ease;
        `;

        btn.addEventListener("mouseenter", () => {
            btn.style.filter = "brightness(1.1)";
            btn.style.transform = "translateY(-1px)";
        });
        btn.addEventListener("mouseleave", () => {
            btn.style.filter = "none";
            btn.style.transform = "none";
        });

        btn.addEventListener("click", async (e) => {
            e.preventDefault();
            btn.textContent = "Buscando servidor com 1 player...";
            btn.disabled = true;

            try {
                const res = await fetch(`https://games.roblox.com/v1/games/${PLACE_ID}/servers/Public?sortOrder=Asc&limit=100`);
                const data = await res.json();
                const servers = (data && data.data) ? data.data : [];
                
                const valid = servers.filter(s => s.id && s.playing < (s.maxPlayers || 20));
                valid.sort((a, b) => a.playing - b.playing);

                if (valid.length > 0) {
                    const best = valid[0];
                    btn.textContent = `Entrando no servidor (${best.playing} player)...`;
                    joinServer(best.id);
                } else {
                    btn.textContent = "Nenhum servidor vazio encontrado";
                }
            } catch (err) {
                console.error(err);
                btn.textContent = "Erro ao buscar servidor";
            } finally {
                setTimeout(() => {
                    btn.textContent = "⚡ Menor Servidor (1 Player)";
                    btn.disabled = false;
                }, 3500);
            }
        });

        playContainer.appendChild(btn);
    }

    // Observa o carregamento da página do Roblox
    const observer = new MutationObserver(() => {
        injectButton();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    injectButton();
})();
