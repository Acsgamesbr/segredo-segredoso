local chart = {}

local indiceNotas = require("notas_index")

local notas = {}
local tempoMusica = 0
local velocidade = 500
local configuracao = nil
local duracaoTotal = 0
local bpm = nil
local offsetBpm = 0

function chart.definirBpm(novoBpm, novoOffset)
    bpm = (type(novoBpm) == "number" and novoBpm > 0) and novoBpm or nil
    offsetBpm = tonumber(novoOffset) or 0
end

function chart.getBpm() return bpm end
function chart.getOffsetBpm() return offsetBpm end
function chart.temBpm() return bpm ~= nil end

-- Duração de uma batida, em segundos. Sem BPM no beatmap (arquivo antigo,
-- sem [TimingPoints], ou seção vazia), cai num valor de referência (120
-- BPM) em vez de travar tudo que depende disso.
function chart.duracaoBatida()
    if bpm and bpm > 0 then return 60 / bpm end
    return 60 / 120
end

function chart.carregar(novasNotas)
    notas = novasNotas or {}
    indiceNotas.resetar(notas)
    tempoMusica = 0
    duracaoTotal = 0
    bpm = nil
    offsetBpm = 0
    for _, nota in ipairs(notas) do
        nota.hit = false
        nota.judged = false
        local inicio = tonumber(nota.time) or 0
        local duracao = tonumber(nota.duration or nota.duracao) or 0
        duracaoTotal = math.max(duracaoTotal, inicio + duracao)
    end
end

function chart.resetar(delay)
    delay = tonumber(delay) or 0
    tempoMusica = -delay
    indiceNotas.resetar(notas)
    for _, nota in ipairs(notas) do
        nota.hit = false
        nota.judged = false
        nota.holdActive = false
        nota.holdFailed = false
    end
end

function chart.atualizar(dt)
    if type(dt) == "number" then tempoMusica = tempoMusica + dt end
end

-- "Velocidade" da correção suave (por segundo) e o limiar acima do qual
-- a diferença é tratada como um salto de verdade (seek, retomar do pause,
-- trocar de beatmap) em vez de ruído normal do relógio de áudio.
local CORRECAO_SUAVE = 10
local LIMIAR_RESSINCRONIA = 0.15

-- Sincroniza tempoMusica com o tempo real do áudio (source:tell()).
--
-- Sem `dt`: encaixe direto (usado nos pontos que fazem um "salto"
-- legítimo, como retomar do pause ou fechar o editor de HUD).
--
-- Com `dt`: correção suave. source:tell() só atualiza em blocos do
-- driver de áudio — bem mais devagar que os quadros de vídeo (180 Hz,
-- por exemplo) — então travar nele a cada chamada de love.update faz as
-- notas "pularem" em vez de caírem fluidas. Em vez disso, o relógio
-- avança por conta própria (chart.atualizar) e aqui só é puxado aos
-- poucos na direção do tempo real, o que apaga o degrau sem deixar a
-- música e as notas saírem de sincronia.
function chart.sincronizarTempo(tempo, dt)
    if type(tempo) ~= "number" then return end

    local diferenca = tempo - tempoMusica

    if type(dt) ~= "number" or math.abs(diferenca) > LIMIAR_RESSINCRONIA then
        tempoMusica = tempo
        return
    end

    tempoMusica = tempoMusica + diferenca * math.min(1, CORRECAO_SUAVE * dt)
end

function chart.getNotas() return notas end
function chart.getTempo() return tempoMusica end
function chart.getVelocidade() return velocidade end

function chart.setVelocidade(novaVelocidade)
    novaVelocidade = tonumber(novaVelocidade)
    if novaVelocidade and novaVelocidade > 0 then
        velocidade = math.max(1, math.min(5000, novaVelocidade))
    end
end

function chart.temNotas() return #notas > 0 end
function chart.getQuantidadeNotas() return #notas end
function chart.getDuracaoTotal() return duracaoTotal end

local function limiteTempoVisivel(margemPixels)
    margemPixels = tonumber(margemPixels) or 100
    return margemPixels / math.max(1, velocidade)
end

local function lowerBound(tempo)
    local lo, hi = 1, #notas + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local valor = tonumber(notas[mid].time) or math.huge
        if valor < tempo then lo = mid + 1 else hi = mid end
    end
    return lo
end

local function upperBound(tempo)
    local lo, hi = 1, #notas + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local valor = tonumber(notas[mid].time) or math.huge
        if valor <= tempo then lo = mid + 1 else hi = mid end
    end
    return lo - 1
end

function chart.getIntervaloVisivel(margemPixels)
    if #notas == 0 then return 1, 0 end
    local margem = limiteTempoVisivel(margemPixels)
    return lowerBound(tempoMusica - margem), upperBound(tempoMusica + margem)
end

-- Tempos (em segundos, no mesmo relógio de chart.getTempo()) de cada
-- batida da música que cabe na janela visível. Uma batida a cada
-- chart.duracaoBatida(), alinhadas em offsetBpm (o instante do primeiro
-- timing point do beatmap) — não em tempoMusica = 0, senão a grade não
-- bateria com a música de verdade.
function chart.getLinhasBpmVisiveis(margemPixels)
    if not bpm or bpm <= 0 then return {} end

    local margem = limiteTempoVisivel(margemPixels)
    local batida = chart.duracaoBatida()
    local inicio = tempoMusica - margem
    local fim = tempoMusica + margem

    -- Quantas batidas já se passaram desde offsetBpm até o começo da
    -- janela visível (pode ser negativo, se offsetBpm for depois de
    -- tempoMusica — beatmap ainda não chegou na primeira batida).
    local primeiraBatida = math.floor((inicio - offsetBpm) / batida)

    local linhas = {}
    local t = offsetBpm + primeiraBatida * batida

    -- Limite de segurança: nunca gera mais linhas do que cabe numa tela
    -- (evita loop longo demais se batida ficar absurdamente pequena por
    -- algum BPM malformado no .osu).
    local maximo = 500

    while t <= fim and #linhas < maximo do
        if t >= inicio then
            linhas[#linhas + 1] = t
        end
        t = t + batida
    end

    return linhas
end

-- Intervalo de notas que podem aparecer na tela. Inclui uma folga para
-- trás com a maior duração de hold, para que holds longos, cujo início
-- já ficou para trás, continuem sendo desenhados.
function chart.getIntervaloDesenho(margemPixels)
    if #notas == 0 then return 1, 0 end
    local margem = limiteTempoVisivel(margemPixels)
    local folgaHold = indiceNotas.duracaoMaxima(notas)
    return lowerBound(tempoMusica - margem - folgaHold),
        upperBound(tempoMusica + margem)
end

function chart.getQuantidadeNotasNaTela()
    local altura = love.graphics.getHeight()
    local alturaStrumline = 100
    local direcao = "down"
    if configuracao then
        -- Mesma escala aplicada em gameplay_ui.lua (valor "base" pensado
        -- pra uma tela de 1080p): sem isso, esse contador de debug ficaria
        -- calculando a posição da strumline errada em qualquer resolução
        -- diferente de 1080p.
        local escalaUI = altura / 1080
        alturaStrumline = (tonumber(configuracao.alturaStrumline) or alturaStrumline) * escalaUI
        direcao = configuracao.direcao or direcao
    end

    local centroY = direcao == "down" and (altura - alturaStrumline) or alturaStrumline
    local inicio, fim = chart.getIntervaloVisivel(math.max(100, altura + 50))
    local quantidade = 0

    for i = inicio, fim do
        local nota = notas[i]
        if nota and not nota.hit and type(nota.time) == "number" then
            local deslocamento = (nota.time - tempoMusica) * velocidade
            local y = direcao == "down" and (centroY - deslocamento) or (centroY + deslocamento)
            if y > -50 and y < altura + 50 then quantidade = quantidade + 1 end
        end
    end
    return quantidade
end

function chart.setConfiguracaoVisual(novaConfiguracao)
    if type(novaConfiguracao) ~= "table" then
        configuracao = nil
        return
    end
    configuracao = {
        alturaStrumline = tonumber(novaConfiguracao.alturaStrumline) or 100,
        direcao = novaConfiguracao.direcao or "down"
    }
end

function chart.limpar()
    notas = {}
    tempoMusica = 0
    duracaoTotal = 0
end

return chart
