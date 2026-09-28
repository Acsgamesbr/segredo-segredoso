local fps = {}

local ok, tema = pcall(require, "tema")
if not ok then tema = nil end

local tempo = 0
local frames = 0
local media = 0
local tempoGameplay = 0
local framesGameplay = 0

-- Média curta (~0,5s) usada no número exibido em tela: o valor "cru" de
-- love.timer.getFPS() pula visivelmente quando o número de notas ainda
-- não julgadas na tela cai (menos coisa pra desenhar = frame mais barato
-- = FPS realmente mais alto por um instante, não é bug do contador).
-- Suavizar deixa o número mais fácil de ler sem esconder quedas reais.
local janela = {}
local somaJanela = 0
local DURACAO_JANELA = 0.5

function fps.resetar()
    tempo = 0
    frames = 0
    media = 0
    tempoGameplay = 0
    framesGameplay = 0
    janela = {}
    somaJanela = 0
end

function fps.atualizar(dt)
    dt = tonumber(dt)
    if not dt then return end

    tempo = tempo + dt
    frames = frames + 1
    tempoGameplay = tempoGameplay + dt
    framesGameplay = framesGameplay + 1

    if tempoGameplay > 0 then
        media = framesGameplay / tempoGameplay
    end

    if tempo >= 0.25 then
        tempo = 0
        frames = 0
    end

    -- janela deslizante simples (soma de dt) para a média curta exibida
    janela[#janela + 1] = dt
    somaJanela = somaJanela + dt

    while somaJanela > DURACAO_JANELA and #janela > 1 do
        somaJanela = somaJanela - janela[1]
        table.remove(janela, 1)
    end
end

function fps.getMedia() return media end

-- FPS suavizado (~0,5s): o que aparece como "FPS:" na tela.
function fps.getSuavizado()
    if #janela < 2 or somaJanela <= 0 then
        return love.timer.getFPS()
    end

    return (#janela - 1) / somaJanela
end

function fps.desenhar(config, chart)
    local modo = tonumber(config.get("fpsModo")) or 0
    if modo <= 0 then return end

    local k = tema and tema.escala() or 1
    local fonte = tema and tema.fonte(18 * k) or love.graphics.getFont()

    local linhas = {string.format("FPS: %d", math.floor(fps.getSuavizado() + 0.5))}

    if modo >= 2 then
        linhas[#linhas + 1] = string.format("MEM: %.1f MB", collectgarbage("count") / 1024)
    end

    if modo >= 3 then
        linhas[#linhas + 1] = string.format("NOTAS NA TELA: %d", chart.getQuantidadeNotasNaTela())
        linhas[#linhas + 1] = string.format("NOTAS NO CHART: %d", chart.getQuantidadeNotas())
        linhas[#linhas + 1] = string.format("FPS INSTANTANEO: %d", love.timer.getFPS())
        linhas[#linhas + 1] = string.format("MEDIA (partida): %.1f", media)
    end

    -- caixa do tamanho do maior texto, em vez de um retângulo fixo
    local padX = 8 * k
    local padY = 5 * k
    local entreLinhas = fonte:getHeight() + 4 * k

    local largura = 0

    for _, linha in ipairs(linhas) do
        largura = math.max(largura, fonte:getWidth(linha))
    end

    largura = largura + padX * 2
    local altura = padY * 2 + entreLinhas * #linhas

    local x, y = 10 * k, 10 * k

    love.graphics.setFont(fonte)
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", x, y, largura, altura, 5 * k, 5 * k)
    love.graphics.setColor(1, 1, 1, 1)

    for i, linha in ipairs(linhas) do
        love.graphics.print(linha, x + padX, y + padY + ((i - 1) * entreLinhas))
    end
end

return fps
