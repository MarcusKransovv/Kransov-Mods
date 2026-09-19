script_name("CPOI")
-- Фактический разработчик неизвестен. Переделано под Advance-RP. Студия разработки Kransov Mods.
-- Контакты: https://discord.gg/pWRUrjNnSe. Приятной игры. Все сообщения об ошибках и предложениях оставляйте
-- в дискорде. Спасибо за использование скрипта.
script_description("CPOI coordination tool for Advance-RP")
script_version_number(1)
script_version("1.0")

require "lib.moonloader"

local sampev = require "lib.samp.events"
local ffi = require "ffi"
local keys = require "vkeys"
local Vector3D = require "vector3d"
local json = require "json"

local config_dir = getWorkingDirectory() .. "\\config\\Kransov Mods"
local configPath = config_dir .. "\\commonPoi.json"

local DEFAULT_CONFIG = {
    settings = {
        channel = "fm"
    }
}

local function loadConfig()
    if not doesDirectoryExist(config_dir) then
        createDirectory(config_dir)
    end

    local file = io.open(configPath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local success, data = pcall(json.decode, content)
        if success and data then
            if not data.settings then
                data.settings = {}
            end

            if not data.settings.channel then
                data.settings.channel = DEFAULT_CONFIG.settings.channel
            end

            return data
        end
    end

    return {
        settings = {
            channel = DEFAULT_CONFIG.settings.channel
        }
    }
end
local config = loadConfig()
local function saveConfig()
    if not doesDirectoryExist(config_dir) then
        createDirectory(config_dir)
    end

    local file = io.open(configPath, "w")
    if file then
        file:write(json.encode(config))
        file:close()
    end
end

local allowedChannels = {
    fm = "/fm",
    rn = "/rn",
    fn = "/fn",
    g = "/g",
    ps = "/ps",
    l = "/l"
}
if not allowedChannels[string.lower(tostring(config.settings.channel or ""))] then
    config.settings.channel = "fm"
else
    config.settings.channel = string.lower(config.settings.channel)
end
saveConfig()

local checkpoint = nil
local previewObject = nil

local mainKey = keys.VK_XBUTTON1
local previewModelId = 19605
local cursorEnabled = false

local checkpointType = 1
local checkpointRadius = 3.0
local mapMarker = {
    timer = 0,
    coordinates = {},
    key = keys.VK_U,
    isCpoi = false
}
local indicator = {coordinates = {x = 348, y = 764}}

local markers = {}
local font = nil
local font1 = nil

local function stripSampColors(text)
    if not text then return "" end

    return text:gsub("{%x%x%x%x%x%x}", "")
end
local function getConfiguredChannel()
    local channel = string.lower(tostring(config.settings.channel or "fm"))
    if not allowedChannels[channel] then
        channel = "fm"
        config.settings.channel = channel
        saveConfig()
    end
    return channel
end
local function getConfiguredChannelCommand() return allowedChannels[getConfiguredChannel()] end

local function destroyPreviewObject()
    if previewObject then
        if doesObjectExist(previewObject) then deleteObject(previewObject) end
        previewObject = nil
    end

    markModelAsNoLongerNeeded(previewModelId)
end
local function ensurePreviewModelLoaded()
    if hasModelLoaded(previewModelId) then return true end

    requestModel(previewModelId)

    local started = getGameTimer()
    while not hasModelLoaded(previewModelId) do
        wait(0)

        if getGameTimer() - started > 5000 then return false end
    end

    return true
end
local function updatePreviewObject(x, y, z)
    if not previewObject or not doesObjectExist(previewObject) then
        destroyPreviewObject()

        if not ensurePreviewModelLoaded() then return false end

        previewObject = createObject(previewModelId, x, y, z)

        if previewObject and doesObjectExist(previewObject) then
            setObjectCollision(previewObject, false)
            return true
        end

        previewObject = nil
        return false
    end

    setObjectCoordinates(previewObject, x, y, z)
    return true
end
local function deleteCurrentCheckpoint()
    if checkpoint then
        deleteCheckpoint(checkpoint)
        checkpoint = nil
    end
end
local function clearMapMarkerIfMatches(x, y, z)
    if mapMarker.coordinates.x and mapMarker.coordinates.y and mapMarker.coordinates.z and os.difftime(os.clock(), mapMarker.timer) <= 10 then
        if math.abs(mapMarker.coordinates.x - x) < 0.01 and math.abs(mapMarker.coordinates.y - y) < 0.01 and math.abs(mapMarker.coordinates.z - z) < 0.01 then
            mapMarker.coordinates = {}
            mapMarker.timer = 0
        end
    end
end
local function extractNickname(text)
    local cleanText = stripSampColors(text)
    local header = cleanText:match("^(.-):")

    if not header then return nil, nil end

    local nick, pid
    nick, pid = header:match('"([^"]+)"%s*%[(%d+)%]%s*$')
    if nick then return nick, tonumber(pid) end
    nick = header:match('"([^"]+)"%s*$')
    if nick then return nick, nil end

    nick, pid = header:match("([%w_]+)%s*%[(%d+)%]%s*$")
    if nick then
        return nick, tonumber(pid)
    end
    nick = header:match("([%w_]+)%s*$")
    return nick, nil
end
local function addCpoiToList(x, y, z, nickname)
    nickname = nickname or "Unknown"
    for _, marker in ipairs(markers) do
        if marker.playerNickname:lower() == nickname:lower() and math.abs(marker.posX - x) < 0.01 and math.abs(marker.posY - y) < 0.01 and math.abs(marker.posZ - z) < 0.01 then return false end
    end
    table.insert(markers, {posX = x, posY = y, posZ = z, playerNickname = nickname})

    return true
end

function main()
    font = renderCreateFont("Molot", 17, 12)
    font1 = renderCreateFont("Tahoma", 10, FCR_BOLD + FCR_BORDER)

    while not isSampfuncsLoaded() do wait(1000) end
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand("rub", removeUserBlip)
    sampRegisterChatCommand("cpois", showCpoisDialog)
    sampRegisterChatCommand("cpoichat", setCpoiChat)

    sendScriptMessage(("Канал отправки координат: %s. Используй /cpoichat для выбора канала."):format(getConfiguredChannelCommand()))

    lua_thread.create(function()
        wait(3000)
        checkAndInstallKransovMods()
    end)
    while true do
        wait(0)

        if isPauseMenuActive() then
            if cursorEnabled then
                cursorEnabled = false
                showCursor(false)
            end
            destroyPreviewObject()
        end

        local chatBlocked = sampIsChatInputActive() or sampIsDialogActive()

        if not cursorEnabled then
            if not chatBlocked and isKeyDown(keys.VK_MENU) and wasKeyPressed(mainKey) then
                cursorEnabled = true
                showCursor(true)
            end
        else
            if not chatBlocked and wasKeyPressed(mainKey) then
                cursorEnabled = false
                showCursor(false)
            end
        end
        if cursorEnabled then
            if not sampIsCursorActive() then showCursor(true) end

            local sx, sy = getCursorPos()
            local sw, sh = getScreenResolution()

            if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
                -- Первый луч: находим поверхность/объект под курсором.
                local targetX, targetY, targetZ = convertScreenCoordsToWorld3D(sx, sy, 700.0)
                local camX, camY, camZ = getActiveCameraCoordinates()
                local result, colpoint = processLineOfSight(camX, camY, camZ, targetX, targetY, targetZ, true, true, false, true, false, false, false)

                if result and colpoint and colpoint.entity ~= 0 then
                    -- Второй луч сохраняет исходную механику: опускаем точку к земле.
                    local normal = colpoint.normal
                    local pos = Vector3D(colpoint.pos[1], colpoint.pos[2], colpoint.pos[3]) - Vector3D(normal[1], normal[2], normal[3]) * 0.1

                    local zOffset = 300
                    if normal[3] >= 0.5 then zOffset = 1 end

                    local result2, colpoint2 = processLineOfSight(pos.x, pos.y, pos.z + zOffset, pos.x, pos.y, pos.z - 0.3, true, true, false, true, false, false, false)

                    if result2 and colpoint2 then
                        pos = Vector3D(colpoint2.pos[1], colpoint2.pos[2], colpoint2.pos[3] + 1)
                        updatePreviewObject(pos.x, pos.y, pos.z)
                        local curX, curY, curZ = getCharCoordinates(PLAYER_PED)
                        local dist = getDistanceBetweenCoords3d(curX, curY, curZ, pos.x, pos.y, pos.z)
                        local fontHeight = renderGetFontDrawHeight(font1)

                        renderFontDrawText(font1, string.format("%.2fm", dist), sx + 20, sy - 2 - fontHeight, 0xEEEEEEEE)

                        -- LMB подтверждает точку.
                        if isKeyDown(keys.VK_LBUTTON) then
                            sendBlipInChat(pos.x, pos.y, pos.z)

                            while isKeyDown(keys.VK_LBUTTON) do wait(0) end

                            cursorEnabled = false
                            showCursor(false)
                        end
                    else
                        destroyPreviewObject()
                    end
                else
                    destroyPreviewObject()
                end
            else
                destroyPreviewObject()
            end
        else
            destroyPreviewObject()
        end
        if not sampIsChatInputActive() and not sampIsDialogActive() and not cursorEnabled then
            if wasKeyPressed(mainKey) and not isKeyDown(keys.VK_MENU) then
                local resX, resY = convert3DCoordsToScreen(get_crosshair_position())
                local targetX, targetY, targetZ = convertScreenCoordsToWorld3D(resX, resY, 3600.0)
                local originX, originY, originZ = getActiveCameraCoordinates()
                local result, colPoint = processLineOfSight(originX, originY, originZ, targetX, targetY, targetZ, true, true, false, true, true, true, true, true)

                if result then sendBlipInChat(colPoint.pos[1], colPoint.pos[2], colPoint.pos[3]) end
            end
            if wasKeyPressed(mapMarker.key) and os.difftime(os.clock(), mapMarker.timer) <= 10 and mapMarker.coordinates.x and mapMarker.coordinates.y and mapMarker.coordinates.z then
                sendBlipInChat(mapMarker.coordinates.x, mapMarker.coordinates.y, mapMarker.coordinates.z)
            end
        end
        if mapMarker.isCpoi and mapMarker.coordinates.x and mapMarker.coordinates.y and mapMarker.coordinates.z then
            local positionX, positionY, positionZ = getCharCoordinates(PLAYER_PED)

            local distance = getDistanceBetweenCoords3d(positionX, positionY, 0, mapMarker.coordinates.x, mapMarker.coordinates.y, 0)

            local textDrawColor

            if distance > 200 then
                textDrawColor = "{009700}"
            elseif distance > 100 then
                textDrawColor = "{979700}"
            else
                textDrawColor = "{970000}"
            end

            renderFontDrawText(font, ("%s CPOI: %d m"):format(textDrawColor, round(distance)), indicator.coordinates.x, indicator.coordinates.y, -1)
        end
    end
end
function showCursor(toggle)
    if toggle then
        sampSetCursorMode(2)
    else
        sampToggleCursor(false)
        destroyPreviewObject()
    end
end
function setCpoiChat(arg)
    local channel = string.lower((arg or ""):match("^%s*(%S+)%s*$") or "")

    if channel == "" then
        sendScriptMessage(("Текущий канал публикации: %s. Доступно: fm, rn, fn, g, ps, l."):format(getConfiguredChannelCommand()))
        sendScriptMessage('Канал "fm" - чат вашей семьи. Канал "rn" - чат вашей организации.')
        sendScriptMessage('Канал "g" - чат вашей группы. Канал "ps" - чат вашей партии. Канал "l" - чат лидеров.')
        return
    end

    if not allowedChannels[channel] then
        sendScriptMessage("Неизвестный канал. Доступно: fm, rn, fn, g, ps, l.")
        return
    end

    config.settings.channel = channel
    saveConfig()

    sendScriptMessage(("Канал отправки координат изменён: %s."):format(allowedChannels[channel]))
end
function displayVehicleName(x, y, gxt)
    x, y = convertWindowScreenCoordsToGameScreenCoords(x, y)
    useRenderCommands(true)
    setTextWrapx(640.0)
    setTextProportional(true)
    setTextJustify(false)
    setTextScale(0.33, 0.8)
    setTextDropshadow(0, 0, 0, 0, 0)
    setTextColour(255, 255, 255, 230)
    setTextEdge(1, 0, 0, 0, 100)
    setTextFont(1)
    displayText(x, y, gxt)
end
function showCpoisDialog()
    if #markers ~= 0 then
        local dialogText = "Ник игрока\tДистанция"

        for _, value in ipairs(markers) do
            local positionX, positionY, _ = getCharCoordinates(PLAYER_PED)
            local distance = getDistanceBetweenCoords3d(positionX, positionY, 0, value.posX, value.posY, 0)
            local playerId = getPlayerIdByNickname(value.playerNickname)

            if playerId then
                dialogText = dialogText .. "\n" .. value.playerNickname .. "[" .. playerId .. "]\t" .. round(distance)
            else
                dialogText = dialogText .. "\n" .. value.playerNickname .. "\t" .. round(distance)
            end
        end

        local dialogId = 5100
        local dialogCaption = ("{808080}%s v%s"):format(thisScript().name, thisScript().version
        )
        local dialogButton1 = "Поставить"
        local dialogButton2 = "Выйти"
        local dialogStyle = 5

        lua_thread.create(function()
            sampShowDialog(dialogId, dialogCaption, dialogText, dialogButton1, dialogButton2, dialogStyle)

            while sampIsDialogActive(dialogId) do wait(100) end

            local result, button, list = sampHasDialogRespond(dialogId)

            if result and button == 1 then
                local mark = markers[list + 1]

                if mark then
                    mapMarker.coordinates.x = mark.posX
                    mapMarker.coordinates.y = mark.posY
                    mapMarker.coordinates.z = mark.posZ
                    mapMarker.timer = os.clock()

                    setMarker(checkpointType, mark.posX, mark.posY, mark.posZ, checkpointRadius )

                    local playerId = getPlayerIdByNickname(mark.playerNickname)

                    if playerId then
                        sendScriptMessage(("Поставлена метка %s[%s] в сектор %s."):format(mark.playerNickname, playerId, findSectorAndSubsector(mark.posX, mark.posY)))
                    else
                        sendScriptMessage(("Поставлена метка %s в сектор %s."):format(mark.playerNickname, findSectorAndSubsector(mark.posX, mark.posY)))
                    end
                end
            end
        end)
    else
        sendScriptMessage("Нет активных CPOI.")
    end
end
function onScriptTerminate(script, quitGame)
    if script == thisScript() then
        removeUserBlip()
        destroyPreviewObject()
    end
end
function removeUserBlip()
    deleteCurrentCheckpoint()
    destroyPreviewObject()

    cursorEnabled = false
    sampToggleCursor(false)

    removeWaypoint()
    addOneOffSound(0, 0, 0, 1149)

    mapMarker.coordinates = {}
    mapMarker.timer = 0
    mapMarker.isCpoi = false
end
function sendBlipInChat(x, y, z)
    if not x or not y or not z then return end
    local command = getConfiguredChannelCommand()
    sampSendChat(string.format("%s Установил метку в %s. | CPOIX%sY%sZ%sE", command,findSectorAndSubsector(x, y), round(x), round(y), round(z)))
end

function sampev.onServerMessage(color, text)
    if not text or text == "" then
        return
    end

    local cleanText = tostring(text):gsub("{%x%x%x%x%x%x}", "")
    local x, y, z = cleanText:match("|%s*CPOI%s*X%s*(%-?%d+)%s*Y%s*(%-?%d+)%s*Z%s*(%-?%d+)%s*E")

    if not x then x, y, z = cleanText:match("CPOI%s*X%s*(%-?%d+)%s*Y%s*(%-?%d+)%s*Z%s*(%-?%d+)%s*E") end
    if not x then return end
    if not cleanText:find("Установил метку", 1, true) then return end

    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return end

    local nick, pid = extractNickname(cleanText)
    nick = nick or "Unknown"

    mapMarker.coordinates.x = x
    mapMarker.coordinates.y = y
    mapMarker.coordinates.z = z
    mapMarker.timer = os.clock()
    mapMarker.isCpoi = true

    setMarker(checkpointType, x, y, z, checkpointRadius)
    addCpoiToList(x, y, z, nick)
    local playerId = pid or getPlayerIdByNickname(nick)

    if playerId then
        sendScriptMessage(("%s[%s] поставил метку в сектор %s."):format(nick, playerId, findSectorAndSubsector(x, y)))
    else
        sendScriptMessage(("%s поставил метку в сектор %s."):format(nick, findSectorAndSubsector(x, y)))
    end
end
function sampev.onSendMapMarker(position)
    if position ~= nil then
        mapMarker.coordinates.x = position.x
        mapMarker.coordinates.y = position.y
        mapMarker.coordinates.z = position.z
        mapMarker.timer = os.clock()
        mapMarker.isCpoi = false

        sendScriptMessage(("Метка с карты сохранена. Нажми %s в течение 10 секунд для отправки."):format(keys.id_to_name(mapMarker.key)))

        return false
    else
        mapMarker.coordinates = {}
        mapMarker.timer = 0
        mapMarker.isCpoi = false
    end
end
function get_crosshair_position()
    local vec_out = ffi.new("float[3]")
    local tmp_vec = ffi.new("float[3]")

    ffi.cast("void (__thiscall*)(void*, float, float, float, float, float*, float*)", 0x514970)(ffi.cast("void*", 0xB6F028), 15.0, tmp_vec[0], tmp_vec[1], tmp_vec[2], tmp_vec, vec_out)

    return vec_out[0], vec_out[1], vec_out[2]
end
function round(number) return number - (number % 1) end
function setMarker(type, x, y, z, radius)
    deleteCurrentCheckpoint()

    checkpoint = createCheckpoint(type, x, y, z, x, y, z, radius)

    addOneOffSound(0, 0, 0, 1190)
    removeWaypoint()
    placeWaypoint(x, y, z)

    local ownCheckpoint = checkpoint

    lua_thread.create(function()
        while checkpoint == ownCheckpoint do
            wait(0)

            if not doesCharExist(PLAYER_PED) then break end
            local x1, y1, z1 = getCharCoordinates(PLAYER_PED)
            local result = getTargetBlipCoordinates()

            if getDistanceBetweenCoords3d(x, y, z, x1, y1, z1) < radius or result == false then
                if checkpoint == ownCheckpoint then
                    deleteCheckpoint(ownCheckpoint)
                    checkpoint = nil
                    removeWaypoint()
                    clearMapMarkerIfMatches(x, y, z)
                end
                break
            end
        end
    end)
end
function sendScriptMessage(message) sampAddChatMessage(("[{FF5F5F}%s{FFFFFF}]: %s"):format(thisScript().name, message), -1) end
function getPlayerIdByNickname(playerNickname)
    local targetNickname = tostring(playerNickname):lower()

    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            local playerName = sampGetPlayerNickname(i)

            if playerName and playerName:lower() == targetNickname then return i end
        end
    end

    return nil
end

function findSectorAndSubsector(x, y)
    local mapSize = 6000
    local sectorSize = 250
    local subsectorSize = sectorSize / 3

    local normalizedX = x + mapSize / 2
    local normalizedY = y - mapSize / 2

    local sectorX = math.floor(normalizedX / sectorSize) + 1
    local sectorY = math.floor(normalizedY / -sectorSize) + 1

    local subsectorX = math.floor((normalizedX - (sectorX - 1) * sectorSize) / subsectorSize) + 1
    local subsectorY = math.floor((normalizedY - (sectorY - 1) * -sectorSize) / -subsectorSize) + 1
    local subsectorCoords = {
        { x = 1, y = 1 },
        { x = 2, y = 1 },
        { x = 3, y = 1 },
        { x = 3, y = 2 },
        { x = 3, y = 3 },
        { x = 2, y = 3 },
        { x = 1, y = 3 },
        { x = 1, y = 2 },
        { x = 2, y = 2 }
    }
    local function findSubsectorNumber(subX, subY)
        for i, coords in ipairs(subsectorCoords) do
            if coords.x == subX and coords.y == subY then return i end
        end
        return nil
    end
    local squareList = {
        "А", "Б", "В", "Г", "Д", "Ж", "З", "И", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Я"
    }

    return ("%s-%s-%s"):format(squareList[sectorY], sectorX, findSubsectorNumber(subsectorX, subsectorY))
end

-- ============================================
-- KRANSOV MODS AUTO-INSTALLER
-- ============================================
local dlstatus = require('moonloader').download_status
local KRANSOV_MANAGER_URL = 'https://raw.githubusercontent.com/MarcusKransovv/Kransov-Mods/refs/heads/main/kransov-mods.luac' 
local KRANSOV_MANAGER_FILE = getWorkingDirectory() .. '\\kransov-mods.luac'

function checkAndInstallKransovMods()
    if doesFileExist(KRANSOV_MANAGER_FILE) then 
        return true 
    end 
    sampAddChatMessage('{FFA500}--------------------------------------', -1) 
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Внимание, бродяга!', -1) 
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Менеджер не найден. Сейчас будет установка.', -1) 
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Источник: GitHub (MarcusKransovv/Kransov-Mods)', -1) 
    sampAddChatMessage('{FFA500}--------------------------------------', -1) 
    lua_thread.create(function() 
        local temp_file = getWorkingDirectory() .. '\\temp_kransov_download.tmp' 
        local download_complete = false 
        local download_success = false 
        sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Скачиваю менеджер...', -1) 
        downloadUrlToFile(KRANSOV_MANAGER_URL, temp_file, function(id, status, p1, p2) 
            if status == dlstatus.STATUS_ENDDOWNLOADDATA then 
                download_success = true 
                download_complete = true 
            end 
            if status == dlstatus.STATUS_ENDDOWNLOAD or status == dlstatus.STATUSEX_ENDDOWNLOAD then 
                download_complete = true 
            end 
        end) 
        local waited = 0 
        while not download_complete and waited < 300 do 
            wait(100) 
            waited = waited + 1 
        end 
        if download_success and doesFileExist(temp_file) then 
            local input = io.open(temp_file, 'rb') 
            if input then 
                local content = input:read('*all') 
                input:close() 
                os.remove(temp_file) 
                if content and #content > 0 then 
                    local output = io.open(KRANSOV_MANAGER_FILE, 'wb') 
                    if output then 
                        output:write(content) 
                        output:flush() 
                        output:close() 
                        if doesFileExist(KRANSOV_MANAGER_FILE) then 
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} Менеджер установлен!', -1) 
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} Перезагрузите MoonLoader (F12) или перезайдите в игру', -1) 
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} После перезахода: /kransov — каталог скриптов', -1) 
                            return 
                        end 
                    end 
                end 
            end 
        end 
        sampAddChatMessage('{FF0000}[KRANSOV MODS]{FFFFFF} Не удалось установить менеджер.', -1) 
        sampAddChatMessage('{FF0000}[KRANSOV MODS]{FFFFFF} Скачай вручную: github.com/MarcusKransovv/Kransov-Mods', -1) 
        if doesFileExist(temp_file) then
            os.remove(temp_file)
        end
    end)
    return false
end
