-- Renderiza o jogo inteiro numa resolução VIRTUAL (um Canvas) e depois
-- escala esse canvas pra resolução real da janela/tela.
--
-- A resolução virtual é sempre um FATOR da resolução real do usuário
-- (largura E altura multiplicadas pelo MESMO número), nunca um tamanho
-- fixo tipo "1280x720": assim o canvas sempre tem exatamente a mesma
-- proporção da tela real, então NUNCA precisa de letterbox (barra preta) e
-- a imagem sempre preenche a tela inteira, sem distorcer.
--
-- fator < 1 -> renderiza em MENOS pixels que a tela (upscale no final,
--              ganha desempenho, perde nitidez). Ex.: 0.5 = metade da
--              largura e da altura reais (1/4 dos pixels totais).
-- fator > 1 -> renderiza em MAIS pixels que a tela (supersampling, mais
--              nítido/suaviza serrilhado, custa mais desempenho).
-- fator = 1 -> nativa, pixel a pixel.
--
-- O fator fica sempre entre 1/8 e 8 (ver LIMITE_FATOR), então o
-- escalonamento nunca passa de 8x a resolução do usuário em nenhuma
-- direção.
--
-- IMPORTANTE: love.graphics.getWidth/getHeight/getDimensions ficam
-- sobrescritas o TEMPO TODO (não só durante o desenho), reportando o
-- tamanho VIRTUAL. É necessário porque código fora do love.draw também
-- consulta essas funções — o cálculo de lane no touch (main.lua) e o
-- hit-test dos botões do menu, por exemplo — e precisa enxergar o MESMO
-- tamanho que foi usado pra desenhar o layout, senão o toque erra o alvo.

local resolucao = {}

local LIMITE_FATOR_MIN = 1 / 8
local LIMITE_FATOR_MAX = 8

-- 1 = nativa. Sempre o mesmo fator nos dois eixos -> proporção da tela do
-- usuário é sempre preservada exatamente.
local fatorAtual = 1

local canvas = nil
local escala, offsetX, offsetY = 1, 0, 0
local canvasW, canvasH = 0, 0

local getWidthOriginal = love.graphics.getWidth
local getHeightOriginal = love.graphics.getHeight
local getDimensionsOriginal = love.graphics.getDimensions

local function limitarFator(fator)
    fator = tonumber(fator) or 1
    return math.max(LIMITE_FATOR_MIN, math.min(LIMITE_FATOR_MAX, fator))
end

-- Fator equivalente a ~1080p (1920x1080, ~2.07 milhões de pixels), mantendo
-- a proporção REAL da tela do usuário. Ex.: numa tela 2340x1080 (proporção
-- bem alongada, comum em celular), isso NÃO vira 1920x1080 (que é 16:9) —
-- vira a mesma proporção 2340:1080, só redimensionada pro total de pixels
-- ficar equivalente a 1080p.
local function fatorPara1080p(realW, realH)
    if realW <= 0 or realH <= 0 then return 1 end
    local pixelsAlvo = 1920 * 1080
    local pixelsReais = realW * realH
    return math.sqrt(pixelsAlvo / pixelsReais)
end

-- Opções mostradas na tela de opções. Cada uma é resolvida pra um fator
-- (ver resolverFator) na hora de aplicar, porque "1080p" depende da tela do
-- usuário e não pode virar um número fixo aqui.
resolucao.predefinidas = {
    {"0.5",    "50% (economia)"},
    {"0.75",   "75%"},
    {"nativa", "Nativa (100%)"},
    {"1080p",  "~1080p"},
    {"1.5",    "150%"},
    {"2",      "200%"},
    {"4",      "400%"},
    {"8",      "800%"},
}

local function resolverFator(valor, realW, realH)
    if valor == "nativa" or valor == nil then
        return 1
    end

    if valor == "1080p" then
        return limitarFator(fatorPara1080p(realW, realH))
    end

    local numero = tonumber(valor)
    if numero then
        return limitarFator(numero)
    end

    return 1
end

-- Recalcula escala/offset (letterbox) a partir do tamanho real ATUAL da
-- janela. Como o canvas usa sempre a MESMA proporção da tela (fator igual
-- nos dois eixos), escala fica idêntica em X e Y e offsetX/offsetY dão
-- exatamente 0 — ou seja, sem barras, preenchendo a tela inteira. Ainda
-- assim calculamos do jeito genérico (min + centralizar) por segurança,
-- caso a tela real mude de proporção (ex.: rotação) entre o cálculo do
-- canvas e este frame.
local function recalcularEscala()
    local realW, realH = getDimensionsOriginal()

    if realW <= 0 or realH <= 0 or canvasW <= 0 or canvasH <= 0 then
        escala, offsetX, offsetY = 1, 0, 0
        return
    end

    escala = math.min(realW / canvasW, realH / canvasH)
    offsetX = (realW - canvasW * escala) / 2
    offsetY = (realH - canvasH * escala) / 2
end

local function recriarCanvas()
    local realW, realH = getDimensionsOriginal()

    canvasW = math.max(1, math.floor(realW * fatorAtual + 0.5))
    canvasH = math.max(1, math.floor(realH * fatorAtual + 0.5))

    if canvas then
        canvas:release()
    end

    canvas = love.graphics.newCanvas(canvasW, canvasH)
    canvas:setFilter("linear", "linear")

    recalcularEscala()
end

-- Lê "resolucaoCanvas" (config) e recria o canvas só se o valor mudou (ou
-- se a tela mudou de proporção desde a última vez — ex.: "1080p" e
-- "nativa" dependem da resolução/proporção real do usuário).
local valorAplicado = nil
local realWAplicado, realHAplicado = nil, nil

function resolucao.aplicar(config)
    local valor = (config and config.get and config.get("resolucaoCanvas")) or "nativa"
    local realW, realH = getDimensionsOriginal()

    if valor == valorAplicado
    and realW == realWAplicado
    and realH == realHAplicado
    and canvas then
        return
    end

    valorAplicado = valor
    realWAplicado, realHAplicado = realW, realH

    fatorAtual = resolverFator(valor, realW, realH)

    recriarCanvas()
end

-- Chamado por love.resize. Em janelas normais (PC) é o principal gatilho
-- pra reagir a uma mudança de tamanho; no Android/fullscreen serve como
-- reforço, mas o antesDesenhar() por frame já cobre o caso de não disparar
-- (comum quando resizable = false).
function resolucao.aoRedimensionar(_, _)
    if not canvas then
        return
    end

    -- A proporção real pode ter mudado (rotação de tela, por exemplo): o
    -- fator continua o mesmo, mas "nativa"/"1080p" dependem da resolução
    -- real, então recalculamos o fator e recriamos o canvas do zero.
    local realW, realH = getDimensionsOriginal()
    fatorAtual = resolverFator(valorAplicado, realW, realH)
    recriarCanvas()
end

function resolucao.antesDesenhar()
    if not canvas then
        recriarCanvas()
    else
        -- Barato (só umas divisões) e garante que a escala nunca fica
        -- desatualizada mesmo se love.resize não disparar nesta plataforma.
        local realW, realH = getDimensionsOriginal()
        local canvasEsperadoW = math.max(1, math.floor(realW * fatorAtual + 0.5))
        local canvasEsperadoH = math.max(1, math.floor(realH * fatorAtual + 0.5))

        if canvasEsperadoW ~= canvasW or canvasEsperadoH ~= canvasH then
            -- A tela real mudou de tamanho/proporção desde a última vez
            -- (ex.: rotação) — recalcula o fator (importante pro "1080p",
            -- que depende da proporção real) e recria o canvas.
            fatorAtual = resolverFator(valorAplicado, realW, realH)
            recriarCanvas()
        else
            recalcularEscala()
        end
    end

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
end

function resolucao.depoisDesenhar()
    love.graphics.setCanvas()
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, offsetX, offsetY, 0, escala, escala)
end

-- Sobrescritas PERMANENTES: qualquer parte do jogo (desenho, update, touch,
-- hit-test de menu) que consultar o tamanho da tela deve enxergar sempre o
-- tamanho VIRTUAL — é o único jeito de o toque e o layout baterem certo.
love.graphics.getWidth = function() return canvasW > 0 and canvasW or getWidthOriginal() end
love.graphics.getHeight = function() return canvasH > 0 and canvasH or getHeightOriginal() end
love.graphics.getDimensions = function()
    if canvasW > 0 and canvasH > 0 then
        return canvasW, canvasH
    end
    return getDimensionsOriginal()
end

-- Converte uma coordenada real de mouse/touch (tela/janela) pra coordenada
-- virtual (a que o resto do jogo entende), descontando o letterbox (que,
-- na prática, deve dar sempre 0/0 agora que a proporção bate exatamente).
function resolucao.paraVirtual(x, y)
    if not canvas or escala == 0 then
        return x, y
    end

    return (x - offsetX) / escala, (y - offsetY) / escala
end

-- Mesma conversão, mas para um DELTA (dx, dy) de movimento: não tem offset
-- pra descontar, só a escala.
function resolucao.paraVirtualDelta(dx, dy)
    if not canvas or escala == 0 then
        return dx, dy
    end

    return dx / escala, dy / escala
end

return resolucao
