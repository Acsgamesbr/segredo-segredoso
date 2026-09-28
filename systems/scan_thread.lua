-- Corpo de uma thread separada (love.thread), disparada por
-- beatmap_library.reescanearAsync().
--
-- Motivo: escanear e reescanear a pasta de beatmaps (interna + externa)
-- lê e faz o parse de TODOS os .osu encontrados, um por um, pra checar
-- se são osu!mania 4K e calcular a dificuldade estimada. Com uma
-- coleção grande isso é pesado o bastante pra travar a tela principal
-- por alguns segundos. Rodando aqui, o jogo continua respondendo
-- (menus, animações, música) enquanto isso acontece em segundo plano.
--
-- Uma thread do LÖVE é uma VM Lua totalmente separada: não enxerga
-- variáveis do jogo, só os módulos "seguros pra thread" (love.filesystem,
-- love.system, love.timer, love.thread, FFI) e o que vier pelos
-- Channels. Por isso este arquivo faz sozinho o ciclo completo de
-- carregar -> sincronizar -> salvar, e devolve o resultado pronto.

local pastaExternaAtiva, modo = ...

local ok, erro = pcall(function()

    local biblioteca = require("beatmap_library")
    local armazenamento = require("armazenamento")

    -- config "de mentira": só precisa responder a pergunta que
    -- armazenamento.montar faz (se a pasta externa está ligada nas
    -- configurações). O valor veio como argumento porque uma thread não
    -- enxerga o config_manager do jogo principal.
    local configFalso = {
        get = function(chave)
            if chave == "pastaExterna" then
                return pastaExternaAtiva
            end
            return nil
        end,
    }

    -- Monta a pasta externa TAMBÉM aqui: o mount do LÖVE é global ao
    -- processo, mas o "estaMontado()" de armazenamento.lua é uma
    -- variável local da instância desta thread, então precisa marcar
    -- de novo por aqui pra beatmap_library enxergar a pasta externa.
    pcall(armazenamento.montar, configFalso)

    biblioteca.carregar()

    if modo == "recalcular" then

        -- Só refaz a nota de dificuldade dos beatmaps já conhecidos,
        -- sem procurar arquivos novos.
        for _, mapa in ipairs(biblioteca.dados) do
            mapa.rating = nil
        end

    else

        -- modo "reescanear" (padrão): procura beatmaps novos/removidos
        biblioteca.sincronizar()
    end

    biblioteca.garantirRatings()
    biblioteca.salvar()

    love.thread.getChannel("biblioteca_resultado"):push(biblioteca.dados)
end)

if not ok then
    love.thread.getChannel("biblioteca_erro"):push(tostring(erro))
end
