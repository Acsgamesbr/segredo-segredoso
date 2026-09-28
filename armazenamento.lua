-- Pasta externa de beatmaps.
--
--   Windows : Documentos\FunkyStudio\beatmaps
--   Android : /storage/emulated/0/FunkyStudio/beatmaps  (raiz do aparelho)
--   Outros  : ~/Documents/FunkyStudio/beatmaps
--
-- A pasta é criada automaticamente e "montada" no love.filesystem em
-- "beatmaps_externos" (somente leitura). Beatmaps soltos (.osz) ou já
-- extraídos (pastas com .osu) colocados ali aparecem na biblioteca.
--
-- No Android 11+ a raiz do armazenamento exige a permissão "Acesso a todos
-- os arquivos" (MANAGE_EXTERNAL_STORAGE). Sem ela o jogo continua funcionando
-- com a pasta interna e avisa o motivo em Debug > Pasta externa.

local armazenamento = {}

local PONTO_MONTAGEM = "beatmaps_externos"
local NOME_PASTA = "FunkyStudio"

local caminhoReal = nil
local montado = false
local motivo = "ainda não verificada"
local cdefFeito = {}

function armazenamento.pontoMontagem()
    return PONTO_MONTAGEM
end

function armazenamento.estaMontado()
    return montado
end

function armazenamento.caminho()
    return caminhoReal
end

function armazenamento.descricao()
    if montado then
        return caminhoReal
    end

    if caminhoReal then
        return caminhoReal .. "  (" .. motivo .. ")"
    end

    return motivo
end

--------------------------------------------------
-- FFI (opcional)
--------------------------------------------------

local function obterFFI()
    local ok, ffi = pcall(require, "ffi")
    if ok then return ffi end
    return nil
end

local function declarar(ffi, chave, texto)
    if cdefFeito[chave] then return true end

    local ok = pcall(ffi.cdef, texto)

    -- se já estava declarado por outro módulo, também serve
    cdefFeito[chave] = true
    return ok
end

local function documentosWindows()
    local ffi = obterFFI()

    if ffi then
        local ok, caminho = pcall(function()
            declarar(ffi, "shfolder",
                "int SHGetFolderPathA(void* hwnd, int csidl, void* token, unsigned long flags, char* path);")

            local shell32 = ffi.load("shell32")
            local buffer = ffi.new("char[520]")

            -- CSIDL_PERSONAL (5) = pasta Documentos, mesmo se estiver no OneDrive
            if shell32.SHGetFolderPathA(nil, 5, nil, 0, buffer) == 0 then
                return ffi.string(buffer)
            end
        end)

        if ok and caminho and caminho ~= "" then return caminho end
    end

    local perfil = os.getenv("USERPROFILE")
    if perfil then return perfil .. "\\Documents" end

    return nil
end

local function criarDiretorio(ffi, windows, caminho)
    if windows then
        declarar(ffi, "createdir", "int CreateDirectoryA(const char* path, void* attrs);")
        return ffi.C.CreateDirectoryA(caminho, nil) ~= 0
    end

    declarar(ffi, "mkdir", "int mkdir(const char* path, unsigned int mode);")
    return ffi.C.mkdir(caminho, 493) == 0 -- 0755
end

-- Cria a pasta e os pais (um nível por vez).
local function garantirPasta(caminho, windows)
    local ffi = obterFFI()
    if not ffi then return false end

    local separador = windows and "\\" or "/"
    local atual = ""

    for parte in caminho:gmatch("[^\\/]+") do
        if atual == "" then
            atual = (windows and "" or "/") .. parte
        else
            atual = atual .. separador .. parte
        end

        -- letra do drive (C:) não precisa ser criada
        if not (windows and parte:match("^%a:$")) then
            pcall(criarDiretorio, ffi, windows, atual)
        end
    end

    return true
end

--------------------------------------------------
-- CAMINHO
--------------------------------------------------

local function calcularCaminho()
    local sistema = love.system.getOS()

    if sistema == "Windows" then
        local docs = documentosWindows()
        if docs then return docs .. "\\" .. NOME_PASTA .. "\\beatmaps", true end

    elseif sistema == "Android" then
        return "/storage/emulated/0/" .. NOME_PASTA .. "/beatmaps", false

    elseif sistema == "OS X" or sistema == "Linux" then
        local home = os.getenv("HOME")
        if home then return home .. "/Documents/" .. NOME_PASTA .. "/beatmaps", false end
    end

    return nil, false
end

local function escreverLeiaMe(caminho, windows)
    local separador = windows and "\\" or "/"
    local arquivo = caminho .. separador .. "LEIA-ME.txt"

    local existente = io.open(arquivo, "rb")

    if existente then
        existente:close()
        return
    end

    local f = io.open(arquivo, "wb")

    if f then
        f:write("wawa.\r\n")
        f:close()
    end
end

--------------------------------------------------
-- MONTAR
--------------------------------------------------

function armazenamento.montar(config)
    if montado then return true end

    if config and config.get("pastaExterna") == false then
        motivo = "desativada nas configurações"
        return false
    end

    local caminho, windows = calcularCaminho()

    if not caminho then
        motivo = "sistema sem pasta externa"
        return false
    end

    caminhoReal = caminho

    garantirPasta(caminho, windows)
    pcall(escreverLeiaMe, caminho, windows)

    if not love.filesystem.mountFullPath then
        motivo = "requer LÖVE 12 (mountFullPath)"
        return false
    end

    local tentativas = {caminho, (caminho:gsub("\\", "/"))}

    for _, tentativa in ipairs(tentativas) do
        local ok, resultado = pcall(
            love.filesystem.mountFullPath, tentativa, PONTO_MONTAGEM, "read", false
        )

        if ok and resultado then
            montado = true
            motivo = "ok"
            return true
        end
    end

    if love.system.getOS() == "Android" then
        motivo = "sem permissão: ative 'Acesso a todos os arquivos' para o app"
    else
        motivo = "não foi possível abrir a pasta"
    end

    return false
end

function armazenamento.desmontar()
    if montado and love.filesystem.unmountFullPath then
        pcall(love.filesystem.unmountFullPath, caminhoReal)
    end

    montado = false
end

-- Caminho real (com barras normais) de um arquivo dentro da pasta externa.
function armazenamento.caminhoReal(nomeArquivo)
    if not caminhoReal then return nil end

    return (caminhoReal:gsub("\\", "/")) .. "/" .. nomeArquivo
end

return armazenamento
