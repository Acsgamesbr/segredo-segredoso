-- Tema visual compartilhado por todos os menus (principal, biblioteca,
-- pausa, editor de HUD e botão de pausa da gameplay).
--
-- Só usa primitivas do love.graphics (sem imagens/fontes externas), então
-- funciona igual no Windows e no Android.

local tema = {}

-- No LÖVE, "utf8" não é global: precisa importar o módulo bundled dele
-- (diferente do utf8 embutido no Lua 5.3/5.4 puro). Sem isso,
-- tema.ajustarTexto quebrava com "attempt to index global 'utf8'" toda vez
-- que um texto precisava ser cortado com "...".
local utf8 = require("utf8")

--------------------------------------------------
-- ÍCONE "ESTRELA" COM ANTI-ALIASING
--
-- love.graphics.polygon("fill", ...) não é suavizado (o jogo roda com
-- msaa = 0 na janela inteira, por desempenho), então o contorno em
-- ziguezague da estrela fica bem visível no tamanho pequeno da lista de
-- beatmaps. Em vez de ligar MSAA pra tela toda (custo em todo frame, só
-- por causa de um ícone), desenhamos a estrela uma vez, ampliada (4x) e
-- com MSAA num canvas pequeno e isolado, e reusamos essa textura daí em
-- diante, reduzida com filtro linear — resultado suave por um custo que
-- só existe na primeira vez que aquele tamanho aparece.
--------------------------------------------------

local cacheEstrela = {}
local ESCALA_ESTRELA = 4

local function obterEstrela(tamanho)
    tamanho = math.max(8, math.floor(tamanho + 0.5))

    local entrada = cacheEstrela[tamanho]
    if entrada then return entrada end

    local lado = tamanho * ESCALA_ESTRELA

    local ok, canvas = pcall(love.graphics.newCanvas, lado, lado, {msaa = 4})

    if not ok then
        -- GPU/backend sem suporte a esse nível de MSAA em canvas: ainda
        -- assim o supersampling (desenhar maior e reduzir) já suaviza.
        ok, canvas = pcall(love.graphics.newCanvas, lado, lado)
    end

    if not ok or not canvas then return nil end

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)

    local cx, cy = lado / 2, lado / 2
    local raio = lado / 2
    local pts = {}

    for i = 0, 9 do
        local r = (i % 2 == 0) and raio * 0.5 or raio * 0.22
        local a = -math.pi / 2 + i * math.pi / 5
        pts[#pts + 1] = cx + r * math.cos(a)
        pts[#pts + 1] = cy + r * math.sin(a)
    end

    love.graphics.polygon("fill", pts)
    love.graphics.pop()

    canvas:setFilter("linear", "linear")

    entrada = {canvas = canvas, lado = lado}
    cacheEstrela[tamanho] = entrada
    return entrada
end

--------------------------------------------------
-- PALETA
--------------------------------------------------

tema.cores = {
    fundoTopo   = {0.045, 0.055, 0.125},
    fundoBase   = {0.105, 0.065, 0.190},
    painel      = {0.085, 0.095, 0.175},
    painelClaro = {0.140, 0.150, 0.265},
    texto       = {0.94, 0.95, 1.00},
    mudo        = {0.56, 0.59, 0.76},
    acento      = {0.49, 0.36, 1.00},
    acento2     = {0.24, 0.86, 1.00},
    perigo      = {1.00, 0.36, 0.48},
    ok          = {0.29, 0.89, 0.63},
    aviso       = {1.00, 0.78, 0.30},
    branco      = {1, 1, 1},
    preto       = {0, 0, 0},
}

function tema.cor(nome, alpha)
    local c = tema.cores[nome] or tema.cores.branco
    love.graphics.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

--------------------------------------------------
-- ESCALA DA INTERFACE
--------------------------------------------------

local uiEscalaPct = 100
local reduzirMovimento = false

function tema.configurar(config)
    if not config then return end
    uiEscalaPct = tonumber(config.get("uiEscala")) or 100
    reduzirMovimento = config.get("reduzirMovimento") == true
end

function tema.reduzirMovimento()
    return reduzirMovimento
end

-- Fator de escala: acompanha a altura da janela (telas pequenas do
-- celular ficam proporcionais) e a opção "tamanho da interface".
function tema.escala()
    local h = love.graphics.getHeight()
    local base = math.max(0.55, math.min(1.5, h / 720))
    return base * (uiEscalaPct / 100)
end

--------------------------------------------------
-- FONTES (cache por tamanho)
--------------------------------------------------

local fontes = {}

function tema.fonte(tamanho)
    tamanho = math.max(8, math.floor((tonumber(tamanho) or 14) + 0.5))

    local f = fontes[tamanho]

    if not f then
        f = love.graphics.newFont(tamanho)
        fontes[tamanho] = f
    end

    return f
end

-- Fonte já escalada pela interface.
function tema.fonteUI(tamanho)
    return tema.fonte(tamanho * tema.escala())
end

function tema.limparFontes()
    fontes = {}
end

-- Corta o texto com "..." para caber em uma largura.
--
-- Remove um caractere UTF-8 inteiro por vez (não um byte): acentos como
-- "ç" e "ã" ocupam 2 bytes, e cortar no meio deles gera texto inválido,
-- que o love.graphics recusa com "UTF-8 decoding error".
function tema.ajustarTexto(fonte, texto, largura)
    texto = tostring(texto or "")

    if fonte:getWidth(texto) <= largura then
        return texto
    end

    while #texto > 1 and fonte:getWidth(texto .. "...") > largura do
        local inicioUltimo = utf8.offset(texto, -1)

        if not inicioUltimo or inicioUltimo <= 1 then
            texto = ""
            break
        end

       texto = texto:sub(1, inicioUltimo - 1)
    end

    return texto .. "..."
end

--------------------------------------------------
-- UTILIDADES
--------------------------------------------------

function tema.dentro(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function tema.tempo()
    return love.timer.getTime()
end

function tema.retangulo(modo, x, y, w, h, r)
    r = math.min(r or 0, w / 2, h / 2)
    love.graphics.rectangle(modo, x, y, w, h, r, r, 8)
end

-- Animação suave 0..1 (ou valor fixo se "reduzir movimento").
function tema.aproximar(atual, alvo, dt, velocidade)
    if reduzirMovimento then return alvo end
    local passo = math.min(1, (velocidade or 14) * dt)
    return atual + (alvo - atual) * passo
end

--------------------------------------------------
-- FUNDO
--------------------------------------------------

local malha = nil
local malhaW, malhaH = 0, 0

local function criarMalha(w, h)
    local t, b = tema.cores.fundoTopo, tema.cores.fundoBase

    malha = love.graphics.newMesh({
        {0, 0, 0, 0, t[1], t[2], t[3], 1},
        {w, 0, 1, 0, t[1], t[2], t[3], 1},
        {w, h, 1, 1, b[1], b[2], b[3], 1},
        {0, h, 0, 1, b[1], b[2], b[3], 1},
    }, "fan", "static")

    malhaW, malhaH = w, h
end

-- Gradiente escuro + "luzes" suaves que se movem devagar.
function tema.fundo(escurecer)
    local w, h = love.graphics.getDimensions()

    if not malha or malhaW ~= w or malhaH ~= h then
        criarMalha(w, h)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(malha, 0, 0)

    local t = reduzirMovimento and 0 or tema.tempo()
    local raio = math.max(w, h) * 0.45

    local luzes = {
        {0.49, 0.36, 1.00, 0.20, 0.22, 0.15, 0.10},
        {0.24, 0.86, 1.00, 0.80, 0.75, 0.12, 0.13},
        {1.00, 0.36, 0.60, 0.55, 0.10, 0.07, 0.17},
    }

    for i, l in ipairs(luzes) do
        local cx = w * (l[4] + 0.06 * math.sin(t * 0.13 * i + i))
        local cy = h * (l[5] + 0.08 * math.cos(t * 0.11 * i + i * 2))

        for passo = 4, 1, -1 do
            love.graphics.setColor(l[1], l[2], l[3], l[6] * 0.30)
            love.graphics.circle("fill", cx, cy, raio * passo / 4 * (0.6 + l[7]))
        end
    end

    if escurecer and escurecer > 0 then
        love.graphics.setColor(0, 0, 0, escurecer)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
end

--------------------------------------------------
-- PAINEL / BOTÃO
--------------------------------------------------

function tema.painel(x, y, w, h, r, alpha)
    r = r or 16 * tema.escala()

    love.graphics.setColor(0, 0, 0, 0.28)
    tema.retangulo("fill", x + 3, y + 5, w, h, r)

    tema.cor("painel", alpha or 0.94)
    tema.retangulo("fill", x, y, w, h, r)

    love.graphics.setColor(1, 1, 1, 0.07)
    love.graphics.setLineWidth(1)
    tema.retangulo("line", x + 0.5, y + 0.5, w - 1, h - 1, r)
end

local estilos = {
    primario   = {"acento",      "acento2"},
    secundario = {"painelClaro", "painelClaro"},
    perigo     = {"perigo",      "perigo"},
    ok         = {"ok",          "ok"},
}

-- opts: estilo, hover (0..1), pressionado (bool), icone, ativo (bool)
function tema.botao(x, y, w, h, texto, opts)
    opts = opts or {}

    local k = tema.escala()
    local par = estilos[opts.estilo or "secundario"] or estilos.secundario
    local hover = opts.hover or 0
    local base = tema.cores[par[1]]
    local topo = tema.cores[par[2]]
    local r = math.min(h * 0.32, 18 * k)

    if opts.pressionado then
        y = y + 1.5
    end

    love.graphics.setColor(0, 0, 0, 0.30)
    tema.retangulo("fill", x, y + 3, w, h, r)

    local m = opts.estilo == "secundario" or not opts.estilo
    local fator = m and (0.75 + 0.35 * hover) or (0.82 + 0.28 * hover)

    love.graphics.setColor(base[1] * fator, base[2] * fator, base[3] * fator, 1)
    tema.retangulo("fill", x, y, w, h, r)

    -- brilho superior
    local mix = m and 0.10 or 0.45
    love.graphics.setColor(
        topo[1], topo[2], topo[3],
        (m and 0.10 or 0.30) * (0.6 + 0.6 * hover)
    )
    tema.retangulo("fill", x, y, w, h * 0.5, r)

    if opts.ativo then
        tema.cor("acento2", 0.9)
        love.graphics.setLineWidth(2)
        tema.retangulo("line", x + 1, y + 1, w - 2, h - 2, r)
    else
        love.graphics.setColor(1, 1, 1, 0.08 + 0.10 * hover)
        love.graphics.setLineWidth(1)
        tema.retangulo("line", x + 0.5, y + 0.5, w - 1, h - 1, r)
    end

    local fonte = opts.fonte or tema.fonte(17 * k)
    love.graphics.setFont(fonte)
    tema.cor("texto", opts.desabilitado and 0.4 or 1)

    local tx = x
    local tw = w

    if opts.icone then
        local isz = h * 0.42
        tema.icone(opts.icone, x + h * 0.52, y + h / 2, isz, "texto")
        tx = x + h * 0.85
        tw = w - h * 0.85 - h * 0.25
    end

    local ty = y + (h - fonte:getHeight()) / 2

    love.graphics.printf(
        tema.ajustarTexto(fonte, texto, tw),
        tx, ty, tw,
        opts.icone and "left" or "center"
    )
end

--------------------------------------------------
-- CONTROLES (toggle / slider)
--------------------------------------------------

function tema.toggle(x, y, w, h, ligado, anim)
    anim = anim or (ligado and 1 or 0)

    local fundo = tema.cores.painelClaro
    local on = tema.cores.acento

    love.graphics.setColor(
        fundo[1] + (on[1] - fundo[1]) * anim,
        fundo[2] + (on[2] - fundo[2]) * anim,
        fundo[3] + (on[3] - fundo[3]) * anim,
        1
    )
    tema.retangulo("fill", x, y, w, h, h / 2)

    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.setLineWidth(1)
    tema.retangulo("line", x + 0.5, y + 0.5, w - 1, h - 1, h / 2)

    local pad = h * 0.14
    local raio = h / 2 - pad
    local cx = x + pad + raio + (w - 2 * pad - 2 * raio) * anim

    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.circle("fill", cx, y + h / 2 + 1.5, raio)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", cx, y + h / 2, raio)
end

function tema.slider(x, y, w, fracao, ativo)
    fracao = math.max(0, math.min(1, fracao or 0))

    local k = tema.escala()
    local alt = 6 * k
    local raio = 9 * k

    tema.cor("painelClaro", 1)
    tema.retangulo("fill", x, y - alt / 2, w, alt, alt / 2)

    tema.cor("acento", 1)
    tema.retangulo("fill", x, y - alt / 2, math.max(alt, w * fracao), alt, alt / 2)

    local cx = x + w * fracao

    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.circle("fill", cx, y + 1.5, raio)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", cx, y, raio + (ativo and 2 or 0))
end

--------------------------------------------------
-- ÍCONES (desenhados com primitivas)
--------------------------------------------------

function tema.icone(nome, cx, cy, s, cor, alpha)
    if type(cor) == "table" then
        love.graphics.setColor(cor[1], cor[2], cor[3], alpha or cor[4] or 1)
    else
        tema.cor(cor or "texto", alpha)
    end

    love.graphics.setLineWidth(math.max(2, s * 0.16))

    if nome == "play" then
        love.graphics.polygon("fill",
            cx - s * 0.30, cy - s * 0.45,
            cx - s * 0.30, cy + s * 0.45,
            cx + s * 0.45, cy)

    elseif nome == "pause" then
        local bw = s * 0.26
        tema.retangulo("fill", cx - s * 0.36, cy - s * 0.42, bw, s * 0.84, bw / 3)
        tema.retangulo("fill", cx + s * 0.10, cy - s * 0.42, bw, s * 0.84, bw / 3)

    elseif nome == "reset" then
        love.graphics.arc("line", "open", cx, cy, s * 0.40, -math.pi * 0.15, math.pi * 1.45, 24)
        local ax = cx + s * 0.40 * math.cos(-math.pi * 0.15)
        local ay = cy + s * 0.40 * math.sin(-math.pi * 0.15)
        love.graphics.polygon("fill",
            ax - s * 0.22, ay - s * 0.06,
            ax + s * 0.22, ay - s * 0.06,
            ax + s * 0.02, ay + s * 0.26)

    elseif nome == "menu" then
        love.graphics.polygon("fill",
            cx, cy - s * 0.48,
            cx + s * 0.52, cy - s * 0.02,
            cx - s * 0.52, cy - s * 0.02)
        love.graphics.rectangle("fill", cx - s * 0.36, cy - s * 0.02, s * 0.72, s * 0.48)

    elseif nome == "engrenagem" then
        for i = 0, 7 do
            local a = i * math.pi / 4
            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.rotate(a)
            love.graphics.rectangle("fill", -s * 0.09, -s * 0.50, s * 0.18, s * 0.24)
            love.graphics.pop()
        end
        love.graphics.circle("line", cx, cy, s * 0.32)
        love.graphics.circle("fill", cx, cy, s * 0.10)

    elseif nome == "voltar" then
        love.graphics.line(cx + s * 0.30, cy - s * 0.40, cx - s * 0.25, cy, cx + s * 0.30, cy + s * 0.40)

    elseif nome == "seta_esq" then
        love.graphics.line(cx + s * 0.22, cy - s * 0.36, cx - s * 0.22, cy, cx + s * 0.22, cy + s * 0.36)

    elseif nome == "seta_dir" then
        love.graphics.line(cx - s * 0.22, cy - s * 0.36, cx + s * 0.22, cy, cx - s * 0.22, cy + s * 0.36)

    elseif nome == "mais" then
        love.graphics.line(cx - s * 0.40, cy, cx + s * 0.40, cy)
        love.graphics.line(cx, cy - s * 0.40, cx, cy + s * 0.40)

    elseif nome == "check" then
        love.graphics.line(cx - s * 0.40, cy, cx - s * 0.10, cy + s * 0.32, cx + s * 0.42, cy - s * 0.32)

    elseif nome == "nota" then
        love.graphics.circle("fill", cx - s * 0.16, cy + s * 0.26, s * 0.22)
        love.graphics.rectangle("fill", cx + s * 0.02, cy - s * 0.44, s * 0.14, s * 0.72)
        love.graphics.polygon("fill",
            cx + s * 0.16, cy - s * 0.44,
            cx + s * 0.46, cy - s * 0.22,
            cx + s * 0.16, cy - s * 0.10)

    elseif nome == "tela" then
        tema.retangulo("line", cx - s * 0.48, cy - s * 0.34, s * 0.96, s * 0.62, s * 0.08)
        love.graphics.line(cx - s * 0.22, cy + s * 0.44, cx + s * 0.22, cy + s * 0.44)

    elseif nome == "olho" then
        love.graphics.ellipse("line", cx, cy, s * 0.50, s * 0.30)
        love.graphics.circle("fill", cx, cy, s * 0.14)

    elseif nome == "som" then
        love.graphics.polygon("fill",
            cx - s * 0.46, cy - s * 0.16, cx - s * 0.22, cy - s * 0.16,
            cx + s * 0.06, cy - s * 0.42, cx + s * 0.06, cy + s * 0.42,
            cx - s * 0.22, cy + s * 0.16, cx - s * 0.46, cy + s * 0.16)
        love.graphics.arc("line", "open", cx + s * 0.06, cy, s * 0.30, -0.9, 0.9, 12)

    elseif nome == "teclado" then
        tema.retangulo("line", cx - s * 0.50, cy - s * 0.30, s * 1.0, s * 0.60, s * 0.08)
        for i = -1, 1 do
            love.graphics.circle("fill", cx + i * s * 0.26, cy - s * 0.08, s * 0.05)
        end
        love.graphics.line(cx - s * 0.24, cy + s * 0.14, cx + s * 0.24, cy + s * 0.14)

    elseif nome == "hud" then
        tema.retangulo("line", cx - s * 0.48, cy - s * 0.40, s * 0.96, s * 0.80, s * 0.08)
        love.graphics.rectangle("fill", cx - s * 0.34, cy - s * 0.26, s * 0.40, s * 0.10)
        love.graphics.rectangle("fill", cx - s * 0.34, cy - s * 0.04, s * 0.28, s * 0.10)

    elseif nome == "estrela" then
        local estrela = obterEstrela(s)

        if estrela then
            local escala = s / estrela.lado
            love.graphics.draw(estrela.canvas, cx - s / 2, cy - s / 2, 0, escala, escala)
        else
            -- Fallback (canvas indisponível): desenho original, cru.
            local pts = {}
            for i = 0, 9 do
                local r = (i % 2 == 0) and s * 0.5 or s * 0.22
                local a = -math.pi / 2 + i * math.pi / 5
                pts[#pts + 1] = cx + r * math.cos(a)
                pts[#pts + 1] = cy + r * math.sin(a)
            end
            love.graphics.polygon("fill", pts)
        end

    elseif nome == "bug" then
        love.graphics.ellipse("fill", cx, cy + s * 0.05, s * 0.28, s * 0.36)
        love.graphics.line(cx - s * 0.28, cy - s * 0.10, cx - s * 0.48, cy - s * 0.20)
        love.graphics.line(cx + s * 0.28, cy - s * 0.10, cx + s * 0.48, cy - s * 0.20)
        love.graphics.line(cx - s * 0.28, cy + s * 0.22, cx - s * 0.48, cy + s * 0.32)
        love.graphics.line(cx + s * 0.28, cy + s * 0.22, cx + s * 0.48, cy + s * 0.32)
        love.graphics.circle("fill", cx, cy - s * 0.34, s * 0.14)

    elseif nome == "acessibilidade" then
        love.graphics.circle("line", cx, cy, s * 0.48)
        love.graphics.circle("fill", cx, cy - s * 0.26, s * 0.08)
        love.graphics.line(cx - s * 0.28, cy - s * 0.06, cx + s * 0.28, cy - s * 0.06)
        love.graphics.line(cx, cy - s * 0.06, cx, cy + s * 0.12)
        love.graphics.line(cx, cy + s * 0.12, cx - s * 0.18, cy + s * 0.36)
        love.graphics.line(cx, cy + s * 0.12, cx + s * 0.18, cy + s * 0.36)

    elseif nome == "raio" then
        love.graphics.polygon("fill",
            cx + s * 0.10, cy - s * 0.50,
            cx - s * 0.30, cy + s * 0.06,
            cx - s * 0.02, cy + s * 0.06,
            cx - s * 0.10, cy + s * 0.50,
            cx + s * 0.30, cy - s * 0.10,
            cx + s * 0.02, cy - s * 0.10)

    elseif nome == "gamepad" then
        tema.retangulo("fill", cx - s * 0.50, cy - s * 0.22, s * 1.0, s * 0.50, s * 0.22)
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", cx - s * 0.32, cy - s * 0.05, s * 0.22, s * 0.06)
        love.graphics.rectangle("fill", cx - s * 0.24, cy - s * 0.13, s * 0.06, s * 0.22)
        love.graphics.circle("fill", cx + s * 0.20, cy - s * 0.02, s * 0.06)
        love.graphics.circle("fill", cx + s * 0.32, cy + s * 0.06, s * 0.06)
    end

    love.graphics.setLineWidth(1)
end

--------------------------------------------------
-- BOTÃO DE PAUSA DA GAMEPLAY
--------------------------------------------------

-- Retângulo do botão (usado também para o toque/clique em main.lua).
function tema.retanguloBotaoPausa()
    local k = math.max(0.75, math.min(1.3, love.graphics.getHeight() / 720))
    local lado = 56 * k
    local margem = 18 * k

    return love.graphics.getWidth() - lado - margem, margem, lado, lado
end

function tema.dentroBotaoPausa(x, y)
    local rx, ry, rw, rh = tema.retanguloBotaoPausa()
    local folga = 8

    return tema.dentro(x, y, rx - folga, ry - folga, rw + folga * 2, rh + folga * 2)
end

-- pressionado: 0..1 (animação); hover: 0..1
function tema.desenharBotaoPausa(hover)
    local x, y, w, h = tema.retanguloBotaoPausa()
    hover = hover or 0

    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.circle("fill", x + w / 2, y + h / 2 + 2, w / 2)

    love.graphics.setColor(0.10, 0.11, 0.20, 0.78 + 0.15 * hover)
    love.graphics.circle("fill", x + w / 2, y + h / 2, w / 2)

    tema.cor("acento2", 0.35 + 0.45 * hover)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", x + w / 2, y + h / 2, w / 2 - 1)

    tema.icone("pause", x + w / 2, y + h / 2, w * 0.46, "texto")
    love.graphics.setLineWidth(1)
end

--------------------------------------------------
-- AVISOS (toasts)
--------------------------------------------------

local toasts = {}

function tema.toast(texto, tipo)
    texto = tostring(texto or "")
    if texto == "" then return end

    toasts[#toasts + 1] = {texto = texto, restante = 2.4, tipo = tipo or "info"}

    while #toasts > 4 do
        table.remove(toasts, 1)
    end
end

function tema.atualizarToasts(dt)
    for i = #toasts, 1, -1 do
        toasts[i].restante = toasts[i].restante - dt

        if toasts[i].restante <= 0 then
            table.remove(toasts, i)
        end
    end
end

function tema.desenharToasts()
    if #toasts == 0 then return end

    local k = tema.escala()
    local w, h = love.graphics.getDimensions()
    local fonte = tema.fonte(15 * k)

    love.graphics.setFont(fonte)

    for i = #toasts, 1, -1 do
        local t = toasts[i]
        local tw = fonte:getWidth(t.texto) + 36 * k
        local th = fonte:getHeight() + 18 * k
        local alpha = math.min(1, t.restante / 0.4)
        local y = h - 70 * k - (#toasts - i) * (th + 8 * k)

        love.graphics.setColor(0, 0, 0, 0.35 * alpha)
        tema.retangulo("fill", (w - tw) / 2 + 2, y + 4, tw, th, th / 2)

        tema.cor("painel", 0.96 * alpha)
        tema.retangulo("fill", (w - tw) / 2, y, tw, th, th / 2)

        local cor = t.tipo == "erro" and "perigo" or (t.tipo == "ok" and "ok" or "acento2")
        tema.cor(cor, alpha)
        love.graphics.setLineWidth(1.5)
        tema.retangulo("line", (w - tw) / 2 + 0.5, y + 0.5, tw - 1, th - 1, th / 2)

        tema.cor("texto", alpha)
        love.graphics.printf(t.texto, (w - tw) / 2, y + 9 * k, tw, "center")
    end

    love.graphics.setLineWidth(1)
end

return tema
