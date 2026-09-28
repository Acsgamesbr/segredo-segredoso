-- Som de acerto sintetizado (não precisa de arquivos de áudio) e vibração.

local hitsound = {}

local ativo = false
local volume = 0.6
local vibrar = false
local pool = nil
local indice = 1

function hitsound.aplicarConfiguracao(config)
    ativo = config.get("hitsom") == true
    volume = (tonumber(config.get("hitsomVolume")) or 60) / 100
    vibrar = config.get("vibrar") == true
end

local function criar()
    local taxa = 44100
    local duracao = 0.05
    local n = math.floor(taxa * duracao)
    local dados = love.sound.newSoundData(n, taxa, 16, 1)

    for i = 0, n - 1 do
        local t = i / taxa
        local envelope = math.exp(-t * 85)
        local v = (math.sin(2 * math.pi * 1500 * t) * 0.7
            + math.sin(2 * math.pi * 3000 * t) * 0.3) * envelope

        dados:setSample(i, v * 0.85)
    end

    local base = love.audio.newSource(dados)

    pool = {base}

    for i = 2, 8 do
        pool[i] = base:clone()
    end
end

function hitsound.tocar()
    if ativo and volume > 0 then
        if not pool then pcall(criar) end

        if pool then
            local s = pool[indice]
            indice = indice % #pool + 1

            s:stop()
            s:setVolume(volume)
            s:play()
        end
    end

    if vibrar and love.system and love.system.vibrate then
        pcall(love.system.vibrate, 0.02)
    end
end

return hitsound
