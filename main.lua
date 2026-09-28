local controles = require("controles")
local osu = require("osu_parser")
local chart = require("chart")
local hit = require("hit_system")
local config = require("config_manager")
local pauseMenu = require("pause_menu")
local music = require("music")
local ui = require("gameplay_ui")
local biblioteca = require("beatmap_library")
local bot = require("systems.bot")
local hud = require("hud")
local fps = require("systems.fps")
local background = require("systems.background")
local inputMode = require("input_mode")
local tema = require("tema")
local opcoes = require("opcoes")
local armazenamento = require("armazenamento")
local hitsound = require("hitsound")
local resolucao = require("systems.resolucao")

local function usaControlesPC()
    return inputMode.usaPC(config)
end

local function usaControlesTouch()
    return inputMode.usaTouch(config)
end


--------------------------------------------------
-- JANELA / CURSOR (PC)
--------------------------------------------------

local cursorIdle = 0
local cursorIdleLimite = 2.0
local cursorVisivel = true
local vsyncAplicado = nil

-- Evita que um mesmo toque físico seja processado duas vezes.
-- Cada dedo possui um ID próprio no LÖVE; enquanto o ID estiver ativo,
-- novos touchpressed com o mesmo ID são ignorados.
local toquesAtivos = {}

local function mostrarCursor()
    cursorIdle = 0
    if not cursorVisivel then
        love.mouse.setVisible(true)
        cursorVisivel = true
    end
end

local function atualizarCursorIdle(dt)
    if not usaControlesPC() then
        return
    end

    cursorIdle = cursorIdle + dt

    if cursorIdle >= cursorIdleLimite
    and cursorVisivel then
        love.mouse.setVisible(false)
        cursorVisivel = false
    end
end

local function salvarTamanhoJanela(w, h)
    if not w or not h then return end
    local _, _, flags = love.window.getMode()
    if flags and flags.fullscreen then return end
    config.set("windowWidth", math.floor(w))
    config.set("windowHeight", math.floor(h))
end

local function alternarTelaCheia()
    local w, h, flags = love.window.getMode()
    local fullscreen = flags and flags.fullscreen == true

    if fullscreen then
        local janelaW = tonumber(config.get("windowWidth")) or 1280
        local janelaH = tonumber(config.get("windowHeight")) or 720
        love.window.setMode(janelaW, janelaH, {
            fullscreen = false,
            resizable = true,
            vsync = 0,
            highdpi = true
        })
        config.set("windowWidth", janelaW)
        config.set("windowHeight", janelaH)
    else
        config.set("windowWidth", w)
        config.set("windowHeight", h)
        love.window.setMode(w, h, {
            fullscreen = true,
            resizable = false,
            vsync = 0,
            highdpi = true
        })
    end

    mostrarCursor()
end


--------------------------------------------------
-- FPS
--------------------------------------------------
local function atualizarLimiteFPS()

    local valor =
        tonumber(config.get("fpsLimite"))

    if valor == nil then
        valor = 120
    end

    valor = math.max(
        0,
        math.min(
            1000,
            valor
        )
    )

    FPS_LIMITE = valor
end

--------------------------------------------------
-- ESTADO
--------------------------------------------------

local estado = "menu"
local estadoAntesDoPause = "menu"
local estadoAntesDoHudEditor = "playing"

local tempoCountdown = 0
local retomadaTimer = 0
-- "Segurar para reiniciar": o atalho de reiniciar precisa ficar pressionado
-- por resetSegurarSeg segundos; enquanto isso a tela vai escurecendo.
local resetSegurando = false
local resetTecla = nil
local resetProgresso = 0
local resetEscurecer = 0 -- 0..1, opacidade do escurecimento na tela

local function cancelarResetSegurado()
    resetSegurando = false
    resetTecla = nil
    resetProgresso = 0
end
local delayInicio = 3

local beatmapCarregado = false
local nomeBeatmap = "Nenhum beatmap carregado"
local caminhoBeatmap = nil

-- Seletor interno da biblioteca
local beatmapSelecionado = 1
local beatmapScroll = 0
local beatmapTouchStartY = nil
local beatmapTouchLastY = nil
local beatmapTouchMoved = false
local beatmapDragAccum = 0
local beatmapEntradaBloqueada = false
local beatmapEntradaTimer = 0
local beatmapIgnorarToqueInicial = false
local beatmapIgnorarProximoToque = false

--------------------------------------------------
-- BOT
--------------------------------------------------

local function sincronizarBotConfiguracao()
    bot.setAtivo(config.get("botAtivo") == true)
    bot.setDuracaoToque(
        tonumber(config.get("botVelocidadePressao")) or 0.055
    )
end

local function limparBot()
    bot.limpar(controles)
end

local function atualizarBot(dt)
    sincronizarBotConfiguracao()
    bot.atualizar(dt, estado, chart, hit, controles)
end

--------------------------------------------------
-- JULGAMENTO
--------------------------------------------------

local ultimoJulgamento = ""

--------------------------------------------------
-- IMAGEM DE FUNDO
--------------------------------------------------

local function limparImagemFundo()
    background.limpar()
end

local function carregarImagemFundo(mapa, caminho)
    return background.carregar(mapa, caminho)
end

local function desenharImagemFundo()
    background.desenhar(config)
end

--------------------------------------------------
-- CONFIGURAÇÕES
--------------------------------------------------

local function aplicarConfiguracoes()

    chart.setVelocidade(
        tonumber(
            config.get("velocidade")
        ) or 800
    )

    music.setVolume(
        (
            tonumber(
                config.get("volumeMusica")
            ) or 100
        ) / 100
    )

    chart.setConfiguracaoVisual({
        alturaStrumline = tonumber(config.get("alturaStrumline")) or 50,
        direcao = config.get("direcao") or "down"
    })

    ui.setEspacamento(
        tonumber(
            config.get("espacamento")
        ) or 80
    )

    ui.setTamanhoBola(
        tonumber(
            config.get("tamanhoBola")
        ) or 35
    )

    ui.setGrossuraHold(
        tonumber(
            config.get("grossuraHold")
        ) or 1.0
    )

    ui.setDirecao(
        config.get("direcao")
        or "down"
    )

    ui.setAlturaStrumline(
        tonumber(
            config.get("alturaStrumline")
        ) or 50
    )

    hit.aplicarConfiguracao(
        config
    )

    hud.aplicarConfiguracao(config)
    sincronizarBotConfiguracao()

    tema.configurar(config)
    ui.aplicarConfiguracao(config)
    hitsound.aplicarConfiguracao(config)
    resolucao.aplicar(config)

    -- tempo para esconder o cursor (0 = nunca)
    local ocultar = tonumber(config.get("ocultarCursorSeg")) or 2
    cursorIdleLimite = ocultar > 0 and ocultar or math.huge

    -- VSync (só chama quando muda)
    local vsync = config.get("vsync") == true

    if vsyncAplicado ~= vsync then
        vsyncAplicado = vsync
        pcall(love.window.setVSync, vsync and 1 or 0)
    end

    delayInicio =
        tonumber(
            config.get("delayInicio")
        ) or 3

    atualizarLimiteFPS()

end

--------------------------------------------------
-- CARREGAR BEATMAP DA BIBLIOTECA
--------------------------------------------------

-- Vídeo de fundo (.ogv): carregado junto com o beatmap.
local function background_video_carregar(mapa)
    local ok, erro = pcall(
        background.carregarVideo,
        mapa,
        osu.videoFundo,
        osu.videoOffset
    )

    if not ok then
        print("ERRO AO CARREGAR VIDEO:", tostring(erro))
    end
end

local function carregarBeatmapDaBiblioteca(mapa)

    if not mapa
    or not mapa.arquivo then

        print("Mapa invalido.")
        return false
    end

    print("================================")
    print("CARREGANDO BEATMAP")
    print("Nome:", mapa.nome)
    print("Dificuldade:", mapa.dificuldade)
    print("Arquivo:", mapa.arquivo)
    print("Pasta:", mapa.pasta)
    print("================================")

    --------------------------------------------------
    -- CARREGAR OSU
    --------------------------------------------------

    local sucesso, resultadoParser =
        pcall(function()

            return osu.carregar(
                mapa.arquivo
            )

        end)

    if not sucesso then

        print("ERRO AO CARREGAR BEATMAP:")
        print(tostring(resultadoParser))

        return false
    end

    if type(resultadoParser) ~= "table" then

        print(
            "ERRO: parser nao retornou uma tabela."
        )

        return false
    end

    --------------------------------------------------
    -- O PARSER RETORNA DIRETAMENTE AS NOTAS
    --------------------------------------------------

    chart.carregar(
        resultadoParser
    )

    chart.definirBpm(
        osu.bpm,
        osu.offsetBpm
    )

    hit.resetar(
        chart.getNotas()
    )

    --------------------------------------------------
    -- BACKGROUND
    --------------------------------------------------

    local background =
        osu.imagemFundo

    if not background
    or background == "" then

        background =
            mapa.background
    end

    if background
    and background ~= "" then

        carregarImagemFundo(
            mapa,
            background
        )

    else

        limparImagemFundo()

        print(
            "Nenhum background encontrado."
        )

    end

    -- vídeo de fundo (.ogv), se o beatmap tiver
    background_video_carregar(mapa)

    --------------------------------------------------
    -- CARREGAR MUSICA
    --------------------------------------------------

    local musicaCarregada =
        music.carregar(
            mapa.pasta
        )

    if not musicaCarregada then

        print(
            "AVISO: musica nao encontrada."
        )

    end

    --------------------------------------------------
    -- INFORMACOES
    --------------------------------------------------

    beatmapCarregado = true

    nomeBeatmap =
        tostring(mapa.nome)
        .. " ["
        .. tostring(mapa.dificuldade)
        .. "]"

    caminhoBeatmap =
        mapa.arquivo

    love.filesystem.write(
        "ultimo_beatmap.txt",
        mapa.arquivo
    )

    print("================================")
    print("BEATMAP CARREGADO")
    print(
        "Notas:",
        chart.getQuantidadeNotas()
    )
    print(
        "Musica:",
        musicaCarregada
            and "OK"
            or "NAO ENCONTRADA"
    )
    print("================================")

    return true
end

--------------------------------------------------
-- CARREGAR ULTIMO BEATMAP
--------------------------------------------------

local function carregarUltimoBeatmap()

    local caminho =
        love.filesystem.read(
            "ultimo_beatmap.txt"
        )

    if not caminho
    or caminho == "" then

        return false
    end

    caminho =
        caminho:gsub("^%s+", "")
               :gsub("%s+$", "")

    local mapas =
        biblioteca.listar()

    if type(mapas) == "table" then

        for _, mapa in ipairs(mapas) do

            if mapa.arquivo == caminho then

                if love.filesystem.getInfo(
                    mapa.arquivo
                ) then

                    return carregarBeatmapDaBiblioteca(
                        mapa
                    )

                end
            end
        end
    end

    print(
        "Ultimo beatmap nao encontrado na biblioteca."
    )

    return false
end

--------------------------------------------------
-- BEATMAP PADRAO
--------------------------------------------------

local function carregarBeatmapPadrao()

    local mapaPadrao = {
        id = "beatmap_padrao",
        nome = "Beatmap Padrao",
        dificuldade = "Normal",
        arquivo = "beatmaps/default/default.osu",
        pasta = "beatmaps/default",
        background = "background.jpg"
    }

    if not love.filesystem.getInfo(
        mapaPadrao.arquivo
    ) then

        print("================================")
        print("BEATMAP PADRAO NAO ENCONTRADO")
        print("Arquivo:", mapaPadrao.arquivo)
        print("================================")

        return false
    end

    print("================================")
    print("CARREGANDO BEATMAP PADRAO")
    print("================================")

    local sucesso =
        carregarBeatmapDaBiblioteca(
            mapaPadrao
        )

    if sucesso then
        print("Beatmap padrao carregado com sucesso!")
    else
        print("ERRO AO CARREGAR BEATMAP PADRAO.")
    end

    return sucesso
end

--------------------------------------------------
-- SELETOR DE BEATMAP
--------------------------------------------------

local function abrirSeletorBeatmap()

    love.window.showFileDialog(
        "openfile",
        function(
            files,
            filtername,
            errorstring
        )

            if errorstring then

                print(
                    "Erro ao selecionar arquivo:"
                )

                print(
                    errorstring
                )

                return
            end

            if not files
            or #files == 0 then

                return
            end

            local caminho =
                files[1]

            print("================================")
            print("OSZ SELECIONADO")
            print(caminho)
            print("================================")

            --------------------------------------------------
            -- IMPORTAR
            --------------------------------------------------

            local sucesso,
                  resultadoImportacao =

                pcall(function()

                    return biblioteca.importarOSZ(
                        caminho
                    )

                end)

            if not sucesso then

                print(
                    "ERRO AO IMPORTAR OSZ:"
                )

                print(
                    tostring(
                        resultadoImportacao
                    )
                )

                return
            end

            if not resultadoImportacao
            or #resultadoImportacao == 0 then

                print(
                    "Nenhum beatmap foi importado."
                )

                return
            end

            --------------------------------------------------
            -- CARREGAR PRIMEIRO MAPA
            --------------------------------------------------

            local primeiro =
                resultadoImportacao[1]

            if not primeiro then
                return
            end

            local carregou =
                carregarBeatmapDaBiblioteca(
                    primeiro
                )

            if not carregou then

                print(
                    "Nao foi possivel carregar o beatmap."
                )

                return
            end

            print("================================")
            print("BIBLIOTECA")
            print("================================")

            local todos =
                biblioteca.listar()

            for i, mapa in ipairs(todos) do

                print(
                    i ..
                    " - " ..
                    mapa.nome ..
                    " [" ..
                    mapa.dificuldade ..
                    "]"
                )

            end

            print("================================")

        end
    )
end

--------------------------------------------------
-- LISTA DE BEATMAPS
--------------------------------------------------

-- Ordem: do mais fácil para o mais difícil (dificuldade estimada pela
-- densidade de notas). Empates ficam em ordem alfabética.
-- Músicas em ordem alfabética; charts da mesma música ficam juntos,
-- do mais fácil para o mais difícil (ver beatmap_library.ordenar).
local function ordenarBeatmaps(mapas)
    biblioteca.ordenar(mapas)
end

local function abrirListaBeatmaps()

    local mapas = biblioteca.listar()

    if type(mapas) ~= "table" then
        mapas = {}
    end

    ordenarBeatmaps(mapas)

    beatmapSelecionado = 1
    beatmapScroll = 0

    if caminhoBeatmap then

        for i, mapa in ipairs(mapas) do

            if mapa.arquivo == caminhoBeatmap then
                beatmapSelecionado = i
                break
            end
        end
    end

    estado = "beatmap_list"

    -- O mesmo toque que abriu a biblioteca não pode selecionar um item.
    beatmapEntradaTimer = 0.16
    beatmapEntradaBloqueada = true
    beatmapIgnorarProximoToque = true
end

local function carregarBeatmapSelecionado()

    local mapas = biblioteca.listar()

    if type(mapas) ~= "table"
    or #mapas == 0 then
        return false
    end

    if beatmapSelecionado < 1 then
        beatmapSelecionado = 1
    end

    if beatmapSelecionado > #mapas then
        beatmapSelecionado = #mapas
    end

    local mapa = mapas[beatmapSelecionado]

    if not mapa then
        return false
    end

    if not love.filesystem.getInfo(
        mapa.arquivo
    ) then

        print(
            "Beatmap nao encontrado: " ..
            tostring(mapa.arquivo)
        )

        return false
    end

    local sucesso =
        carregarBeatmapDaBiblioteca(
            mapa
        )

    if sucesso then
        estado = "menu"
    end

    return sucesso
end

local function moverSelecaoBeatmap(delta)

    local mapas = biblioteca.listar()

    if type(mapas) ~= "table"
    or #mapas == 0 then
        return
    end

    beatmapSelecionado =
        beatmapSelecionado + delta

    if beatmapSelecionado < 1 then
        beatmapSelecionado = #mapas
    elseif beatmapSelecionado > #mapas then
        beatmapSelecionado = 1
    end

    beatmapScroll =
        math.max(
            0,
            beatmapSelecionado - 1
        )
end

--------------------------------------------------
-- INICIAR CHART
--------------------------------------------------

-- true só quando a opção está ligada E o beatmap atual tem BPM detectado
-- (arquivos antigos ou sem [TimingPoints] caem sempre no modo normal).
local function contagemPorBpmAtiva()
    return config.get("countdownBpm") == true and chart.temBpm()
end

-- Quanto tempo a contagem inicial deve durar.
--
-- Modo normal: o valor configurado é em segundos (3 = "3, 2, 1" a 1 por
-- segundo).
--
-- Modo BPM: o valor configurado vira a QUANTIDADE de números mostrados
-- (3 = "3, 2, 1"), cada um durando exatamente uma batida da música. Em
-- uma música rápida isso dura menos que 3 segundos; o que o jogador
-- configurou continua sendo a quantidade de números na tela. (Antes,
-- convertíamos os segundos em batidas, e um BPM alto virava uma contagem
-- de 8, 11 números.)
local function duracaoContagemInicial(valorConfigurado)
    if not contagemPorBpmAtiva() or valorConfigurado <= 0 then
        return valorConfigurado
    end

    local quantidade = math.max(1, math.floor(valorConfigurado + 0.5))

    return quantidade * chart.duracaoBatida()
end

-- Número exibido na tela (3, 2, 1...) a partir do tempo restante: em
-- segundos no modo normal, em batidas no modo BPM.
local function numeroDaContagem(restante)
    if contagemPorBpmAtiva() then
        return math.max(1, math.ceil(restante / chart.duracaoBatida()))
    end

    return math.max(1, math.ceil(restante))
end

local function iniciarChart()

    if not beatmapCarregado then

        print(
            "Nenhum beatmap carregado."
        )

        return
    end

    music.parar()
    background.pararVideo()
    retomadaTimer = 0

    limparBot()

    aplicarConfiguracoes()

    delayInicio =
        tonumber(
            config.get("delayInicio")
        ) or 3

    tempoCountdown =
        duracaoContagemInicial(delayInicio)

    chart.resetar(
        tempoCountdown
    )

    hit.resetar(
        chart.getNotas()
    )

    ultimoJulgamento = ""

    fps.resetar()

    estado =
        "countdown"

end

--------------------------------------------------
-- PAUSE
--------------------------------------------------

local function reiniciarChart()
    music.parar()
    background.pararVideo()
    retomadaTimer = 0
    limparBot()
    aplicarConfiguracoes()

    delayInicio = tonumber(config.get("delayInicio")) or 3
    tempoCountdown = duracaoContagemInicial(delayInicio)
    chart.resetar(tempoCountdown)
    hit.resetar(chart.getNotas())
    ultimoJulgamento = ""
    fps.resetar()

    pauseMenu.fechar()
    estado = "countdown"
end

local function abrirEditorHUD()
    estadoAntesDoHudEditor = estadoAntesDoPause
    if estadoAntesDoHudEditor ~= "playing"
    and estadoAntesDoHudEditor ~= "countdown"
    and estadoAntesDoHudEditor ~= "menu" then
        estadoAntesDoHudEditor = "playing"
    end
    pauseMenu.fechar()
    hud.iniciarEditor()
    estado = "hud_editor"
end

local function fecharEditorHUD()
    hud.fecharEditor()
    estado = estadoAntesDoHudEditor or "playing"
    if estado == "playing" then
        music.resumir()
        local offset = tonumber(config.get("offset")) or 0
        chart.sincronizarTempo(music.getTempo() + (offset / 1000))
    end
end

local function abrirPause()

    estadoAntesDoPause =
        estado

    limparBot()

    if estado == "playing" then
        music.pausar()
        background.pausarVideo()
    end

    retomadaTimer = 0

    cancelarResetSegurado()
    resetEscurecer = 0

    pauseMenu.definirInfo(nomeBeatmap)
    pauseMenu.abrir()

end

-- Configurações abertas pelo menu principal (sem partida em andamento).
local function abrirConfigMenu()

    estadoAntesDoPause =
        estado

    pauseMenu.abrir("config", true)

end

local function retomarJogo()

    pauseMenu.fechar()

    if estadoAntesDoPause == "playing" then

        estado =
            "playing"

        local offset =
            tonumber(
                config.get(
                    "offset"
                )
            ) or 0

        if config.get("contagemRetomar") ~= false then

            -- 3, 2, 1 antes de a música voltar (3 batidas no modo BPM)
            retomadaTimer =
                contagemPorBpmAtiva() and (3 * chart.duracaoBatida()) or 3

            chart.sincronizarTempo(
                music.getTempo() +
                (offset / 1000)
            )

        else

            music.resumir()

            chart.sincronizarTempo(
                music.getTempo() +
                (offset / 1000)
            )

            background.retomarVideo(
                music.getTempo()
            )
        end

    elseif estadoAntesDoPause == "countdown" then

        estado =
            "countdown"

    else

        estado =
            estadoAntesDoPause

    end
end

--------------------------------------------------
-- AÇÕES DO MENU DE PAUSA / ATALHOS
--------------------------------------------------

local function tratarAcaoPause(acao)

    if not acao then
        return
    end

    local semPartida =
        estado == "menu"
        or (
            pauseMenu.estaAberto()
            and estadoAntesDoPause == "menu"
        )

    if acao == "continuar" or acao == "resumir" then

        aplicarConfiguracoes()
        retomarJogo()

    elseif acao == "configuracao" then

        aplicarConfiguracoes()

    elseif acao == "resetar" then

        if semPartida then
            tema.toast("Disponível durante uma partida", "erro")
        else
            reiniciarChart()
        end

    elseif acao == "sair" then

        if semPartida then
            tema.toast("Você já está no menu", "erro")
        else
            music.parar()
            background.pararVideo()
            retomadaTimer = 0
            limparBot()
            pauseMenu.fechar()
            estado = "menu"
        end

    elseif acao == "editar_hud" then

        aplicarConfiguracoes()
        abrirEditorHUD()

    elseif acao == "tela_cheia" then

        alternarTelaCheia()

    elseif acao == "alternar_pausa" then

        if pauseMenu.estaAberto() then

            aplicarConfiguracoes()
            retomarJogo()

        elseif estado == "playing"
        or estado == "countdown" then

            abrirPause()
        end

    elseif acao == "recarregar_config" then

        if controles.carregarTeclas then
            controles.carregarTeclas(config)
        end

        if controles.carregarBotoes then
            controles.carregarBotoes(config)
        end

        aplicarConfiguracoes()
    end
end

--------------------------------------------------
-- ENTRADA
--------------------------------------------------

local function pressionarLaneEntrada(
    id,
    lane
)

    if not lane
    or lane < 1
    or lane > 4 then

        return
    end

    if estado ~= "playing"
    and estado ~= "countdown" then

        return
    end

    -- durante o 3, 2, 1 depois de pausar, nada é acertado
    if retomadaTimer > 0 then
        return
    end

    local largura =
        love.graphics.getWidth()

    local tamanhoTile =
        largura / 4

    local x =
        (lane - 0.5) *
        tamanhoTile

    local y =
        love.graphics.getHeight() - 50

    controles.pressionou(
        id,
        x,
        y
    )

    if estado == "playing" then

        local offset =
            tonumber(
                config.get("offset")
            ) or 0

        local tempoAjustado =
            music.getTempo() +
            (offset / 1000)

        if hit.tentar(
            chart.getNotas(),
            lane,
            tempoAjustado
        ) then
            hitsound.tocar()
        end
    end
end

local function soltarLaneEntrada(
    id,
    lane
)

    if not lane
    or lane < 1
    or lane > 4 then

        return
    end
    controles.soltou(id)

    if estado == "playing" then

        local offset =
            tonumber(
                config.get("offset")
            ) or 0

        local tempoAjustado =
            music.getTempo() +
            (offset / 1000)

        hit.soltarLane(
            chart.getNotas(),
            lane,
            tempoAjustado
        )
    end
end

--------------------------------------------------
-- LOAD
--------------------------------------------------

function love.load()

    estado = "menu"
    tempoCountdown = 0

    if type(config.carregar) == "function" then
        config.carregar()
    end

    local janelaW = tonumber(config.get("windowWidth")) or 1280
    local janelaH = tonumber(config.get("windowHeight")) or 720
    love.window.setMode(janelaW, janelaH, {
        fullscreen = true,
        resizable = false,
        vsync = 0,
    })
    love.mouse.setVisible(true)
    cursorIdle = 0
    cursorVisivel = true

    tema.configurar(config)
    pauseMenu.configurar(config, controles)
    resolucao.aplicar(config)

    -- pasta externa de beatmaps (Documentos/FunkyStudio no Windows)
    pcall(armazenamento.montar, config)

    if type(biblioteca.carregar) == "function" then

        biblioteca.carregar()

        local mapas =
            biblioteca.listar()

        print("================================")
        print("BIBLIOTECA CARREGADA")
        print(
            "Beatmaps:",
            #mapas
        )
        print("================================")

        --------------------------------------------------
        -- SE NAO EXISTIR NENHUM BEATMAP
        --------------------------------------------------

        if #mapas == 0 then

            print(
                "Nenhum beatmap encontrado."
            )

            carregarBeatmapPadrao()

        end
    end

    if controles.carregarTeclas then

        controles.carregarTeclas(
            config
        )

    end

    if controles.carregarBotoes then

        controles.carregarBotoes(
            config
        )

    end

    aplicarConfiguracoes()

    local ultimoCarregado = false
    local sucessoUltimo, resultadoUltimo = pcall(carregarUltimoBeatmap)
    if sucessoUltimo then
        ultimoCarregado = resultadoUltimo == true
    end

    if not ultimoCarregado and not beatmapCarregado then
        carregarBeatmapPadrao()
    end

    estado = "menu"

end

--------------------------------------------------
-- UPDATE
--------------------------------------------------

local function resetSegurarAtivo()
    return config.get("resetSegurar") == true
end

local function iniciarResetSegurado(tecla)
    resetSegurando = true
    resetTecla = tecla
    resetProgresso = 0
end

-- Avança o "segurar para reiniciar": a tela escurece até o tempo definido
-- pelo jogador e, ao completar, reinicia. Fora do escurecimento, a
-- opacidade volta a zero rápido (cancelou ou acabou de reiniciar).
local function atualizarResetSegurado(dt)

    local emPartida =
        estado == "playing" or estado == "countdown"

    if resetSegurando and not emPartida then
        cancelarResetSegurado()
    end

    if resetSegurando then

        local duracao =
            math.max(
                0.1,
                tonumber(config.get("resetSegurarSeg")) or 1.5
            )

        resetProgresso = resetProgresso + dt
        resetEscurecer = math.min(1, resetProgresso / duracao)

        if resetProgresso >= duracao then
            cancelarResetSegurado()
            reiniciarChart()
        end

    elseif resetEscurecer > 0 then

        resetEscurecer = math.max(0, resetEscurecer - dt * 3)
    end
end

function love.update(dt)

    atualizarCursorIdle(dt)

    -- Não bloqueia: só confere se a varredura de beatmaps em segundo
    -- plano (Debug > Reescanear beatmaps) já terminou.
    if biblioteca.verificarAsync then
        biblioteca.verificarAsync()
    end

    if pauseMenu.estaAberto() then
        pauseMenu.atualizar(dt)
        return
    end

    tema.atualizarToasts(dt)

    if estado == "hud_editor" then
        return
    end

    atualizarResetSegurado(dt)

    --------------------------------------------------
    -- LISTA DE BEATMAPS
    --------------------------------------------------

    -- A lista e desenhada em love.draw().
    if estado == "beatmap_list" then
        if beatmapEntradaBloqueada then
            beatmapEntradaTimer = beatmapEntradaTimer - dt
            if beatmapEntradaTimer <= 0 then
                beatmapEntradaTimer = 0
                beatmapEntradaBloqueada = false
            end
        end
        return
    end

    --------------------------------------------------
    -- COUNTDOWN
    --------------------------------------------------

    if estado == "countdown" then

        tempoCountdown =
            tempoCountdown - dt

        chart.atualizar(dt)

        if tempoCountdown <= 0 then

            tempoCountdown = 0

            estado = "playing"

            fps.resetar()

            local tocou =
                music.tocar()

            if not tocou then

                print("================================")
                print(
                    "ERRO: NAO FOI POSSIVEL TOCAR A MUSICA"
                )
                print(
                    "Beatmap:",
                    nomeBeatmap
                )
                print(
                    "Arquivo:",
                    caminhoBeatmap
                )
                print("================================")

                estado = "menu"

                return
            end

            local offset =
                tonumber(
                    config.get("offset")
                ) or 0

            chart.sincronizarTempo(
                music.getTempo() +
                (offset / 1000)
            )

            background.iniciarVideo(
                music.getTempo()
            )

        end

        return
    end

    --------------------------------------------------
    -- PLAYING
    --------------------------------------------------

    if estado == "playing" then

        if retomadaTimer > 0 then

            retomadaTimer = retomadaTimer - dt

            if retomadaTimer <= 0 then

                retomadaTimer = 0

                music.resumir()

                background.retomarVideo(
                    music.getTempo()
                )
            end

            return
        end

        fps.atualizar(dt)

        background.atualizarVideo(
            music.getTempo()
        )

        local offset =
            tonumber(
                config.get("offset")
            ) or 0

        chart.atualizar(dt)

        chart.sincronizarTempo(
            music.getTempo() +
            (offset / 1000),
            dt
        )

        atualizarBot(dt)

        hit.atualizar(
            chart.getNotas(),
            chart.getTempo(),
            dt
        )

        ultimoJulgamento =
            hit.getUltimoJulgamento()

        if not music.estaTocando() then

            if music.getTempo() > 0 then

                limparBot()

                music.parar()

                background.pararVideo()

                estado = "menu"

            end
        end
    end
end

--------------------------------------------------
-- DRAW
--------------------------------------------------

--------------------------------------------------
-- MENU PRINCIPAL / BIBLIOTECA (visual)
--------------------------------------------------

local function layoutMenu()

    local W, H = love.graphics.getDimensions()
    local k = tema.escala()

    local itens = {
        {id = "iniciar",    texto = "INICIAR",                icone = "play",       estilo = "primario"},
        {id = "biblioteca", texto = "BIBLIOTECA DE BEATMAPS", icone = "nota",       estilo = "secundario"},
        {id = "osz",        texto = "CARREGAR OSZ",           icone = "mais",       estilo = "secundario"},
        {id = "config",     texto = "CONFIGURAÇÕES",          icone = "engrenagem", estilo = "secundario"},
    }

    local bw = math.min(W - 40, 380 * k)
    local bh = 56 * k
    local gap = 12 * k
    local total = #itens * bh + (#itens - 1) * gap
    local y0 = math.max(H * 0.36, H - total - 30 * k)

    if y0 + total > H - 8 then
        y0 = math.max(8, H - total - 8)
    end

    for i, it in ipairs(itens) do
        it.x = (W - bw) / 2
        it.y = y0 + (i - 1) * (bh + gap)
        it.w = bw
        it.h = bh
    end

    return itens, W, H, k
end

local function desenharMenu()

    tema.fundo()

    local itens, W, H, k = layoutMenu()
    local primeiro = itens[1]

    -- título
    local ft = tema.fonte(60 * k)

    love.graphics.setFont(ft)
    tema.cor("texto")
    love.graphics.printf(
        "FunkyStudio",
        0,
        math.max(10, primeiro.y - 96 * k - 150 * k),
        W,
        "center"
    )

    -- cartão do beatmap atual
    local cw = math.min(W - 40, 520 * k)
    local ch = 74 * k
    local cx = (W - cw) / 2
    local cy = math.max(10, primeiro.y - ch - 18 * k)

    tema.painel(cx, cy, cw, ch)

    local fn = tema.fonte(18 * k)
    local fs = tema.fonte(12 * k)

    love.graphics.setFont(fn)
    tema.cor("texto")
    love.graphics.printf(
        tema.ajustarTexto(fn, nomeBeatmap, cw - 40 * k),
        cx + 20 * k, cy + 12 * k, cw - 40 * k, "center"
    )

    love.graphics.setFont(fs)
    tema.cor(beatmapCarregado and "ok" or "perigo")
    love.graphics.printf(
        beatmapCarregado and "BEATMAP CARREGADO" or "NENHUM BEATMAP",
        cx + 20 * k, cy + ch - fs:getHeight() - 12 * k, cw - 40 * k, "center"
    )

    -- botões
    local mx, my = resolucao.paraVirtual(love.mouse.getPosition())
    local usaMouse = usaControlesPC()

    for _, it in ipairs(itens) do

        local sobre = usaMouse
            and tema.dentro(mx, my, it.x, it.y, it.w, it.h)

        tema.botao(it.x, it.y, it.w, it.h, it.texto, {
            estilo = it.estilo,
            icone = it.icone,
            hover = sobre and 1 or 0,
            fonte = tema.fonte(17 * k),
        })
    end
end

local function corDificuldade(estrelas)

    if estrelas < 3 then return {0.35, 0.90, 0.50} end
    if estrelas < 6 then return {0.30, 0.80, 1.00} end
    if estrelas < 9 then return {1.00, 0.85, 0.30} end
    if estrelas < 12 then return {1.00, 0.55, 0.30} end

    return {1.00, 0.35, 0.55}
end

local function desenharLista(largura, altura)

    tema.fundo()

    local k = math.min(tema.escala(), 1.1)

    local ftit = tema.fonte(26 * k)
    love.graphics.setFont(ftit)
    tema.cor("texto")
    love.graphics.printf("BIBLIOTECA DE BEATMAPS", 20, 28, largura - 40, "center")

    local mapas = biblioteca.listar()
    local fdica = tema.fonte(12 * math.min(k, 1))

    love.graphics.setFont(fdica)

    if type(mapas) ~= "table" or #mapas == 0 then

        tema.cor("mudo")
        love.graphics.printf(
            "Nenhum beatmap salvo.\nColoque .osz na pasta de beatmaps ou use CARREGAR OSZ.",
            20, altura / 2 - 30, largura - 40, "center"
        )

        tema.cor("mudo", 0.8)
        love.graphics.printf("ESC para voltar", 20, altura - 45, largura - 40, "center")

        return
    end

    local itemAltura = 58
    local inicioY = 90
    local visiveis = math.max(1, math.floor((altura - 155) / itemAltura))

    if beatmapSelecionado < 1 then
        beatmapSelecionado = 1
    end

    if beatmapSelecionado > #mapas then
        beatmapSelecionado = #mapas
    end

    beatmapScroll = math.max(
        0,
        math.min(
            beatmapSelecionado - 1,
            math.max(0, #mapas - visiveis)
        )
    )

    local primeiro = beatmapScroll + 1
    local ultimo = math.min(#mapas, primeiro + visiveis - 1)

    local fTitulo = tema.fonte(18 * k)
    local fDif = tema.fonte(14 * k)
    local fEstrela = tema.fonte(15 * k)
    local h = itemAltura - 6

    for i = primeiro, ultimo do

        local mapa = mapas[i]
        local y = inicioY + (i - primeiro) * itemAltura
        local sel = i == beatmapSelecionado
        local anterior = mapas[i - 1]
        local mesmoGrupo = anterior ~= nil and anterior.pasta == mapa.pasta
        local estrelas = (tonumber(mapa.rating) or 0) / 100
        local cor = corDificuldade(estrelas)

        if sel then
            tema.cor("acento", 0.45)
        else
            love.graphics.setColor(0.10, 0.11, 0.21, 0.88)
        end

        tema.retangulo("fill", 20, y, largura - 40, h, 12 * k)

        if sel then
            tema.cor("acento2", 0.95)
            love.graphics.setLineWidth(2)
            tema.retangulo("line", 21, y + 1, largura - 42, h - 2, 12 * k)
            love.graphics.setLineWidth(1)
        end

        -- barra lateral com a cor da dificuldade
        love.graphics.setColor(cor[1], cor[2], cor[3], 1)
        tema.retangulo("fill", 20, y + 7, 5 * k, h - 14, 2)

        -- ligação visual entre charts da mesma música
        if mesmoGrupo then
            love.graphics.setColor(1, 1, 1, 0.14)
            love.graphics.rectangle("fill", 12, y - 6, 2, h / 2 + 6)
        end

        local larguraTexto = largura - 40 - 36 - 120 * k

        love.graphics.setFont(fTitulo)
        tema.cor("texto", mesmoGrupo and 0.55 or 1)
        love.graphics.print(
            tema.ajustarTexto(fTitulo, tostring(mapa.nome or "Beatmap"), larguraTexto),
            36, y + 6 * k
        )

        love.graphics.setFont(fDif)
        love.graphics.setColor(cor[1], cor[2], cor[3], 1)
        love.graphics.print(
            tema.ajustarTexto(fDif, "[" .. tostring(mapa.dificuldade or "Unknown") .. "]", larguraTexto),
            36, y + h - fDif:getHeight() - 6 * k
        )

        -- estrelas (estimativa pela densidade de notas)
        local txt = string.format("%.2f", estrelas)
        local tw = fEstrela:getWidth(txt)
        local ex = largura - 20 - 16 - tw

        love.graphics.setFont(fEstrela)
        tema.cor("texto")
        love.graphics.print(txt, ex, y + (h - fEstrela:getHeight()) / 2)
        tema.icone("estrela", ex - 14 * k, y + h / 2, 15 * k, cor)
    end

    tema.cor("mudo", 0.9)
    love.graphics.setFont(fdica)
    love.graphics.printf(
        (usaControlesPC()
            and "Roda/arrastar: rolar    clique: carregar    CIMA/BAIXO: navegar    ESC: voltar    "
            or "Arraste: rolar    toque: carregar    ")
        .. tostring(#mapas) .. " beatmap(s)",
        20, altura - 45, largura - 40, "center"
    )
end


-- Botão de pausa da gameplay (canto superior direito).
local function desenharBotaoPausaGameplay()

    if config.get("botaoPausa") == false then
        return
    end

    local sobre = 0

    if usaControlesPC() then
        local mx, my = resolucao.paraVirtual(love.mouse.getPosition())
        sobre = tema.dentroBotaoPausa(mx, my) and 1 or 0
    end

    tema.desenharBotaoPausa(sobre)
end

local function desenharTudo()
    
    local largura =
        love.graphics.getWidth()

    local altura =
        love.graphics.getHeight()

    --------------------------------------------------
    -- LISTA DE BEATMAPS
    --------------------------------------------------

    if estado == "beatmap_list" then

        desenharLista(largura, altura)

        return
    end

    --------------------------------------------------
    -- MENU
    --------------------------------------------------

    if estado == "menu" then

        desenharMenu()

        if pauseMenu.estaAberto() then
            pauseMenu.desenhar(config, controles)
        end

        return
    end

    --------------------------------------------------
    -- COUNTDOWN
    --------------------------------------------------

    if estado == "countdown" then

        desenharImagemFundo()

        ui.desenhar(
            chart,
            controles
        )

        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        local numero =
            numeroDaContagem(
                tempoCountdown
            )

        love.graphics.printf(
            tostring(numero),
            0,
            altura / 2 - 50,
            largura,
            "center"
        )

        desenharBotaoPausaGameplay()

        -- Faltava isso: sem desenhar o pause aqui, abrir o pause durante
        -- o countdown "congelava" a tela (o número ficava parado) sem
        -- mostrar o menu — só aparecia depois que o countdown acabava.
        if pauseMenu.estaAberto() then

            pauseMenu.desenhar(
                config,
                controles
            )

        end

        return
    end

    --------------------------------------------------
    -- GAMEPLAY
    --------------------------------------------------

    if estado == "playing" then

        desenharImagemFundo()

        ui.desenhar(
            chart,
            controles
        )

        hud.desenhar(hit, config)
        fps.desenhar(config, chart)

        if bot.estaAtivo() then

            -- Sem setFont, isso herdava a fonte grande do popup de
            -- julgamento (mesma causa do bug do contador de FPS).
            love.graphics.setFont(
                tema.fonte(15 * tema.escala())
            )

            love.graphics.setColor(
                0.3,
                1,
                0.3,
                1
            )

            love.graphics.print(
                "BOT ATIVO",
                10,
                altura - 30
            )

        end

        desenharBotaoPausaGameplay()

        if retomadaTimer > 0 then

            love.graphics.setColor(0, 0, 0, 0.40)
            love.graphics.rectangle("fill", 0, 0, largura, altura)

            local fr = tema.fonte(110 * tema.escala())

            love.graphics.setFont(fr)
            tema.cor("texto")
            love.graphics.printf(
                tostring(numeroDaContagem(retomadaTimer)),
                0,
                altura / 2 - fr:getHeight() / 2,
                largura,
                "center"
            )
        end
    end

    --------------------------------------------------
    -- EDITOR HUD
    --------------------------------------------------

    if estado == "hud_editor" then
        desenharImagemFundo()
        ui.desenhar(chart, controles)
        hud.desenhar(hit, config)
        hud.desenharEditor(config)
        return
    end

    --------------------------------------------------
    -- PAUSE
    --------------------------------------------------

    if pauseMenu.estaAberto() then

        pauseMenu.desenhar(
            config,
            controles
        )

    end
end

function love.draw()

    resolucao.antesDesenhar()

    desenharTudo()

    if resetEscurecer > 0 and not pauseMenu.estaAberto() then
        love.graphics.setColor(0, 0, 0, resetEscurecer)
        love.graphics.rectangle(
            "fill",
            0,
            0,
            love.graphics.getWidth(),
            love.graphics.getHeight()
        )
    end

    if not pauseMenu.estaAberto() then
        tema.desenharToasts()
    end

    love.graphics.setColor(1, 1, 1, 1)

    resolucao.depoisDesenhar()
end

--------------------------------------------------
-- CLIQUES / TOUCH
--
-- Fora do gameplay, o toque no Android é tratado como
-- um clique esquerdo do mouse.
--
-- Durante gameplay/countdown, TOUCH continua reservado
-- aos tiles. No PC, o mouse controla as lanes.
--------------------------------------------------

local function tratarCliqueMenu(x, y)

    if estado ~= "menu" then
        return false
    end

    local itens = layoutMenu()

    for _, it in ipairs(itens) do

        if tema.dentro(x, y, it.x, it.y, it.w, it.h) then

            if it.id == "iniciar" then
                iniciarChart()
            elseif it.id == "biblioteca" then
                abrirListaBeatmaps()
            elseif it.id == "osz" then
                abrirSeletorBeatmap()
            elseif it.id == "config" then
                abrirConfigMenu()
            end

            return true
        end
    end

    return false
end

--------------------------------------------------
-- MODO DE ENTRADA
--
-- Windows -> teclado/mouse.
-- Android/iOS -> touch.
-- Android/iOS + enablePcControls -> teclado/mouse.
--------------------------------------------------

--------------------------------------------------
-- TOUCH PRESSED
--------------------------------------------------

function love.touchpressed(
    id,
    x,
    y,
    dx,
    dy,
    pressure
)

    if not usaControlesTouch() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)

    -- Alguns backends mobile podem reenviar o mesmo touchpressed.
    -- Um ID já ativo não deve pressionar a lane novamente.
    if toquesAtivos[id] then
        return
    end

    toquesAtivos[id] = true

    -- Pause tem prioridade: o toque não pode virar input das lanes.
    if pauseMenu.estaAberto() then
        pauseMenu.touchpressed(id, x, y)
        return
    end

    if estado == "playing"
    or estado == "countdown" then

        if config.get("botaoPausa") ~= false
        and tema.dentroBotaoPausa(x, y) then
            abrirPause()
            return
        end

        local largura = love.graphics.getWidth()
        local tamanhoTile = largura / 4
        local lane = math.floor(x / tamanhoTile) + 1

        if lane >= 1 and lane <= 4 then
            pressionarLaneEntrada(id, lane)
        end

        return
    end

    if estado == "beatmap_list" then
        beatmapTouchStartY = y
        beatmapTouchLastY = y
        beatmapTouchMoved = false
        beatmapDragAccum = 0
        return
    end

    if estado == "hud_editor" then
        local acao =
            hud.touchpressed(
                id,
                x,
                y,
                config
            )

        if acao == "voltar" or acao == "cancelar" then
            fecharEditorHUD()
        end

        return
    end

    if pauseMenu.estaAberto() then
        pauseMenu.touchpressed(id, x, y)
        return
    end

    if estado == "menu" then
        tratarCliqueMenu(x, y)
        return
    end
end

--------------------------------------------------
-- TOUCH MOVED
--------------------------------------------------

function love.touchmoved(
    id,
    x,
    y,
    dx,
    dy,
    pressure
)

    if not usaControlesTouch() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)
    dx, dy = resolucao.paraVirtualDelta(dx, dy)

    -- Com o pause aberto, o dedo pertence exclusivamente ao menu.
    if pauseMenu.estaAberto() then
        pauseMenu.touchmoved(id, x, y, dx, dy)
        return
    end

    if estado == "playing"
    or estado == "countdown" then

        controles.mover(
            id,
            x,
            y,
            dx,
            dy
        )

        return
    end

    if estado == "beatmap_list" then

        if beatmapTouchStartY ~= nil then

            local deltaY =
                y - (beatmapTouchLastY or y)

            if math.abs(
                y - beatmapTouchStartY
            ) > 8 then
                beatmapTouchMoved = true
            end

            if beatmapTouchMoved then

                beatmapDragAccum =
                    beatmapDragAccum + deltaY

                local itemAltura = 58

                while beatmapDragAccum <= -itemAltura do
                    moverSelecaoBeatmap(1)
                    beatmapDragAccum =
                        beatmapDragAccum + itemAltura
                end

                while beatmapDragAccum >= itemAltura do
                    moverSelecaoBeatmap(-1)
                    beatmapDragAccum =
                        beatmapDragAccum - itemAltura
                end
            end

            beatmapTouchLastY = y
        end

        return
    end

    if estado == "hud_editor" then
        hud.touchmoved(id, x, y, dx, dy, config)
        return
    end

    if pauseMenu.estaAberto() then
        pauseMenu.touchmoved(id, x, y, dx, dy)
        return
    end
end

--------------------------------------------------
-- TOUCH RELEASED
--------------------------------------------------

function love.touchreleased(
    id,
    x,
    y,
    dx,
    dy,
    pressure
)

    if not usaControlesTouch() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)

    -- Libera o ID antes de tratar o restante do evento.
    -- Um novo toque poderá reutilizar esse ID normalmente depois.
    toquesAtivos[id] = nil

    -- A soltura também precisa ser consumida pelo pause antes do gameplay.
    if pauseMenu.estaAberto() then
        tratarAcaoPause(
            pauseMenu.touchreleased(id, x, y, config, controles)
        )

        return
    end

    if estado == "playing" then

        local largura =
            love.graphics.getWidth()

        local tamanhoTile =
            largura / 4

        local lane =
            math.floor(
                x / tamanhoTile
            ) + 1

        if lane >= 1 and lane <= 4 then
            soltarLaneEntrada(id, lane)
        else
            controles.soltou(id)
        end

        return
    end

    if estado == "countdown" then
        controles.soltou(id)
        return
    end

    if estado == "beatmap_list" then

        local moveu = beatmapTouchMoved
        local ignorar =
            beatmapIgnorarProximoToque
            or beatmapEntradaBloqueada

        beatmapIgnorarProximoToque = false

        beatmapTouchStartY = nil
        beatmapTouchLastY = nil
        beatmapTouchMoved = false
        beatmapDragAccum = 0

        if moveu or ignorar then
            return
        end

        local mapas = biblioteca.listar()
        local altura = love.graphics.getHeight()
        local itemAltura = 58
        local inicioY = 90

        local visiveis =
            math.max(
                1,
                math.floor(
                    (altura - 155) /
                    itemAltura
                )
            )

        local primeiro = beatmapScroll + 1
        local ultimo =
            math.min(
                #mapas,
                primeiro + visiveis - 1
            )

        if y >= inicioY
        and y < inicioY + visiveis * itemAltura then

            local indice =
                primeiro +
                math.floor(
                    (y - inicioY) /
                    itemAltura
                )

            if indice >= primeiro
            and indice <= ultimo then

                beatmapSelecionado = indice
                carregarBeatmapSelecionado()
            end
        end

        return
    end

    if estado == "hud_editor" then
        local acao =
            hud.touchreleased(id, x, y, config)

        if acao == "voltar" or acao == "cancelar" then
            fecharEditorHUD()
        end

        return
    end

    if pauseMenu.estaAberto() then

        tratarAcaoPause(
            pauseMenu.touchreleased(id, x, y, config, controles)
        )

        return
    end

    -- Menu: o clique acontece no release para manter o comportamento
    -- de botão consistente com o restante das telas.
    if estado == "menu" then
        tratarCliqueMenu(x, y)
        return
    end
end

--------------------------------------------------
-- MOUSE MOVED
--------------------------------------------------

function love.mousemoved(
    x,
    y,
    dx,
    dy,
    istouch
)

    if not usaControlesPC() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)
    dx, dy = resolucao.paraVirtualDelta(dx, dy)

    mostrarCursor()

    -- Mouse real ou mouse-emulado pelo touch.
    if estado == "hud_editor" then

        hud.mousemoved(
            x,
            y,
            config
        )

        return
    end

    if pauseMenu.estaAberto() then

        pauseMenu.mousemoved(
            x,
            y
        )

        if love.mouse.isDown(1)
        and not istouch then

            pauseMenu.mousemovedScroll(
                x,
                y
            )

        end

        return
    end
end

--------------------------------------------------
-- MOUSE PRESSED
--------------------------------------------------

function love.mousepressed(
    x,
    y,
    button,
    istouch,
    presses
)

    if not usaControlesPC() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)

    mostrarCursor()

    if button ~= 1 then
        return
    end

    --------------------------------------------------
    -- EDITOR HUD
    --------------------------------------------------

    if estado == "hud_editor" then

        local acao =
            hud.editorPress(
                x,
                y,
                config
            )

        if acao == "voltar" or acao == "cancelar" then
            fecharEditorHUD()
        end

        return
    end

    --------------------------------------------------
    -- PAUSE
    --------------------------------------------------

    if pauseMenu.estaAberto() then

        pauseMenu.mousepressed(
            x,
            y,
            button
        )

        return
    end

    --------------------------------------------------
    -- BIBLIOTECA
    --------------------------------------------------

    if estado == "beatmap_list" then

        beatmapTouchStartY = y
        beatmapTouchLastY = y
        beatmapTouchMoved = false
        beatmapDragAccum = 0

        return
    end

    --------------------------------------------------
    -- MENU
    --------------------------------------------------

    if estado == "menu" then

        tratarCliqueMenu(
            x,
            y
        )

        return
    end

    if (estado == "playing" or estado == "countdown")
    and config.get("botaoPausa") ~= false
    and tema.dentroBotaoPausa(x, y) then

        abrirPause()

        return
    end

    --------------------------------------------------
    -- GAMEPLAY
    --
    -- No PC, mouse funciona como as lanes.
    --------------------------------------------------

    if estado == "playing" then

        local largura =
            love.graphics.getWidth()

        local lane =
            math.floor(
                x / (largura / 4)
            ) + 1

        if lane >= 1
        and lane <= 4 then

            pressionarLaneEntrada(
                "mouse_lane_" ..
                tostring(lane),
                lane
            )

        end

        return
    end
end

--------------------------------------------------
-- MOUSE RELEASED
--------------------------------------------------

function love.mousereleased(
    x,
    y,
    button,
    istouch,
    presses
)

    if not usaControlesPC() then
        return
    end

    x, y = resolucao.paraVirtual(x, y)

    if button ~= 1 then
        return
    end

    --------------------------------------------------
    -- EDITOR HUD
    --------------------------------------------------

    if estado == "hud_editor" then

        hud.editorRelease(
            config
        )

        return
    end

    --------------------------------------------------
    -- PAUSE
    --------------------------------------------------

    if pauseMenu.estaAberto() then

        tratarAcaoPause(
            pauseMenu.mousereleased(x, y, button, config, controles)
        )

        return
    end

    --------------------------------------------------
    -- BIBLIOTECA
    --------------------------------------------------

    if estado == "beatmap_list" then

        local moveu =
            beatmapTouchMoved

        local ignorar =
            beatmapIgnorarProximoToque
            or beatmapEntradaBloqueada

        beatmapIgnorarProximoToque = false

        if not moveu
        and not ignorar then

            local mapas =
                biblioteca.listar()

            local altura =
                love.graphics.getHeight()

            local itemAltura = 58
            local inicioY = 90

            local visiveis =
                math.max(
                    1,
                    math.floor(
                        (altura - 155) /
                        itemAltura
                    )
                )

            local primeiro =
                beatmapScroll + 1

            local ultimo =
                math.min(
                    #mapas,
                    primeiro +
                    visiveis - 1
                )

            if y >= inicioY
            and y < inicioY +
                visiveis * itemAltura then

                local indice =
                    primeiro +
                    math.floor(
                        (y - inicioY) /
                        itemAltura
                    )

                if indice >= primeiro
                and indice <= ultimo then

                    beatmapSelecionado =
                        indice

                    carregarBeatmapSelecionado()
                end
            end
        end

        beatmapTouchStartY = nil
        beatmapTouchLastY = nil
        beatmapTouchMoved = false
        beatmapDragAccum = 0

        return
    end

    --------------------------------------------------
    -- GAMEPLAY
    --------------------------------------------------

    if estado == "playing" then

        local largura =
            love.graphics.getWidth()

        local lane =
            math.floor(
                x / (largura / 4)
            ) + 1

        if lane >= 1
        and lane <= 4 then

            soltarLaneEntrada(
                "mouse_lane_" ..
                tostring(lane),
                lane
            )

        end

        return
    end
end


function love.wheelmoved(x, y)

    if not usaControlesPC() then
        return
    end

    if estado == "beatmap_list" then
        if y > 0 then
            moverSelecaoBeatmap(-1)
        elseif y < 0 then
            moverSelecaoBeatmap(1)
        end
        return
    end

    if pauseMenu.estaAberto() then
        tratarAcaoPause(pauseMenu.wheelmoved(x, y, config))
        return
    end
end

--------------------------------------------------
-- VOLUME
--------------------------------------------------

local function ehTeclaVolumeMenos(key)
    return key == "-" or key == "kp-"
end

local function ehTeclaVolumeMais(key)
    -- "key" já é a tecla PÓS-shift (KeyConstant do LÖVE): num teclado
    -- padrão, a tecla física "+/=" chega como "=" sem Shift e como "+"
    -- com Shift. Aceitar os dois faz o atalho funcionar sem precisar
    -- segurar Shift.
    return key == "+" or key == "kp+" or key == "="
end

local function ajustarVolumeTeclado(delta)
    local valor =
        tonumber(
            config.get("volumeMusica")
        ) or 100

    valor =
        math.max(
            0,
            math.min(
                100,
                valor + delta
            )
        )

    config.set(
        "volumeMusica",
        valor
    )

    music.setVolume(
        valor / 100
    )
end

--------------------------------------------------
-- TECLADO
--------------------------------------------------

function love.keypressed(
    key,
    scancode,
    isrepeat
)

    if not usaControlesPC() then
        return
    end

    if not isrepeat and key == "f11" then
        alternarTelaCheia()
        return
    end

    if not isrepeat then

        if ehTeclaVolumeMenos(key) then
            ajustarVolumeTeclado(-5)
            return
        end

        if ehTeclaVolumeMais(key) then
            ajustarVolumeTeclado(5)
            return
        end
    end

    if estado == "beatmap_list" then

        if key == "escape" then
            estado = "menu"
            return
        end

        if key == "up" or key == "w" then
            moverSelecaoBeatmap(-1)
            return
        end

        if key == "down" or key == "s" then
            moverSelecaoBeatmap(1)
            return
        end

        if key == "return" or key == "kpenter" or key == "space" then
            carregarBeatmapSelecionado()
            return
        end

        return
    end

    if pauseMenu.estaAberto() then

        local aceitou, acaoTecla =
            pauseMenu.receberTecla(
                key,
                config,
                controles
            )

        if acaoTecla then
            tratarAcaoPause(acaoTecla)
        end

        if aceitou then
            return
        end

        -- atalhos criados pelo jogador (F5) também valem com o pause aberto
        if not isrepeat then

            local acaoAtalho, usou =
                opcoes.tratarAtalho(
                    key,
                    config,
                    {controles = controles}
                )

            if usou then
                tratarAcaoPause(acaoAtalho)
                return
            end
        end

        if not isrepeat and love.keyboard.isDown("lctrl", "rctrl") then
            if key == "b" then
                bot.setAtivo(not bot.estaAtivo())
                config.set("botAtivo", bot.estaAtivo())
                limparBot()
                return
            elseif key == "h" then
                hud.alternar(config)
                return
            elseif key == "r" then
                reiniciarChart()
                return
            elseif key == "p" then
                retomarJogo()
                return
            end
        end

        if key == "escape" then

            retomarJogo()

            return
        end

        return
    end

    if estado == "hud_editor" then
        if key == "escape" or key == "return" or key == "kpenter" then
            hud.confirmar(config)
            fecharEditorHUD()
        else
            hud.teclado(key)
        end
        return
    end

    --------------------------------------------------
    -- ATALHOS CRIADOS PELO JOGADOR (F5 nas configurações)
    --------------------------------------------------

    if not isrepeat then

        local acaoAtalho, usou =
            opcoes.tratarAtalho(
                key,
                config,
                {controles = controles}
            )

        if usou then

            local emPartida =
                estado == "playing" or estado == "countdown"

            if acaoAtalho == "resetar"
            and emPartida
            and resetSegurarAtivo() then

                iniciarResetSegurado(key)
            else
                tratarAcaoPause(acaoAtalho)
            end

            return
        end
    end

    --------------------------------------------------
    -- ATALHOS GLOBAIS
    --------------------------------------------------

    if not isrepeat then
        local ctrl = love.keyboard.isDown("lctrl", "rctrl")

        if ctrl then
            if key == "l" then
                abrirListaBeatmaps()
                return
            elseif key == "r" then
                iniciarChart()
                return
            elseif key == "b" then
                bot.setAtivo(not bot.estaAtivo())
                config.set("botAtivo", bot.estaAtivo())
                return
            elseif key == "h" then
                hud.alternar(config)
                return
            elseif key == "p" and (estado == "playing" or estado == "countdown") then
                abrirPause()
                return
            elseif key == "q" then
                love.event.quit()
                return
            end
        end
    end

    --------------------------------------------------
    -- ATALHOS DO MENU NO PC
    -- L = carregar beatmap
    -- ENTER / ESPACO = dar play
    --------------------------------------------------

    if estado == "menu"
    and not isrepeat then

        if key == "l" then

            abrirListaBeatmaps()
            return

        end

        if key == "return"
        or key == "kpenter"
        or key == "space" then

            iniciarChart()
            return

        end
    end

    local lane =
        controles.teclaParaLane(key)

    if lane
    and not isrepeat then

        pressionarLaneEntrada(
            "keyboard_" ..
            tostring(lane),
            lane
        )

        return
    end

    if key == "b"
    and not isrepeat then

        bot.setAtivo(not bot.estaAtivo())
        config.set("botAtivo", bot.estaAtivo())
        limparBot()

        return
    end

    if key ~= "escape" then
        return
    end

    if estado == "playing" then

        abrirPause()

        return
    end

    if estado == "countdown" then

        abrirPause()

        return
    end

    if estado == "menu" then

        love.event.quit()

        return
    end
end

--------------------------------------------------
-- TECLA SOLTA
--------------------------------------------------

function love.focus(focado)

    if not focado
    and config.get("pausarSemFoco") ~= false
    and estado == "playing"
    and not pauseMenu.estaAberto() then

        abrirPause()
    end
end

function love.resize(w, h)
    resolucao.aoRedimensionar(w, h)

    if usaControlesPC() then
        salvarTamanhoJanela(w, h)
        mostrarCursor()
    end
end

--------------------------------------------------
-- TECLADO
--------------------------------------------------

-- Sem o filtro de usaControlesPC() dos outros callbacks de teclado: esse
-- evento é o que carrega os caracteres digitados de verdade, inclusive
-- pelo teclado virtual do Android (que não passa por love.keypressed de
-- forma confiável), e é assim que "digitar valor" no menu funciona lá.
function love.textinput(t)

    if pauseMenu.estaAberto()
    and pauseMenu.textinput then

        pauseMenu.textinput(t)
    end

end

function love.keyreleased(key)

    if not usaControlesPC() then
        return
    end

    if resetSegurando and key == resetTecla then
        cancelarResetSegurado()
    end

    if pauseMenu.estaAberto() then
        return
    end

    local lane =
        controles.teclaParaLane(key)

    if not lane then
        return
    end

    soltarLaneEntrada(
        "keyboard_" ..
        tostring(lane),
        lane
    )
end

--------------------------------------------------
-- GAMEPAD
--------------------------------------------------

local function idGamepadLane(
    joystick,
    lane
)

    return
        "gamepad:" ..
        tostring(joystick) ..
        ":" ..
        tostring(lane)
end

function love.gamepadpressed(
    joystick,
    button
)

    if pauseMenu.estaAberto() then

        local aceitou, acaoBotao =
            pauseMenu.receberBotao(
                button,
                config,
                controles
            )

        if acaoBotao then
            tratarAcaoPause(acaoBotao)
        end

        if aceitou then
            return
        end

        return
    end

    -- Antes disso não havia como abrir o pause pelo controle: START/B
    -- fazia a mesma coisa que o ESC do teclado.
    if (estado == "playing" or estado == "countdown")
    and (button == "start" or button == "back") then

        abrirPause()

        return
    end

    local lane =
        controles.botaoParaLane(
            button
        )

    if not lane then
        return
    end

    local id =
        idGamepadLane(
            joystick,
            lane
        )

    pressionarLaneEntrada(
        id,
        lane
    )
end

function love.gamepadreleased(
    joystick,
    button
)

    if pauseMenu.estaAberto() then
        return
    end

    local lane =
        controles.botaoParaLane(
            button
        )

    if not lane then
        return
    end

    local id =
        idGamepadLane(
            joystick,
            lane
        )

    soltarLaneEntrada(
        id,
        lane
    )
end

--------------------------------------------------
-- LOVE RUN
--------------------------------------------------

function love.run()

    if love.load then

        love.load(
            love.arg.parseGameArguments(arg),
            arg
        )

    end

    if love.timer then
        love.timer.step()
    end

    local dt = 0

    local tempoProximoFrame =
        love.timer.getTime()

    return function()

        if love.event then

            love.event.pump()

            for name, a, b, c, d, e, f in
                love.event.poll() do

                if name == "quit" then

                    if not love.quit
                    or not love.quit()
                    then

                        return a or 0
                    end
                end

                love.handlers[name](
                    a,
                    b,
                    c,
                    d,
                    e,
                    f
                )
            end
        end

        if love.timer then

            love.timer.step()

            dt =
                love.timer.getDelta()

        end

        if love.update then

            love.update(dt)

        end

        if love.graphics
        and love.graphics.isActive() then

            love.graphics.origin()

            love.graphics.clear(
                love.graphics.getBackgroundColor()
            )

            love.draw()

            love.graphics.present()

        else

            -- Janela minimizada / app em segundo plano: sem isso o modo
            -- ILIMITADO ficaria girando a 100% de CPU sem desenhar nada.
            love.timer.sleep(0.05)

        end

        if FPS_LIMITE > 0 then

            local tempoPorFrame =
                1 / FPS_LIMITE

            tempoProximoFrame =
                tempoProximoFrame +
                tempoPorFrame

            local agora =
                love.timer.getTime()

            local espera =
                tempoProximoFrame -
                agora

            if espera > 0 then

                love.timer.sleep(
                    espera
                )

            else

                tempoProximoFrame =
                    agora

            end

        else

            tempoProximoFrame =
                love.timer.getTime()

        end
    end
end
