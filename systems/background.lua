-- Fundo do beatmap: imagem e, opcionalmente, vídeo.
--
-- O LÖVE só decodifica vídeo Ogg Theora (.ogv). Se o beatmap referencia
-- outro formato (mp4, avi, flv...), procuramos um .ogv com o mesmo nome na
-- pasta (é só converter com ffmpeg e colocar ao lado). Sem vídeo utilizável,
-- o jogo usa a imagem normalmente.

local background = {}

local imagem = nil
local caminhoAtual = nil

local video = nil
local videoOffset = 0
local videoRodando = false
local videoStatus = "Nenhum vídeo neste beatmap"
local ultimoReinicio = -10
local videoAcabou = false

--------------------------------------------------
-- LIMPAR
--------------------------------------------------

function background.limpar()
    if imagem then
        pcall(function() imagem:release() end)
        imagem = nil
    end

    if video then
        pcall(function() video:pause() end)
        pcall(function() video:release() end)
        video = nil
    end

    caminhoAtual = nil
    videoOffset = 0
    videoRodando = false
    videoAcabou = false
    videoStatus = "Nenhum vídeo neste beatmap"
end

--------------------------------------------------
-- IMAGEM
--------------------------------------------------

function background.carregar(mapa, caminho)
    background.limpar()
    if not mapa or not caminho or caminho == "" then return false end

    caminho = tostring(caminho):gsub("\\", "/")
    local nomeArquivo = caminho:match("([^/]+)$") or caminho
    if nomeArquivo == "" then return false end

    local completo = tostring(mapa.pasta) .. "/" .. nomeArquivo
    completo = completo:gsub("\\", "/")

    local sucesso, resultado = pcall(love.graphics.newImage, completo)
    if not sucesso or not resultado then
        print("ERRO AO CARREGAR BACKGROUND:", completo, tostring(resultado))
        return false
    end

    imagem = resultado
    caminhoAtual = completo
    return true
end

function background.getCaminho() return caminhoAtual end

--------------------------------------------------
-- VÍDEO
--------------------------------------------------

-- Deve ser chamado DEPOIS de background.carregar (que limpa tudo).
function background.carregarVideo(mapa, nomeArquivo, offsetMs)
    if video then
        pcall(function() video:release() end)
        video = nil
    end

    videoRodando = false
    videoAcabou = false
    videoStatus = "Nenhum vídeo neste beatmap"

    if not mapa or not nomeArquivo or nomeArquivo == "" then return false end

    local nome = tostring(nomeArquivo):gsub("\\", "/"):match("([^/]+)$") or nomeArquivo
    local base, ext = nome:match("^(.*)%.([^.]+)$")
    ext = (ext or ""):lower()

    local candidatos = {nome}

    if base and ext ~= "ogv" then
        candidatos[#candidatos + 1] = base .. ".ogv"
    end

    local achouArquivo = false

    for _, cand in ipairs(candidatos) do
        local completo = (tostring(mapa.pasta) .. "/" .. cand):gsub("\\", "/")

        if cand:lower():match("%.ogv$") and love.filesystem.getInfo(completo) then
            achouArquivo = true

            local ok, v = pcall(love.graphics.newVideo, completo, {audio = false})

            if ok and v then
                video = v
                videoOffset = tonumber(offsetMs) or 0
                videoStatus = "Disponível: " .. cand
                return true
            end

            videoStatus = "Falha ao abrir " .. cand
        end
    end

    if not achouArquivo then
        if ext == "ogv" then
            videoStatus = "Arquivo não encontrado: " .. nome
        else
            videoStatus = "." .. ext .. " não é suportado (converta para .ogv)"
        end
    end

    return false
end

function background.temVideo()
    return video ~= nil
end

function background.statusVideo()
    return videoStatus
end

function background.iniciarVideo(tempoMusica)
    if not video then return end

    videoRodando = true
    videoAcabou = false
    background.atualizarVideo(tempoMusica or 0)
end

function background.pausarVideo()
    if not video then return end

    pcall(function() video:pause() end)
    videoRodando = false
end

function background.retomarVideo(tempoMusica)
    if not video then return end

    videoRodando = true
    videoAcabou = false
    background.atualizarVideo(tempoMusica or 0)
end

function background.pararVideo()
    if not video then return end

    pcall(function()
        video:pause()
        video:seek(0)
    end)

    videoRodando = false
    videoAcabou = false
end

-- Mantém o vídeo alinhado com a música (tolerância de 0,3 s).
function background.atualizarVideo(tempoMusica)
    if not video or not videoRodando or videoAcabou then return end

    local alvo = (tempoMusica or 0) - videoOffset / 1000

    pcall(function()
        if alvo < 0 then
            if video:isPlaying() then
                video:pause()
                video:seek(0)
            end
            return
        end

        if not video:isPlaying() then
            local agora = love.timer.getTime()

            -- se ficar parando logo após reiniciar, é porque acabou
            if agora - ultimoReinicio < 1.0 then
                videoAcabou = true
                return
            end

            ultimoReinicio = agora
            video:seek(alvo)
            video:play()
            return
        end

        if math.abs(video:tell() - alvo) > 0.3 then
            video:seek(alvo)
        end
    end)
end

--------------------------------------------------
-- DESENHO
--------------------------------------------------

local function desenharCobrindo(objeto, iw, ih)
    local largura = love.graphics.getWidth()
    local altura = love.graphics.getHeight()

    if iw <= 0 or ih <= 0 then return end

    local escala = math.max(largura / iw, altura / ih)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        objeto,
        (largura - iw * escala) / 2,
        (altura - ih * escala) / 2,
        0, escala, escala
    )
end

function background.desenhar(config)
    local usarVideo = video ~= nil
        and config.get("fundoModo") == "video"

    if usarVideo then
        desenharCobrindo(video, video:getWidth(), video:getHeight())
    elseif imagem then
        desenharCobrindo(imagem, imagem:getWidth(), imagem:getHeight())
    else
        return
    end

    local brilho = tonumber(config.get("brilhoFundo")) or 100
    brilho = math.max(0, math.min(100, brilho))

    local escurecimento = 1 - brilho / 100

    if escurecimento > 0 then
        love.graphics.setColor(0, 0, 0, escurecimento)
        love.graphics.rectangle(
            "fill", 0, 0,
            love.graphics.getWidth(), love.graphics.getHeight()
        )
    end
end

return background
