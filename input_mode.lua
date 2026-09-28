local inputMode = {}

local function obterOS()
    if love and love.system and type(love.system.getOS) == "function" then
        local ok, sistema = pcall(love.system.getOS)
        if ok and type(sistema) == "string" then
            return sistema
        end
    end

    return "Unknown"
end

function inputMode.getOS()
    return obterOS()
end

function inputMode.usaPC(config)
    if obterOS() == "Windows" then
        return true
    end

    if config and type(config.get) == "function" then
        return config.get("enablePcControls") == true
    end

    return false
end

function inputMode.usaTouch(config)
    if inputMode.usaPC(config) then
        return false
    end

    local sistema = obterOS()

    return sistema == "Android"
        or sistema == "iOS"
end

return inputMode
