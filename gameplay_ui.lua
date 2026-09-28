local ui = {}

-- Os valores configurados pelo jogador (slider "Tamanho das notas" = 33,
-- por exemplo) são guardados como "_base": pensados para uma tela de
-- referência de 1080p de altura. Na hora de desenhar (ui.desenhar), eles
-- são multiplicados por REFERENCIA_ALTURA/altura-da-tela-atual, então o
-- MESMO valor 33 ocupa a MESMA fração da tela pra qualquer jogador,
-- independente da resolução do aparelho dele (ou da resolução interna do
-- Canvas escolhida nas opções de vídeo).
--
-- espacamento/tamanhoBola/alturaStrumline (sem "_base") guardam o valor JÁ
-- escalado do frame atual: desenharCabeca/desenharHold (abaixo) são
-- closures que os leem como upvalue, então são recalculados no início de
-- ui.desenhar a cada frame antes de qualquer desenho acontecer.
local REFERENCIA_ALTURA = 450

local espacamentoBase = 75
local tamanhoBolaBase = 33
local alturaStrumlineBase = 40

local espacamento = espacamentoBase
local tamanhoBola = tamanhoBolaBase
local alturaStrumline = alturaStrumlineBase

local direcao = "down"
local grossuraHold = 1.0 -- já é uma proporção (multiplica tamanhoBola), não precisa escalar

function ui.setEspacamento(valor)
    if type(valor) == "number" and valor > 0 then
        espacamentoBase = valor
    end
end

function ui.setTamanhoBola(valor)
    if type(valor) == "number" and valor > 0 then
        tamanhoBolaBase = valor
    end
end

function ui.setDirecao(valor)
    if valor == "up" or valor == "down" then
        direcao = valor
    end
end

function ui.setAlturaStrumline(valor)
    if type(valor) == "number" and valor > 0 then
        alturaStrumlineBase = valor
    end
end

function ui.setGrossuraHold(valor)
    if type(valor) == "number" and valor > 0 then
        grossuraHold = valor
    end
end

--------------------------------------------------
-- APARÊNCIA (acessibilidade / vídeo)
--------------------------------------------------

local esquemaCores = "padrao"
local formaNotas = "circulo"
local contornoNotas = false
local laneOpacidade = 0
local debugHitboxes = false
local linhasBpmAtivo = false

local coresLane = {
    lanes = {
        {0.95, 0.36, 0.58}, {0.36, 0.78, 0.98},
        {0.56, 0.92, 0.42}, {0.99, 0.76, 0.30},
    },
    -- paleta Okabe-Ito (segura para daltonismo)
    daltonico = {
        {0.00, 0.447, 0.698}, {0.90, 0.62, 0.00},
        {0.337, 0.706, 0.914}, {0.94, 0.894, 0.259},
    },
}

local formasPorLane = {"circulo", "losango", "quadrado", "triangulo"}

function ui.aplicarConfiguracao(config)
    if not config then return end

    esquemaCores = tostring(config.get("esquemaCores") or "padrao")
    formaNotas = tostring(config.get("formaNotas") or "circulo")
    contornoNotas = config.get("contornoNotas") == true
    laneOpacidade = (tonumber(config.get("laneOpacidade")) or 0) / 100
    debugHitboxes = config.get("debugHitboxes") == true
    linhasBpmAtivo = config.get("linhasBpm") == true
end

-- Cor da cabeça da nota e do corpo do hold para uma lane.
local function coresDaLane(lane)
    if esquemaCores == "contraste" then
        return {1, 1, 1}, {0.92, 0.92, 0.60}
    end

    local tabela = coresLane[esquemaCores]

    if tabela then
        local c = tabela[lane] or tabela[1]
        return c, {c[1] * 0.75 + 0.25, c[2] * 0.75 + 0.25, c[3] * 0.75 + 0.25}
    end

    return {0.8, 0.8, 0.8}, {0.72, 0.78, 0.92}
end

local function formaDaLane(lane)
    if formaNotas == "lane" then
        return formasPorLane[lane] or "circulo"
    end

    return formaNotas
end

local function desenharForma(modo, forma, x, y, r)
    if forma == "quadrado" then
        love.graphics.rectangle(modo, x - r * 0.9, y - r * 0.9, r * 1.8, r * 1.8, r * 0.25, r * 0.25)
    elseif forma == "losango" then
        love.graphics.polygon(modo, x, y - r * 1.15, x + r * 1.15, y, x, y + r * 1.15, x - r * 1.15, y)
    elseif forma == "triangulo" then
        love.graphics.polygon(modo, x, y - r * 1.1, x + r * 1.05, y + r * 0.85, x - r * 1.05, y + r * 0.85)
    else
        love.graphics.circle(modo, x, y, r)
    end
end

local function comContorno()
    return contornoNotas or esquemaCores == "contraste"
end

-- Cabeça de nota (com contorno opcional).
local function desenharCabeca(lane, x, y, raio)
    local cor = coresDaLane(lane)
    local forma = formaDaLane(lane)

    if comContorno() then
        love.graphics.setColor(0, 0, 0, 0.95)
        desenharForma("fill", forma, x, y, raio + 3)
    end

    love.graphics.setColor(cor[1], cor[2], cor[3], 1)
    desenharForma("fill", forma, x, y, raio)
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

-- =========================================================
-- DESENHA HOLD
-- =========================================================

local function desenharHold(
    x,
    yInicio,
    yFim,
    sentido,
    lane
)

    local corCabeca, corCorpo = coresDaLane(lane or 1)

    local raioCauda =
        tamanhoBola *
        0.55 *
        grossuraHold

    local larguraHold =
        tamanhoBola *
        1.1 *
        grossuraHold

    local yPonta

    if sentido < 0 then

        yPonta =
            yFim +
            raioCauda

    else

        yPonta =
            yFim -
            raioCauda
    end

    local topo =
        math.min(
            yInicio,
            yPonta
        )

    local baixo =
        math.max(
            yInicio,
            yPonta
        )

    -- =====================================================
    -- CAUDA
    -- =====================================================

    if comContorno() then
        love.graphics.setColor(0, 0, 0, 0.95)
        love.graphics.rectangle(
            "fill",
            x - larguraHold * 0.5 - 3,
            topo,
            larguraHold + 6,
            baixo - topo
        )
    end

    love.graphics.setColor(
        corCorpo[1],
        corCorpo[2],
        corCorpo[3],
        1
    )

    love.graphics.rectangle(
        "fill",
        x - larguraHold * 0.5,
        topo,
        larguraHold,
        baixo - topo
    )

    -- =====================================================
    -- PONTA DA CAUDA
    -- =====================================================

    love.graphics.circle(
        "fill",
        x,
        yPonta,
        raioCauda
    )

    -- =====================================================
    -- CABEÇA
    -- =====================================================

    desenharCabeca(lane or 1, x, yInicio, tamanhoBola)
end

-- =========================================================
-- VERIFICA SE O HOLD ESTÁ VISÍVEL
-- =========================================================

local function holdEstaVisivel(
    yInicio,
    yFim,
    altura
)

    local topo =
        math.min(
            yInicio,
            yFim
        )

    local baixo =
        math.max(
            yInicio,
            yFim
        )

    return
        baixo > -100
        and
        topo < altura + 100
end

function ui.desenhar(
    chart,
    controles
)

    local largura =
        love.graphics.getWidth()

    local altura =
        love.graphics.getHeight()

    -- Recalcula os tamanhos JÁ escalados pra essa tela: o mesmo valor
    -- configurado (base) sempre vira a mesma fração da altura da tela,
    -- então o jogo parece do mesmo tamanho pra qualquer resolução.
    local escalaUI = altura / REFERENCIA_ALTURA
    espacamento = espacamentoBase * escalaUI
    tamanhoBola = tamanhoBolaBase * escalaUI
    alturaStrumline = alturaStrumlineBase * escalaUI

    local notas =
        chart.getNotas()

    local tempoMusica =
        chart.getTempo()

    local velocidade =
        chart.getVelocidade() * escalaUI

    local tamanhoTile =
        largura / 4

    -- Usado tanto pra decidir quais notas desenhar quanto pra decidir
    -- quais linhas de BPM desenhar (mesma janela de visibilidade).
    local margemDesenho =
        altura +
        math.abs(tonumber(alturaStrumline) or 0) +
        200

    -- =====================================================
    -- FUNDO DAS LANES (opcional: "Destaque das lanes")
    -- =====================================================

    if laneOpacidade > 0 then

        local colunaX =
            largura / 2 -
            espacamento * 2

        for i = 1, 4 do

            local x =
                colunaX +
                (i - 1) *
                espacamento

            if controles.estaPressionado(i) then

                love.graphics.setColor(
                    0.4,
                    0.5,
                    1,
                    0.34 * laneOpacidade
                )

            else

                love.graphics.setColor(
                    0.12,
                    0.12,
                    0.18,
                    0.55 * laneOpacidade
                )
            end

            love.graphics.rectangle(
                "fill",
                x,
                0,
                espacamento,
                altura
            )
        end

        love.graphics.setColor(
            1,
            1,
            1,
            0.35 * laneOpacidade
        )

        for i = 0, 4 do

            local x =
                colunaX +
                i *
                espacamento

            love.graphics.line(
                x,
                0,
                x,
                altura
            )
        end
    end

    -- =====================================================
    -- STRUMLINE
    -- =====================================================

    local centroX =
        largura / 2

    local centroY

    if direcao == "down" then

        centroY =
            altura -
            alturaStrumline

    else

        centroY =
            alturaStrumline
    end

    -- =====================================================
    -- LINHAS DE BPM (opcional)
    --
    -- Uma linha horizontal cruzando as 4 lanes a cada batida da música,
    -- caindo junto com as notas (mesma fórmula de posição). Ajuda a
    -- perceber o ritmo visualmente, principalmente em partes sem notas.
    -- =====================================================

    if linhasBpmAtivo then

        local colunaXBpm =
            centroX - espacamento * 2

        local larguraBpm =
            espacamento * 4

        local linhasBpm =
            chart.getLinhasBpmVisiveis(
                margemDesenho
            )

        love.graphics.setLineWidth(1)

        for _, tempoBatida in ipairs(linhasBpm) do

            local deslocamento =
                (tempoBatida - tempoMusica) *
                velocidade

            local y =
                direcao == "down" and
                (centroY - deslocamento) or
                (centroY + deslocamento)

            if y > -20 and y < altura + 20 then

                love.graphics.setColor(1, 1, 1, 0.20)

                love.graphics.line(
                    colunaXBpm,
                    y,
                    colunaXBpm + larguraBpm,
                    y
                )
            end
        end
    end

    -- =====================================================
    -- STRUMLINE / RECEPTORES (desenhados ANTES das notas, para
    -- que as notas passem por cima dos indicadores das lanes)
    -- =====================================================

    for i = 1, 4 do

        local x =
            centroX +
            (i - 2.5) *
            espacamento

        if controles.estaPressionado(i) then

            love.graphics.setColor(
                1,
                1,
                1,
                1
            )

        else

            love.graphics.setColor(
                0.5,
                0.5,
                0.5,
                0.8
            )
        end

        love.graphics.setLineWidth(
            comContorno() and 3 or 1
        )

        desenharForma(
            "line",
            formaDaLane(i),
            x,
            centroY,
            tamanhoBola
        )

        love.graphics.setLineWidth(1)
    end

    -- =====================================================
    -- NOTAS
    -- =====================================================

    -- Só as notas que podem estar visíveis: o custo por frame não
    -- depende mais do tamanho do mapa.
    local primeiraVisivel, ultimaVisivel =
        chart.getIntervaloDesenho(
            margemDesenho
        )

    for indiceNota = primeiraVisivel, ultimaVisivel do

        local nota = notas[indiceNota]

        if nota and not nota.hit then

            local duracao =
                pegarDuracao(nota)

            local x =
                centroX +
                (nota.lane - 2.5) *
                espacamento

            -- =================================================
            -- HOLD
            -- =================================================

            if duracao > 0 then

                local inicio =
                    nota.time

                local fim =
                    inicio +
                    duracao

                local yInicio
                local yFim

                -- =============================================
                -- HOLD ATIVO
                -- =============================================

                if nota.holdActive then

                    local restante =
                        math.max(
                            0,
                            fim -
                            tempoMusica
                        )

                    if restante > 0 then

                        yInicio =
                            centroY

                        if direcao == "down" then

                            yFim =
                                centroY -
                                restante *
                                velocidade

                            desenharHold(
                                x,
                                yInicio,
                                yFim,
                                -1,
                                nota.lane
                            )

                        else

                            yFim =
                                centroY +
                                restante *
                                velocidade

                            desenharHold(
                                x,
                                yInicio,
                                yFim,
                                1,
                                nota.lane
                            )
                        end
                    end

                -- =============================================
                -- HOLD AINDA NÃO FOI ATIVADO
                -- =============================================

                elseif not nota.judged then

                    if direcao == "down" then

                        yInicio =
                            centroY -
                            (
                                inicio -
                                tempoMusica
                            ) *
                            velocidade

                        yFim =
                            centroY -
                            (
                                fim -
                                tempoMusica
                            ) *
                            velocidade

                    else

                        yInicio =
                            centroY +
                            (
                                inicio -
                                tempoMusica
                            ) *
                            velocidade

                        yFim =
                            centroY +
                            (
                                fim -
                                tempoMusica
                            ) *
                            velocidade
                    end

                    if holdEstaVisivel(
                        yInicio,
                        yFim,
                        altura
                    ) then

                        if direcao == "down" then

                            desenharHold(
                                x,
                                yInicio,
                                yFim,
                                -1,
                                nota.lane
                            )

                        else

                            desenharHold(
                                x,
                                yInicio,
                                yFim,
                                1,
                                nota.lane
                            )
                        end
                    end
                end

            else

                local restante =
                    nota.time -
                    tempoMusica

                local deslocamento =
                    restante *
                    velocidade

                local y

                if direcao == "down" then

                    y =
                        centroY -
                        deslocamento

                else

                    y =
                        centroY +
                        deslocamento
                end

                if y > -50
                and y < altura + 50 then

                    desenharCabeca(
                        nota.lane,
                        x,
                        y,
                        tamanhoBola
                    )
                end
            end
        end
    end

    -- =====================================================
    -- DEBUG: ÁREAS DE TOQUE
    -- =====================================================

    if debugHitboxes then

        local temaOk, tema = pcall(require, "tema")

        if temaOk then
            -- sem isso, herdava a fonte de qualquer coisa desenhada no
            -- frame anterior (mesma causa do bug do FPS/bot)
            love.graphics.setFont(tema.fonte(13 * tema.escala()))
        end

        love.graphics.setLineWidth(2)

        for i = 1, 4 do

            local x =
                (i - 1) *
                tamanhoTile

            love.graphics.setColor(1, 0.3, 0.3, 0.7)

            love.graphics.rectangle(
                "line",
                x + 1,
                1,
                tamanhoTile - 2,
                altura - 2
            )

            love.graphics.setColor(1, 1, 1, 0.9)

            love.graphics.print(
                "LANE " .. i,
                x + 8,
                altura - 24
            )
        end

        if temaOk then

            local bx, by, bw, bh =
                tema.retanguloBotaoPausa()

            love.graphics.setColor(0.3, 1, 0.5, 0.8)

            love.graphics.rectangle(
                "line",
                bx - 8,
                by - 8,
                bw + 16,
                bh + 16
            )
        end

        love.graphics.setLineWidth(1)
    end

    -- =====================================================
    -- BARRA DE PROGRESSO
    -- =====================================================

    local duracaoTotal =
        chart.getDuracaoTotal()

    if duracaoTotal > 0 then

        local progresso =
            math.max(
                0,
                math.min(
                    1,
                    tempoMusica /
                    duracaoTotal
                )
            )

        local barraAltura =
            5

        -- Fundo

        love.graphics.setColor(
            0.15,
            0.15,
            0.15,
            0
        )

        love.graphics.rectangle(
            "fill",
            0,
            0,
            largura,
            barraAltura
        )

        -- Progresso

        love.graphics.setColor(
            0.8,
            0.8,
            0.8,
            0.8
        )

        love.graphics.rectangle(
            "fill",
            0,
            0,
            largura * progresso,
            barraAltura
        )
    end
end

return ui