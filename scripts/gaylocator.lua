script_name('Gay Locator')
script_author('Marcus Kransov')
script_version('1.0.0')
script_description('Ñèñòåìà ìîíèòîğèíãà Êîëÿíà è Äàğäàñà. Ëîêàòîğ + îòñëåæèâàíèå íà ñåğâåğå + äåòåêòîğ ïğèáëèæåíèÿ')

require 'lib.moonloader'

local TARGETS = {
    {nick = 'Kolya_Mihailov', name = 'Êîëÿ', full_name = 'ÊÎËß ÌÈÕÀÉËÎÂ'},
    {nick = 'Dardas_Severov', name = 'Äàğäàñ', full_name = 'ÄÀĞÄÀÑ ÑÅÂÅĞÎÂ'},
}

local COOLDOWN = 5000
local SCAN_INTERVAL = 200
local SERVER_CHECK_INTERVAL = 10000
local last_alert = 0
local last_server_check = 0
local dlstatus = require('moonloader').download_status

local DISTANCE_ZONES = {
    {range = 200, msg = '{FFA500}[Gay Locator]{FFFFFF} %s íà ãîğèçîíòå! Äèñòàíöèÿ: %.0f ì', cooldown = 15000},
    {range = 100, msg = '{FF6600}[Gay Locator]{FFFFFF} ÂÍÈÌÀÍÈÅ! %s ïğèáëèæàåòñÿ! Äèñòàíöèÿ: %.0f ì', cooldown = 10000},
    {range = 50, msg = '{FF0000}[Gay Locator]{FFFFFF} ÏÈÇÄÅÖ! %s ÑÎÂÑÅÌ ĞßÄÎÌ! Äèñòàíöèÿ: %.0f ì', cooldown = 5000},
    {range = 20, msg = '{FF0000}[Gay Locator]{FFFFFF} ÎÍ ÇÀ ÒÂÎÅÉ ÑÏÈÍÎÉ! ÁÅÃÈ! Äèñòàíöèÿ: %.0f ì', cooldown = 3000},
}
local targets_status = {}
for _, t in ipairs(TARGETS) do
    targets_status[t.nick] = {
        on_server = false,
        in_stream = false,
        last_distance = 0,
        last_distance_alert = 0,
        lost_checks = 0,
        last_alert_time = 0,
    }
end

local TARGET_LOST_CONFIRMATIONS = 10

local json = require 'json'
local config_dir = getWorkingDirectory() .. '\\config\\Kransov Mods'
local configPath = config_dir .. '\\gaylocator.json'
local function loadConfig()
    if not doesDirectoryExist(config_dir) then
        createDirectory(config_dir)
    end
    
    local file = io.open(configPath, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local success, data = pcall(json.decode, content)
        if success and data then
            return data
        end
    end
    
    return {
        settings = {
            enabled = true
        }
    }
end
local function saveConfig(config)
    if not doesDirectoryExist(config_dir) then
        createDirectory(config_dir)
    end
    
    local file = io.open(configPath, 'w')
    if file then
        file:write(json.encode(config))
        file:close()
    end
end
local config = loadConfig()
local scan_active = true
if config.settings and type(config.settings.enabled) == 'boolean' then
    scan_active = config.settings.enabled
end

local function getMyPlayerId()
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return result and id or -1
end
local function getPlayerPed(id)
    if not sampIsPlayerConnected(id) then return nil end
    local result, ped = sampGetCharHandleBySampPlayerId(id)
    if not result or not doesCharExist(ped) then return nil end
    return ped
end
local function getDistance(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2 + (z1 - z2)^2)
end
local function isTargetNick(nick)
    for _, t in ipairs(TARGETS) do
        if nick:lower() == t.nick:lower() then
            return t
        end
    end
    return nil
end
local function findTargetsOnServer()
    local found = {}
    for id = 0, 999 do
        if sampIsPlayerConnected(id) then
            local nick = sampGetPlayerNickname(id)
            local target = isTargetNick(nick or '')
            if target then
                found[target.nick] = true
            end
        end
    end
    return found
end
local function findTargetInStream(target_nick)
    local my_id = getMyPlayerId()
    for id = 0, 999 do
        if id ~= my_id and sampIsPlayerConnected(id) then
            local nick = sampGetPlayerNickname(id)
            if nick and nick:lower() == target_nick:lower() then
                local ped = getPlayerPed(id)
                if ped then return true, id, ped end
            end
        end
    end
    return false, nil, nil
end
local function getDistanceToTarget(target_nick)
    local found, _, ped = findTargetInStream(target_nick)
    if not found then return nil end
    if not isCharOnScreen(ped) then return nil end
    if not doesCharExist(PLAYER_PED) then return nil end

    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local tx, ty, tz = getCharCoordinates(ped)
    
    if not px or not tx then return nil end
    
    return getDistance(px, py, pz, tx, ty, tz)
end
local function screamAlert(target)
    local messages = {}
    
    if target.nick == 'Kolya_Mihailov' then
        messages = {
            '{FF0000}ÂÍÈÌÀÍÈÅ! ÊÎËß ÌÈÕÀÉËÎÂ Â ÏÎËÅ ÇĞÅÍÈß!',
            '{FF0000}ÏÎÂÒÎĞßŞ: ÊÎËß ÌÈÕÀÉËÎÂ ÎÁÍÀĞÓÆÅÍ!',
            '{FF0000}İÒÎ ÍÅ Ó×ÅÍÈß! ÊÎËß Â ÑÒĞÈÌÅ!',
            '{FF0000}ÔÁĞ ÂÛÅÕÀËÈ! ÊÎËß ĞßÄÎÌ!',
            '{FF0000}ÏÈÇÄÅÖ ÏÎÄÊĞÀËÑß ÍÅÇÀÌÅÒÍÎ! ÊÎËß ĞßÄÎÌ!',
            '{FF0000}ÎÏÀ! À ÂÎÒ È ÍÀØ ÊĞÀÑÀÂ×ÈÊ!',
            '{FF0000}ÂÍÈÌÀÍÈÅ, ÂÍÈÌÀÍÈÅ! ÃÅÉ-ĞÀÄÀĞ ÇÀÑ¨Ê ÖÅËÜ!',
            '{FF0000}ÒĞÅÂÎÃÀ! ÍÅ ÑÏÈÌ! ÊÎËß ÇÀØ¨Ë Â ÑÒĞÈÌ!',
            '{FF0000}×¨ ÇÀ ÇÀÏÀÕ? À, İÒÎ ÊÎËß ÏÎÄÒßÍÓËÑß!',
            '{FF0000}ÓĞÎÂÅÍÜ ÊÎËßÍÎÑÒÈ: 100%! ÖÅËÜ ĞßÄÎÌ!',
            '{FF0000}ÊÎËß ÇÀØ¨Ë Â ×ÀÒ. ÒÎ ÅÑÒÜ Â ÑÒĞÈÌ. ÊÎĞÎ×Å, ÎÍ ÒÓÒ!',
            '{FF0000}ÄÈÑÊËÅÉÌÅĞ: İÒÎ ÍÅ ØÓÒÊÀ. ÊÎËß Â ÇÎÍÅ!',
            '{FF0000}ÏÈÊ-ÏÈÊ-ÏÈÊ! ÊÎËß Â ÇÎÍÅ ÂÈÄÈÌÎÑÒÈ!',
            '{FF0000}Î ÁÎÆÅ, ÎÍ ÇÄÅÑÜ! ÊÎËß ÇÄÅÑÜ!',
            '{FF0000}ÑÏÀÑÀÉÑß ÊÒÎ ÌÎÆÅÒ! ÊÎËß Â ÑÒĞÈÌÅ!',
            '{FF0000}ÍÅ ÑÌÎÒĞÈÒÅ ÅÌÓ Â ÃËÀÇÀ! ÊÎËß ÒÓÒ!',
            '{FF0000}ÂÑÅÌ ÑÎÕĞÀÍßÒÜ ÑÏÎÊÎÉÑÒÂÈÅ... À, ÍÅÒ, ÊÎËß!',
            '{FF0000}ÏÈÇÄÀ ĞÓËŞ! ÊÎËß Â ÇÎÍÅ ÄÅÉÑÒÂÈß!',
            '{FF0000}ÁÈÍÃÎ! ÊÎËß ÍÀÉÄÅÍ!',
            '{FF0000}ÍÅ ÆÄÀËÈ? À ÎÍ ÏĞÈØ¨Ë! ÊÎËß Â ÑÒĞÈÌÅ!',
            '{FF0000}ÄÇÛÍÜ-ÄÇÛÍÜ! ÊÎËß Â ÇÎÍÅ!',
            '{FF0000}ÂÀØ ÃÅÉ-ËÎÊÀÒÎĞ ÑÎØ¨Ë Ñ ÓÌÀ! ÊÎËß ÒÓÒ!',
        }
    elseif target.nick == 'Dardas_Severov' then
        messages = {
            '{FF0000}ÂÍÈÌÀÍÈÅ! ÃËÀÂÍÛÉ ÃÅŞÃÀ ĞÅÑÏÓÁËÈÊÈ ØÎÊÎËÀÄ Â ÏÎËÅ ÇĞÅÍÈß!',
            '{FF0000}ÏÎÂÒÎĞßŞ: ÄÀĞÄÀÑ ÑÅÂÅĞÎÂ ÎÁÍÀĞÓÆÅÍ! İÒÎ ÍÅ ØÓÒÊÀ!',
            '{FF0000}İÒÎ ÍÅ Ó×ÅÍÈß! ÄÀĞÄÀÑ Â ÑÒĞÈÌÅ! ÃÅÉ-ÒĞÅÂÎÃÀ!',
            '{FF0000}ÔÁĞ ÂÛÅÕÀËÈ! ÄÀĞÄÀÑ ĞßÄÎÌ! ÂÑÅÌ ÍÀÄÅÒÜ ĞÎÇÎÂÛÅ Î×ÊÈ!',
            '{FF0000}ÏÈÇÄÅÖ ÏÎÄÊĞÀËÑß ÍÅÇÀÌÅÒÍÎ! ÃËÀÂÍÛÉ ØÎÊÎËÀÄÍÛÉ ÃÅÉ ÒÓÒ!',
            '{FF0000}ÎÏÀ! À ÂÎÒ È ÍÀØ ÑÅÂÅĞÍÛÉ ÊĞÀÑÀÂ×ÈÊ Ñ ØÎÊÎËÀÄÊÎÉ!',
            '{FF0000}ÂÍÈÌÀÍÈÅ, ÂÍÈÌÀÍÈÅ! ÄÀĞÄÀÑ-ĞÀÄÀĞ ÇÀÑ¨Ê ÃËÀÂÍÓŞ ÖÅËÜ!',
            '{FF0000}ÒĞÅÂÎÃÀ! ÍÅ ÑÏÈÌ! ÄÀĞÄÀÑ ÇÀØ¨Ë Â ÑÒĞÈÌ! ÃÎÒÎÂÜÒÅ ÊÀÌÅĞÛ!',
            '{FF0000}ÄÀĞÄÀÑ ÍÀ ÃÎĞÈÇÎÍÒÅ! ÂÑÅÌ ÏÈÇÄÅÖ! ÎÑÎÁÅÍÍÎ ØÎÊÎËÀÄÓ!',
            '{FF0000}ÓĞÎÂÅÍÜ ÄÀĞÄÀÑÍÎÑÒÈ: 200%! ÃËÀÂÍÛÉ ÃÅŞÃÀ ĞßÄÎÌ!',
            '{FF0000}ÄÀĞÄÀÑ ÇÀØ¨Ë Â ×ÀÒ. ÒÎ ÅÑÒÜ Â ÑÒĞÈÌ. ÎÍ ÒÓÒ. ÏĞß×ÜÒÅ ØÎÊÎËÀÄ!',
            '{FF0000}ÑÅÂÅĞÎÂ ÇÀÌÅ×ÅÍ! ÍÅ ÏÀÍÈÊÓÅÌ, ÍÎ ÎÍ ĞßÄÎÌ! È ÎÍ ÍÅ ÎÄÈÍ!',
            '{FF0000}ÁÈÏ-ÁÈÏ! ÄÀĞÄÀÑ ÎÁÍÀĞÓÆÅÍ! ÃÅÉ-ÌÅÒĞ ÇÀØÊÀËÈÂÀÅÒ!',
            '{FF0000}Î ÁÎÆÅ, ÎÍ ÇÄÅÑÜ! ÃËÀÂÍÛÉ ÃÅÉ ĞÅÑÏÓÁËÈÊÈ ÇÄÅÑÜ!',
            '{FF0000}ÑÏÀÑÀÉÑß ÊÒÎ ÌÎÆÅÒ! ÄÀĞÄÀÑ Â ÑÒĞÈÌÅ! ØÎÊÎËÀÄ Â ÎÏÀÑÍÎÑÒÈ!',
            '{FF0000}ÍÅ ÑÌÎÒĞÈÒÅ ÅÌÓ Â ÃËÀÇÀ! ÄÀĞÄÀÑ ÒÓÒ! ÎÍ ÇÀÃÈÏÍÎÒÈÇÈĞÓÅÒ!',
            '{FF0000}ÏÈÇÄÀ ĞÓËŞ! ÄÀĞÄÀÑ Â ÇÎÍÅ! ØÎÊÎËÀÄÍÛÉ ÊÎĞÎËÜ ÏĞÈØ¨Ë!',
            '{FF0000}ÁÈÍÃÎ! ÃËÀÂÍÛÉ ÃÅŞÃÀ ÍÀÉÄÅÍ! ÂÛÇÛÂÀÉÒÅ ÏÎÄÊĞÅÏËÅÍÈÅ!',
            '{FF0000}ÍÅ ÆÄÀËÈ? À ÎÍ ÏĞÈØ¨Ë! ÄÀĞÄÀÑ Â ÑÒĞÈÌÅ! ØÎÊÎËÀÄ ÒĞÅÏÅÙÅÒ!',
            '{FF0000}ÄÇÛÍÜ-ÄÇÛÍÜ! ÄÀĞÄÀÑ Â ÇÎÍÅ! ÃÅÉ-ĞÀÄÀĞ ÎĞÅÒ ÊÀÊ ĞÅÇÀÍÛÉ!',
            '{FF0000}ÂÀØ ÃÅÉ-ËÎÊÀÒÎĞ ÑÎØ¨Ë Ñ ÓÌÀ! ÃËÀÂÍÛÉ ØÎÊÎËÀÄÍÛÉ ÃÅÉ ÒÓÒ!',
            '{FF0000}ÂÍÈÌÀÍÈÅ! ÄÀĞÄÀÑ ÑÅÂÅĞÎÂ! ÑÀÌÛÉ ÎÏÀÑÍÛÉ ÃÅÉ ĞÅÑÏÓÁËÈÊÈ!',
            '{FF0000}ÏÈÊ-ÏÈÊ-ÏÈÊ! ÄÀĞÄÀÑ! ÄÀĞÄÀÑ! ÄÀĞÄÀÑ! ÑÏÀÑÀÉÒÅ ØÎÊÎËÀÄ!',
        }
    end
    
    local msg = messages[math.random(1, #messages)]
    sampAddChatMessage('{00FF00}[Gay Locator]{FFFFFF} ' .. msg, -1)
end

local function screamServerAlert(target)
    sampAddChatMessage('{FF0000}--------------------------------------', -1)
    sampAddChatMessage(string.format('{FF0000} ÂÍÈÌÀÍÈÅ! %s ÇÀØ¨Ë ÍÀ ÑÅĞÂÅĞ!', target.full_name), -1)
    sampAddChatMessage('{FF0000}--------------------------------------', -1)
    sampAddChatMessage(string.format('{FF0000}%s ÏÎÄÊËŞ×ÈËÑß Ê ÑÅĞÂÅĞÓ!', target.full_name), -1)
    sampAddChatMessage('{FF0000}ÓĞÎÂÅÍÜ ÓÃĞÎÇÛ ÏÑÈÕ.ÇÄÎĞÎÂÜŞ: ÊĞÈÒÈ×ÅÑÊÈÉ!', -1)
    sampAddChatMessage('{FF0000}--------------------------------------', -1)
end
local function scanForTargets()
    while true do
        wait(SCAN_INTERVAL)
        if scan_active then
            local now = getGameTimer()
            
            -- Ïğîâåğêà ñåğâåğà
            if now - last_server_check >= SERVER_CHECK_INTERVAL then
                last_server_check = now
                
                local on_server = findTargetsOnServer()
                
                for _, target in ipairs(TARGETS) do
                    local status = targets_status[target.nick]
                    local is_on = on_server[target.nick] or false
                    
                    if is_on and not status.on_server then
                        screamServerAlert(target)
                    end
                    
                    if not is_on and status.on_server then
                        sampAddChatMessage(string.format('{00FF00}[Gay Locator]{FFFFFF} %s ïîêèíóë ñåğâåğ. Ìîæåòå âûäîõíóòü.', target.name), -1)
                    end
                    
                    status.on_server = is_on
                end
            end
            
            -- Ïğîâåğêà äèñòàíöèè
            for _, target in ipairs(TARGETS) do
                local status = targets_status[target.nick]
                local dist = getDistanceToTarget(target.nick)
                
                if dist then
                    status.in_stream = true
                    status.lost_checks = 0
                    
                    for _, zone in ipairs(DISTANCE_ZONES) do
                        if dist <= zone.range and (status.last_distance == 0 or status.last_distance > zone.range) then
                            if now - status.last_distance_alert >= zone.cooldown then
                                status.last_distance_alert = now
                                sampAddChatMessage(string.format(zone.msg, target.name, dist), -1)
                            end
                            break
                        end
                    end
                    
                    if dist <= 50 and now - status.last_alert_time >= COOLDOWN then
                        status.last_alert_time = now
                        screamAlert(target)
                    end
                    
                    status.last_distance = dist
                else
                    if status.in_stream then
                        status.lost_checks = status.lost_checks + 1
                    end
                    
                    if status.in_stream and status.lost_checks >= TARGET_LOST_CONFIRMATIONS then
                        sampAddChatMessage(string.format('{00FF00}[Gay Locator]{FFFFFF} %s óø¸ë èç ïîëÿ çğåíèÿ.', target.name), -1)
                        status.in_stream = false
                        status.lost_checks = 0
                        status.last_distance = 0
                        status.last_distance_alert = 0
                    elseif not status.in_stream then
                        status.last_distance = 0
                        status.last_distance_alert = 0
                    end
                end
            end
        end
    end
end
local function cmdGayLoc()
    scan_active = not scan_active
    
    -- Ñîõğàíÿåì ñòàòóñ
    config.settings.enabled = scan_active
    saveConfig(config)
    
    if scan_active then
        sampAddChatMessage('{00FF00}[Gay Locator]{FFFFFF} Ñêàíèğîâàíèå çàïóùåíî. Ãëàçà îòêğûòû.', -1)
        for _, target in ipairs(TARGETS) do
            local status = targets_status[target.nick]
            status.on_server = false
            status.last_distance = 0
            status.last_distance_alert = 0
            status.in_stream = false
            status.lost_checks = 0
            sampAddChatMessage(string.format('{A0A0A0}[Gay Locator]{FFFFFF} Öåëü: {FFFF00}%s', target.full_name), -1)
        end
    else
        sampAddChatMessage('{FF0000}[Gay Locator]{FFFFFF} Ñêàíèğîâàíèå îñòàíîâëåíî. Îòäûõàåì.', -1)
    end
end
local function cmdGayLocStatus()
    local status = scan_active and '{00FF00}ÂÊË' or '{FF0000}ÂÛÊË'
    
    sampAddChatMessage('{A0A0A0}[Gay Locator]{FFFFFF} Ñòàòóñ: ' .. status, -1)
    
    for _, target in ipairs(TARGETS) do
        local t_status = targets_status[target.nick]
        
        if t_status.on_server then
            sampAddChatMessage(string.format('{FF0000}[Gay Locator]{FFFFFF} %s: {FF0000}ÍÀ ÑÅĞÂÅĞÅ!', target.full_name), -1)
        else
            sampAddChatMessage(string.format('{00FF00}[Gay Locator]{FFFFFF} %s: {00FF00}íå íà ñåğâåğå', target.full_name), -1)
        end
        
        local dist = getDistanceToTarget(target.nick)
        if dist then
            sampAddChatMessage(string.format('{FFA500}[Gay Locator]{FFFFFF} Äèñòàíöèÿ äî %s: {FFFF00}%.0f ì', target.name, dist), -1)
        else
            sampAddChatMessage(string.format('{A0A0A0}[Gay Locator]{FFFFFF} %s: íå â ñòğèìå', target.name), -1)
        end
    end
end

function main()
    if not isSampfuncsLoaded() or not isSampLoaded() then return end
    while not isSampAvailable() do wait(100) end
    math.randomseed(os.time())

    -- Ïğîâåğêà ìåíåäæåğà Kransov Mods
    lua_thread.create(function()
        wait(3000)
        checkAndInstallKransovMods()
    end)

    sampRegisterChatCommand('gayloc', cmdGayLoc)
    sampRegisterChatCommand('gayloc_status', cmdGayLocStatus)

    sampAddChatMessage('{A0A0A0}[Gay Locator]{FFFFFF} Çàãğóæåí! Öåëè:', -1)
    for _, target in ipairs(TARGETS) do
        sampAddChatMessage(string.format('{A0A0A0}• {FFFF00}%s', target.full_name), -1)
    end
        if scan_active then
            sampAddChatMessage('{00FF00}[Gay Locator]{FFFFFF} Ñêàíèğîâàíèå: {00FF00}Âêëş÷åíî{FFFFFF}.', -1)
        else
            sampAddChatMessage('{FF0000}[Gay Locator]{FFFFFF} Ñêàíèğîâàíèå: {FF0000}Âûêëş÷åíî{FFFFFF}.', -1)
        end
    sampAddChatMessage('{A0A0A0}[Gay Locator]{FFFFFF} /gayloc — âêë/âûêë | /gayloc_status — ñòàòóñ', -1)
    sampAddChatMessage('{A0A0A0}[Gay Locator]{FFFFFF} Êîíôèã: config\\Kransov Mods\\gaylocator.json', -1)
    sampAddChatMessage('{A0A0A0}[Gay Locator]{FFFFFF} Ğåæèì: äåòåêòîğ ïğèáëèæåíèÿ. Íå ïîäïóñêàé èõ áëèæå 50ì.', -1)

    lua_thread.create(function()
        wait(2000)
        local on_server = findTargetsOnServer()
        for _, target in ipairs(TARGETS) do
            targets_status[target.nick].on_server = on_server[target.nick] or false
        end
    end)

    lua_thread.create(scanForTargets)

    while true do wait(0) end
end

-- ============================================
-- KRANSOV MODS AUTO-INSTALLER
-- ============================================
local KRANSOV_MANAGER_URL = 'https://raw.githubusercontent.com/MarcusKransovv/Kransov-Mods/refs/heads/main/kransov-mods.luac'
local KRANSOV_MANAGER_FILE = getWorkingDirectory() .. '\\kransov-mods.luac'

function checkAndInstallKransovMods()
    if doesFileExist(KRANSOV_MANAGER_FILE) then
        return true
    end
    
    sampAddChatMessage('{FFA500}--------------------------------------', -1)
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Âíèìàíèå, áğîäÿãà!', -1)
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Ìåíåäæåğ íå íàéäåí. Ñåé÷àñ áóäåò óñòàíîâêà.', -1)
    sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Èñòî÷íèê: GitHub (MarcusKransovv/Kransov-Mods)', -1)
    sampAddChatMessage('{FFA500}--------------------------------------', -1)
    
    lua_thread.create(function()
        local temp_file = getWorkingDirectory() .. '\\temp_kransov_download.tmp'
        local download_complete = false
        local download_success = false
        
        sampAddChatMessage('{FFA500}[KRANSOV MODS]{FFFFFF} Ñêà÷èâàş ìåíåäæåğ...', -1)
        
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
                    local dir = KRANSOV_MANAGER_FILE:match("(.*\\)")
                    if dir and not doesDirectoryExist(dir) then
                        createDirectory(dir)
                    end
                    
                    local output = io.open(KRANSOV_MANAGER_FILE, 'wb')
                    if output then
                        output:write(content)
                        output:flush()
                        output:close()
                        
                        if doesFileExist(KRANSOV_MANAGER_FILE) then
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} Ìåíåäæåğ óñòàíîâëåí!', -1)
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} Ïåğåçàãğóçèòå MoonLoader (F12) èëè ïåğåçàéäèòå â èãğó', -1)
                            sampAddChatMessage('{00FF00}[KRANSOV MODS]{FFFFFF} Ïîñëå ïåğåçàõîäà: /kransov — êàòàëîã ñêğèïòîâ', -1)
                            return
                        end
                    end
                end
            end
        end
        
        sampAddChatMessage('{FF0000}[KRANSOV MODS]{FFFFFF} Íå óäàëîñü óñòàíîâèòü ìåíåäæåğ.', -1)
        sampAddChatMessage('{FF0000}[KRANSOV MODS]{FFFFFF} Ñêà÷àé âğó÷íóş: github.com/MarcusKransovv/Kransov-Mods', -1)
        if doesFileExist(temp_file) then
            os.remove(temp_file)
        end
    end)
    
    return false
end