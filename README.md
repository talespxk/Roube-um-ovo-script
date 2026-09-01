# 🥚 Roube um Ovo - Fluent Stealth Hub

Um script completo, otimizado e furtivo para o jogo **Roube um Ovo** no Roblox.

## 🚀 Como Executar (Loadstring)

### 🥚 Script Principal (Auto-Steal Hub):
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/refs/heads/main/main.lua"))()
```

### ⚡ Hop Server (Troca Rápida de Servidores):
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/refs/heads/main/hop_server.lua"))()
```

---

## ✨ Funcionalidades

- **🚀 Roubo automático:** Localiza prompts observáveis `Steal / Egg`, voa até o alcance, aciona o prompt e retorna à posição registrada como base.
- **🎯 Radar verificável:** Lista somente prompts compatíveis com `Steal / Egg` e informa a fonte de valores ou raridades exibidos.
- **🥋 Bloqueio local de ragdoll:** Tenta restaurar estados, postura e atributos locais de queda. O servidor pode sobrescrever o efeito.
- **🥚 Recuperação de ovo:** Tenta reequipar uma ferramenta de ovo ou reacionar o prompt próximo após um impacto detectado.
- **🧬 Diagnóstico honesto:** Registra ações locais e mudanças observáveis. Não afirma interceptar chamadas remotas nem acessar dados internos do servidor.
- **🎨 Interface em português:** Visual moderno com atalho no `Control` esquerdo.

Recursos que dependem de autoridade do servidor são tentativas locais e podem variar conforme atualizações do jogo ou do executor.
