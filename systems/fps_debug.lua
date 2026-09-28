local debug = {}

function debug.load()
    debug.ativo = true
end

function debug.draw()
    if not debug.ativo then
        return
    end

    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.rectangle("fill", 10, 10, 300, 90)

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.print(
        "FPS: " .. tostring(love.timer.getFPS()),
        20,
        20
    )

    love.graphics.print(
        "FPS_LIMITE: " .. tostring(FPS_LIMITE),
        20,
        45
    )

    love.graphics.print(
        "DEBUG FPS ATIVO",
        20,
        70
    )
end

return debug