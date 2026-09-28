local music = {}

local source = nil
local caminhoAtual = nil
local volume = 1.0

--------------------------------------------------
-- ENCONTRAR AUDIO
--------------------------------------------------

local function encontrarAudio(pasta)
    if not pasta then
        return nil
    end

    local arquivos =
        love.filesystem.getDirectoryItems(
            pasta
        )

    -- Beatmaps às vezes têm mais de um áudio na pasta (ex.: uma prévia
    -- curta, ou sobra de outra dificuldade do mesmo .osz). Pegar o
    -- PRIMEIRO que aparecer é loteria — a ordem não é garantida e, se
    -- vier um áudio curto, a música acaba antes do chart. Em vez disso,
    -- usamos sempre o maior arquivo de áudio da pasta, que é o mais
    -- provável de ser a faixa completa.
    local melhorCaminho = nil
    local melhorTamanho = -1

    for _, arquivo in ipairs(arquivos) do

        local nome =
            arquivo:lower()

        if nome:match("%.mp3$")
        or nome:match("%.ogg$")
        or nome:match("%.oga$")
        or nome:match("%.wav$") then

            local caminho =
                pasta .. "/" .. arquivo

            local info =
                love.filesystem.getInfo(
                    caminho
                )

            local tamanho =
                (info and info.size) or 0

            if tamanho > melhorTamanho then
                melhorCaminho = caminho
                melhorTamanho = tamanho
            end
        end
    end

    return melhorCaminho
end

--------------------------------------------------
-- CARREGAR
--------------------------------------------------

function music.carregar(pasta)

    if source then
        pcall(function()
            source:stop()
        end)

        source = nil
    end

    caminhoAtual =
        encontrarAudio(pasta)

    if not caminhoAtual then
        print("AUDIO NAO ENCONTRADO")
        return false
    end

    local sucesso, resultado =
        pcall(function()

            return love.audio.newSource(
                caminhoAtual,
                "stream"
            )

        end)

    if not sucesso then

        print("ERRO AO CARREGAR AUDIO:")
        print(tostring(resultado))

        source = nil

        return false
    end

    source = resultado

    source:setLooping(false)
    source:setVolume(volume)

    return true
end

--------------------------------------------------
-- VOLUME
--------------------------------------------------

function music.setVolume(valor)

    valor = tonumber(valor)

    if not valor then
        return volume
    end

    volume = math.max(
        0,
        math.min(
            1,
            valor
        )
    )

    if source then
        source:setVolume(volume)
    end

    return volume
end

function music.getVolume()
    return volume
end

--------------------------------------------------
-- TOCAR
--------------------------------------------------

function music.tocar()

    if not source then
        return false
    end

    local sucesso =
        pcall(function()
            source:play()
        end)

    return sucesso
end

--------------------------------------------------
-- PAUSAR
--------------------------------------------------

function music.pausar()

    if source then
        source:pause()
    end

end

--------------------------------------------------
-- RETOMAR
--------------------------------------------------

function music.resumir()

    if source then
        source:play()
    end

end

--------------------------------------------------
-- PARAR
--------------------------------------------------

function music.parar()

    if source then
        source:stop()
        source:seek(0)
    end

end

--------------------------------------------------
-- TEMPO
--------------------------------------------------

function music.getTempo()

    if not source then
        return 0
    end

    return source:tell()

end

--------------------------------------------------
-- TOCANDO?
--------------------------------------------------

function music.estaTocando()

    if not source then
        return false
    end

    return source:isPlaying()

end

--------------------------------------------------
-- SOURCE
--------------------------------------------------

function music.getSource()
    return source
end

return music