-- Definição de TODAS as opções do jogo (abas, seções, tipos) e a lógica de
-- ler/alterar/formatar cada uma, incluindo atalhos de teclado (F5) e ações.
--
-- Reorganizado:
-- * Tudo relacionado às notas fica em GAMEPLAY.
-- * Offset de áudio fica em ÁUDIO > Música.
--
-- Este módulo não desenha nada: o menu de pausa só percorre a lista abaixo.
-- Para adicionar uma opção nova basta acrescentar uma linha em "lista".

local opcoes = {}

--------------------------------------------------
-- ABAS
--------------------------------------------------

opcoes.abas = {
    {id = "gameplay",       nome = "GAMEPLAY",       icone = "nota"},
    {id = "video",          nome = "VÍDEO",          icone = "tela"},
    {id = "audio",          nome = "ÁUDIO",          icone = "som"},
    {id = "hud",            nome = "HUD",            icone = "hud"},
    {id = "controles",      nome = "CONTROLES",      icone = "teclado"},
    {id = "acessibilidade", nome = "ACESSIBILIDADE", icone = "acessibilidade"},
    {id = "qol",            nome = "QoL",            icone = "raio"},
    {id = "debug",          nome = "DEBUG",          icone = "bug"},
}

--------------------------------------------------
-- CONSTRUTORES
--------------------------------------------------

local lista = {}
local porId = {}

local function add(op)
    lista[#lista + 1] = op
    porId[op.id] = op
    return op
end

local function toggle(aba, secao, chave, nome, desc, extra)
    local op = {aba = aba, secao = secao, id = chave, chave = chave,
        nome = nome, desc = desc, tipo = "toggle"}
    for k, v in pairs(extra or {}) do op[k] = v end
    return add(op)
end

local function slider(aba, secao, chave, nome, desc, min, max, passo, fmt)
    local op = {aba = aba, secao = secao, id = chave, chave = chave,
        nome = nome, desc = desc, tipo = "slider",
        min = min, max = max, passo = passo}
    for k, v in pairs(fmt or {}) do op[k] = v end
    return add(op)
end

local function escolha(aba, secao, chave, nome, desc, valores)
    return add({aba = aba, secao = secao, id = chave, chave = chave,
        nome = nome, desc = desc, tipo = "escolha", valores = valores})
end

local function acao(aba, secao, id, nome, desc, extra)
    local op = {aba = aba, secao = secao, id = id, nome = nome, desc = desc,
        tipo = "acao", texto = "EXECUTAR"}
    for k, v in pairs(extra or {}) do op[k] = v end
    return add(op)
end

local function info(aba, secao, id, nome, fn, extra)
    local op = {aba = aba, secao = secao, id = id, nome = nome,
        tipo = "info", texto = fn}
    for k, v in pairs(extra or {}) do op[k] = v end
    return add(op)
end

local MS = {mult = 1000, unidade = " ms", casas = 0}

--------------------------------------------------
-- GAMEPLAY
--------------------------------------------------

slider("gameplay", "Notas", "velocidade", "Velocidade das notas",
    "Quanto maior, mais rápido as notas descem.", 100, 3000, 50, {unidade = " px/s"})
escolha("gameplay", "Notas", "direcao", "Direção das notas",
    "Notas caem de cima para baixo ou sobem de baixo para cima.",
    {{"down", "Descendo"}, {"up", "Subindo"}})
slider("gameplay", "Notas", "alturaStrumline", "Altura da linha de acerto",
    "Distância da linha de acerto até a borda da tela.", -50, 1000, 10, {unidade = " px"})

-- Tudo que altera aparência/posição das notas também fica em Gameplay.
slider("gameplay", "Notas", "tamanhoBola", "Tamanho das notas", nil, 5, 100, 1, {unidade = " px"})
slider("gameplay", "Notas", "espacamento", "Espaçamento entre lanes", nil, 20, 300, 5, {unidade = " px"})
slider("gameplay", "Notas", "grossuraHold", "Grossura do hold", nil, 0.2, 3, 0.1, {casas = 1, unidade = "x"})
slider("gameplay", "Notas", "laneOpacidade", "Destaque das lanes",
    "Mostra o fundo e as divisórias das lanes.", 0, 100, 5, {unidade = "%"})
escolha("gameplay", "Notas", "esquemaCores", "Cores das notas",
    "Daltônico usa a paleta Okabe-Ito, segura para os principais tipos de daltonismo.",
    {{"padrao", "Padrão"}, {"lanes", "Cor por lane"}, {"contraste", "Alto contraste"},
     {"daltonico", "Daltônico"}})
escolha("gameplay", "Notas", "formaNotas", "Forma das notas",
    "\"Por lane\" dá um formato diferente para cada lane, sem depender de cor.",
    {{"circulo", "Círculo"}, {"quadrado", "Quadrado"}, {"losango", "Losango"},
     {"lane", "Por lane"}})
toggle("gameplay", "Notas", "contornoNotas", "Contorno nas notas",
    "Borda escura ao redor das notas para separar do fundo.")
toggle("gameplay", "Notas", "linhasBpm", "Linhas de BPM",
    "Mostra uma linha cruzando as lanes a cada batida da música. " ..
    "Sem efeito em beatmaps sem BPM detectado.")

slider("gameplay", "Tempo", "delayInicio", "Contagem inicial",
    "Segundos de espera antes da música começar.", 0, 10, 0.5,
    {unidade = " s", casas = 1})
toggle("gameplay", "Tempo", "countdownBpm", "Contagem baseada no BPM",
    "Cada número da contagem dura uma batida da música. O valor de " ..
    "\"Contagem inicial\" passa a ser a quantidade de números (3 = 3, 2, 1), " ..
    "não segundos. Sem efeito em beatmaps sem BPM detectado.")

slider("gameplay", "Julgamento", "janelaPerfect", "Janela PERFECT", "Tolerância para PERFECT.",
    0.02, 0.09, 0.005, MS)
slider("gameplay", "Julgamento", "janelaGood", "Janela GOOD", "Tolerância para GOOD.",
    0.04, 0.12, 0.005, MS)
slider("gameplay", "Julgamento", "janelaOk", "Janela OK", "Tolerância para OK.",
    0.06, 0.16, 0.005, MS)
slider("gameplay", "Julgamento", "janelaBad", "Janela BAD", "Tolerância máxima para acertar a nota.",
    0.08, 0.25, 0.005, MS)
toggle("gameplay", "Julgamento", "holdObrigatorioSoltar", "Soltar hold no fim",
    "Exige soltar a tecla no final da nota longa.")

toggle("gameplay", "Assistência", "botAtivo", "Bot (autoplay)",
    "O jogo acerta todas as notas sozinho.")

--------------------------------------------------
-- VÍDEO
--------------------------------------------------

add({aba = "video", secao = "Desempenho", id = "fpsLimite", chave = "fpsLimite",
    nome = "Limite de FPS", desc = "De 15 a 1000. Depois de 1000 vem ILIMITADO e volta para 15.",
    tipo = "fps"})
escolha("video", "Desempenho", "fpsModo", "Contador de FPS",
    "Mostra informações de desempenho na tela.",
    {{0, "Desativado"}, {1, "FPS"}, {2, "FPS + memória"}, {3, "FPS + mem. + notas"}})
toggle("video", "Desempenho", "vsync", "VSync",
    "Sincroniza com o monitor. Limita o FPS, mas evita rasgos de imagem.")
escolha("video", "Desempenho", "resolucaoCanvas", "Resolução interna",
    "Renderiza numa resolução menor e amplia para a tela. Reduz nitidez, mas pode melhorar o FPS em aparelhos fracos.",
    (function()
        local resolucao = require("systems.resolucao")
        return resolucao.predefinidas
    end)())

acao("video", "Tela", "acao_tela_cheia", "Tela cheia",
    "Alterna entre janela e tela cheia (F11).", {texto = "ALTERNAR", so_desktop = true})

escolha("video", "Fundo", "fundoModo", "Fundo do beatmap",
    "Vídeo usa o arquivo .ogv do beatmap; se não existir, usa a imagem.",
    {{"imagem", "Imagem"}, {"video", "Vídeo"}})
slider("video", "Fundo", "brilhoFundo", "Brilho do fundo",
    "Escurece o fundo para destacar as notas.", 0, 100, 5, {unidade = "%"})
info("video", "Fundo", "info_video", "Vídeo do beatmap atual", function()
    local ok, bg = pcall(require, "systems.background")
    if ok and bg.statusVideo then return bg.statusVideo() end
    return "-"
end)

escolha("video", "Backend gráfico", "backendGrafico", "Renderizador",
    "Vulkan é o nativo, com fallback automático pro OpenGL se não abrir. " ..
    "Precisa reiniciar o jogo para valer.",
    {{"vulkan", "Vulkan"}, {"opengl", "OpenGL"}})
acao("video", "Backend gráfico", "acao_reiniciar_backend", "Aplicar e reiniciar",
    "Fecha e abre o jogo de novo com o backend escolhido. No Android, " ..
    "pode ser preciso reabrir o jogo manualmente.", {texto = "REINICIAR"})
info("video", "Backend gráfico", "info_backend_atual", "Backend ativo agora", function()
    local nome = love.graphics.getRendererInfo()
    return tostring(nome)
end)

--------------------------------------------------
-- ÁUDIO
--------------------------------------------------

slider("audio", "Música", "volumeMusica", "Volume da música", nil, 0, 100, 1, {unidade = "%"})
slider("audio", "Música", "offset", "Offset de áudio",
    "Ajusta o sincronismo. Positivo = notas mais tarde.", -1000, 1000, 5,
    {unidade = " ms", sinal = true})
toggle("audio", "Efeitos", "hitsom", "Som de acerto",
    "Toca um clique curto quando você acerta uma nota.")
slider("audio", "Efeitos", "hitsomVolume", "Volume do som de acerto", nil, 0, 100, 5, {unidade = "%"})

--------------------------------------------------
-- HUD
--------------------------------------------------

toggle("hud", "Geral", "hudVisivel", "Mostrar HUD", "Liga/desliga todos os elementos do HUD.")
acao("hud", "Geral", "acao_editar_hud", "Editar posição do HUD",
    "Arraste cada métrica para onde quiser.", {texto = "ABRIR"})
slider("hud", "Geral", "hudEscala", "Tamanho do HUD", nil, 50, 200, 10,
    {unidade = "%", tambem = "acessibilidade", secaoTambem = "Leitura"})
slider("hud", "Geral", "hudOpacidade", "Opacidade do HUD", nil, 20, 100, 10, {unidade = "%"})
toggle("hud", "Geral", "hudFundo", "Fundo escuro no texto",
    "Coloca uma caixa translúcida atrás do HUD para ler melhor.",
    {tambem = "acessibilidade", secaoTambem = "Leitura"})

toggle("hud", "Julgamento (popup)", "hudCoresJulgamento", "Popup colorido",
    "PERFECT, GOOD, OK, BAD e MISS com cores diferentes.")
toggle("hud", "Julgamento (popup)", "hudMostrarMs", "Mostrar cedo/tarde em ms",
    "Ex.: PERFECT -12 ms (negativo = cedo).",
    {tambem = "acessibilidade", secaoTambem = "Movimento e feedback"})
slider("hud", "Julgamento (popup)", "popupDuracao", "Duração do popup", nil, 0.2, 2, 0.1,
    {unidade = " s", casas = 1})

toggle("hud", "Elementos visíveis", "hud_accuracy_ativo", "Precisão", nil)
toggle("hud", "Elementos visíveis", "hud_combo_ativo", "Combo", nil)
toggle("hud", "Elementos visíveis", "hud_score_ativo", "Pontuação", nil)
toggle("hud", "Elementos visíveis", "hud_misses_ativo", "Misses", nil)
toggle("hud", "Elementos visíveis", "hud_ratings_ativo", "Resumo dos julgamentos", nil)
toggle("hud", "Elementos visíveis", "hud_ratingPopup_ativo", "Popup de julgamento", nil)

acao("hud", "Restaurar", "acao_resetar_hud", "Restaurar posições do HUD",
    "Volta todas as métricas para o lugar original.", {texto = "RESTAURAR", perigo = true})

--------------------------------------------------
-- CONTROLES
--------------------------------------------------

for lane = 1, 4 do
    add({aba = "controles", secao = "Teclado", id = "tecla_lane" .. lane,
        nome = "Lane " .. lane, tipo = "tecla", lane = lane,
        desc = lane == 1 and "Clique e aperte a nova tecla." or nil})
end

for lane = 1, 4 do
    add({aba = "controles", secao = "Controle (gamepad)", id = "botao_lane" .. lane,
        nome = "Lane " .. lane, tipo = "botao", lane = lane,
        desc = lane == 1 and "Clique e aperte o novo botão do controle." or nil})
end

toggle("controles", "Entrada", "enablePcControls", "Usar teclado/mouse no Android",
    "No Windows os controles de PC já são sempre usados.")

--------------------------------------------------
-- ACESSIBILIDADE
--------------------------------------------------

toggle("acessibilidade", "Movimento e feedback", "reduzirMovimento", "Reduzir movimento",
    "Desliga animações do menu e do popup de julgamento.")
toggle("controles", "Entrada", "vibrar", "Vibrar ao acertar",
    "Vibração curta a cada acerto (só Android).")

slider("acessibilidade", "Leitura", "uiEscala", "Tamanho da interface",
    "Aumenta textos e botões dos menus.", 80, 160, 10, {unidade = "%"})

--------------------------------------------------
-- QOL
--------------------------------------------------

toggle("qol", "Durante a partida", "pausarSemFoco", "Pausar ao perder o foco",
    "Pausa sozinho se você trocar de janela ou minimizar o app.")
toggle("qol", "Durante a partida", "contagemRetomar", "Contagem ao retomar",
    "Conta 3, 2, 1 antes de continuar depois de pausar.")
toggle("qol", "Durante a partida", "botaoPausa", "Botão de pausa na tela",
    "Mostra o botão de pausa no canto da gameplay.")
toggle("qol", "Durante a partida", "resetSegurar", "Segurar para reiniciar",
    "O atalho de reiniciar precisa ser mantido pressionado: a tela escurece " ..
    "e a partida só reinicia ao completar o tempo. Soltar antes cancela. " ..
    "No menu de pausa o reinício continua instantâneo.")
slider("qol", "Durante a partida", "resetSegurarSeg", "Tempo para segurar", nil,
    0.2, 5, 0.1, {unidade = " s", casas = 1})
toggle("qol", "Menus", "confirmarSair", "Confirmar ao voltar ao menu",
    "Pede um segundo toque para não perder a partida sem querer.")
slider("qol", "Menus", "ocultarCursorSeg", "Esconder cursor após", "0 = nunca esconder.",
    0, 10, 0.5, {unidade = " s", casas = 1})

acao("qol", "Ações rápidas (atalho com F5)", "acao_pausar", "Pausar / continuar",
    "Ideal para atribuir um atalho.", {texto = "EXECUTAR"})
acao("qol", "Ações rápidas (atalho com F5)", "acao_resetar", "Reiniciar partida", nil,
    {texto = "REINICIAR"})
acao("qol", "Ações rápidas (atalho com F5)", "acao_menu", "Voltar ao menu", nil,
    {texto = "SAIR", perigo = true, atalho = false})
acao("qol", "Ações rápidas (atalho com F5)", "acao_screenshot", "Captura de tela",
    "Salva um PNG na pasta de dados do jogo.", {texto = "CAPTURAR"})

--------------------------------------------------
-- DEBUG
--------------------------------------------------

local function seguro(fn, padrao)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return tostring(v) end
    return padrao or "?"
end

info("debug", "Diagnóstico", "info_love", "Versão do LÖVE", function()
    local a, b, c, nome = love.getVersion()
    return string.format("%d.%d.%d (%s)", a, b, c, tostring(nome))
end)
info("debug", "Diagnóstico", "info_os", "Sistema", function() return love.system.getOS() end)
info("debug", "Diagnóstico", "info_gpu", "Renderer", function()
    local nome, versao, _, dispositivo = love.graphics.getRendererInfo()
    return tostring(dispositivo or nome) .. " / " .. tostring(versao)
end)
info("debug", "Diagnóstico", "info_tela", "Resolução", function()
    local w, h = love.graphics.getDimensions()
    return string.format("%dx%d  (dpi x%.2f)", w, h, love.window.getDPIScale())
end)
info("debug", "Diagnóstico", "info_fps", "FPS atual", function() return love.timer.getFPS() end)
info("debug", "Diagnóstico", "info_mem", "Memória (Lua / texturas)", function()
    local st = love.graphics.getStats()
    return string.format("%.1f MB / %.1f MB", collectgarbage("count") / 1024,
        (st.texturememory or 0) / 1048576)
end)
info("debug", "Diagnóstico", "info_notas", "Notas no beatmap", function()
    return require("chart").getQuantidadeNotas()
end)
toggle("debug", "Diagnóstico", "debugHitboxes", "Mostrar áreas de toque",
    "Desenha as áreas das lanes e do botão de pausa.")
acao("debug", "Diagnóstico", "acao_copiar_info", "Copiar informações",
    "Copia o diagnóstico para a área de transferência.", {texto = "COPIAR"})

info("debug", "Arquivos", "info_saves", "Pasta de dados (love.filesystem)", function()
    return love.filesystem.getSaveDirectory()
end, {copiavel = true})
info("debug", "Arquivos", "info_externa", "Pasta externa de beatmaps", function()
    local ok, arm = pcall(require, "armazenamento")
    if ok then return arm.descricao() end
    return "-"
end, {copiavel = true})
info("debug", "Arquivos", "info_biblioteca", "Beatmaps na biblioteca", function()
    local lib = require("beatmap_library")
    local n = #lib.listar()

    if lib.escaneandoEmSegundoPlano and lib.escaneandoEmSegundoPlano() then
        return n .. " (escaneando em segundo plano...)"
    end

    return n
end)
toggle("debug", "Arquivos", "pastaExterna", "Ler beatmaps da pasta externa",
    "Documentos\\FunkyStudio\\beatmaps (Windows) ou FunkyStudio/beatmaps (Android).")
acao("debug", "Arquivos", "acao_abrir_saves", "Abrir pasta de dados", nil,
    {texto = "ABRIR", so_desktop = true})
acao("debug", "Arquivos", "acao_abrir_externa", "Abrir pasta de beatmaps", nil,
    {texto = "ABRIR", so_desktop = true})
acao("debug", "Arquivos", "acao_reescanear", "Reescanear beatmaps",
    "Procura beatmaps novos e remove os que sumiram.", {texto = "ESCANEAR"})
acao("debug", "Arquivos", "acao_recalcular", "Recalcular dificuldades",
    "Refaz a nota de dificuldade usada na ordenação.", {texto = "RECALCULAR"})
acao("debug", "Arquivos", "acao_gc", "Limpar memória (GC)", nil, {texto = "LIMPAR"})

acao("debug", "Resetar", "acao_resetar_atalhos", "Apagar todos os atalhos",
    "Remove os atalhos de teclado que você criou.", {texto = "APAGAR", perigo = true})
acao("debug", "Resetar", "acao_apagar_biblioteca", "Apagar biblioteca de beatmaps",
    "Apaga só a lista; ela é refeita a partir das pastas.", {texto = "APAGAR", perigo = true})
acao("debug", "Resetar", "acao_resetar_config", "Resetar arquivo de configuração",
    "Apaga config_save.lua e volta tudo ao padrão.", {texto = "RESETAR TUDO", perigo = true})

--------------------------------------------------
-- CONSULTAS
--------------------------------------------------

opcoes.lista = lista

function opcoes.porId(id)
    return porId[id]
end

function opcoes.indiceAba(id)
    for i, aba in ipairs(opcoes.abas) do
        if aba.id == id then return i end
    end
    return 1
end

function opcoes.daAba(abaId, sistema)
    local mobile = sistema == "Android" or sistema == "iOS"
    local ordem = {}
    local grupos = {}

    for _, op in ipairs(lista) do
        local daqui = op.aba == abaId
        local tambem = op.tambem == abaId

        if (daqui or tambem) and not (mobile and op.so_desktop) then
            local secao = daqui and op.secao or (op.secaoTambem or op.secao)

            if not grupos[secao] then
                grupos[secao] = {}
                ordem[#ordem + 1] = secao
            end

            grupos[secao][#grupos[secao] + 1] = {tipo = "opcao", op = op}
        end
    end

    local saida = {}

    for _, secao in ipairs(ordem) do
        saida[#saida + 1] = {tipo = "secao", nome = secao}

        for _, entrada in ipairs(grupos[secao]) do
            saida[#saida + 1] = entrada
        end
    end

    return saida
end

--------------------------------------------------
-- LEITURA
--------------------------------------------------

local function numero(v, padrao)
    v = tonumber(v)
    if v == nil then return padrao end
    return v
end

local function arredondar(v, passo)
    local n = math.floor(v / passo + 0.5)
    return tonumber(string.format("%.6f", n * passo))
end

function opcoes.valor(op, config)
    if op.tipo == "toggle" then
        return config.get(op.chave) == true
    end

    return config.get(op.chave)
end

local FPS_MIN, FPS_MAX, FPS_PASSO = 15, 1000, 5

function opcoes.proximoFPS(valor, direcao)
    valor = math.floor(numero(valor, 60))

    if valor <= 0 then
        if direcao < 0 then return FPS_MAX end
        return FPS_MIN
    end

    valor = math.max(FPS_MIN, math.min(FPS_MAX, valor))

    if direcao < 0 then
        valor = valor - FPS_PASSO
        if valor < FPS_MIN then return 0 end
        return valor
    end

    valor = valor + FPS_PASSO
    if valor > FPS_MAX then return 0 end
    return valor
end

local function indiceEscolha(op, valor)
    for i, par in ipairs(op.valores) do
        if par[1] == valor then return i end
    end
    return 1
end

function opcoes.nomeTecla(tecla)
    if not tecla or tecla == "" then return "—" end

    local nomes = {
        ["return"] = "ENTER", space = "ESPAÇO", escape = "ESC", backspace = "BACKSPACE",
        lshift = "SHIFT", rshift = "SHIFT", lctrl = "CTRL", rctrl = "CTRL",
        up = "CIMA", down = "BAIXO", left = "ESQ", right = "DIR",
    }

    return nomes[tecla] or string.upper(tecla)
end

function opcoes.texto(op, config, controles)
    local t = op.tipo

    if t == "toggle" then
        return config.get(op.chave) == true and "LIGADO" or "DESLIGADO"

    elseif t == "slider" then
        local v = numero(config.get(op.chave), op.min)
        v = v * (op.mult or 1)
        local casas = op.casas or 0
        local txt = string.format("%." .. casas .. "f", v)

        if op.sinal and v > 0 then txt = "+" .. txt end

        return txt .. (op.unidade or "")

    elseif t == "fps" then
        local v = numero(config.get(op.chave), 60)
        if v <= 0 then return "ILIMITADO" end
        return string.format("%d FPS", math.floor(v))

    elseif t == "escolha" then
        local valor = config.get(op.chave)
        return op.valores[indiceEscolha(op, valor)][2]

    elseif t == "tecla" then
        local tecla = controles and controles.getTecla and controles.getTecla(op.lane) or ""
        return opcoes.nomeTecla(tecla)

    elseif t == "botao" then
        local b = controles and controles.getBotao and controles.getBotao(op.lane) or ""
        return b ~= "" and string.upper(b) or "—"

    elseif t == "info" then
        return seguro(op.texto)
    end

    return ""
end

function opcoes.fracao(op, config)
    if op.tipo == "fps" then
        local v = numero(config.get(op.chave), 60)
        if v <= 0 then return 1 end
        return (math.max(FPS_MIN, math.min(FPS_MAX, v)) - FPS_MIN) / (FPS_MAX - FPS_MIN)
    end

    local v = numero(config.get(op.chave), op.min)
    return (math.max(op.min, math.min(op.max, v)) - op.min) / (op.max - op.min)
end

--------------------------------------------------
-- ALTERAÇÃO
--------------------------------------------------

local function definir(config, chave, valor)
    config.set(chave, valor)
end

local function corrigirJanelas(config, chave)
    local ordem = {"janelaPerfect", "janelaGood", "janelaOk", "janelaBad"}
    local pos = 0

    for i, c in ipairs(ordem) do
        if c == chave then pos = i end
    end

    if pos == 0 then return end

    local v = numero(config.get(chave), 0)

    for i = pos + 1, #ordem do
        if numero(config.get(ordem[i]), 0) < v then
            definir(config, ordem[i], v)
            v = numero(config.get(ordem[i]), v)
        end
    end

    v = numero(config.get(chave), 0)

    for i = pos - 1, 1, -1 do
        if numero(config.get(ordem[i]), 0) > v then
            definir(config, ordem[i], v)
            v = numero(config.get(ordem[i]), v)
        end
    end
end

function opcoes.ajustar(op, direcao, config, ctx)
    local t = op.tipo

    if t == "toggle" then
        definir(config, op.chave, not (config.get(op.chave) == true))
        return "configuracao"

    elseif t == "slider" then
        local v = numero(config.get(op.chave), op.min)
        v = arredondar(v + op.passo * direcao, op.passo)
        v = math.max(op.min, math.min(op.max, v))
        definir(config, op.chave, v)
        corrigirJanelas(config, op.chave)
        return "configuracao"

    elseif t == "fps" then
        definir(config, op.chave, opcoes.proximoFPS(config.get(op.chave), direcao))
        return "configuracao"

    elseif t == "escolha" then
        local i = indiceEscolha(op, config.get(op.chave))
        i = i + direcao

        if i < 1 then i = #op.valores end
        if i > #op.valores then i = 1 end

        definir(config, op.chave, op.valores[i][1])
        return "configuracao"
    end

    return nil
end

function opcoes.definirFracao(op, fracao, config)
    fracao = math.max(0, math.min(1, fracao))

    if op.tipo == "fps" then
        local v = FPS_MIN + fracao * (FPS_MAX - FPS_MIN)
        v = math.floor(v / FPS_PASSO + 0.5) * FPS_PASSO

        if fracao >= 0.995 then v = 0 end

        definir(config, op.chave, v)
        return "configuracao"
    end

    local v = op.min + (op.max - op.min) * fracao
    v = arredondar(v, op.passo)
    v = math.max(op.min, math.min(op.max, v))

    definir(config, op.chave, v)
    corrigirJanelas(config, op.chave)
    return "configuracao"
end

-- Valor digitado pelo jogador (clicando no número, em vez de arrastar o
-- slider ou usar +/-). Só faz sentido pra "slider" e "fps": os outros
-- tipos (toggle, escolha, tecla...) não são numéricos.
--
-- Ao contrário do +/- e do arraste, um valor digitado é intenção
-- explícita do jogador: no "fps" isso não arredonda pro múltiplo de 5 do
-- passo do botão (só limita à faixa válida), pra ele conseguir travar num
-- número exato (ex.: 144) que o +/- de 5 em 5 não alcançaria.
function opcoes.textoParaValor(op, texto)
    if op.tipo ~= "slider" and op.tipo ~= "fps" then
        return nil, "Esta opção não aceita valor digitado"
    end

    local limpo = tostring(texto or ""):gsub(",", ".")
    local v = tonumber(limpo)

    if not v then
        return nil, "Valor inválido"
    end

    if op.tipo == "fps" then
        v = math.floor(v + 0.5)

        if v <= 0 then
            v = 0
        else
            v = math.max(FPS_MIN, math.min(FPS_MAX, v))
        end

        return v
    end

    v = arredondar(v, op.passo)
    v = math.max(op.min, math.min(op.max, v))

    return v
end

function opcoes.definirValorDigitado(op, texto, config)
    local v, erro = opcoes.textoParaValor(op, texto)

    if not v then
        return false, erro
    end

    definir(config, op.chave, v)
    corrigirJanelas(config, op.chave)
    return true
end

--------------------------------------------------
-- AÇÕES
--------------------------------------------------

local function aviso(texto, tipo)
    local ok, tema = pcall(require, "tema")
    if ok and tema.toast then tema.toast(texto, tipo) end
end

local function textoDiagnostico(config)
    local linhas = {}

    for _, op in ipairs(lista) do
        if op.aba == "debug" and op.tipo == "info" then
            linhas[#linhas + 1] = op.nome .. ": " .. seguro(op.texto)
        end
    end

    return table.concat(linhas, "\n")
end

local function limparAtalhos(config)
    local removidos = 0

    for chave in pairs(config.dados or {}) do
        if type(chave) == "string" and chave:sub(1, 7) == "atalho_" then
            config.dados[chave] = nil
            removidos = removidos + 1
        end
    end

    config.salvar()
    return removidos
end

local function abrirPasta(caminho)
    if not caminho or caminho == "" then return false end

    caminho = tostring(caminho):gsub("\\", "/")

    if caminho:sub(1, 1) ~= "/" then caminho = "/" .. caminho end

    return love.system.openURL("file://" .. caminho)
end

local acoes = {}

acoes.acao_pausar = function() return "alternar_pausa" end
acoes.acao_resetar = function() return "resetar" end
acoes.acao_menu = function() return "sair" end
acoes.acao_editar_hud = function() return "editar_hud" end
acoes.acao_tela_cheia = function() return "tela_cheia" end

acoes.acao_reiniciar_backend = function()
    -- salva o backend escolhido: aplicado por conf.lua no próximo boot
    love.event.quit("restart")
end

acoes.acao_screenshot = function()
    local nome = "screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
    love.graphics.captureScreenshot(nome)
    aviso("Captura salva: " .. nome, "ok")
end

acoes.acao_gc = function()
    local antes = collectgarbage("count")
    collectgarbage("collect")
    collectgarbage("collect")
    aviso(string.format("Memória liberada: %.1f MB", (antes - collectgarbage("count")) / 1024), "ok")
end

acoes.acao_copiar_info = function(config)
    love.system.setClipboardText(textoDiagnostico(config))
    aviso("Diagnóstico copiado", "ok")
end

acoes.acao_abrir_saves = function()
    abrirPasta(love.filesystem.getSaveDirectory())
end

acoes.acao_abrir_externa = function()
    local arm = require("armazenamento")
    local pasta = arm.caminho()

    if pasta then
        abrirPasta(pasta)
    else
        aviso("Pasta externa indisponível", "erro")
    end
end

acoes.acao_reescanear = function(config)
    local lib = require("beatmap_library")

    if lib.escaneandoEmSegundoPlano and lib.escaneandoEmSegundoPlano() then
        aviso("Já tem uma varredura em andamento", "erro")
        return
    end

    -- Roda numa thread separada pra não travar a tela enquanto lê e
    -- calcula a dificuldade de cada beatmap encontrado.
    if lib.reescanearAsync then
        lib.reescanearAsync(config, aviso)
        aviso("Escaneando em segundo plano...")
    else
        lib.reescanear(config)
        aviso("Beatmaps: " .. #lib.listar(), "ok")
    end
end

acoes.acao_recalcular = function()
    local lib = require("beatmap_library")

    if lib.escaneandoEmSegundoPlano and lib.escaneandoEmSegundoPlano() then
        aviso("Já tem uma varredura em andamento", "erro")
        return
    end

    if lib.recalcularAsync then
        lib.recalcularAsync(aviso)
        aviso("Recalculando em segundo plano...")
    else
        for _, mapa in ipairs(lib.listar()) do mapa.rating = nil end
        lib.garantirRatings()
        aviso("Dificuldades recalculadas", "ok")
    end
end

acoes.acao_resetar_atalhos = function(config)
    aviso("Atalhos removidos: " .. limparAtalhos(config), "ok")
    return "configuracao"
end

acoes.acao_resetar_hud = function(config)
    local padroes = {
        accuracy = {10, 35}, combo = {10, 62}, score = {10, 89},
        misses = {10, 116}, ratings = {10, 143}, ratingPopup = {0, 60},
    }

    for nome, p in pairs(padroes) do
        config.set("hud_" .. nome .. "_x", p[1])
        config.set("hud_" .. nome .. "_y", p[2])
    end

    aviso("HUD restaurado", "ok")
    return "configuracao"
end

acoes.acao_apagar_biblioteca = function(config)
    local lib = require("beatmap_library")
    love.filesystem.remove("beatmaps_library.lua")
    lib.dados = {}
    lib.reescanear(config)
    aviso("Biblioteca refeita: " .. #lib.listar() .. " beatmap(s)", "ok")
end

acoes.acao_resetar_config = function(config)
    love.filesystem.remove("config_save.lua")
    config.resetar()
    aviso("Configurações resetadas", "ok")
    return "recarregar_config"
end

function opcoes.executarAcao(id, config, ctx)
    local fn = acoes[id]
    if not fn then return nil end

    local ok, resultado = pcall(fn, config, ctx)

    if not ok then
        aviso("Erro: " .. tostring(resultado), "erro")
        return nil
    end

    return resultado
end

--------------------------------------------------
-- ATIVAR (toque / Enter)
--------------------------------------------------

function opcoes.ativar(op, config, ctx)
    local t = op.tipo

    if t == "acao" then
        return opcoes.executarAcao(op.id, config, ctx)

    elseif t == "toggle" or t == "escolha" then
        return opcoes.ajustar(op, 1, config, ctx)

    elseif t == "fps" then
        return opcoes.ajustar(op, 1, config, ctx)

    elseif t == "slider" then
        local v = numero(config.get(op.chave), op.min)

        if v >= op.max then
            definir(config, op.chave, op.min)
            corrigirJanelas(config, op.chave)
            return "configuracao"
        end

        return opcoes.ajustar(op, 1, config, ctx)
    end

    return nil
end

--------------------------------------------------
-- ATALHOS
--------------------------------------------------

local RESERVADAS = {
    escape = true, f5 = true, f11 = true, ["return"] = true, kpenter = true,
    space = true, tab = true, backspace = true, delete = true,
    up = true, down = true, left = true, right = true,
    pageup = true, pagedown = true, home = true, ["end"] = true,
    lctrl = true, rctrl = true, lshift = true, rshift = true,
    lalt = true, ralt = true, lgui = true, rgui = true, capslock = true,
}

function opcoes.podeAtalho(op)
    if op.atalho == false or op.perigo then return false end
    if op.so_desktop and op.tipo == "acao" and op.id ~= "acao_tela_cheia" then return false end

    local t = op.tipo
    return t == "toggle" or t == "slider" or t == "fps" or t == "escolha" or t == "acao"
end

function opcoes.atalhoDe(op, config)
    local tecla = config.get("atalho_" .. op.id)
    if type(tecla) == "string" and tecla ~= "" then return tecla end
    return nil
end

function opcoes.removerAtalho(op, config)
    config.set("atalho_" .. op.id, nil)
end

local function teclaDeLane(controles, tecla)
    if not controles or not controles.getTecla then return false end

    for lane = 1, 4 do
        if controles.getTecla(lane) == tecla then
            return lane
        end
    end

    return false
end

function opcoes.definirAtalho(op, tecla, config, controles)
    if not opcoes.podeAtalho(op) then
        return false, "Esta opção não aceita atalho"
    end

    if type(tecla) ~= "string" or tecla == "" then
        return false, "Tecla inválida"
    end

    if RESERVADAS[tecla] then
        return false, "Tecla reservada: " .. opcoes.nomeTecla(tecla)
    end

    local lane = teclaDeLane(controles, tecla)

    if lane then
        return false, "Essa tecla é da Lane " .. lane
    end

    for _, outra in ipairs(lista) do
        if outra ~= op and opcoes.atalhoDe(outra, config) == tecla then
            opcoes.removerAtalho(outra, config)
        end
    end

    config.set("atalho_" .. op.id, tecla)
    return true
end

function opcoes.tratarAtalho(tecla, config, ctx)
    if type(tecla) ~= "string" then return nil, false end

    if teclaDeLane(ctx and ctx.controles, tecla) then return nil, false end

    for _, op in ipairs(lista) do
        if opcoes.podeAtalho(op) and opcoes.atalhoDe(op, config) == tecla then
            local resultado = opcoes.ativar(op, config, ctx)

            if op.tipo ~= "acao" then
                aviso(op.nome .. ": " .. opcoes.texto(op, config, ctx and ctx.controles), "info")
            end

            return resultado or "configuracao", true
        end
    end

    return nil, false
end

return opcoes
