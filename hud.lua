-- HUD da gameplay + editor de posição.
--
-- Cada métrica tem uma caixa (retângulo) calculada a partir do texto, então
-- o que aparece no editor é exatamente o que se arrasta. Para mover:
--   * toque/clique direto na métrica e arraste; ou
--   * escolha a métrica nos botões de baixo e arraste em QUALQUER lugar
--     da tela (o dedo não precisa acertar a métrica);
--   * botões de seta / setas do teclado ajustam de 1 em 1 (Shift = 10).

local tema = require("tema")

local hud = {}

--------------------------------------------------
-- ESTADO
--------------------------------------------------

local visivel = true
local editando = false
local selecionado = nil
local arrastando = false
local dragDx, dragDy = 0, 0
local snapAtivo = true
local snapshot = nil
local botaoAtivo = nil

local ordem = {"accuracy", "combo", "score", "misses", "ratings", "ratingPopup"}

local rotulos = {
    accuracy = "PRECISÃO", combo = "COMBO", score = "PONTOS",
    misses = "MISSES", ratings = "RESUMO", ratingPopup = "POPUP",
}

-- ratingPopup.x = CENTRO do popup (nil = centro da tela)
local padroes = {
    accuracy    = {x = 10, y = 35},
    combo       = {x = 10, y = 62},
    score       = {x = 10, y = 89},
    misses      = {x = 10, y = 116},
    ratings     = {x = 10, y = 143},
    ratingPopup = {x = nil, y = 60},
}

local elementos = {}

for nome, p in pairs(padroes) do
    elementos[nome] = {x = p.x, y = p.y, ativo = true}
end

-- textos usados para medir a caixa no editor
local exemplos = {
    accuracy = "ACCURACY: 100.00%",
    combo = "COMBO: 9999  |  MAX: 9999",
    score = "SCORE: 99999999",
    misses = "MISSES: 9999",
    ratings = "R:SS  P:9999  G:9999  O:9999  B:9999  J:9999/9999",
    ratingPopup = "PERFECT -99 ms",
}

local opc = {
    escala = 1, opacidade = 1, fundo = false, cores = true,
    ms = false, duracao = 0.6, reduzir = false,
}

local coresJulgamento = {
    PERFECT = {0.45, 0.92, 1.00},
    GOOD    = {0.45, 1.00, 0.55},
    OK      = {1.00, 0.90, 0.40},
    BAD     = {1.00, 0.62, 0.30},
    MISS    = {1.00, 0.36, 0.42},
}

local ultimoId = -1
local inicioPopup = -100

--------------------------------------------------
-- CONFIGURAÇÃO
--------------------------------------------------

local function numero(v, padrao)
    v = tonumber(v)
    if v == nil then return padrao end
    return v
end

function hud.aplicarConfiguracao(config)
    if not config then return end

    for nome, e in pairs(elementos) do
        local x = numero(config.get("hud_" .. nome .. "_x"), e.x)
        local y = numero(config.get("hud_" .. nome .. "_y"), e.y)

        if nome == "ratingPopup" and (x == nil or x <= 0) then x = nil end

        e.x, e.y = x, y

        local ativo = config.get("hud_" .. nome .. "_ativo")
        e.ativo = ativo ~= false
    end

    local salvo = config.get("hudVisivel")
    if salvo ~= nil then visivel = salvo == true end

    opc.escala = numero(config.get("hudEscala"), 100) / 100
    opc.opacidade = numero(config.get("hudOpacidade"), 100) / 100
    opc.fundo = config.get("hudFundo") == true
    opc.cores = config.get("hudCoresJulgamento") ~= false
    opc.ms = config.get("hudMostrarMs") == true
    opc.duracao = numero(config.get("popupDuracao"), 0.6)
    opc.reduzir = config.get("reduzirMovimento") == true
end

function hud.setVisivel(valor) visivel = valor == true end
function hud.estaVisivel() return visivel end
function hud.estaEditando() return editando end

function hud.alternar(config)
    visivel = not visivel
    if config then config.set("hudVisivel", visivel) end
end

--------------------------------------------------
-- MEDIDAS
--------------------------------------------------

local function escalaTela()
    return math.max(0.7, math.min(1.5, love.graphics.getHeight() / 720)) * opc.escala
end

local function fonteDe(nome)
    local base = nome == "ratingPopup" and 30 or 17
    return tema.fonte(base * escalaTela())
end

-- Caixa (x, y, w, h, pad) do elemento na tela.
local function caixa(nome, texto)
    local e = elementos[nome]
    local f = fonteDe(nome)
    local pad = 7 * escalaTela()
    local w = f:getWidth(texto or exemplos[nome]) + pad * 2
    local h = f:getHeight() + pad
    local x = e.x

    if nome == "ratingPopup" then
        x = (x or love.graphics.getWidth() / 2) - w / 2
    end

    return x, e.y, w, h, pad
end

local function limitar(nome, x, y)
    local W, H = love.graphics.getDimensions()
    local _, _, w, h = caixa(nome)

    return math.max(0, math.min(W - w, x)), math.max(0, math.min(H - h, y))
end

-- Move pelo canto superior esquerdo da caixa.
local function moverCaixa(nome, x, y)
    local e = elementos[nome]
    if not e then return end

    x, y = limitar(nome, x, y)

    if snapAtivo then
        x = math.floor(x / 10 + 0.5) * 10
        y = math.floor(y / 10 + 0.5) * 10
    end

    if nome == "ratingPopup" then
        local _, _, w = caixa(nome)
        local centro = x + w / 2
        local meio = love.graphics.getWidth() / 2

        if math.abs(centro - meio) < (snapAtivo and 16 or 6) then centro = meio end

        e.x = centro
    else
        e.x = x
    end

    e.y = y
end

function hud.mover(nome, x, y)
    local e = elementos[nome]
    if not e then return false end

    e.x = tonumber(x) or e.x
    e.y = tonumber(y) or e.y
    return true
end

function hud.getPosicao(nome)
    local e = elementos[nome]
    if not e then return nil end
    return e.x, e.y
end

function hud.getElementos()
    return elementos
end

function hud.salvarPosicoes(config)
    if not config then return end

    for nome, e in pairs(elementos) do
        config.set("hud_" .. nome .. "_x", math.floor((e.x or 0) + 0.5))
        config.set("hud_" .. nome .. "_y", math.floor((e.y or 0) + 0.5))
    end
end

function hud.restaurarPosicoes()
    for nome, p in pairs(padroes) do
        elementos[nome].x = p.x
        elementos[nome].y = p.y
    end
end

--------------------------------------------------
-- TEXTOS
--------------------------------------------------

local function textos(hit)
    local stats = hit.getEstatisticas()

    if type(stats) ~= "table" then return nil end

    return {
        accuracy = string.format("ACCURACY: %.2f%%", numero(stats.precisaoMedia, 0) * 100),
        combo = string.format("COMBO: %d  |  MAX: %d", numero(stats.combo, 0), numero(stats.maxCombo, 0)),
        score = string.format("SCORE: %d", numero(stats.score, 0)),
        misses = string.format("MISSES: %d", numero(stats.miss, 0)),
        ratings = string.format("R:%s  P:%d  G:%d  O:%d  B:%d  J:%d/%d",
            hit.getRating and hit.getRating() or "-",
            numero(stats.perfect, 0), numero(stats.good, 0), numero(stats.ok, 0),
            numero(stats.bad, 0), numero(stats.julgadas, 0), numero(stats.total, 0)),
    }
end

--------------------------------------------------
-- DESENHO DAS MÉTRICAS
--------------------------------------------------

local function desenharTexto(nome, texto, alpha, corTexto)
    local x, y, w, h, pad = caixa(nome, texto)
    local f = fonteDe(nome)
    local a = (alpha or 1) * opc.opacidade

    if opc.fundo then
        love.graphics.setColor(0, 0, 0, 0.45 * a)
        tema.retangulo("fill", x, y, w, h, 6 * escalaTela())
    end

    love.graphics.setFont(f)

    -- sombra leve para ler sobre qualquer fundo
    love.graphics.setColor(0, 0, 0, 0.55 * a)
    love.graphics.print(texto, x + pad + 1, y + pad / 2 + 1)

    local c = corTexto or {1, 1, 1}
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.print(texto, x + pad, y + pad / 2)
end

function hud.desenhar(hit, config)
    if not visivel or not hit then return end

    local t = textos(hit)
    if not t then return end

    for _, nome in ipairs(ordem) do
        local e = elementos[nome]

        if e.ativo and nome ~= "ratingPopup" then
            local cor = nome == "ratings" and {0.72, 0.72, 0.80} or nil
            desenharTexto(nome, t[nome], 1, cor)
        end
    end

    -- popup do último julgamento
    local id = hit.idJulgamento or 0

    if id ~= ultimoId then
        ultimoId = id
        inicioPopup = love.timer.getTime()
    end

    local julgamento = hit.getUltimoJulgamento and hit.getUltimoJulgamento() or ""

    if elementos.ratingPopup.ativo and julgamento ~= "" then
        local idade = love.timer.getTime() - inicioPopup

        if idade <= opc.duracao then
            local texto = julgamento

            if opc.ms and hit.ultimoDesvio then
                texto = string.format("%s %+d ms", julgamento, math.floor(hit.ultimoDesvio * 1000 + 0.5))
            end

            local alpha = 1

            if idade > opc.duracao * 0.6 then
                alpha = 1 - (idade - opc.duracao * 0.6) / (opc.duracao * 0.4)
            end

            local cor = opc.cores and coresJulgamento[julgamento] or {1, 1, 1}

            if not opc.reduzir and idade < 0.12 then
                -- "pulo" curto no início do popup
                local x, y, w, h = caixa("ratingPopup", texto)
                local s = 1 + 0.22 * (1 - idade / 0.12)

                love.graphics.push()
                love.graphics.translate(x + w / 2, y + h / 2)
                love.graphics.scale(s, s)
                love.graphics.translate(-(x + w / 2), -(y + h / 2))
                desenharTexto("ratingPopup", texto, alpha, cor)
                love.graphics.pop()
            else
                desenharTexto("ratingPopup", texto, alpha, cor)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------
-- EDITOR: GEOMETRIA DA BARRA INFERIOR
--------------------------------------------------

local function geoBarra()
    local W, H = love.graphics.getDimensions()
    local k = math.max(0.7, math.min(1.4, H / 720))
    local m = 12 * k
    local gap = 8 * k

    local g = {W = W, H = H, k = k, m = m}

    local bh = 44 * k
    g.botoes = {}

    local nomes = {
        {id = "cancelar", texto = "CANCELAR"},
        {id = "resetar", texto = "RESETAR"},
        {id = "snap", texto = snapAtivo and "GRADE: LIGADA" or "GRADE: DESLIGADA"},
        {id = "voltar", texto = "SALVAR E SAIR"},
    }

    local bw = math.min(190 * k, (W - 2 * m - gap * (#nomes - 1)) / #nomes)
    local total = bw * #nomes + gap * (#nomes - 1)
    local x0 = (W - total) / 2
    local by = H - m - bh

    for i, b in ipairs(nomes) do
        g.botoes[i] = {id = b.id, texto = b.texto, x = x0 + (i - 1) * (bw + gap), y = by, w = bw, h = bh}
    end

    local ch = 38 * k
    local cw = math.min(160 * k, (W - 2 * m - gap * (#ordem - 1)) / #ordem)
    local ctotal = cw * #ordem + gap * (#ordem - 1)
    local cx0 = (W - ctotal) / 2
    local cy = by - gap - ch

    g.chips = {}

    for i, nome in ipairs(ordem) do
        g.chips[i] = {nome = nome, x = cx0 + (i - 1) * (cw + gap), y = cy, w = cw, h = ch}
    end

    -- setas de ajuste fino (só com uma métrica selecionada)
    local ns = 40 * k
    local nx = W - m - (ns * 4 + gap * 3)
    local ny = cy - gap - ns

    g.setas = {
        {id = "esq",   x = nx,                    y = ny, w = ns, h = ns, dx = -1, dy = 0},
        {id = "cima",  x = nx + (ns + gap),       y = ny, w = ns, h = ns, dx = 0,  dy = -1},
        {id = "baixo", x = nx + (ns + gap) * 2,   y = ny, w = ns, h = ns, dx = 0,  dy = 1},
        {id = "dir",   x = nx + (ns + gap) * 3,   y = ny, w = ns, h = ns, dx = 1,  dy = 0},
    }

    g.topoY = cy

    return g
end

--------------------------------------------------
-- EDITOR: ENTRADA
--------------------------------------------------

function hud.iniciarEditor()
    editando = true
    arrastando = false
    selecionado = nil
    botaoAtivo = nil
    snapshot = {}

    for nome, e in pairs(elementos) do
        snapshot[nome] = {x = e.x, y = e.y}
    end
end

function hud.fecharEditor()
    editando = false
    arrastando = false
    selecionado = nil
    botaoAtivo = nil
    snapshot = nil
end

function hud.cancelar()
    if snapshot then
        for nome, s in pairs(snapshot) do
            elementos[nome].x = s.x
            elementos[nome].y = s.y
        end
    end
end

function hud.confirmar(config)
    hud.salvarPosicoes(config)
end

local function ajustar(nome, dx, dy, passo)
    local e = elementos[nome]
    if not e then return end

    local x, y, w = caixa(nome)
    local nx, ny = limitar(nome, x + dx * passo, y + dy * passo)

    if nome == "ratingPopup" then
        e.x = nx + w / 2
    else
        e.x = nx
    end

    e.y = ny
end

function hud.teclado(tecla)
    if not editando then return false end

    local passo = love.keyboard.isDown("lshift", "rshift") and 10 or 1

    if tecla == "tab" then
        local atual = 0

        for i, nome in ipairs(ordem) do
            if nome == selecionado then atual = i end
        end

        selecionado = ordem[atual % #ordem + 1]
        return true
    end

    if not selecionado then return false end

    if tecla == "left" then ajustar(selecionado, -1, 0, passo); return true end
    if tecla == "right" then ajustar(selecionado, 1, 0, passo); return true end
    if tecla == "up" then ajustar(selecionado, 0, -1, passo); return true end
    if tecla == "down" then ajustar(selecionado, 0, 1, passo); return true end

    return false
end

local function elementoEm(x, y)
    local melhor, menorArea = nil, math.huge
    local folga = 10 * escalaTela()

    for _, nome in ipairs(ordem) do
        local cx, cy, w, h = caixa(nome)

        if tema.dentro(x, y, cx - folga, cy - folga, w + folga * 2, h + folga * 2) then
            local area = w * h

            if area < menorArea then
                melhor, menorArea = nome, area
            end
        end
    end

    return melhor
end

-- Devolve "voltar", "cancelar", "resetar", "snap", "selecionou",
-- "arrastando" ou "capturado".
function hud.editorPress(x, y, config)
    if not editando then return nil end

    x, y = tonumber(x) or 0, tonumber(y) or 0

    local g = geoBarra()

    for _, b in ipairs(g.botoes) do
        if tema.dentro(x, y, b.x, b.y, b.w, b.h) then
            botaoAtivo = b.id

            if b.id == "resetar" then
                hud.restaurarPosicoes()
                return "resetar"
            elseif b.id == "snap" then
                snapAtivo = not snapAtivo
                return "snap"
            elseif b.id == "cancelar" then
                hud.cancelar()
                return "cancelar"
            else
                hud.confirmar(config)
                return "voltar"
            end
        end
    end

    for _, c in ipairs(g.chips) do
        if tema.dentro(x, y, c.x, c.y, c.w, c.h) then
            selecionado = c.nome
            return "selecionou"
        end
    end

    if selecionado then
        for _, s in ipairs(g.setas) do
            if tema.dentro(x, y, s.x, s.y, s.w, s.h) then
                ajustar(selecionado, s.dx, s.dy, snapAtivo and 10 or 1)
                return "capturado"
            end
        end
    end

    local alvo = elementoEm(x, y)

    if alvo then selecionado = alvo end

    if selecionado then
        local cx, cy, w, h = caixa(selecionado)

        dragDx = x - cx
        dragDy = y - cy
        arrastando = true
        return "arrastando"
    end

    return "capturado"
end

function hud.editorRelease()
    if not editando then return false end

    arrastando = false
    botaoAtivo = nil
    return true
end

function hud.mousepressed(x, y, config)
    return hud.editorPress(x, y, config)
end

function hud.mousemoved(x, y)
    if not editando or not arrastando or not selecionado then return false end

    moverCaixa(selecionado, x - dragDx, y - dragDy)
    return true
end

function hud.mousereleased()
    return hud.editorRelease()
end

function hud.touchpressed(_, x, y, config)
    return hud.editorPress(x, y, config)
end

function hud.touchmoved(_, x, y)
    return hud.mousemoved(x, y)
end

function hud.touchreleased()
    return hud.editorRelease()
end

--------------------------------------------------
-- EDITOR: DESENHO
--------------------------------------------------

local function seta(s, ativo)
    tema.botao(s.x, s.y, s.w, s.h, "", {hover = ativo and 1 or 0})

    local cx, cy = s.x + s.w / 2, s.y + s.h / 2

    love.graphics.push()
    love.graphics.translate(cx, cy)

    if s.id == "cima" then love.graphics.rotate(math.pi / 2)
    elseif s.id == "baixo" then love.graphics.rotate(-math.pi / 2)
    elseif s.id == "dir" then love.graphics.rotate(math.pi) end

    tema.icone("voltar", 0, 0, s.w * 0.5, "texto")
    love.graphics.pop()
end

function hud.desenharEditor()
    if not editando then return end

    local g = geoBarra()
    local k = g.k
    local W, H = g.W, g.H

    love.graphics.setColor(0, 0, 0, 0.42)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- grade
    if snapAtivo then
        love.graphics.setColor(1, 1, 1, 0.10)

        for gx = 0, W, 40 do
            for gy = 0, H, 40 do
                love.graphics.rectangle("fill", gx, gy, 2, 2)
            end
        end
    end

    -- linha central (referência do popup)
    love.graphics.setColor(0.24, 0.86, 1, 0.16)
    love.graphics.rectangle("fill", W / 2 - 0.5, 0, 1, H)

    -- métricas
    for _, nome in ipairs(ordem) do
        local e = elementos[nome]
        local x, y, w, h = caixa(nome)
        local sel = nome == selecionado

        local exemplo = exemplos[nome]

        if nome == "ratingPopup" then exemplo = "PERFECT" end

        desenharTexto(nome, exemplo, e.ativo and 1 or 0.35,
            nome == "ratingPopup" and coresJulgamento.PERFECT or nil)

        love.graphics.setLineWidth(sel and 3 or 1.5)

        if sel then
            tema.cor("acento2", 1)
        else
            love.graphics.setColor(1, 1, 1, 0.45)
        end

        tema.retangulo("line", x, y, w, h, 6 * k)

        -- etiqueta
        local f = tema.fonte(12 * k)
        local rot = rotulos[nome] .. (e.ativo and "" or " (OCULTO)")
        local rw = f:getWidth(rot) + 12 * k
        local ry = y - f:getHeight() - 6 * k

        if ry < 0 then ry = y + h + 2 * k end

        if sel then tema.cor("acento2", 1) else love.graphics.setColor(0.2, 0.2, 0.35, 0.95) end
        tema.retangulo("fill", x, ry, rw, f:getHeight() + 4 * k, 4 * k)

        love.graphics.setFont(f)
        if sel then love.graphics.setColor(0, 0, 0, 1) else tema.cor("texto") end
        love.graphics.print(rot, x + 6 * k, ry + 2 * k)
    end

    love.graphics.setLineWidth(1)

    -- barra superior
    local ft = tema.fonte(22 * k)
    local fi = tema.fonte(13 * k)

    love.graphics.setColor(0.04, 0.05, 0.12, 0.88)
    love.graphics.rectangle("fill", 0, 0, W, 64 * k)

    love.graphics.setFont(ft)
    tema.cor("texto")
    love.graphics.printf("EDITOR DO HUD", 0, 8 * k, W, "center")

    love.graphics.setFont(fi)
    tema.cor("mudo")
    love.graphics.printf(
        selecionado
            and ("Arraste em qualquer lugar para mover: " .. rotulos[selecionado])
            or "Escolha uma métrica abaixo (ou toque nela) e arraste",
        0, 38 * k, W, "center")

    -- setas
    if selecionado then
        for _, s in ipairs(g.setas) do seta(s, false) end
    end

    -- chips
    for _, c in ipairs(g.chips) do
        local sel = c.nome == selecionado
        local oculto = not elementos[c.nome].ativo

        tema.botao(c.x, c.y, c.w, c.h, rotulos[c.nome], {
            estilo = sel and "primario" or "secundario",
            ativo = sel,
            hover = sel and 1 or 0,
            fonte = tema.fonte(12 * k),
            desabilitado = oculto,
        })
    end

    -- botões
    for _, b in ipairs(g.botoes) do
        local estilo = "secundario"

        if b.id == "voltar" then estilo = "ok"
        elseif b.id == "cancelar" then estilo = "perigo" end

        tema.botao(b.x, b.y, b.w, b.h, b.texto, {
            estilo = estilo,
            pressionado = botaoAtivo == b.id,
            fonte = tema.fonte(13 * k),
        })
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return hud
