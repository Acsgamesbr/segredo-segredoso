-- Lê a preferência de backend gráfico salva (config_save.lua) ANTES de
-- love.graphics existir, porque é o único momento em que dá pra escolher
-- o renderer. Sem arquivo salvo ainda (primeira execução), usa Vulkan
-- como nativo. A ordem da lista é a própria ordem de fallback do LÖVE:
-- ele tenta o primeiro item e, se não conseguir abrir, tenta o próximo
-- sozinho — não precisamos escrever essa lógica.
local function backendSalvo()
    if not love.filesystem.getInfo("config_save.lua") then
        return nil
    end

    local conteudo = love.filesystem.read("config_save.lua")
    if not conteudo then return nil end

    local funcao = load(conteudo, "config_save.lua", "t")
    if not funcao then return nil end

    local ok, dados = pcall(funcao)
    if not ok or type(dados) ~= "table" then return nil end

    return dados.backendGrafico
end

function love.conf(t)
    t.window.height = 480
    t.window.width = 720
    t.window.title = "FunkyStudio"
    t.window.resizable = false
    t.highdpi = true
    t.window.fullscreen = true
    t.window.vsync = 0
    t.window.msaa = 0

    if backendSalvo() == "opengl" then
        -- forçado pelo jogador (Vídeo > Backend gráfico)
        t.graphics.renderers = {"opengl", "opengles"}
    else
        -- padrão: Vulkan nativo, com fallback automático pro OpenGL
        t.graphics.renderers = {"vulkan", "opengl", "opengles"}
    end
end
