-- Utilitários de índice para a lista de notas (ordenada por tempo).
--
-- Motivo: percorrer TODAS as notas do chart a cada frame (desenho, hit,
-- bot) faz o custo por frame crescer com o tamanho do mapa e cair
-- conforme as notas são acertadas. Aqui as buscas ficam limitadas às
-- notas que realmente importam naquele instante.

local indice = {}

-- Primeiro índice cuja nota tem time >= tempo (ou #notas + 1).
function indice.primeiroApartir(notas, tempo)
    local lo, hi = 1, #notas + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local valor = tonumber(notas[mid].time) or math.huge
        if valor < tempo then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

-- Último índice cuja nota tem time <= tempo (ou 0).
function indice.ultimoAte(notas, tempo)
    local lo, hi = 1, #notas + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local valor = tonumber(notas[mid].time) or math.huge
        if valor <= tempo then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo - 1
end

-- Primeiro índice que ainda pode ter nota não julgada.
-- Todas as notas antes dele já foram julgadas. O cursor fica guardado
-- na própria tabela de notas e volta para 1 em qualquer reinício.
function indice.primeiraPendente(notas, tempo)
    local i = notas.cursorPendente or 1

    if i > 1 then
        local anterior = notas[i - 1]

        if not anterior
        or not anterior.judged
        or (tempo and anterior.time > tempo + 1.0) then
            i = 1
        end
    end

    local total = #notas

    while i <= total and notas[i].judged do
        i = i + 1
    end

    notas.cursorPendente = i

    return i
end

function indice.resetar(notas)
    if type(notas) == "table" then
        notas.cursorPendente = 1
        notas.duracaoMaxima = nil
    end
end

-- Maior duração de hold do mapa (calculada uma vez por tabela de notas).
function indice.duracaoMaxima(notas)
    local maxima = notas.duracaoMaxima

    if maxima == nil then
        maxima = 0

        for i = 1, #notas do
            local nota = notas[i]
            local d = tonumber(nota.duration or nota.duracao) or 0

            if d > maxima then
                maxima = d
            end
        end

        notas.duracaoMaxima = maxima
    end

    return maxima
end

return indice
