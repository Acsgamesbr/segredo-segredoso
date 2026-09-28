local hit = {}

local indiceNotas = require("notas_index")

hit.janelaPerfect = 0.070
hit.janelaGood = 0.090
hit.janelaOk = 0.120
hit.janelaBad = 0.160

-- Tolerância para SOLTAR um hold, simétrica ao redor do fim da nota:
-- soltar em [fim - janela, fim + janela] conta como PERFECT. Antes disso
-- (cedo demais) é MISS. Depois disso (o jogador nunca soltou a tempo),
-- quem decide é hit.atualizar() junto com a opção "segurar hold".
hit.janelaSoltarHold = 0.180

-- Opção "Soltar hold no fim": se o jogador não soltar a tecla até um
-- pouco depois do final (a mesma janela acima), o resultado vira GOOD em
-- vez de PERFECT. Com a opção desligada, apenas segurar até o fim já
-- basta para PERFECT (soltar continua opcional).
hit.holdObrigatorioSoltar = true
hit.offsetFinalHold = 0

hit.estatisticas = {}
hit.ultimoJulgamento = ""
hit.ultimoDesvio = nil
hit.proximoDesvio = nil
hit.idJulgamento = 0
hit.tempoUltimoJulgamento = 0

local valoresScore = {
    PERFECT = 1000,
    GOOD = 700,
    OK = 400,
    BAD = 100,
    MISS = 0,
}

local function numero(valor, padrao)
    valor = tonumber(valor)
    return valor == nil and padrao or valor
end

local function pegarDuracao(nota)
    if type(nota.duration) == "number" then
        return nota.duration
    end

    if type(nota.duracao) == "number" then
        return nota.duracao
    end

    if type(nota.endTime) == "number"
    and type(nota.time) == "number" then
        return nota.endTime - nota.time
    end

    return 0
end

local function resetarEstatisticas(total)
    hit.estatisticas = {
        apertadas = 0,
        acertadas = 0,
        erradas = 0,

        perfect = 0,
        good = 0,
        ok = 0,
        bad = 0,
        miss = 0,

        combo = 0,
        maxCombo = 0,
        score = 0,

        total = numero(total, 0),
        julgadas = 0,

        precisaoTotal = 0,
        precisaoMedia = 0,
    }
end

function hit.aplicarConfiguracao(config)
    if not config then
        return
    end

    hit.janelaPerfect = numero(config.get("janelaPerfect"), 0.040)
    hit.janelaGood = numero(config.get("janelaGood"), 0.080)
    hit.janelaOk = numero(config.get("janelaOk"), 0.120)
    hit.janelaBad = numero(config.get("janelaBad"), 0.180)

    hit.holdObrigatorioSoltar =
        config.get("holdObrigatorioSoltar") == true
end

function hit.resetar(notas)

    resetarEstatisticas(
        type(notas) == "table" and #notas or 0
    )

    hit.ultimoJulgamento = ""
    hit.tempoUltimoJulgamento = 0

    if type(notas) ~= "table" then
        return
    end

    indiceNotas.resetar(notas)

    for _, nota in ipairs(notas) do

        nota.hit = false
        nota.judged = false

        nota.holdActive = false
        nota.holdFailed = false

        nota.holdStartTime = nil
        nota.holdEndTime = nil
    end
end

local function atualizarPrecisao(valor)

    hit.estatisticas.precisaoTotal =
        hit.estatisticas.precisaoTotal + numero(valor, 0)

    local total = hit.estatisticas.julgadas

    if total > 0 then
        hit.estatisticas.precisaoMedia =
            hit.estatisticas.precisaoTotal / total
    else
        hit.estatisticas.precisaoMedia = 0
    end
end

-- Só usada para o toque inicial (cabeça da nota, tap ou hold): decide se
-- o aperto foi perto o bastante da nota pra contar, e com qual tier.
local function julgar(diferenca)

    local distancia = math.abs(numero(diferenca, 999))

    if distancia <= hit.janelaPerfect then return "PERFECT", 1.00 end
    if distancia <= hit.janelaGood then return "GOOD", 0.75 end
    if distancia <= hit.janelaOk then return "OK", 0.50 end
    if distancia <= hit.janelaBad then return "BAD", 0.25 end

    return nil, 0
end

local function registrarResultado(julgamento, precisao, tempo, acerto)

    local stats = hit.estatisticas

    stats.apertadas = stats.apertadas + 1
    stats.julgadas = stats.julgadas + 1
    stats.score = stats.score + (valoresScore[julgamento] or 0)

    if julgamento == "PERFECT" then
        stats.perfect = stats.perfect + 1
    elseif julgamento == "GOOD" then
        stats.good = stats.good + 1
    elseif julgamento == "OK" then
        stats.ok = stats.ok + 1
    elseif julgamento == "BAD" then
        stats.bad = stats.bad + 1
    end

    if acerto then
        stats.acertadas = stats.acertadas + 1
        stats.combo = stats.combo + 1

        if stats.combo > stats.maxCombo then
            stats.maxCombo = stats.combo
        end
    else
        stats.erradas = stats.erradas + 1
        stats.combo = 0
    end

    atualizarPrecisao(precisao)

    hit.ultimoJulgamento = julgamento
    hit.tempoUltimoJulgamento = tempo
    hit.ultimoDesvio = hit.proximoDesvio
    hit.proximoDesvio = nil
    hit.idJulgamento = (hit.idJulgamento or 0) + 1
end

local function registrarMiss(tempo)

    local stats = hit.estatisticas

    stats.miss = stats.miss + 1
    stats.erradas = stats.erradas + 1
    stats.julgadas = stats.julgadas + 1
    stats.combo = 0

    atualizarPrecisao(0)

    hit.ultimoJulgamento = "MISS"
    hit.tempoUltimoJulgamento = tempo
    hit.ultimoDesvio = nil
    hit.idJulgamento = (hit.idJulgamento or 0) + 1
end

-- =========================================================
-- APERTAR (cabeça da nota — tap ou hold)
-- =========================================================

function hit.tentar(notas, lane, tempoMusica)

    if type(notas) ~= "table" then
        return false
    end

    lane = tonumber(lane)
    tempoMusica = tonumber(tempoMusica)

    if not lane or not tempoMusica then
        return false
    end

    local melhorNota
    local menorDistancia = math.huge

    -- Só notas dentro da janela de acerto: não precisa percorrer o mapa
    -- inteiro a cada toque.
    local primeiraCandidata =
        indiceNotas.primeiroApartir(notas, tempoMusica - hit.janelaBad)

    local ultimaCandidata =
        indiceNotas.ultimoAte(notas, tempoMusica + hit.janelaBad)

    for indiceNota = primeiraCandidata, ultimaCandidata do

        local nota = notas[indiceNota]

        if nota.lane == lane
        and not nota.judged
        and not nota.holdActive
        and type(nota.time) == "number" then

            local distancia = math.abs(tempoMusica - nota.time)

            if distancia <= hit.janelaBad
            and distancia < menorDistancia then
                melhorNota = nota
                menorDistancia = distancia
            end
        end
    end

    if not melhorNota then
        return false
    end

    local diferenca = tempoMusica - melhorNota.time
    local julgamento, precisao = julgar(diferenca)

    if not julgamento then
        return false
    end

    local duracao = pegarDuracao(melhorNota)

    if duracao > 0 then

        -- HOLD: pressionar só "arma" a nota. O resultado (PERFECT, GOOD
        -- ou MISS) é sempre decidido por quando ela é SOLTA — como uma
        -- tecla normal — em hit.soltarLane / hit.atualizar, não pela
        -- precisão deste aperto inicial.
        melhorNota.holdActive = true
        melhorNota.holdFailed = false
        melhorNota.holdStartTime = melhorNota.time
        melhorNota.holdEndTime = melhorNota.time + duracao

        return true
    end

    melhorNota.hit = true
    melhorNota.judged = true

    -- Desvio em segundos (negativo = cedo). Usado pelo HUD.
    hit.proximoDesvio = diferenca

    registrarResultado(julgamento, precisao, tempoMusica, julgamento ~= "BAD")

    return true
end

-- =========================================================
-- FINALIZAR HOLD (compartilhado entre soltar manual e o time-out)
-- =========================================================

-- cedoDemais == true: o jogador soltou antes da janela em volta do fim.
-- comoSePerfeito == true: acerto pleno (o padrão ao soltar dentro da
-- janela). Quando falso (só usado no time-out com a opção ativa), o
-- resultado vira GOOD em vez de PERFECT.
local function finalizarHold(nota, tempoMusica, cedoDemais, comoSePerfeito)

    nota.holdActive = false
    nota.judged = true

    if cedoDemais then

        nota.holdFailed = true
        nota.hit = false

        registrarMiss(tempoMusica)

        return
    end

    nota.holdFailed = false
    nota.hit = true

    if comoSePerfeito then
        registrarResultado("PERFECT", 1.00, tempoMusica, true)
    else
        registrarResultado("GOOD", 0.75, tempoMusica, true)
    end
end

-- =========================================================
-- SOLTAR (evento real de tecla solta — igual a uma tecla normal)
-- =========================================================

function hit.soltarLane(notas, lane, tempoMusica)

    if type(notas) ~= "table" then
        return
    end

    lane = tonumber(lane)
    tempoMusica = tonumber(tempoMusica)

    if not lane or not tempoMusica then
        return
    end

    -- Um hold ativo nunca está julgado e já começou (ou está prestes
    -- a começar), então basta olhar do primeiro pendente até o tempo atual.
    local primeiraPendente = indiceNotas.primeiraPendente(notas, tempoMusica)
    local ultimaAlvo = indiceNotas.ultimoAte(notas, tempoMusica + 1.0)

    for indiceNota = primeiraPendente, ultimaAlvo do

        local nota = notas[indiceNota]

        if nota.lane == lane
        and nota.holdActive
        and not nota.judged then

            local fim = tonumber(nota.holdEndTime)

            if not fim then
                return
            end

            fim = fim + hit.offsetFinalHold

            local diferenca = tempoMusica - fim

            -- Soltou cedo demais (fora da janela, antes do fim): miss,
            -- igual a soltar uma tecla normal antes da hora.
            if diferenca < -hit.janelaSoltarHold then
                finalizarHold(nota, tempoMusica, true)
                return
            end

            -- Soltou perto o suficiente do final (antes OU depois, dentro
            -- da janela) — ou até um pouco tarde, mas de forma manual:
            -- conta como PERFECT. Soltar involuntariamente tarde demais
            -- (além da janela) não acontece aqui na prática, porque
            -- hit.atualizar já teria resolvido a nota antes disso.
            finalizarHold(nota, tempoMusica, false, true)

            return
        end
    end
end

function hit.atualizar(notas, tempoMusica, dt)

    if type(notas) ~= "table" then
        return
    end

    tempoMusica = tonumber(tempoMusica)

    if not tempoMusica then
        return
    end

    -- Notas já julgadas ficam para trás e notas distantes no futuro não
    -- têm nada a atualizar: o custo por frame não depende do tamanho do mapa.
    local primeiraPendente = indiceNotas.primeiraPendente(notas, tempoMusica)
    local ultimaAlvo = indiceNotas.ultimoAte(notas, tempoMusica + 1.0)

    for indiceNota = primeiraPendente, ultimaAlvo do

        local nota = notas[indiceNota]

        if not nota.judged and type(nota.time) == "number" then

            if nota.holdActive then

                local fim = tonumber(nota.holdEndTime)

                if fim then

                    fim = fim + hit.offsetFinalHold

                    -- O jogador continuou segurando além da janela de
                    -- soltar sem nunca largar a tecla: com "Soltar hold
                    -- no fim" ativado, isso vale GOOD (era pra ter
                    -- soltado); desativado, ainda vale PERFECT (segurar
                    -- até o fim já é suficiente).
                    if tempoMusica >= fim + hit.janelaSoltarHold then
                        finalizarHold(
                            nota,
                            tempoMusica,
                            false,
                            not hit.holdObrigatorioSoltar
                        )
                    end
                end

            elseif tempoMusica - nota.time > hit.janelaBad then

                nota.judged = true
                nota.hit = false

                -- Nunca chegou a ser pressionada: também é uma falha de
                -- hold (não só a de soltar cedo demais), pra manter o
                -- campo coerente caso algo mais venha a usá-lo.
                if pegarDuracao(nota) > 0 then
                    nota.holdFailed = true
                end

                registrarMiss(tempoMusica)
            end
        end
    end
end

function hit.getPrecisao()
    return hit.estatisticas.precisaoMedia
end

function hit.getEstatisticas()
    return hit.estatisticas
end

function hit.getUltimoJulgamento()
    return hit.ultimoJulgamento
end

function hit.getTempoUltimoJulgamento()
    return hit.tempoUltimoJulgamento
end

function hit.getRating()

    local a = numero(hit.estatisticas.precisaoMedia, 0) * 100

    if a >= 100 then return "SS" end
    if a >= 90 then return "S" end
    if a >= 80 then return "A" end
    if a >= 70 then return "B" end
    if a >= 60 then return "C" end
    if hit.estatisticas.julgadas > 0 then return "D" end

    return "-"
end

return hit
