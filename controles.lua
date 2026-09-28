local controles = {}

controles.toques = {}
controles.botToques = {}

--------------------------------------------------
-- TECLADO
--------------------------------------------------

local teclasPadrao = {
    [1] = "d",
    [2] = "f",
    [3] = "j",
    [4] = "k"
}

controles.teclas = {
    [1] = "d",
    [2] = "f",
    [3] = "j",
    [4] = "k"
}

function controles.carregarTeclas(config)

    for lane = 1, 4 do

        local valor = nil

        if config and type(config.get) == "function" then
            valor = config.get("teclaLane" .. lane)
        end

        if type(valor) == "string" and valor ~= "" then
            controles.teclas[lane] = valor
        else
            controles.teclas[lane] = teclasPadrao[lane]
        end
    end
end

function controles.definirTecla(lane, tecla, config)

    lane = tonumber(lane)

    if not lane or lane < 1 or lane > 4 then
        return false
    end

    if type(tecla) ~= "string" or tecla == "" then
        return false
    end

    controles.teclas[lane] = tecla

    if config and type(config.set) == "function" then
        config.set(
            "teclaLane" .. lane,
            tecla
        )
    end

    return true
end

function controles.getTecla(lane)

    lane = tonumber(lane)

    if not lane then
        return ""
    end

    return controles.teclas[lane] or ""
end

--------------------------------------------------
-- CONTROLE
--------------------------------------------------

local botoesPadrao = {
    [1] = "dpleft",
    [2] = "dpdown",
    [3] = "dpup",
    [4] = "dpright"
}

controles.botoes = {
    [1] = "dpleft",
    [2] = "dpdown",
    [3] = "dpup",
    [4] = "dpright"
}

function controles.carregarBotoes(config)

    for lane = 1, 4 do

        local valor = nil

        if config and type(config.get) == "function" then
            valor = config.get(
                "controleLane" .. lane
            )
        end

        if type(valor) == "string" and valor ~= "" then
            controles.botoes[lane] = valor
        else
            controles.botoes[lane] =
                botoesPadrao[lane]
        end
    end
end

function controles.definirBotao(
    lane,
    botao,
    config
)

    lane = tonumber(lane)

    if not lane or lane < 1 or lane > 4 then
        return false
    end

    if type(botao) ~= "string" or botao == "" then
        return false
    end

    controles.botoes[lane] = botao

    if config and type(config.set) == "function" then
        config.set(
            "controleLane" .. lane,
            botao
        )
    end

    return true
end

function controles.getBotao(lane)

    lane = tonumber(lane)

    if not lane then
        return ""
    end

    return controles.botoes[lane] or ""
end

--------------------------------------------------
-- TOQUES
--------------------------------------------------

function controles.pressionou(id, x, y)

    local largura =
        love.graphics.getWidth()

    local tamanhoTile =
        largura / 4

    local tile =
        math.floor(
            x / tamanhoTile
        ) + 1

    tile =
        math.max(
            1,
            math.min(
                tile,
                4
            )
        )

    controles.toques[id] = {
        tile = tile,
        x = x,
        y = y
    }
end

function controles.mover(id, x, y)

    if not controles.toques[id] then
        return
    end

    local largura =
        love.graphics.getWidth()

    local tamanhoTile =
        largura / 4

    local tile =
        math.floor(
            x / tamanhoTile
        ) + 1

    tile =
        math.max(
            1,
            math.min(
                tile,
                4
            )
        )

    controles.toques[id].tile = tile
    controles.toques[id].x = x
    controles.toques[id].y = y
end

function controles.soltou(id)
    controles.toques[id] = nil
end

function controles.soltar(id)
    controles.soltou(id)
end

--------------------------------------------------
-- TECLADO
--------------------------------------------------

function controles.teclaParaLane(tecla)

    if type(tecla) ~= "string" then
        return nil
    end

    for lane = 1, 4 do

        if controles.teclas[lane] == tecla then
            return lane
        end
    end

    return nil
end

--------------------------------------------------
-- CONTROLE
--------------------------------------------------

function controles.botaoParaLane(botao)

    if type(botao) ~= "string" then
        return nil
    end

    for lane = 1, 4 do

        if controles.botoes[lane] == botao then
            return lane
        end
    end

    return nil
end

--------------------------------------------------
-- BOT
--------------------------------------------------

function controles.botPressionar(tile)

    tile = tonumber(tile)

    if not tile or tile < 1 or tile > 4 then
        return
    end

    controles.botToques[tile] = true
end

function controles.botSoltar(tile)

    tile = tonumber(tile)

    if not tile then
        return
    end

    controles.botToques[tile] = nil
end

function controles.botLimpar()

    controles.botToques = {}
end

--------------------------------------------------
-- VERIFICAR LANE
--------------------------------------------------

function controles.estaPressionado(tile)

    tile = tonumber(tile)

    if not tile then
        return false
    end

    for _, toque in pairs(controles.toques) do

        if toque.tile == tile then
            return true
        end
    end

    if controles.botToques[tile] then
        return true
    end

    return false
end

--------------------------------------------------
-- LIMPAR
--------------------------------------------------

function controles.limpar()

    controles.toques = {}
    controles.botToques = {}
end

return controles