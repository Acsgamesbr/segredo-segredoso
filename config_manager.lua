local config = {}

--------------------------------------------------
-- CONFIGURAÇÕES PADRÃO
--------------------------------------------------

local padrao = {

    velocidade = 1000,
    delayInicio = 3,
    fpsLimite = 240,
    volumeMusica = 100,
    grossuraHold = 1,
    holdObrigatorioSoltar = true,
    -- Em Android/iOS, false = touch. true = teclado/mouse.
    -- No Windows, os controles de PC sao sempre usados.
    enablePcControls = false,
    windowWidth = 1280,
    windowHeight = 720,

    espacamento = 80,
    tamanhoBola = 33,

    direcao = "down",
    alturaStrumline = 50,
    
    teclaLane1 = "d",
    teclaLane2 = "f",
    teclaLane3 = "j",
    teclaLane4 = "k",

    controleLane1 = "dpleft",
    controleLane2 = "dpdown",
    controleLane3 = "dpup",
    controleLane4 = "dpright",

    janelaPerfect = 0.060,
    janelaGood = 0.090,
    janelaOk = 0.120,
    janelaBad = 0.180,

    --------------------------------------------------
    -- NOVAS CONFIGURAÇÕES
    --------------------------------------------------

    -- 100 = imagem normal
    -- 0 = totalmente escura
    brilhoFundo = 35,

    -- Offset em milissegundos
    offset = 0,

    -- 0 = desligado
    -- 1 = FPS
    -- 2 = FPS + memória
    -- 3 = FPS + memória + notas + média
    fpsModo = 0,

    -- Gameplay / bot
    botAtivo = false,
    botVelocidadePressao = 0.055,

    -- HUD
    hudVisivel = true,
    hud_accuracy_x = 10,
    hud_accuracy_y = 35,
    hud_combo_x = 10,
    hud_combo_y = 62,
    hud_score_x = 10,
    hud_score_y = 89,
    hud_misses_x = 10,
    hud_misses_y = 116,
    hud_ratings_x = 10,
    hud_ratings_y = 143,

    -- Popup do julgamento: x = centro do popup (0 = centro da tela)
    hud_ratingPopup_x = 0,
    hud_ratingPopup_y = 60,

    hud_accuracy_ativo = true,
    hud_combo_ativo = true,
    hud_score_ativo = true,
    hud_misses_ativo = true,
    hud_ratings_ativo = true,
    hud_ratingPopup_ativo = true,

    hudEscala = 100,
    hudOpacidade = 100,
    hudFundo = false,
    hudCoresJulgamento = true,
    hudMostrarMs = false,
    popupDuracao = 0.6,

    --------------------------------------------------
    -- VIDEO
    --------------------------------------------------

    -- "imagem" ou "video" (video usa o .ogv do beatmap, se existir)
    fundoModo = "imagem",
    vsync = false,
    backendGrafico = "vulkan",
    -- "nativa" ou "LARGxALT" (ex: "1280x720"): resolução do Canvas interno,
    -- que depois é escalada pra tela real. Ver systems/resolucao.lua.
    resolucaoCanvas = "nativa",
    laneOpacidade = 0,
    esquemaCores = "padrao",
    formaNotas = "circulo",
    contornoNotas = false,
    linhasBpm = false,
    countdownBpm = false,

    --------------------------------------------------
    -- ACESSIBILIDADE
    --------------------------------------------------

    reduzirMovimento = false,
    uiEscala = 100,
    vibrar = false,

    --------------------------------------------------
    -- AUDIO
    --------------------------------------------------

    hitsom = false,
    hitsomVolume = 60,

    --------------------------------------------------
    -- QOL
    --------------------------------------------------

    pausarSemFoco = true,
    contagemRetomar = true,
    botaoPausa = true,
    resetSegurar = false,
    resetSegurarSeg = 1.5,
    confirmarSair = true,
    ocultarCursorSeg = 2,

    --------------------------------------------------
    -- ARMAZENAMENTO / DEBUG
    --------------------------------------------------

    pastaExterna = true,
    debugHitboxes = false
}

--------------------------------------------------
-- DADOS
--------------------------------------------------

config.dados = {}

--------------------------------------------------
-- CARREGAR
--------------------------------------------------

function config.carregar()

    config.dados = {}

    if love.filesystem.getInfo("config_save.lua") then

        local conteudo =
            love.filesystem.read(
                "config_save.lua"
            )

        if conteudo then

            local funcao, erro =
                load(
                    conteudo,
                    "config_save.lua",
                    "t"
                )

            if funcao then

                local sucesso, resultado =
                    pcall(funcao)

                if sucesso
                and type(resultado) == "table" then

                    config.dados =
                        resultado
                end

            else

                print(
                    "ERRO AO CARREGAR CONFIG:"
                )

                print(
                    tostring(erro)
                )
            end
        end
    end

    --------------------------------------------------
    -- COMPLETAR PADRÕES
    --------------------------------------------------

    for chave, valor in pairs(padrao) do

        if config.dados[chave] == nil then

            config.dados[chave] =
                valor
        end
    end

    config.salvar()
end

--------------------------------------------------
-- SALVAR
--------------------------------------------------

function config.salvar()

    local linhas = {}

    linhas[#linhas + 1] =
        "return {"

    for chave, valor in pairs(config.dados) do

        local linha

        if type(valor) == "string" then

            linha =
                "    " ..
                chave ..
                " = " ..
                string.format("%q", valor) ..
                ","

        elseif type(valor) == "number" then

            linha =
                "    " ..
                chave ..
                " = " ..
                tostring(valor) ..
                ","

        elseif type(valor) == "boolean" then

            linha =
                "    " ..
                chave ..
                " = " ..
                tostring(valor) ..
                ","
        end

        if linha then
            linhas[#linhas + 1] = linha
        end
    end

    linhas[#linhas + 1] =
        "}"

    local sucesso, erro =
        love.filesystem.write(
            "config_save.lua",
            table.concat(
                linhas,
                "\n"
            )
        )

    if not sucesso then

        print(
            "ERRO AO SALVAR CONFIG:"
        )

        print(
            tostring(erro)
        )
    end
end

--------------------------------------------------
-- PEGAR
--------------------------------------------------

function config.get(chave)

    return config.dados[chave]
end

--------------------------------------------------
-- ALTERAR
--------------------------------------------------

-- Atalhos de teclado das opções ("atalho_<id>") são criados sob demanda.
local function chaveLivre(chave)
    return type(chave) == "string"
        and chave:sub(1, 7) == "atalho_"
end

function config.set(
    chave,
    valor
)

    if config.dados[chave] == nil
    and not chaveLivre(chave) then
        return
    end

    if valor == nil and chaveLivre(chave) then
        config.dados[chave] = nil
        config.salvar()
        return
    end

    config.dados[chave] =
        valor

    config.salvar()
end

--------------------------------------------------
-- RESETAR
--------------------------------------------------

function config.resetar()

    config.dados = {}

    for chave, valor in pairs(padrao) do

        config.dados[chave] =
            valor
    end

    config.salvar()
end

return config