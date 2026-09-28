local biblioteca = {}

local armazenamento = require("armazenamento")

local PASTA_BIBLIOTECA = "beatmaps"
local ARQUIVO_BIBLIOTECA =
    "beatmaps_library.lua"

biblioteca.dados = {}

--------------------------------------------------
-- UTILIDADES
--------------------------------------------------

local function garantirPasta()

    if not love.filesystem.getInfo(
        PASTA_BIBLIOTECA
    ) then

        love.filesystem.createDirectory(
            PASTA_BIBLIOTECA
        )
    end
end

--------------------------------------------------

local function limparNome(nome)

    nome =
        tostring(nome or "")

    nome =
        nome:gsub(
            "[\\/:*?\"<>|]",
            "_"
        )

    nome =
        nome:gsub(
            "%s+",
            " "
        )

    nome =
        nome:gsub(
            "^%s+",
            ""
        )

    nome =
        nome:gsub(
            "%s+$",
            ""
        )

    if nome == "" then
        nome = "beatmap"
    end

    return nome
end

--------------------------------------------------

local function copiarArquivo(
    origem,
    destino
)

    local dados, erro =
        love.filesystem.read(
            origem
        )

    if not dados then

        print(
            "ERRO AO LER: " ..
            tostring(origem)
        )

        print(
            tostring(erro)
        )

        return false
    end

    local sucesso,
          erroEscrita =
        love.filesystem.write(
            destino,
            dados
        )

    if not sucesso then

        print(
            "ERRO AO ESCREVER: " ..
            tostring(destino)
        )

        print(
            tostring(
                erroEscrita
            )
        )

        return false
    end

    return true
end

--------------------------------------------------
-- SALVAR
--------------------------------------------------

function biblioteca.salvar()

    garantirPasta()

    local linhas = {}

    linhas[#linhas + 1] =
        "return {"

    for _, mapa in ipairs(
        biblioteca.dados
    ) do

        linhas[#linhas + 1] =
            "    {"

        linhas[#linhas + 1] =
            "        id = " ..
            string.format(
                "%q",
                tostring(
                    mapa.id
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        nome = " ..
            string.format(
                "%q",
                tostring(
                    mapa.nome
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        dificuldade = " ..
            string.format(
                "%q",
                tostring(
                    mapa.dificuldade
                    or ""
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        rating = " ..
            tostring(
                math.floor(
                    tonumber(mapa.rating) or 0
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        arquivo = " ..
            string.format(
                "%q",
                tostring(
                    mapa.arquivo
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        pasta = " ..
            string.format(
                "%q",
                tostring(
                    mapa.pasta
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "        background = " ..
            string.format(
                "%q",
                tostring(
                    mapa.background
                    or ""
                )
            ) ..
            ","

        linhas[#linhas + 1] =
            "    },"
    end

    linhas[#linhas + 1] =
        "}"

    local sucesso, erro =
        love.filesystem.write(
            ARQUIVO_BIBLIOTECA,
            table.concat(
                linhas,
                "\n"
            )
        )

    if not sucesso then

        print(
            "ERRO AO SALVAR BIBLIOTECA:"
        )

        print(
            tostring(erro)
        )

        return false
    end

    return true
end

--------------------------------------------------
-- CARREGAR
--------------------------------------------------

function biblioteca.carregar()

    biblioteca.dados = {}

    if not love.filesystem.getInfo(
        ARQUIVO_BIBLIOTECA
    ) then

        biblioteca.salvar()

        biblioteca.sincronizar()

        return
    end

    local conteudo, erro =
        love.filesystem.read(
            ARQUIVO_BIBLIOTECA
        )

    if not conteudo then

        print(
            "ERRO AO LER BIBLIOTECA:"
        )

        print(
            tostring(erro)
        )

        return
    end

    local funcao,
          erroLoad =
        load(
            conteudo,
            ARQUIVO_BIBLIOTECA,
            "t"
        )

    if not funcao then

        print(
            "ERRO AO INTERPRETAR BIBLIOTECA:"
        )

        print(
            tostring(erroLoad)
        )

        return
    end

    local sucesso,
          resultado =
        pcall(funcao)

    if sucesso
    and type(resultado) == "table" then

        biblioteca.dados =
            resultado

    else

        print(
            "ERRO: biblioteca invalida."
        )
    end

    biblioteca.sincronizar()
end

--------------------------------------------------
-- LISTAR
--------------------------------------------------

function biblioteca.listar()

    return biblioteca.dados
end

--------------------------------------------------
-- OBTER
--------------------------------------------------

function biblioteca.obter(id)

    for _, mapa in ipairs(
        biblioteca.dados
    ) do

        if mapa.id == id then
            return mapa
        end
    end

    return nil
end

--------------------------------------------------
-- VERIFICAR ARQUIVO
--------------------------------------------------

local function existeArquivo(
    arquivo
)

    for _, mapa in ipairs(
        biblioteca.dados
    ) do

        if mapa.arquivo == arquivo then
            return true
        end
    end

    return false
end

--------------------------------------------------
-- SINCRONIZAR ARQUIVOS EXISTENTES
--------------------------------------------------

local function normalizarTexto(texto)

    texto =
        tostring(texto or "")

    texto =
        texto:gsub("\r", "")

    texto =
        texto:gsub("^%s+", "")

    texto =
        texto:gsub("%s+$", "")

    return texto
end

--------------------------------------------------
-- DIFICULDADE ESTIMADA (para ordenar a lista)
--------------------------------------------------
-- O .osu não traz estrelas prontas, então a dificuldade é estimada pela
-- densidade de notas: pico sustentado (percentil 95 em janelas de 2 s),
-- média de notas por segundo e uma pequena parcela por holds.
-- O resultado é um inteiro (centésimos) para não depender de locale
-- ao salvar o arquivo da biblioteca.

local JANELA_DENSIDADE = 2.0

local function calcularRating(conteudo)

    local inicios = {}
    local holds = 0
    local lendoHitObjects = false

    for linha in tostring(conteudo or ""):gmatch("[^\r\n]+") do

        if linha:sub(1, 1) == "[" then

            lendoHitObjects =
                linha:match("^%[HitObjects%]") ~= nil

        elseif lendoHitObjects then

            local tempo, tipo =
                linha:match(
                    "^[^,]*,[^,]*,(%-?%d+),(%d+)"
                )

            if tempo then

                inicios[#inicios + 1] =
                    tonumber(tempo) / 1000

                if math.floor(
                    tonumber(tipo) / 128
                ) % 2 == 1 then
                    holds = holds + 1
                end
            end
        end
    end

    local total = #inicios

    if total < 2 then
        return 0
    end

    table.sort(inicios)

    local densidades = {}
    local fim = 1

    for i = 1, total do

        if fim < i then
            fim = i
        end

        while fim < total
        and inicios[fim + 1]
            <= inicios[i] + JANELA_DENSIDADE do

            fim = fim + 1
        end

        densidades[i] =
            (fim - i + 1) / JANELA_DENSIDADE
    end

    table.sort(densidades)

    local pico =
        densidades[
            math.max(
                1,
                math.ceil(total * 0.95)
            )
        ]

    local duracao =
        math.max(
            1,
            inicios[total] - inicios[1]
        )

    local media = total / duracao

    local nota =
        (pico * 0.6 + media * 0.4)
        * (1 + 0.15 * (holds / total))

    return math.floor(nota * 100 + 0.5)
end

--------------------------------------------------
-- GARANTIR DIFICULDADE DE TODOS OS MAPAS
--------------------------------------------------
-- Mapas antigos (salvos antes deste campo existir) e mapas recém
-- importados ganham a nota na primeira vez que a lista é aberta.
-- O cálculo é feito uma única vez por mapa e salvo na biblioteca.

function biblioteca.garantirRatings()

    local alterou = false

    for _, mapa in ipairs(
        biblioteca.dados
    ) do

        if type(mapa.rating) ~= "number" then

            local conteudo =
                mapa.arquivo
                and love.filesystem.read(
                    mapa.arquivo
                )

            mapa.rating =
                conteudo
                and calcularRating(conteudo)
                or 0

            alterou = true
        end
    end

    if alterou then
        biblioteca.salvar()
    end
end

biblioteca.calcularRating = calcularRating

local function extrairInfoOsu(caminhoOsu)

    local conteudo =
        love.filesystem.read(
            caminhoOsu
        )

    if not conteudo then
        return nil
    end

    local nome =
        conteudo:match(
            "Title:(.-)\n"
        )

    local dificuldade =
        conteudo:match(
            "Version:(.-)\n"
        )

    nome = normalizarTexto(nome)
    dificuldade = normalizarTexto(dificuldade)

    if nome == "" then
        nome =
            caminhoOsu:match(
                "([^/]+)%.osu$"
            )
            or "Beatmap"
    end

    if dificuldade == "" then
        dificuldade = "Unknown"
    end

    local background =
        conteudo:match(
            '[\r\n]0,0,"([^"]+)"'
        )

    if background then

        background =
            background:gsub(
                "\\",
                "/"
            )

        background =
            background:match(
                "([^/]+)$"
            )
    end

    return {
        nome = nome,
        dificuldade = dificuldade,
        background = background
    }
end

local function arquivoJaRegistrado(caminho)

    for _, mapa in ipairs(
        biblioteca.dados
    ) do

        if mapa.arquivo == caminho then
            return true
        end
    end

    return false
end

local function gerarId(nome, dificuldade)

    local id =
        limparNome(nome)
        .. "_"
        .. limparNome(dificuldade)

    id =
        id:gsub(
            "[^%w_%-]",
            "_"
        )

    local original = id
    local contador = 1

    while biblioteca.obter(id) do

        contador =
            contador + 1

        id =
            original
            .. "_"
            .. contador
    end

    return id
end

-- Em pastas externas (ex.: uma pasta Songs do osu!) só entram mapas
-- osu!mania 4K; outros modos/quantidades de teclas são ignorados.
local function ehMania4K(caminhoOsu)

    local conteudo =
        love.filesystem.read(
            caminhoOsu
        )

    if not conteudo then
        return false
    end

    local modo =
        conteudo:match("[\r\n]Mode:%s*(%d+)")

    if modo and tonumber(modo) ~= 3 then
        return false
    end

    local teclas =
        conteudo:match("[\r\n]CircleSize:%s*([%d%.]+)")

    if modo and teclas and math.floor(tonumber(teclas) or 0) ~= 4 then
        return false
    end

    return true
end

local function registrarOsuExistente(
    caminhoOsu,
    apenasMania4K
)

    if arquivoJaRegistrado(caminhoOsu) then
        return nil
    end

    if apenasMania4K and not ehMania4K(caminhoOsu) then
        return nil
    end

    local info =
        extrairInfoOsu(
            caminhoOsu
        )

    if not info then
        return nil
    end

    local pasta =
        caminhoOsu:match(
            "^(.*)/[^/]+$"
        )

    if not pasta then
        pasta = PASTA_BIBLIOTECA
    end

    local mapa = {

        id =
            gerarId(
                info.nome,
                info.dificuldade
            ),

        nome = info.nome,
        dificuldade = info.dificuldade,
        arquivo = caminhoOsu,
        pasta = pasta,
        background = info.background
    }

    biblioteca.dados[
        #biblioteca.dados + 1
    ] = mapa

    return mapa
end

local function escanearPasta(
    pasta,
    encontrados,
    apenasMania4K
)

    local arquivos =
        love.filesystem.getDirectoryItems(
            pasta
        )

    for _, nomeArquivo in ipairs(
        arquivos
    ) do

        local caminho =
            pasta .. "/" .. nomeArquivo

        local info =
            love.filesystem.getInfo(
                caminho
            )

        if info then

            if info.type == "directory" then

                escanearPasta(
                    caminho,
                    encontrados,
                    apenasMania4K
                )

            elseif nomeArquivo:lower():match(
                "%.osu$"
            ) then

                local mapa =
                    registrarOsuExistente(
                        caminho,
                        apenasMania4K
                    )

                if mapa then
                    encontrados[#encontrados + 1] = mapa
                end
            end
        end
    end
end

-- Remove da lista os mapas cujo arquivo não existe mais.
local function removerInexistentes()

    local removidos = 0

    for i = #biblioteca.dados, 1, -1 do

        local mapa = biblioteca.dados[i]

        if type(mapa) ~= "table"
        or not mapa.arquivo
        or not love.filesystem.getInfo(mapa.arquivo) then

            table.remove(biblioteca.dados, i)
            removidos = removidos + 1
        end
    end

    return removidos
end

biblioteca.removerInexistentes = removerInexistentes

-- Procura beatmaps na pasta externa (montada em "beatmaps_externos").
local function escanearExterno(encontrados)

    if not armazenamento.estaMontado() then
        return
    end

    local ponto = armazenamento.pontoMontagem()

    for _, item in ipairs(
        love.filesystem.getDirectoryItems(ponto)
    ) do

        local caminho = ponto .. "/" .. item
        local info = love.filesystem.getInfo(caminho)

        if info and info.type == "directory" then

            escanearPasta(caminho, encontrados, true)

        elseif item:lower():match("%.osu$") then

            local mapa = registrarOsuExistente(caminho, true)

            if mapa then
                encontrados[#encontrados + 1] = mapa
            end

        elseif item:lower():match("%.osz$") then

            -- .osz solto: importa uma vez (copia para a pasta interna)
            local nomeOsz = item:gsub("%.[oO][sS][zZ]$", "")
            local destino =
                PASTA_BIBLIOTECA .. "/" .. limparNome(nomeOsz)

            if not love.filesystem.getInfo(destino) then

                local real = armazenamento.caminhoReal(item)

                local ok, resultado = pcall(
                    biblioteca.importarOSZ, real
                )

                if ok and type(resultado) == "table" then
                    for _, mapa in ipairs(resultado) do
                        encontrados[#encontrados + 1] = mapa
                    end
                else
                    print("ERRO AO IMPORTAR OSZ EXTERNO:", item, tostring(resultado))
                end
            end
        end
    end
end

function biblioteca.sincronizar()

    garantirPasta()

    removerInexistentes()

    local encontrados = {}

    escanearPasta(
        PASTA_BIBLIOTECA,
        encontrados
    )

    escanearExterno(encontrados)

    if #encontrados > 0 then

        biblioteca.salvar()

        print(
            "Beatmaps encontrados no armazenamento: "
            .. tostring(#encontrados)
        )
    end

    return encontrados
end

-- Refaz a varredura (inclui a pasta externa) e atualiza a biblioteca.
-- Bloqueia a thread principal até terminar — só ainda usada como
-- fallback caso o jogo tenha sido aberto sem suporte a threads.
function biblioteca.reescanear(config)

    armazenamento.montar(config)

    local encontrados = biblioteca.sincronizar()

    biblioteca.garantirRatings()
    biblioteca.salvar()

    return encontrados
end

--------------------------------------------------
-- REESCANEAR EM SEGUNDO PLANO (thread separada)
--------------------------------------------------
-- A varredura completa (ler cada .osu, checar se é mania 4K, calcular a
-- dificuldade) pode ser lenta com uma coleção grande. Rodar numa thread
-- evita que a tela principal congele enquanto isso acontece.

local threadAtiva = nil
local canalResultado = nil
local canalErro = nil

function biblioteca.escaneandoEmSegundoPlano()
    return threadAtiva ~= nil
end

-- Dispara o escaneamento em background. "aviso(texto, tipo)" é opcional
-- (por exemplo tema.toast) — chamado quando a varredura termina ou falha.
-- "modo": "reescanear" (padrão, procura beatmaps novos) ou "recalcular"
-- (só refaz a dificuldade dos beatmaps já conhecidos).
function biblioteca.reescanearAsync(config, aviso, modo)

    if threadAtiva then

        if aviso then
            aviso("Já tem uma varredura em andamento", "erro")
        end

        return false
    end

    if not love.thread then

        -- Sem suporte a threads (não deveria acontecer no LÖVE 12):
        -- cai para a versão que trava a tela, mas ainda funciona.
        if modo == "recalcular" then

            for _, mapa in ipairs(biblioteca.dados) do
                mapa.rating = nil
            end

            biblioteca.garantirRatings()
            biblioteca.salvar()
        else
            biblioteca.reescanear(config)
        end

        if aviso then
            aviso("Beatmaps: " .. #biblioteca.listar(), "ok")
        end

        return true
    end

    canalResultado = love.thread.getChannel("biblioteca_resultado")
    canalErro = love.thread.getChannel("biblioteca_erro")

    -- limpa qualquer lixo de uma rodada anterior que ninguém consumiu
    canalResultado:clear()
    canalErro:clear()

    local pastaExternaAtiva =
        not config or config.get("pastaExterna") ~= false

    threadAtiva =
        love.thread.newThread("systems/scan_thread.lua")

    threadAtiva:start(pastaExternaAtiva, modo)

    biblioteca.avisoPendente = aviso

    return true
end

-- Atalho: só refaz a dificuldade dos beatmaps já conhecidos (sem
-- procurar arquivos novos), também em segundo plano.
function biblioteca.recalcularAsync(aviso)
    return biblioteca.reescanearAsync(nil, aviso, "recalcular")
end

-- Chamar uma vez por frame (ex.: dentro de love.update). Não bloqueia:
-- só olha se a thread já deixou um resultado nos canais. Devolve true
-- quando a biblioteca acabou de ser atualizada, pra quem chamou poder
-- reagir (ex.: atualizar a lista já aberta na tela).
function biblioteca.verificarAsync()

    if not threadAtiva then
        return false
    end

    local erro = canalErro and canalErro:pop()

    if erro then

        threadAtiva = nil

        if biblioteca.avisoPendente then
            biblioteca.avisoPendente("Erro ao escanear: " .. tostring(erro), "erro")
        end

        biblioteca.avisoPendente = nil

        return false
    end

    local resultado = canalResultado and canalResultado:pop()

    if resultado then

        biblioteca.dados = resultado
        threadAtiva = nil

        if biblioteca.avisoPendente then
            biblioteca.avisoPendente(
                "Beatmaps atualizados: " .. #resultado,
                "ok"
            )
        end

        biblioteca.avisoPendente = nil

        return true
    end

    return false
end

--------------------------------------------------
-- ORDENAÇÃO
--------------------------------------------------
-- Músicas em ordem alfabética. Os diferentes charts da mesma música
-- (mesma pasta/.osz) ficam juntos, do mais fácil para o mais difícil.

function biblioteca.ordenar(mapas)

    mapas = mapas or biblioteca.dados

    biblioteca.garantirRatings()

    local grupos = {}
    local ordem = {}

    for _, mapa in ipairs(mapas) do

        local chave =
            tostring(mapa.pasta or mapa.nome or ""):lower()

        local grupo = grupos[chave]

        if not grupo then

            grupo = {
                chave = chave,
                nome = tostring(mapa.nome or ""):lower(),
                itens = {},
            }

            grupos[chave] = grupo
            ordem[#ordem + 1] = grupo
        end

        grupo.itens[#grupo.itens + 1] = mapa
    end

    for _, grupo in ipairs(ordem) do

        table.sort(
            grupo.itens,
            function(a, b)

                local ra = tonumber(a.rating) or 0
                local rb = tonumber(b.rating) or 0

                if ra ~= rb then
                    return ra < rb
                end

                local da = tostring(a.dificuldade or ""):lower()
                local db = tostring(b.dificuldade or ""):lower()

                if da ~= db then
                    return da < db
                end

                return tostring(a.arquivo or "") < tostring(b.arquivo or "")
            end
        )
    end

    table.sort(
        ordem,
        function(a, b)

            if a.nome ~= b.nome then
                return a.nome < b.nome
            end

            return a.chave < b.chave
        end
    )

    for i = #mapas, 1, -1 do
        mapas[i] = nil
    end

    for _, grupo in ipairs(ordem) do
        for _, mapa in ipairs(grupo.itens) do
            mapas[#mapas + 1] = mapa
        end
    end

    return mapas
end

--------------------------------------------------
-- IMPORTAR OSZ
--------------------------------------------------

function biblioteca.importarOSZ(
    caminho
)

    garantirPasta()

    if not caminho then

        print(
            "ERRO: caminho do OSZ nao informado."
        )

        return nil
    end

    --------------------------------------------------
    -- NOME DA PASTA
    --------------------------------------------------

    local nomeOsz =
        caminho:match(
            "([^/]+)%.osz$"
        )

    if not nomeOsz then
        nomeOsz = "beatmap"
    end

    nomeOsz =
        limparNome(nomeOsz)

    local pastaDestino =
        PASTA_BIBLIOTECA ..
        "/" ..
        nomeOsz

    if not love.filesystem.getInfo(
        pastaDestino
    ) then

        love.filesystem.createDirectory(
            pastaDestino
        )
    end

    --------------------------------------------------
    -- MONTAR OSZ
    --------------------------------------------------

    local montagem =
        love.filesystem.mountFullPath(
            caminho,
            "osz_temp",
            "read",
            false
        )

    if not montagem then

        print(
            "ERRO: nao foi possivel montar o OSZ."
        )

        return nil
    end

    --------------------------------------------------
    -- ARQUIVOS
    --------------------------------------------------

    local arquivos =
        love.filesystem.getDirectoryItems(
            "osz_temp"
        )

    local importados = {}

    --------------------------------------------------
    -- PRIMEIRO: COPIAR ASSETS
    --------------------------------------------------

    for _, arquivo in ipairs(
        arquivos
    ) do

        local nomeLower =
            arquivo:lower()

        local ehAudio =
            nomeLower:match(
                "%.mp3$"
            )
            or
            nomeLower:match(
                "%.ogg$"
            )
            or
            nomeLower:match(
                "%.wav$"
            )

        local ehImagem =
            nomeLower:match(
                "%.jpg$"
            )
            or
            nomeLower:match(
                "%.jpeg$"
            )
            or
            nomeLower:match(
                "%.png$"
            )

        -- Vídeo de fundo: o LÖVE só reproduz Ogg Theora (.ogv)
        local ehVideo =
            nomeLower:match(
                "%.ogv$"
            )

        if ehAudio or ehImagem or ehVideo then

            local origem =
                "osz_temp/" ..
                arquivo

            local destino =
                pastaDestino ..
                "/" ..
                limparNome(
                    arquivo
                )

            if copiarArquivo(
                origem,
                destino
            ) then

                print(
                    "Asset copiado: " ..
                    arquivo
                )
            end
        end
    end

    --------------------------------------------------
    -- SEGUNDO: OSU
    --------------------------------------------------

    for _, arquivo in ipairs(
        arquivos
    ) do

        if arquivo:lower():match(
            "%.osu$"
        ) then

            local caminhoOsu =
                "osz_temp/" ..
                arquivo

            local conteudo =
                love.filesystem.read(
                    caminhoOsu
                )

            if conteudo then

                --------------------------------------------------
                -- TITULO
                --------------------------------------------------

                local titulo =
                    conteudo:match(
                        "Title:(.-)\n"
                    )

                titulo =
                    titulo
                    or
                    nomeOsz

                titulo =
                    titulo:gsub(
                        "\r",
                        ""
                    )

                titulo =
                    titulo:gsub(
                        "^%s+",
                        ""
                    )

                titulo =
                    titulo:gsub(
                        "%s+$",
                        ""
                    )

                --------------------------------------------------
                -- DIFICULDADE
                --------------------------------------------------

                local dificuldade =
                    conteudo:match(
                        "Version:(.-)\n"
                    )

                dificuldade =
                    dificuldade
                    or
                    arquivo

                dificuldade =
                    dificuldade:gsub(
                        "\r",
                        ""
                    )

                dificuldade =
                    dificuldade:gsub(
                        "^%s+",
                        ""
                    )

                dificuldade =
                    dificuldade:gsub(
                        "%s+$",
                        ""
                    )

                --------------------------------------------------
                -- BACKGROUND
                --------------------------------------------------

                local background =
                    conteudo:match(
                        '[\r\n]0,0,"([^"]+)"'
                    )

                if background then

                    background =
                        background:gsub(
                            "\\",
                            "/"
                        )

                    background =
                        background:match(
                            "([^/]+)$"
                        )
                end

                --------------------------------------------------
                -- COPIAR OSU
                --------------------------------------------------

                local destino =
                    pastaDestino ..
                    "/" ..
                    limparNome(
                        arquivo
                    )

                local sucesso =
                    copiarArquivo(
                        caminhoOsu,
                        destino
                    )

                if sucesso then

                    --------------------------------------------------
                    -- ID
                    --------------------------------------------------

                    local id =
                        limparNome(
                            titulo
                        )
                        ..
                        "_"
                        ..
                        limparNome(
                            dificuldade
                        )

                    id =
                        id:gsub(
                            "[^%w_%-]",
                            "_"
                        )

                    local idOriginal =
                        id

                    local contador = 1

                    while biblioteca.obter(
                        id
                    ) do

                        contador =
                            contador + 1

                        id =
                            idOriginal ..
                            "_" ..
                            contador
                    end

                    --------------------------------------------------
                    -- MAPA
                    --------------------------------------------------

                    local mapa = {

                        id = id,

                        nome =
                            titulo,

                        dificuldade =
                            dificuldade,

                        arquivo =
                            destino,

                        pasta =
                            pastaDestino,

                        background =
                            background
                    }

                    biblioteca.dados[
                        #biblioteca.dados + 1
                    ] = mapa

                    importados[
                        #importados + 1
                    ] = mapa

                    print(
                        "Beatmap importado: " ..
                        titulo ..
                        " [" ..
                        dificuldade ..
                        "]"
                    )

                    if background then

                        print(
                            "Background: " ..
                            background
                        )
                    end
                end
            end
        end
    end

    --------------------------------------------------
    -- SALVAR
    --------------------------------------------------

    biblioteca.salvar()

    --------------------------------------------------
    -- DESMONTAR
    --------------------------------------------------

    love.filesystem.unmountFullPath(
        caminho
    )

    print(
        "================================"
    )

    print(
        "IMPORTACAO TERMINADA"
    )

    print(
        "Mapas: " ..
        tostring(
            #importados
        )
    )

    print(
        "================================"
    )

    return importados
end

--------------------------------------------------
-- IMPORTAR OSU
--------------------------------------------------

function biblioteca.importarOsu(
    caminhoOsu,
    nome,
    dificuldade,
    pastaDestino
)

    garantirPasta()

    nome =
        limparNome(nome)

    dificuldade =
        tostring(
            dificuldade
            or "Unknown"
        )

    local nomeArquivo =
        caminhoOsu:match(
            "([^/]+)$"
        )

    if not nomeArquivo then
        return nil
    end

    nomeArquivo =
        limparNome(
            nomeArquivo
        )

    local arquivoDestino =
        pastaDestino ..
        "/" ..
        nomeArquivo

    if existeArquivo(
        arquivoDestino
    ) then

        return nil
    end

    if not copiarArquivo(
        caminhoOsu,
        arquivoDestino
    ) then

        return nil
    end

    local id =
        nome ..
        "_" ..
        dificuldade

    id =
        id:gsub(
            "[^%w_%-]",
            "_"
        )

    local idOriginal =
        id

    local contador = 1

    while biblioteca.obter(
        id
    ) do

        contador =
            contador + 1

        id =
            idOriginal ..
            "_" ..
            contador
    end

    local mapa = {

        id = id,

        nome =
            nome,

        dificuldade =
            dificuldade,

        arquivo =
            arquivoDestino,

        pasta =
            pastaDestino,

        background = nil
    }

    biblioteca.dados[
        #biblioteca.dados + 1
    ] = mapa

    biblioteca.salvar()

    return mapa
end

--------------------------------------------------
-- REMOVER
--------------------------------------------------

function biblioteca.remover(id)

    local indice = nil
    local mapa = nil

    for i, item in ipairs(
        biblioteca.dados
    ) do

        if item.id == id then

            indice = i
            mapa = item

            break
        end
    end

    if not indice then
        return false
    end

    if mapa.arquivo then

        if love.filesystem.getInfo(
            mapa.arquivo
        ) then

            love.filesystem.remove(
                mapa.arquivo
            )
        end
    end

    table.remove(
        biblioteca.dados,
        indice
    )

    biblioteca.salvar()

    return true
end

return biblioteca