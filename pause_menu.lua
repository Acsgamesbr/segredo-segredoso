-- Menu de pausa.
--
-- Página principal: Continuar / Resetar / Voltar ao menu / Configurações.
-- Configurações: abas (Gameplay, Vídeo, Áudio, HUD, Controles,
-- Acessibilidade, QoL, Debug) montadas a partir de opcoes.lua.
--
local tema = require("tema")
local opcoes = require("opcoes")

local pause = {}

--------------------------------------------------
-- ESTADO
--------------------------------------------------

local cfg = nil        -- config_manager
local ctrls = nil      -- controles

local aberto = false
local pagina = "principal"
local infoBeatmap = ""

local origemMenu = false   -- aberto pelo menu principal (sem partida)
local principalSel = 1
local abaIdx = 1
local scrolls = {}
local tabScroll = 0
local entradas = {}
local alturaTotal = 0
local sujo = true
local selId = nil
local hoverChave = nil

local ponteiro = nil       -- gesto em andamento
local esperando = nil      -- {tipo="tecla"|"botao"|"atalho"|"valor", op=}
local bufferValor = ""     -- texto sendo digitado quando esperando.tipo == "valor"
local confirma = {}        -- id -> segundos restantes para confirmar
local confirmaSair = 0
local animacao = {}        -- chave -> 0..1

local BOTOES_PRINCIPAIS = {
    {id = "continuar", texto = "CONTINUAR",      icone = "play",       estilo = "primario"},
    {id = "resetar",   texto = "RESETAR",        icone = "reset",      estilo = "secundario"},
    {id = "config",    texto = "CONFIGURAÇÕES",  icone = "engrenagem", estilo = "secundario"},
    {id = "sair",      texto = "VOLTAR AO MENU", icone = "menu",       estilo = "secundario"},
}

local function ehMobile()
    local os = love.system.getOS()
    return os == "Android" or os == "iOS"
end

--------------------------------------------------
-- CONFIGURAÇÃO EXTERNA
--------------------------------------------------

function pause.configurar(config, controles)
    cfg = config
    ctrls = controles
end

function pause.definirInfo(texto)
    infoBeatmap = tostring(texto or "")
end

--------------------------------------------------
-- ABRIR / FECHAR
--------------------------------------------------

-- paginaInicial: "principal" (padrão) ou "config".
-- doMenu: true quando aberto pelo menu principal (VOLTAR fecha tudo).
function pause.abrir(paginaInicial, doMenu)
    aberto = true
    pagina = paginaInicial == "config" and "config" or "principal"
    origemMenu = doMenu == true
    principalSel = 1
    ponteiro = nil
    esperando = nil
    bufferValor = ""
    love.keyboard.setTextInput(false)
    confirmaSair = 0
    confirma = {}
    sujo = true
end

function pause.fechar()
    aberto = false
    ponteiro = nil
    esperando = nil
    bufferValor = ""
    love.keyboard.setTextInput(false)
    confirmaSair = 0
end

function pause.estaAberto()
    return aberto
end

function pause.atualizar(dt)
    for id, t in pairs(confirma) do
        confirma[id] = t - dt
        if confirma[id] <= 0 then confirma[id] = nil end
    end

    if confirmaSair > 0 then
        confirmaSair = math.max(0, confirmaSair - dt)
    end

    tema.atualizarToasts(dt)
end

--------------------------------------------------
-- LAYOUT
--------------------------------------------------

local function geoPrincipal()
    local W, H = love.graphics.getDimensions()
    local k = tema.escala()
    local bw = math.min(W - 40, 400 * k)
    local bh = 64 * k
    local gap = 14 * k
    local total = #BOTOES_PRINCIPAIS * bh + (#BOTOES_PRINCIPAIS - 1) * gap
    local topo = math.max(110 * k, (H - total) / 2 + 46 * k)
    local x = (W - bw) / 2
    local lista = {}

    for i = 1, #BOTOES_PRINCIPAIS do
        lista[i] = {x = x, y = topo + (i - 1) * (bh + gap), w = bw, h = bh}
    end

    return {W = W, H = H, k = k, botoes = lista, topo = topo, bw = bw}
end

local function alturaLinha(op, k)
    return (op.desc and 66 or 52) * k
end

local escalaConstruida = nil

-- "sujo" cobre trocas de aba etc.; isso aqui cobre o caso em que só a
-- ESCALA da interface mudou (o jogador arrastou o slider "Tamanho da
-- interface" dentro do próprio menu) — sem isso, as posições calculadas
-- em reconstruir() ficam da escala antiga e tudo desalinha até trocar de
-- aba (ou sair e entrar) de novo.
local function precisaReconstruir()
    return sujo or tema.escala() ~= escalaConstruida
end

local function reconstruir()
    local k = tema.escala()
    local aba = opcoes.abas[abaIdx]

    entradas = {}
    local y = 0
    local lista = opcoes.daAba(aba.id, love.system.getOS())

    for _, e in ipairs(lista) do
        local h

        if e.tipo == "secao" then
            h = 40 * k
        else
            h = alturaLinha(e.op, k)
        end

        e.y = y
        e.h = h
        y = y + h + (e.tipo == "secao" and 0 or 6 * k)
        entradas[#entradas + 1] = e
    end

    alturaTotal = y
    sujo = false
    escalaConstruida = k

    if selId then
        local existe = false

        for _, e in ipairs(entradas) do
            if e.op and e.op.id == selId then existe = true end
        end

        if not existe then selId = nil end
    end
end

local function geoConfig()
    local W, H = love.graphics.getDimensions()
    local k = tema.escala()
    local m = 14 * k
    local pw = math.min(W - 2 * m, 1020 * k)
    local px = (W - pw) / 2

    local g = {W = W, H = H, k = k, px = px, pw = pw}

    g.cabY = m
    g.cabH = 48 * k
    g.voltar = {x = px, y = g.cabY + 2 * k, w = 128 * k, h = 44 * k}

    g.tabsY = g.cabY + g.cabH + 8 * k
    g.tabsH = 42 * k

    local rodape = 30 * k
    g.listaX = px
    g.listaW = pw
    g.listaY = g.tabsY + g.tabsH + 10 * k
    g.listaH = H - g.listaY - rodape - m
    g.rodapeY = H - rodape - m + 6 * k

    return g
end

local function maxScroll(g)
    return math.max(0, alturaTotal - g.listaH)
end

-- Geometria do modal "digitar valor": caixa central com o texto sendo
-- digitado e 3 botões (Apagar / Cancelar / Confirmar). Calculada uma vez
-- só e reutilizada tanto pro desenho quanto pra detecção de toque nos
-- botões — assim eles nunca saem de sincronia um do outro.
local function geoEsperaValor(g)
    local k = g.k
    local largura = math.min(g.W - 40, 540 * k)
    local altura = 200 * k
    local x = (g.W - largura) / 2
    local y = (g.H - altura) / 2

    local caixaW = largura - 64 * k
    local caixaH = 46 * k
    local caixaX = x + (largura - caixaW) / 2
    local caixaY = y + 50 * k

    local dicaY = caixaY + caixaH + 12 * k

    local botaoH = 42 * k
    local espacoBotoes = 10 * k
    local botaoW = (caixaW - espacoBotoes * 2) / 3
    local botoesY = dicaY + 26 * k

    return {
        x = x, y = y, w = largura, h = altura,
        caixa = {x = caixaX, y = caixaY, w = caixaW, h = caixaH},
        dicaY = dicaY,
        apagar = {x = caixaX, y = botoesY, w = botaoW, h = botaoH},
        cancelar = {x = caixaX + botaoW + espacoBotoes, y = botoesY, w = botaoW, h = botaoH},
        confirmar = {x = caixaX + (botaoW + espacoBotoes) * 2, y = botoesY, w = botaoW, h = botaoH},
    }
end

local function scrollAtual()
    return scrolls[abaIdx] or 0
end

local function definirScroll(v, g)
    scrolls[abaIdx] = math.max(0, math.min(maxScroll(g), v))
end

-- Geometria dos controles de uma linha (usada no desenho e no clique).
local function geoLinha(op, x, y, w, h, k)
    local g = {x = x, y = y, w = w, h = h}
    local pad = 16 * k
    local cy = y + h / 2
    local dir = x + w - pad
    local t = op.tipo

    if t == "toggle" then
        g.ctrl = {x = dir - 54 * k, y = cy - 15 * k, w = 54 * k, h = 30 * k}
        g.esq = g.ctrl.x

    elseif t == "slider" or t == "fps" then
        local valW = 104 * k
        local btn = 26 * k
        local trackW = math.max(70 * k, math.min(230 * k, w * 0.24))

        g.val = {x = dir - valW, y = cy - 15 * k, w = valW, h = 30 * k}
        g.plus = {x = g.val.x - 8 * k - btn, y = cy - btn / 2, w = btn, h = btn}
        g.track = {x = g.plus.x - 8 * k - trackW, y = cy - 15 * k, w = trackW, h = 30 * k}
        g.minus = {x = g.track.x - 8 * k - btn, y = cy - btn / 2, w = btn, h = btn}
        g.esq = g.minus.x

    elseif t == "escolha" then
        local pw = math.min(250 * k, w * 0.36)
        g.ctrl = {x = dir - pw, y = cy - 17 * k, w = pw, h = 34 * k}
        g.esq = g.ctrl.x

    elseif t == "info" then
        local iw = math.min(w * 0.5, 440 * k)
        g.ctrl = {x = dir - iw, y = cy - 15 * k, w = iw, h = 30 * k}
        g.esq = g.ctrl.x

    else
        local bw = 150 * k
        g.ctrl = {x = dir - bw, y = cy - 18 * k, w = bw, h = 36 * k}
        g.esq = g.ctrl.x
    end

    if opcoes.podeAtalho(op) then
        g.atalho = {x = g.esq - 10 * k - 74 * k, y = cy - 13 * k, w = 74 * k, h = 26 * k}
    end

    local limite = g.atalho and g.atalho.x or g.esq
    g.rotuloW = math.max(40, limite - (x + pad) - 12 * k)

    return g
end

-- Retângulos das abas (com rolagem horizontal).
local function geoAbas(g)
    local k = g.k
    local fonte = tema.fonte(14 * k)
    local lista = {}
    local x = 0

    for i, aba in ipairs(opcoes.abas) do
        local w = fonte:getWidth(aba.nome) + 58 * k
        lista[i] = {x = x, y = g.tabsY, w = w, h = g.tabsH, i = i}
        x = x + w + 6 * k
    end

    local total = math.max(0, x - 6 * k)
    local visivel = g.pw
    local maxTab = math.max(0, total - visivel)

    tabScroll = math.max(0, math.min(maxTab, tabScroll))

    -- mantém a aba atual visível
    local a = lista[abaIdx]

    if a then
        if a.x < tabScroll then tabScroll = a.x end
        if a.x + a.w > tabScroll + visivel then tabScroll = a.x + a.w - visivel end
        tabScroll = math.max(0, math.min(maxTab, tabScroll))
    end

    local deslocamento = g.px - tabScroll

    if total < visivel then
        deslocamento = g.px + (visivel - total) / 2
    end

    for _, r in ipairs(lista) do r.x = r.x + deslocamento end

    return lista, total > visivel
end

--------------------------------------------------
-- AÇÕES
--------------------------------------------------

local function ctx()
    return {controles = ctrls}
end

local function converterAcao(acao)
    if acao == "alternar_pausa" then return "continuar" end
    return acao
end

local function iniciarEspera(tipo, op)
    esperando = {tipo = tipo, op = op}

    if tipo == "valor" and cfg then
        local v = opcoes.valor(op, cfg)
        bufferValor = (type(v) == "number") and tostring(v) or ""

        -- O primeiro caractere digitado substitui o valor atual (como
        -- selecionar tudo num campo de texto), em vez de emendar nele.
        esperando.substituir = true
        -- No Android chama o teclado virtual; no PC não muda nada visível,
        -- mas ativa o evento love.textinput (é por ele, não por
        -- love.keypressed, que os dígitos realmente chegam — layouts,
        -- IME e teclado virtual não passam de forma confiável pelas teclas).
        love.keyboard.setTextInput(true)
    else
        bufferValor = ""
    end
end

local function sairDoModoValor()
    if esperando and esperando.tipo == "valor" then
        love.keyboard.setTextInput(false)
    end

    esperando = nil
    bufferValor = ""
end

-- Compartilhados entre o atalho de teclado (Enter/Backspace) e os botões
-- tocáveis do modal (Confirmar/Apagar), pra não duplicar a lógica.
local function confirmarValorDigitado()
    local op = esperando.op
    local ok, erro = opcoes.definirValorDigitado(op, bufferValor, cfg)
    sairDoModoValor()
    return ok, erro
end

local function apagarUltimoDigito()
    if esperando then esperando.substituir = false end
    bufferValor = bufferValor:sub(1, -2)
end

local function ativarOpcao(op)
    if not cfg then return nil end

    local t = op.tipo

    if t == "tecla" then
        iniciarEspera("tecla", op)
        return nil

    elseif t == "botao" then
        iniciarEspera("botao", op)
        return nil

    elseif t == "info" then
        if op.copiavel then
            local texto = opcoes.texto(op, cfg, ctrls)
            love.system.setClipboardText(texto)
            tema.toast("Copiado: " .. texto)
        end

        return nil

    elseif t == "acao" and op.perigo then
        if confirma[op.id] then
            confirma[op.id] = nil
            sujo = true
            return converterAcao(opcoes.ativar(op, cfg, ctx()))
        end

        confirma[op.id] = 3
        return nil
    end

    local r = converterAcao(opcoes.ativar(op, cfg, ctx()))
    sujo = true
    return r
end

local function ativarPrincipal(id)
    if id == "continuar" then
        return "continuar"

    elseif id == "resetar" then
        return "resetar"

    elseif id == "sair" then
        if cfg and cfg.get("confirmarSair") == true and confirmaSair <= 0 then
            confirmaSair = 2.5
            return nil
        end

        confirmaSair = 0
        return "sair"

    elseif id == "config" then
        pagina = "config"
        sujo = true
        return nil
    end

    return nil
end

--------------------------------------------------
-- PONTEIRO (mouse e toque)
--------------------------------------------------

local function linhaEm(g, y)
    local localY = y - g.listaY + scrollAtual()

    for _, e in ipairs(entradas) do
        if e.tipo == "opcao" and localY >= e.y and localY <= e.y + e.h then
            return e
        end
    end

    return nil
end

local function fracaoNoTrack(geo, x)
    return (x - geo.track.x) / geo.track.w
end

local function alvoConfig(x, y)
    if precisaReconstruir() then reconstruir() end

    local g = geoConfig()
    local k = g.k

    if tema.dentro(x, y, g.voltar.x, g.voltar.y, g.voltar.w, g.voltar.h) then
        return {t = "voltar"}
    end

    if y >= g.tabsY and y <= g.tabsY + g.tabsH then
        for _, r in ipairs((geoAbas(g))) do
            if tema.dentro(x, y, r.x, r.y, r.w, r.h) then
                return {t = "aba", i = r.i, tabs = true}
            end
        end

        return {t = "abas", tabs = true}
    end

    if tema.dentro(x, y, g.listaX, g.listaY, g.listaW, g.listaH) then
        local e = linhaEm(g, y)

        if e then
            local gy = g.listaY + e.y - scrollAtual()
            local geo = geoLinha(e.op, g.listaX, gy, g.listaW, e.h, k)
            local op = e.op

            if geo.atalho and tema.dentro(x, y, geo.atalho.x, geo.atalho.y, geo.atalho.w, geo.atalho.h) then
                return {t = "atalho", e = e}
            end

            if op.tipo == "slider" or op.tipo == "fps" then
                if tema.dentro(x, y, geo.minus.x, geo.minus.y, geo.minus.w, geo.minus.h) then
                    return {t = "menos", e = e}
                end

                if tema.dentro(x, y, geo.plus.x, geo.plus.y, geo.plus.w, geo.plus.h) then
                    return {t = "mais", e = e}
                end

                if geo.val and tema.dentro(x, y, geo.val.x, geo.val.y, geo.val.w, geo.val.h) then
                    return {t = "valor", e = e}
                end

                local tr = geo.track

                if tema.dentro(x, y, tr.x - 12 * k, tr.y, tr.w + 24 * k, tr.h) then
                    return {t = "slider", e = e, geo = geo}
                end
            end

            if op.tipo == "escolha" and geo.ctrl
            and tema.dentro(x, y, geo.ctrl.x, geo.ctrl.y, geo.ctrl.w, geo.ctrl.h) then
                local meio = geo.ctrl.x + geo.ctrl.w / 2
                return {t = "escolha", e = e, lado = x < meio and -1 or 1}
            end

            if geo.ctrl and tema.dentro(x, y, geo.ctrl.x, geo.ctrl.y, geo.ctrl.w, geo.ctrl.h) then
                return {t = "ctrl", e = e}
            end

            return {t = "linha", e = e}
        end

        return {t = "lista"}
    end

    return nil
end

local function alvoPrincipal(x, y)
    local g = geoPrincipal()

    for i, r in ipairs(g.botoes) do
        if tema.dentro(x, y, r.x, r.y, r.w, r.h) then
            return {t = "principal", i = i}
        end
    end

    return nil
end

local function aplicarSlider(alvo, x)
    return opcoes.definirFracao(alvo.e.op, fracaoNoTrack(alvo.geo, x), cfg)
end

local function pressionar(x, y, id)
    if not aberto then return end

    if esperando then

        if esperando.tipo == "valor" then
            local g = geoEsperaValor(geoConfig())

            if tema.dentro(x, y, g.apagar.x, g.apagar.y, g.apagar.w, g.apagar.h) then
                apagarUltimoDigito()
                ponteiro = {id = id, cancelado = true}
                return
            end

            if tema.dentro(x, y, g.cancelar.x, g.cancelar.y, g.cancelar.w, g.cancelar.h) then
                sairDoModoValor()
                ponteiro = {id = id, cancelado = true}
                return
            end

            if tema.dentro(x, y, g.confirmar.x, g.confirmar.y, g.confirmar.w, g.confirmar.h) then
                local ok, erro = confirmarValorDigitado()
                ponteiro = {id = id, cancelado = true, acaoAoSoltar = ok and "configuracao" or nil}

                if not ok then
                    tema.toast(erro or "Valor inválido", "erro")
                end

                return
            end

            -- clique dentro da própria caixa de texto: não faz nada (mantém
            -- o modo aberto), só sai se for realmente fora do modal.
            if tema.dentro(x, y, g.x, g.y, g.w, g.h) then
                ponteiro = {id = id, cancelado = true}
                return
            end
        end

        -- tocar fora cancela a espera
        sairDoModoValor()
        ponteiro = {id = id, cancelado = true}
        return
    end

    local alvo

    if pagina == "principal" then
        alvo = alvoPrincipal(x, y)
    else
        alvo = alvoConfig(x, y)
    end

    ponteiro = {id = id, x0 = x, y0 = y, ultY = y, ultX = x, moveu = false, alvo = alvo}

    if alvo and alvo.t == "slider" and cfg then
        aplicarSlider(alvo, x)
        ponteiro.mudou = true
        selId = alvo.e.op.id
    end
end

local function mover(x, y)
    if not aberto or not ponteiro or ponteiro.cancelado then return end

    local alvo = ponteiro.alvo

    if alvo and alvo.t == "slider" and cfg then
        aplicarSlider(alvo, x)
        ponteiro.mudou = true
        return
    end

    local k = tema.escala()

    if not ponteiro.moveu then
        if math.abs(y - ponteiro.y0) > 10 * k or math.abs(x - ponteiro.x0) > 10 * k then
            ponteiro.moveu = true
        end
    end

    if ponteiro.moveu and pagina == "config" then
        local g = geoConfig()

        if alvo and alvo.tabs then
            tabScroll = tabScroll - (x - ponteiro.ultX)
        else
            definirScroll(scrollAtual() - (y - ponteiro.ultY), g)
        end
    end

    ponteiro.ultY = y
    ponteiro.ultX = x
end

local function soltar()
    if not aberto or not ponteiro then return nil end

    local p = ponteiro
    ponteiro = nil

    if p.cancelado then return p.acaoAoSoltar end

    local alvo = p.alvo

    if alvo and alvo.t == "slider" then
        return p.mudou and "configuracao" or nil
    end

    if p.moveu or not alvo then return nil end

    if alvo.t == "principal" then
        principalSel = alvo.i
        return ativarPrincipal(BOTOES_PRINCIPAIS[alvo.i].id)

    elseif alvo.t == "voltar" then
        esperando = nil

        if origemMenu then return "continuar" end

        pagina = "principal"
        return nil

    elseif alvo.t == "aba" then
        abaIdx = alvo.i
        selId = nil
        sujo = true
        return nil

    elseif alvo.t == "atalho" then
        selId = alvo.e.op.id
        iniciarEspera("atalho", alvo.e.op)
        return nil

    elseif alvo.t == "menos" or alvo.t == "mais" then
        selId = alvo.e.op.id
        return opcoes.ajustar(alvo.e.op, alvo.t == "mais" and 1 or -1, cfg, ctx())

    elseif alvo.t == "escolha" then
        selId = alvo.e.op.id
        return opcoes.ajustar(alvo.e.op, alvo.lado, cfg, ctx())

    elseif alvo.t == "ctrl" then
        selId = alvo.e.op.id
        return ativarOpcao(alvo.e.op)

    elseif alvo.t == "valor" then
        selId = alvo.e.op.id
        iniciarEspera("valor", alvo.e.op)
        return nil

    elseif alvo.t == "linha" then
        selId = alvo.e.op.id
        return nil
    end

    return nil
end

--------------------------------------------------
-- EVENTOS DE MOUSE / TOQUE
--------------------------------------------------

local function hoverEm(x, y)
    if not aberto then return end

    hoverChave = nil

    if pagina == "principal" then
        local a = alvoPrincipal(x, y)

        if a then
            hoverChave = "p" .. a.i
            principalSel = a.i
        end
    else
        local a = alvoConfig(x, y)

        if a then
            if a.t == "aba" then hoverChave = "a" .. a.i
            elseif a.t == "voltar" then hoverChave = "voltar"
            elseif a.e then hoverChave = "l" .. a.e.op.id end
        end
    end
end

function pause.mousepressed(x, y, botao)
    if botao == 1 then pressionar(x, y, "mouse") end
end

function pause.mousemoved(x, y)
    hoverEm(x, y)
    mover(x, y)
end

function pause.mousemovedScroll() end

function pause.mousereleased(_, _, botao)
    if botao ~= 1 then return nil end
    return soltar()
end

function pause.touchpressed(id, x, y)
    if ponteiro and ponteiro.id ~= id then return end
    pressionar(x, y, id)
end

function pause.touchmoved(id, x, y)
    if ponteiro and ponteiro.id ~= id then return end
    mover(x, y)
end

function pause.touchreleased(id)
    if ponteiro and ponteiro.id ~= id then return nil end
    return soltar()
end

function pause.finalizarScroll()
    return false
end

-- Shift + roda ajusta a opção sob o cursor; a roda sozinha rola a lista.
function pause.wheelmoved(_, y)
    if not aberto or pagina ~= "config" or y == 0 then return nil end

    if precisaReconstruir() then reconstruir() end

    local mx, my = love.mouse.getPosition()
    local g = geoConfig()

    if tema.dentro(mx, my, g.listaX, g.listaY, g.listaW, g.listaH) then
        local e = linhaEm(g, my)

        if e and love.keyboard.isDown("lshift", "rshift") then
            local op = e.op

            if op.tipo == "slider" or op.tipo == "fps" or op.tipo == "escolha" or op.tipo == "toggle" then
                selId = op.id
                return opcoes.ajustar(op, y > 0 and 1 or -1, cfg, ctx())
            end
        end

        definirScroll(scrollAtual() - y * 70 * g.k, g)
    elseif my >= g.tabsY and my <= g.tabsY + g.tabsH then
        tabScroll = tabScroll - y * 70 * g.k
    end

    return nil
end

--------------------------------------------------
-- TECLADO / CONTROLE
--------------------------------------------------

local function opcoesVisiveis()
    local lista = {}

    for _, e in ipairs(entradas) do
        if e.tipo == "opcao" then lista[#lista + 1] = e end
    end

    return lista
end

local function garantirVisivel(e)
    local g = geoConfig()

    if e.y < scrollAtual() then
        definirScroll(e.y - 30 * g.k, g)
    elseif e.y + e.h > scrollAtual() + g.listaH then
        definirScroll(e.y + e.h - g.listaH + 10 * g.k, g)
    end
end

local function moverSelecao(delta)
    if precisaReconstruir() then reconstruir() end

    local lista = opcoesVisiveis()
    if #lista == 0 then return end

    local atual = 0

    for i, e in ipairs(lista) do
        if e.op.id == selId then atual = i end
    end

    local novo

    if atual == 0 then
        novo = delta > 0 and 1 or #lista
    else
        novo = math.max(1, math.min(#lista, atual + delta))
    end

    selId = lista[novo].op.id
    garantirVisivel(lista[novo])
end

local function opcaoSelecionada()
    for _, e in ipairs(entradas) do
        if e.op and e.op.id == selId then return e.op end
    end

    return nil
end

local function trocarAba(delta)
    abaIdx = abaIdx + delta

    if abaIdx < 1 then abaIdx = #opcoes.abas end
    if abaIdx > #opcoes.abas then abaIdx = 1 end

    selId = nil
    sujo = true
end

local function limparAtalhoDaTecla(tecla)
    for _, op in ipairs(opcoes.lista) do
        if opcoes.atalhoDe(op, cfg) == tecla then
            opcoes.removerAtalho(op, cfg)
        end
    end
end

-- Devolve consumido, acao.
function pause.receberTecla(tecla, config, controles)
    if not aberto then return false end

    cfg = config or cfg
    ctrls = controles or ctrls

    ------------------------------------------------
    -- ESPERANDO UMA TECLA
    ------------------------------------------------

    if esperando then
        local e = esperando

        if tecla == "escape" then
            sairDoModoValor()
            return true
        end

        if e.tipo == "valor" then

            if tecla == "return" or tecla == "kpenter" then
                local ok, erro = confirmarValorDigitado()

                if ok then
                    return true, "configuracao"
                end

                tema.toast(erro or "Valor inválido", "erro")
                return true
            end

            if tecla == "backspace" then
                apagarUltimoDigito()
                return true
            end

            -- dígitos, ponto e sinal chegam por pause.textinput(), não por
            -- aqui: é o caminho certo pra layout de teclado, IME e teclado
            -- virtual do Android funcionarem sem duplicar caracteres.
            return true
        end

        if e.tipo == "atalho" then
            esperando = nil

            if tecla == "delete" or tecla == "backspace" then
                opcoes.removerAtalho(e.op, cfg)
                tema.toast("Atalho removido")
            else
                local ok, motivo = opcoes.definirAtalho(e.op, tecla, cfg, ctrls)

                if ok then
                    tema.toast(e.op.nome .. " = " .. opcoes.nomeTecla(tecla), "ok")
                else
                    tema.toast(motivo, "erro")
                end
            end

            return true
        end

        if e.tipo == "tecla" then
            esperando = nil

            if ctrls and ctrls.definirTecla then
                limparAtalhoDaTecla(tecla)
                ctrls.definirTecla(e.op.lane, tecla, cfg)
                tema.toast("Lane " .. e.op.lane .. " = " .. opcoes.nomeTecla(tecla), "ok")
            end

            return true
        end

        return true
    end

    ------------------------------------------------
    -- PRINCIPAL
    ------------------------------------------------

    if pagina == "principal" then
        if tecla == "up" or tecla == "w" then
            principalSel = (principalSel - 2) % #BOTOES_PRINCIPAIS + 1
            return true

        elseif tecla == "down" or tecla == "s" then
            principalSel = principalSel % #BOTOES_PRINCIPAIS + 1
            return true

        elseif tecla == "return" or tecla == "kpenter" or tecla == "space" then
            return true, ativarPrincipal(BOTOES_PRINCIPAIS[principalSel].id)
        end

        -- ESC continua o jogo (tratado pelo main)
        return false
    end

    ------------------------------------------------
    -- CONFIGURAÇÕES
    ------------------------------------------------

    if precisaReconstruir() then reconstruir() end

    if tecla == "escape" then
        if origemMenu then return true, "continuar" end

        pagina = "principal"
        return true

    elseif tecla == "up" then
        moverSelecao(-1)
        return true

    elseif tecla == "down" then
        moverSelecao(1)
        return true

    elseif tecla == "left" or tecla == "right" then
        local op = opcaoSelecionada()

        if op then
            return true, converterAcao(opcoes.ajustar(op, tecla == "right" and 1 or -1, cfg, ctx()))
        end

        return true

    elseif tecla == "return" or tecla == "kpenter" or tecla == "space" then
        local op = opcaoSelecionada()

        if op then return true, ativarOpcao(op) end

        return true

    elseif tecla == "tab" then
        trocarAba(love.keyboard.isDown("lshift", "rshift") and -1 or 1)
        return true

    elseif tecla == "pagedown" then
        trocarAba(1)
        return true

    elseif tecla == "pageup" then
        trocarAba(-1)
        return true

    elseif tecla == "home" then
        definirScroll(0, geoConfig())
        return true

    elseif tecla == "end" then
        local g = geoConfig()
        definirScroll(maxScroll(g), g)
        return true

    elseif tecla == "f5" then
        local op = opcaoSelecionada()

        if op and opcoes.podeAtalho(op) then
            iniciarEspera("atalho", op)
        else
            tema.toast("Selecione uma opção que aceite atalho", "erro")
        end

        return true

    elseif tecla == "delete" then
        local op = opcaoSelecionada()

        if op and opcoes.atalhoDe(op, cfg) then
            opcoes.removerAtalho(op, cfg)
            tema.toast("Atalho removido")
        end

        return true
    end

    return false
end

-- Caracteres digitados de verdade (teclado físico em qualquer layout,
-- teclado virtual do Android, IME): love.keypressed não é confiável pra
-- isso (nomes de tecla mudam por layout/idioma, teclado virtual nem
-- sempre gera os mesmos códigos). Só processa algo quando o modo de
-- digitar valor está ativo; o resto do jogo não usa texto.
function pause.textinput(t)
    if not aberto or not esperando or esperando.tipo ~= "valor" then
        return false
    end

    local op = esperando.op

    -- Só caracteres que o campo aceita substituem o valor pré-preenchido.
    local aceito = t:match("^%d$") or t == "." or t == "," or t == "-"

    if aceito and esperando.substituir then
        bufferValor = ""
        esperando.substituir = false
    end

    if t:match("^%d$") then
        bufferValor = bufferValor .. t
        return true
    end

    if t == "." or t == "," then
        if not bufferValor:find("[.,]") then
            bufferValor = bufferValor .. "."
        end
        return true
    end

    if t == "-" then
        -- só faz sentido no começo, e só se a opção aceitar negativo
        if bufferValor == "" and (op.min or 0) < 0 then
            bufferValor = "-"
        end
        return true
    end

    -- qualquer outro caractere é ignorado (mas consumido, pra não vazar).
    return true
end

function pause.receberBotao(botao, config, controles)
    if not aberto then return false end

    cfg = config or cfg
    ctrls = controles or ctrls

    if esperando and esperando.tipo == "botao" then
        local e = esperando
        esperando = nil

        if ctrls and ctrls.definirBotao then
            ctrls.definirBotao(e.op.lane, botao, cfg)
            tema.toast("Lane " .. e.op.lane .. " = " .. string.upper(botao), "ok")
        end

        return true
    end

    if esperando then
        esperando = nil
        return true
    end

    -- navegação simples com D-pad / A / B
    if pagina == "principal" then
        if botao == "dpup" then
            principalSel = (principalSel - 2) % #BOTOES_PRINCIPAIS + 1
        elseif botao == "dpdown" then
            principalSel = principalSel % #BOTOES_PRINCIPAIS + 1
        elseif botao == "a" then
            return true, ativarPrincipal(BOTOES_PRINCIPAIS[principalSel].id)
        elseif botao == "b" or botao == "start" then
            return true, "continuar"
        end

        return true
    end

    if precisaReconstruir() then reconstruir() end

    if botao == "b" then
        if origemMenu then return true, "continuar" end

        pagina = "principal"
    elseif botao == "dpup" then
        moverSelecao(-1)
    elseif botao == "dpdown" then
        moverSelecao(1)
    elseif botao == "dpleft" or botao == "dpright" then
        local op = opcaoSelecionada()

        if op then
            return true, converterAcao(opcoes.ajustar(op, botao == "dpright" and 1 or -1, cfg, ctx()))
        end
    elseif botao == "a" then
        local op = opcaoSelecionada()

        if op then return true, ativarOpcao(op) end
    elseif botao == "leftshoulder" then
        trocarAba(-1)
    elseif botao == "rightshoulder" then
        trocarAba(1)
    end

    return true
end

--------------------------------------------------
-- DESENHO
--------------------------------------------------

local function suave(chave, alvo)
    local atual = animacao[chave] or alvo
    animacao[chave] = tema.aproximar(atual, alvo, love.timer.getDelta(), 14)
    return animacao[chave]
end

local function desenharPrincipal()
    local g = geoPrincipal()
    local k = g.k

    love.graphics.setColor(0.02, 0.02, 0.06, 0.74)
    love.graphics.rectangle("fill", 0, 0, g.W, g.H)

    love.graphics.setFont(tema.fonte(44 * k))
    tema.cor("texto")
    love.graphics.printf("PAUSADO", 0, g.topo - 104 * k, g.W, "center")

    if infoBeatmap ~= "" then
        local f = tema.fonte(16 * k)
        local largura = math.min(g.W - 40, 600 * k)

        love.graphics.setFont(f)
        tema.cor("mudo")
        love.graphics.printf(tema.ajustarTexto(f, infoBeatmap, largura),
            (g.W - largura) / 2, g.topo - 48 * k, largura, "center")
    end

    for i, b in ipairs(BOTOES_PRINCIPAIS) do
        local r = g.botoes[i]
        local sel = (hoverChave == "p" .. i) or (principalSel == i and not hoverChave)
        local texto = b.texto
        local estilo = b.estilo

        if b.id == "sair" and confirmaSair > 0 then
            texto = "TOQUE DE NOVO PARA CONFIRMAR"
            estilo = "perigo"
        end

        tema.botao(r.x, r.y, r.w, r.h, texto, {
            estilo = estilo,
            hover = suave("p" .. i, sel and 1 or 0),
            icone = b.icone,
            ativo = principalSel == i and not ehMobile(),
            pressionado = ponteiro ~= nil and ponteiro.alvo ~= nil
                and ponteiro.alvo.t == "principal" and ponteiro.alvo.i == i,
            fonte = tema.fonte(18 * k),
        })
    end

    if not ehMobile() then
        love.graphics.setFont(tema.fonte(13 * k))
        tema.cor("mudo", 0.8)
        love.graphics.printf("ESC continua   |   CIMA/BAIXO navegar   |   ENTER escolher",
            0, g.H - 34 * k, g.W, "center")
    end
end

local function desenharControle(op, geo, k, hover)
    local t = op.tipo
    local fonte = tema.fonte(15 * k)

    love.graphics.setFont(fonte)

    if t == "toggle" then
        local ligado = cfg.get(op.chave) == true
        tema.toggle(geo.ctrl.x, geo.ctrl.y, geo.ctrl.w, geo.ctrl.h, ligado,
            suave("t" .. op.id, ligado and 1 or 0))

    elseif t == "slider" or t == "fps" then
        local ativo = ponteiro ~= nil and ponteiro.alvo ~= nil
            and ponteiro.alvo.t == "slider" and ponteiro.alvo.e.op == op

        tema.botao(geo.minus.x, geo.minus.y, geo.minus.w, geo.minus.h, "", {hover = 0})
        tema.botao(geo.plus.x, geo.plus.y, geo.plus.w, geo.plus.h, "", {hover = 0})

        love.graphics.setLineWidth(2)
        tema.cor("texto")

        local m, p = geo.minus, geo.plus

        love.graphics.line(m.x + m.w * 0.28, m.y + m.h / 2, m.x + m.w * 0.72, m.y + m.h / 2)
        love.graphics.line(p.x + p.w * 0.28, p.y + p.h / 2, p.x + p.w * 0.72, p.y + p.h / 2)
        love.graphics.line(p.x + p.w / 2, p.y + p.h * 0.28, p.x + p.w / 2, p.y + p.h * 0.72)
        love.graphics.setLineWidth(1)

        tema.slider(geo.track.x, geo.track.y + geo.track.h / 2, geo.track.w,
            opcoes.fracao(op, cfg), ativo)

        tema.cor((t == "fps" and cfg.get(op.chave) == 0) and "acento2" or "texto")
        love.graphics.printf(opcoes.texto(op, cfg, ctrls), geo.val.x,
            geo.val.y + (geo.val.h - fonte:getHeight()) / 2, geo.val.w, "right")

    elseif t == "escolha" then
        local c = geo.ctrl

        tema.cor("painelClaro", 1)
        tema.retangulo("fill", c.x, c.y, c.w, c.h, c.h / 2)
        tema.icone("seta_esq", c.x + c.h * 0.5, c.y + c.h / 2, c.h * 0.5, "mudo")
        tema.icone("seta_dir", c.x + c.w - c.h * 0.5, c.y + c.h / 2, c.h * 0.5, "mudo")

        love.graphics.setFont(fonte)
        tema.cor("texto")
        love.graphics.printf(
            tema.ajustarTexto(fonte, opcoes.texto(op, cfg, ctrls), c.w - c.h * 1.2),
            c.x + c.h * 0.6, c.y + (c.h - fonte:getHeight()) / 2, c.w - c.h * 1.2, "center")

    elseif t == "info" then
        local c = geo.ctrl
        local f = tema.fonte(13 * k)

        love.graphics.setFont(f)
        tema.cor("acento2", 0.95)
        love.graphics.printf(
            tema.ajustarTexto(f, opcoes.texto(op, cfg, ctrls), c.w),
            c.x, c.y + (c.h - f:getHeight()) / 2, c.w, "right")

    else
        local c = geo.ctrl
        local texto = op.texto
        local estilo = op.perigo and "perigo" or "secundario"
        local esperandoEste = esperando ~= nil and esperando.op == op

        if type(texto) ~= "string" then texto = "EXECUTAR" end

        if t == "tecla" then
            texto = esperandoEste and "APERTE UMA TECLA..." or opcoes.texto(op, cfg, ctrls)
            estilo = esperandoEste and "primario" or "secundario"
        elseif t == "botao" then
            texto = esperandoEste and "APERTE UM BOTÃO..." or opcoes.texto(op, cfg, ctrls)
            estilo = esperandoEste and "primario" or "secundario"
        elseif t == "acao" and op.perigo and confirma[op.id] then
            texto = "CONFIRMAR?"
        end

        tema.botao(c.x, c.y, c.w, c.h, texto, {
            estilo = estilo,
            hover = hover and 1 or 0,
            fonte = tema.fonte(13 * k),
            ativo = esperandoEste,
        })
    end
end

local function desenharAtalho(op, geo, k, selecionado, hover)
    if not geo.atalho then return end

    local tecla = opcoes.atalhoDe(op, cfg)
    local aguardando = esperando ~= nil and esperando.tipo == "atalho" and esperando.op == op

    if not (tecla or selecionado or hover or aguardando) then return end

    local r = geo.atalho
    local f = tema.fonte(12 * k)
    local ty = r.y + (r.h - f:getHeight()) / 2

    love.graphics.setFont(f)

    if aguardando then
        tema.cor("acento", 0.9)
        tema.retangulo("fill", r.x, r.y, r.w, r.h, r.h / 2)
        tema.cor("texto")
        love.graphics.printf("APERTE...", r.x, ty, r.w, "center")

    elseif tecla then
        tema.cor("acento2", 0.20)
        tema.retangulo("fill", r.x, r.y, r.w, r.h, r.h / 2)
        tema.cor("acento2", 0.9)
        tema.retangulo("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, r.h / 2)
        tema.cor("texto")
        love.graphics.printf(opcoes.nomeTecla(tecla), r.x, ty, r.w, "center")

    else
        love.graphics.setColor(1, 1, 1, 0.07)
        tema.retangulo("fill", r.x, r.y, r.w, r.h, r.h / 2)
        tema.cor("mudo")
        love.graphics.printf("+ ATALHO", r.x, ty, r.w, "center")
    end
end

local function desenharLinha(e, g, gy)
    local op = e.op
    local k = g.k
    local geo = geoLinha(op, g.listaX, gy, g.listaW, e.h, k)
    local selecionado = selId == op.id
    local hover = hoverChave == "l" .. op.id
    local a = suave("r" .. op.id, (selecionado and 1) or (hover and 0.6) or 0)

    love.graphics.setColor(0.14 + 0.05 * a, 0.15 + 0.03 * a, 0.27 + 0.10 * a, 0.55 + 0.25 * a)
    tema.retangulo("fill", geo.x, geo.y, geo.w, geo.h, 12 * k)

    if selecionado then
        tema.cor("acento", 0.9)
        love.graphics.setLineWidth(2)
        tema.retangulo("line", geo.x + 1, geo.y + 1, geo.w - 2, geo.h - 2, 12 * k)
        love.graphics.setLineWidth(1)
    end

    local fLabel = tema.fonte(17 * k)
    local fDesc = tema.fonte(12 * k)
    local pad = 16 * k
    local ly = op.desc and (geo.y + 10 * k) or (geo.y + (geo.h - fLabel:getHeight()) / 2)

    love.graphics.setFont(fLabel)
    tema.cor("texto")
    love.graphics.print(tema.ajustarTexto(fLabel, op.nome, geo.rotuloW), geo.x + pad, ly)

    if op.desc then
        love.graphics.setFont(fDesc)
        tema.cor("mudo")
        love.graphics.print(tema.ajustarTexto(fDesc, op.desc, geo.rotuloW),
            geo.x + pad, ly + fLabel:getHeight() + 2 * k)
    end

    desenharAtalho(op, geo, k, selecionado, hover)
    desenharControle(op, geo, k, hover)
end

local function desenharEspera(g)
    local k = g.k
    local ehValor = esperando.tipo == "valor"

    if ehValor then
        local op = esperando.op
        local ge = geoEsperaValor(g)

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, g.W, g.H)

        tema.painel(ge.x, ge.y, ge.w, ge.h)

        love.graphics.setFont(tema.fonte(18 * k))
        tema.cor("texto")
        love.graphics.printf(
            "NOVO VALOR - " .. op.nome,
            ge.x + 16 * k, ge.y + 16 * k, ge.w - 32 * k, "center")

        tema.cor("painelClaro", 1)
        tema.retangulo("fill", ge.caixa.x, ge.caixa.y, ge.caixa.w, ge.caixa.h, 8 * k)

        -- cursor piscando no fim do texto
        local cursor = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "|" or ""

        love.graphics.setFont(tema.fonte(22 * k))
        tema.cor("texto")
        love.graphics.printf(
            (bufferValor == "" and "0" or bufferValor) .. cursor,
            ge.caixa.x + 14 * k, ge.caixa.y + (ge.caixa.h - 22 * k) / 2, ge.caixa.w - 28 * k, "left")

        local faixa

        if op.tipo == "fps" then
            faixa = "0 = ilimitado, ou de 15 a 1000"
        else
            local casas = op.casas or 0
            faixa = string.format(
                "de %." .. casas .. "f a %." .. casas .. "f%s",
                op.min, op.max, op.unidade or "")
        end

        love.graphics.setFont(tema.fonte(13 * k))
        tema.cor("mudo")
        love.graphics.printf(faixa, ge.x + 16 * k, ge.dicaY, ge.w - 32 * k, "center")

        tema.botao(ge.apagar.x, ge.apagar.y, ge.apagar.w, ge.apagar.h, "APAGAR",
            {estilo = "secundario", fonte = tema.fonte(14 * k)})
        tema.botao(ge.cancelar.x, ge.cancelar.y, ge.cancelar.w, ge.cancelar.h, "CANCELAR",
            {estilo = "secundario", fonte = tema.fonte(14 * k)})
        tema.botao(ge.confirmar.x, ge.confirmar.y, ge.confirmar.w, ge.confirmar.h, "CONFIRMAR",
            {estilo = "primario", fonte = tema.fonte(14 * k)})

        return
    end

    local largura = math.min(g.W - 40, 540 * k)
    local altura = 130 * k
    local x = (g.W - largura) / 2
    local y = (g.H - altura) / 2

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, g.W, g.H)

    tema.painel(x, y, largura, altura)

    local titulo = "NOVO ATALHO"
    local ajuda = "Aperte a tecla desejada.  ESC cancela  |  DEL remove o atalho"

    if esperando.tipo == "tecla" then
        titulo = "NOVA TECLA"
        ajuda = "Aperte a nova tecla.  ESC cancela"
    elseif esperando.tipo == "botao" then
        titulo = "NOVO BOTÃO"
        ajuda = "Aperte o botão do controle.  Toque fora para cancelar"
    end

    love.graphics.setFont(tema.fonte(20 * k))
    tema.cor("texto")
    love.graphics.printf(titulo .. " - " .. esperando.op.nome, x + 16 * k, y + 22 * k, largura - 32 * k, "center")

    love.graphics.setFont(tema.fonte(14 * k))
    tema.cor("mudo")
    love.graphics.printf(ajuda, x + 16 * k, y + 76 * k, largura - 32 * k, "center")
end

local function desenharConfig()
    if precisaReconstruir() then reconstruir() end

    local g = geoConfig()
    local k = g.k

    love.graphics.setColor(0.02, 0.02, 0.06, 0.94)
    love.graphics.rectangle("fill", 0, 0, g.W, g.H)

    -- cabeçalho
    tema.botao(g.voltar.x, g.voltar.y, g.voltar.w, g.voltar.h, "VOLTAR", {
        hover = suave("voltar", hoverChave == "voltar" and 1 or 0),
        icone = "voltar",
        fonte = tema.fonte(15 * k),
    })

    local ft = tema.fonte(26 * k)
    love.graphics.setFont(ft)
    tema.cor("texto")
    love.graphics.printf("CONFIGURAÇÕES", g.px, g.cabY + (g.cabH - ft:getHeight()) / 2, g.pw, "center")

    -- abas
    local abas = geoAbas(g)
    local fa = tema.fonte(14 * k)

    love.graphics.setScissor(g.px, g.tabsY - 2, g.pw, g.tabsH + 4)

    for i, r in ipairs(abas) do
        local aba = opcoes.abas[i]
        local ativa = i == abaIdx
        local h = suave("a" .. i, (ativa and 1) or (hoverChave == "a" .. i and 0.6) or 0)

        if ativa then
            tema.cor("acento", 1)
        else
            love.graphics.setColor(0.14 + 0.05 * h, 0.15 + 0.05 * h, 0.27 + 0.08 * h, 0.85)
        end

        tema.retangulo("fill", r.x, r.y, r.w, r.h, r.h / 2)
        tema.icone(aba.icone, r.x + r.h * 0.55, r.y + r.h / 2, r.h * 0.42, ativa and "texto" or "mudo")

        love.graphics.setFont(fa)
        tema.cor(ativa and "texto" or "mudo")
        love.graphics.print(aba.nome, r.x + r.h * 0.95, r.y + (r.h - fa:getHeight()) / 2)
    end

    love.graphics.setScissor()

    -- lista
    love.graphics.setScissor(g.listaX - 4, g.listaY, g.listaW + 8, g.listaH)

    local rolagem = scrollAtual()
    local fs = tema.fonte(13 * k)

    for _, e in ipairs(entradas) do
        local gy = g.listaY + e.y - rolagem

        if gy + e.h >= g.listaY - 4 and gy <= g.listaY + g.listaH + 4 then
            if e.tipo == "secao" then
                local nome = string.upper(e.nome)
                local tw = fs:getWidth(nome)

                love.graphics.setFont(fs)
                tema.cor("acento2", 0.95)
                love.graphics.print(nome, g.listaX + 10 * k, gy + e.h - fs:getHeight() - 6 * k)
                tema.cor("acento2", 0.20)
                love.graphics.rectangle("fill", g.listaX + 22 * k + tw,
                    gy + e.h - 12 * k, math.max(0, g.listaW - tw - 34 * k), 1)
            else
                desenharLinha(e, g, gy)
            end
        end
    end

    love.graphics.setScissor()

    -- barra de rolagem
    local maxS = maxScroll(g)

    if maxS > 0 then
        local barraH = math.max(30 * k, g.listaH * (g.listaH / alturaTotal))
        local barraY = g.listaY + (g.listaH - barraH) * (rolagem / maxS)

        love.graphics.setColor(1, 1, 1, 0.10)
        tema.retangulo("fill", g.listaX + g.listaW + 2, barraY, 4 * k, barraH, 2 * k)
    end

    -- rodapé
    love.graphics.setFont(tema.fonte(12 * k))
    tema.cor("mudo", 0.85)

    local dica = "Toque para ajustar   |   Arraste para rolar   |   Toque numa linha e depois em + ATALHO"

    if not ehMobile() then
        dica = "CIMA/BAIXO navegar   ESQ/DIR ajustar   ENTER ativar   TAB trocar aba   F5 atalho   DEL remove atalho"
    end

    love.graphics.printf(dica, g.px, g.rodapeY, g.pw, "center")

    if esperando then desenharEspera(g) end
end

function pause.desenhar(config, controles)
    if not aberto then return end

    cfg = config or cfg
    ctrls = controles or ctrls

    if pagina == "principal" then
        desenharPrincipal()
    else
        desenharConfig()
    end

    tema.desenharToasts()
    love.graphics.setColor(1, 1, 1, 1)
end

return pause
