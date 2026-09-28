local bot = {}

local indiceNotas = require("notas_index")

local ativo = false
local pressionadas = {}

local duracaoToque = 0.055

-- Cursor de varredura por lane (1 a 4): evita que cada lane precise
-- reescanear, a cada frame, as notas de OUTRAS lanes que já ficaram
-- para trás. Reseta junto com o cursor global em bot.limpar/resetar.
local cursoresLane = {1, 1, 1, 1}

function bot.setAtivo(valor)

    local novo =
        valor == true

    if novo == ativo then
        return
    end

    ativo = novo

    if not ativo then
        bot.limpar()
    end
end

function bot.estaAtivo()
    return ativo
end

function bot.setDuracaoToque(valor)

    valor = tonumber(valor)

    if valor and valor > 0 then

        duracaoToque =
            math.max(
                0.01,
                math.min(
                    0.25,
                    valor
                )
            )
    end
end

function bot.limpar(controles)

    if controles
    and type(controles.botLimpar) == "function" then

        controles.botLimpar()
    end

    pressionadas = {}
    cursoresLane = {1, 1, 1, 1}
end

local function pegarOffsetFinalHold(hit)

    if hit
    and type(hit.offsetFinalHold) == "number" then

        return hit.offsetFinalHold
    end

    return 0
end

local function pressionar(
    controles,
    lane,
    modo,
    fim
)

    if pressionadas[lane] then
        return false
    end

    controles.botPressionar(lane)

    pressionadas[lane] = {
        modo = modo,
        restante = duracaoToque,
        fim = fim
    }

    return true
end

local function soltar(
    controles,
    lane
)

    if not pressionadas[lane] then
        return
    end

    controles.botSoltar(lane)

    pressionadas[lane] = nil
end

-- =========================================================
-- PROCURA NOTA
-- =========================================================
--
-- IMPORTANTE:
-- O bot NÃO antecipa mais a nota.
--
-- Ele só pega a nota quando o tempo musical já chegou
-- ao tempo exato dela.
--
local function encontrarNota(
    notas,
    tempo,
    lane
)

    -- Cursor global (compartilhado entre lanes) só pra saber a partir de
    -- onde pode ter algo pendente; o cursor DESSA lane nunca fica atrás
    -- dele, pra não perder notas caso o chart seja trocado/resetado.
    local inicioGlobal =
        indiceNotas.primeiraPendente(
            notas,
            tempo
        )

    local indiceNota =
        math.max(
            cursoresLane[lane] or 1,
            inicioGlobal
        )

    local total = #notas

    -- Avança o cursor da lane por cima de notas já resolvidas (de
    -- QUALQUER lane) ou de outras lanes: cada lane só reexamina, frame a
    -- frame, a partir de onde parou da última vez.
    while indiceNota <= total do

        local nota = notas[indiceNota]

        if type(nota.time) ~= "number"
        or nota.time > tempo then
            break
        end

        if nota.lane == lane
        and not nota.judged
        and not nota.hit
        and not nota.holdActive then

            -- Como as notas são ordenadas por tempo, a primeira que
            -- passa nos filtros já É a mais antiga pendente da lane:
            -- não precisa continuar procurando uma "melhor".
            cursoresLane[lane] = indiceNota
            return nota
        end

        indiceNota = indiceNota + 1
    end

    cursoresLane[lane] = indiceNota

    return nil
end

function bot.atualizar(
    dt,
    estado,
    chart,
    hit,
    controles
)

    if not ativo
    or estado ~= "playing" then

        if next(pressionadas) ~= nil then
            bot.limpar(controles)
        end

        return
    end

    dt =
        tonumber(dt)
        or 0

    local tempo =
        tonumber(
            chart.getTempo()
        )
        or 0

    local notas =
        chart.getNotas()

    if type(notas) ~= "table" then
        return
    end

    local offsetFinalHold =
        pegarOffsetFinalHold(hit)

    -- =====================================================
    -- SOLTAR NOTAS / HOLDS
    -- =====================================================

    for lane, dados in pairs(pressionadas) do

        if dados.modo == "hold" then

            if dados.fim then

                local tempoSoltar =
                    dados.fim +
                    offsetFinalHold

                if tempo >= tempoSoltar then

                    if hit
                    and type(hit.soltarLane) == "function" then

                        hit.soltarLane(
                            notas,
                            lane,
                            tempo
                        )
                    end

                    soltar(
                        controles,
                        lane
                    )
                end
            end

        else

            dados.restante =
                dados.restante -
                dt

            if dados.restante <= 0 then

                soltar(
                    controles,
                    lane
                )
            end
        end
    end

    -- =====================================================
    -- APERTAR NOTAS
    -- =====================================================

    for lane = 1, 4 do

        if not pressionadas[lane] then

            local nota =
                encontrarNota(
                    notas,
                    tempo,
                    lane
                )

            if nota then

                local duracao =
                    tonumber(
                        nota.duration
                        or nota.duracao
                    )
                    or 0

                local ehHold =
                    duracao > 0

                local fim = nil

                if ehHold then

                    fim =
                        tonumber(
                            nota.holdEndTime
                        )

                    if not fim then

                        fim =
                            nota.time +
                            duracao
                    end
                end

                local conseguiuPressionar =
                    pressionar(
                        controles,
                        lane,
                        ehHold
                            and "hold"
                            or "tap",
                        fim
                    )

                if conseguiuPressionar then

                    -- Usa o TEMPO ATUAL.
                    -- Nunca usa nota.time aqui.
                    hit.tentar(
                        notas,
                        lane,
                        tempo
                    )

                    if ehHold
                    and nota.holdActive then

                        pressionadas[lane].modo =
                            "hold"

                        pressionadas[lane].fim =
                            tonumber(
                                nota.holdEndTime
                            )
                            or fim

                    elseif ehHold
                    and not nota.holdActive then

                        soltar(
                            controles,
                            lane
                        )
                    end
                end
            end
        end
    end
end

return bot