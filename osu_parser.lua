local parser = {}

local bit = require("bit")

parser.imagemFundo = nil
parser.videoFundo = nil
parser.videoOffset = 0

-- BPM do primeiro timing point "uninherited" (red line) e o instante em
-- que ele começa, em segundos. O jogo não suporta mudança de BPM no meio
-- da música (nenhum sistema aqui usa isso hoje) — pegamos só a primeira,
-- que cobre a grande maioria dos beatmaps 4K simples.
parser.bpm = nil
parser.offsetBpm = 0

--------------------------------------------------
-- DESCOBRIR LANE
--------------------------------------------------

local function descobrirLane(x)

    -- osu!mania 4K
    if x < 128 then
        return 1

    elseif x < 256 then
        return 2

    elseif x < 384 then
        return 3

    else
        return 4
    end
end

--------------------------------------------------
-- LIMPAR STRING
--------------------------------------------------

local function limparString(valor)

    if not valor then
        return nil
    end

    valor = valor:gsub("\r", "")
    valor = valor:gsub("^%s+", "")
    valor = valor:gsub("%s+$", "")

    return valor
end

--------------------------------------------------
-- CARREGAR
--------------------------------------------------

function parser.carregar(caminho)

    local conteudo, erro =
        love.filesystem.read(caminho)

    if not conteudo then

        error(
            "Erro lendo .osu: " ..
            tostring(erro)
        )
    end

    local notas = {}

    parser.imagemFundo = nil
    parser.videoFundo = nil
    parser.videoOffset = 0
    parser.bpm = nil
    parser.offsetBpm = 0

    local lendoEvents = false
    local lendoHitObjects = false
    local lendoTimingPoints = false

    --------------------------------------------------
    -- LER LINHAS
    --------------------------------------------------

    for linha in conteudo:gmatch("[^\r\n]+") do

        --------------------------------------------------
        -- EVENTS
        --------------------------------------------------

        if linha == "[Events]" then

            lendoEvents = true
            lendoHitObjects = false
            lendoTimingPoints = false

        --------------------------------------------------
        -- TIMING POINTS (BPM)
        --------------------------------------------------

        elseif linha == "[TimingPoints]" then

            lendoEvents = false
            lendoHitObjects = false
            lendoTimingPoints = true

        --------------------------------------------------
        -- HIT OBJECTS
        --------------------------------------------------

        elseif linha == "[HitObjects]" then

            lendoEvents = false
            lendoHitObjects = true
            lendoTimingPoints = false

        --------------------------------------------------
        -- TIMING POINTS
        --------------------------------------------------

        elseif lendoTimingPoints
        and linha ~= ""
        and linha:sub(1, 1) ~= "[" then

            if not parser.bpm then

                local partes = {}

                for valor in linha:gmatch("[^,]+") do
                    partes[#partes + 1] = valor
                end

                local tempoInicio = tonumber(partes[1])
                local beatLength = tonumber(partes[2])

                -- beatLength positivo = timing point "uninherited" (red
                -- line), o único tipo que define BPM. Negativo é
                -- "inherited" (green line, multiplicador de velocidade de
                -- slider) e não tem BPM — ignorado.
                if tempoInicio and beatLength and beatLength > 0 then
                    parser.bpm = 60000 / beatLength
                    parser.offsetBpm = tempoInicio / 1000
                end
            end

        --------------------------------------------------
        -- BACKGROUND
        --------------------------------------------------

        elseif lendoEvents
        and linha ~= "" then

            -- Vídeo de fundo: Video,<offset ms>,"arquivo"  (ou 1,<offset>,"arquivo")
            local offsetVideo, arquivoVideo =
                linha:match('^Video,%s*(%-?%d+)%s*,%s*"([^"]+)"')

            if not arquivoVideo then
                offsetVideo, arquivoVideo =
                    linha:match('^1,%s*(%-?%d+)%s*,%s*"([^"]+)"')
            end

            if arquivoVideo and not parser.videoFundo then
                parser.videoFundo = limparString(arquivoVideo)
                parser.videoOffset = tonumber(offsetVideo) or 0
            end

            local caminhoImagem =
                linha:match(
                    '^0,0,"([^"]+)"'
                )

            if caminhoImagem then

                parser.imagemFundo =
                    limparString(
                        caminhoImagem
                    )

                print(
                    "BACKGROUND ENCONTRADO: " ..
                    tostring(
                        parser.imagemFundo
                    )
                )
            end

        --------------------------------------------------
        -- HIT OBJECTS
        --------------------------------------------------

        elseif lendoHitObjects
        and linha ~= "" then

            local valores = {}

            for valor in linha:gmatch(
                "[^,]+"
            ) do

                valores[#valores + 1] =
                    valor
            end

            if #valores >= 4 then

                local x =
                    tonumber(
                        valores[1]
                    )

                local tempo =
                    tonumber(
                        valores[3]
                    )

                local tipo =
                    tonumber(
                        valores[4]
                    )

                if x
                and tempo
                and tipo then

                    local lane =
                        descobrirLane(x)

                    local duracao = 0

                    --------------------------------------------------
                    -- HOLD
                    --
                    -- Tipo 128 = long note
                    --------------------------------------------------

                    if bit.band(tipo, 128) ~= 0 then

                        local dadosHold =
                            valores[6]

                        if dadosHold then

                            local tempoFinal =
                                tonumber(
                                    dadosHold:match(
                                        "^(%d+)"
                                    )
                                )

                            if tempoFinal then

                                duracao =
                                    (
                                        tempoFinal -
                                        tempo
                                    ) / 1000

                            end
                        end
                    end

                    if duracao < 0 then
                        duracao = 0
                    end

                    --------------------------------------------------
                    -- ADICIONAR NOTA
                    --------------------------------------------------

                    notas[#notas + 1] = {

                        time =
                            tempo / 1000,

                        lane =
                            lane,

                        duration =
                            duracao,

                        hit = false,

                        judged = false
                    }
                end
            end
        end
    end

    --------------------------------------------------
    -- ORDENAR
    --------------------------------------------------

    table.sort(
        notas,
        function(a, b)

            return a.time < b.time

        end
    )

    --------------------------------------------------
    -- DEBUG
    --------------------------------------------------

    print(
        "================================"
    )

    print(
        "CHART CARREGADO"
    )

    print(
        "Notas: " ..
        tostring(#notas)
    )

    print(
        "Background: " ..
        tostring(
            parser.imagemFundo
            or "nenhum"
        )
    )

    print(
        "================================"
    )

    --------------------------------------------------
    -- RETORNA AS NOTAS
    --------------------------------------------------

    return notas
end

return parser