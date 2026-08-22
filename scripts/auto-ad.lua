script_name("auto-ad")
script_author("Marcus_Kransov") -- (by Rubin for Samp-Rp), Marcus_Kransov (Revised for Advance-RP)
script_version("28.07.2026")
sampev = require("samp.events")
antiflood = 0

-- Инициализация конфига через JSON
local json = require("json")
local configPath = getWorkingDirectory() .. "\\config\\auto-ad.json"

-- Функция для создания директории
local function ensureDirectory(path)
    local dir = path:match("(.*\\)")
    if dir and not doesDirectoryExist(dir) then
        createDirectory(dir)
    end
end

-- Функция для безопасного сохранения конфига
local function safeJsonSave(data, path)
    ensureDirectory(path)
    local file, err = io.open(path, "w")
    if file then
        local encoded = json.encode(data)
        file:write(encoded)
        file:close()
        return true
    else
        local altPath = getWorkingDirectory() .. "\\auto-ad.json"
        local file2, err2 = io.open(altPath, "w")
        if file2 then
            file2:write(json.encode(data))
            file2:close()
            return true
        end
        return false, err or err2
    end
end

-- Функция для безопасной загрузки конфига
local function safeJsonLoad(path)
    local file, err = io.open(path, "r")
    if not file then
        local altPath = getWorkingDirectory() .. "\\auto-ad.json"
        file, err = io.open(altPath, "r")
    end
    
    if file then
        local content = file:read("*all")
        file:close()
        local success, data = pcall(json.decode, content)
        if success and data then
            return data
        end
    end
    
    return nil
end

-- Вспомогательная функция для получения даты понедельника
function getMondayDate()
    local current_date = os.date("*t")
    local wday = current_date.wday -- 1=воскресенье, 2=понедельник, ...
    local days_to_monday
    if wday == 1 then
        days_to_monday = 6
    else
        days_to_monday = wday - 2
    end
    local monday_time = os.time(current_date) - (days_to_monday * 86400)
    return os.date("%d.%m.%Y", monday_time)
end

-- Функция получения даты воскресенья
function getSundayDate()
    local current_date = os.date("*t")
    local wday = current_date.wday
    local days_to_sunday
    if wday == 1 then
        days_to_sunday = 0
    else
        days_to_sunday = 8 - wday
    end
    local sunday_time = os.time(current_date) + (days_to_sunday * 86400)
    return os.date("%d.%m.%Y", sunday_time)
end

-- Загружаем или создаём конфиг
local config = safeJsonLoad(configPath)
if not config then
    config = {
        main = {
            text = "1",
            one = false,
            autoup = false,
            cycle_mode = false,
        },
        dynamic_ads = {},
        stats = nil
    }
end

ad = {
    status = false,
    text = config.main.text or "1",
    one = config.main.one or false,
    autoup = config.main.autoup or false,
    status_2_wait = false,
    dynamic_ads = {},
    current_index = 0,
    cycle_mode = config.main.cycle_mode or false,
    is_main_text = true,
    up_sent = false,
    ad_state = "idle",
    stats = {
        session_start_time = os.time(),
        today_date = os.date("%d.%m.%Y"),
        week_start = getMondayDate(),
        session = {ads_sent = 0, ups_used = 0, errors = 0},
        today = {ads_sent = 0, ups_used = 0},
        week = {ads_sent = 0, ups_used = 0},
        total = {ads_sent = 0, ups_used = 0}
    },
    retry_scheduled = false,
    last_sent_text = ""
}

-- Загружаем сохранённую статистику
if config.stats then
    if config.stats.total then
        ad.stats.total = config.stats.total
    end
    if config.stats.today_date == os.date("%d.%m.%Y") then
        ad.stats.today = config.stats.today or {ads_sent = 0, ups_used = 0}
    end
    local current_monday = getMondayDate()
    if config.stats.week_start == current_monday then
        ad.stats.week = config.stats.week or {ads_sent = 0, ups_used = 0}
    else
        if config.stats.week and (config.stats.week.ads_sent > 0 or config.stats.week.ups_used > 0) then
            -- Уведомление о сбросе недельной статистики будет при запуске
            ad._pending_week_reset = config.stats.week
        end
    end
end
ad.stats.week_start = getMondayDate()
ad.stats.today_date = os.date("%d.%m.%Y")

-- Загружаем динамические объявления
if config.dynamic_ads then
    for k, v in pairs(config.dynamic_ads) do
        if type(v) == "string" then
            table.insert(ad.dynamic_ads, v)
        end
    end
end

-- Функция сохранения настроек
function ad.saveConfig()
    local saveData = {
        main = {
            text = ad.text,
            one = ad.one,
            autoup = ad.autoup,
            cycle_mode = ad.cycle_mode,
        },
        dynamic_ads = {},
        stats = {
            today_date = ad.stats.today_date,
            week_start = ad.stats.week_start,
            today = ad.stats.today,
            week = ad.stats.week,
            total = ad.stats.total
        }
    }
    
    for i, text in ipairs(ad.dynamic_ads) do
        saveData.dynamic_ads[tostring(i)] = text
    end
    
    local success, err = safeJsonSave(saveData, configPath)
    if not success then
        ad.chatMessage("{FF0000}Ошибка сохранения: " .. tostring(err))
    end
end

-- Функция обновления статистики
function ad.updateStats(action)
    -- Сессионная статистика
    if action == "ad" then
        ad.stats.session.ads_sent = ad.stats.session.ads_sent + 1
    elseif action == "up" then
        ad.stats.session.ups_used = ad.stats.session.ups_used + 1
    elseif action == "error" then
        ad.stats.session.errors = ad.stats.session.errors + 1
    end
    
    -- Дневная статистика
    local today = os.date("%d.%m.%Y")
    if ad.stats.today_date ~= today then
        ad.stats.today = {ads_sent = 0, ups_used = 0}
        ad.stats.today_date = today
    end
    if action == "ad" then ad.stats.today.ads_sent = ad.stats.today.ads_sent + 1 end
    if action == "up" then ad.stats.today.ups_used = ad.stats.today.ups_used + 1 end
    
    -- Недельная статистика
    local current_monday = getMondayDate()
    if ad.stats.week_start ~= current_monday then
        ad.stats.week = {ads_sent = 0, ups_used = 0}
        ad.stats.week_start = current_monday
        ad.chatMessage("{FFA500}📊 Началась новая неделя! Статистика сброшена.")
    end
    if action == "ad" then ad.stats.week.ads_sent = ad.stats.week.ads_sent + 1 end
    if action == "up" then ad.stats.week.ups_used = ad.stats.week.ups_used + 1 end
    
    -- Общая статистика
    if action == "ad" then ad.stats.total.ads_sent = ad.stats.total.ads_sent + 1 end
    if action == "up" then ad.stats.total.ups_used = ad.stats.total.ups_used + 1 end
    
    ad.saveConfig()
end

-- Функция для форматирования времени сессии
function ad.getSessionTime()
    local elapsed = os.difftime(os.time(), ad.stats.session_start_time)
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local seconds = elapsed % 60
    
    if hours > 0 then
        return string.format("%d ч %d мин %d сек", hours, minutes, seconds)
    elseif minutes > 0 then
        return string.format("%d мин %d сек", minutes, seconds)
    else
        return string.format("%d сек", seconds)
    end
end

-- Функция для отправки сообщения в чат от имени скрипта
function ad.chatMessage(msg)
    sampAddChatMessage(string.format("{FFA500}[Auto AD]{FFFFFF} %s", msg), -1)
end

function ad.sender()
    if not ad.status then return end

    local text_to_send = ad.text
    
    if ad.cycle_mode and #ad.dynamic_ads > 0 then
        if not ad.is_main_text and ad.current_index > 0 and ad.dynamic_ads[ad.current_index] then
            text_to_send = ad.dynamic_ads[ad.current_index]
        end
    end

    if not ad.status_2_wait and not ad.retry_scheduled then
        if os.clock() * 1000 - antiflood > 750 then
            sampSendChat("/ad "..text_to_send)
            ad.last_sent_text = text_to_send
            ad.status_2_wait = true
        end
    end
end

function main()
    while not isSampfuncsLoaded() do wait(100) end
    repeat wait(0) until isSampAvailable()
    sampRegisterChatCommand("aad", menu.show)
    ad.chatMessage("{00FF00}Auto-AD by Marcus Kransov for Advance RolePlay Chocolate {FFFFFF}загружен!")
    ad.chatMessage("Используйте {FFFF00}/aad{FFFFFF} для настройки.")
    ad.chatMessage(string.format("Загружено сохранений: {FFFF00}%d{FFFFFF} доп. объявлений.", #ad.dynamic_ads))
    if ad.cycle_mode and #ad.dynamic_ads > 0 then
        ad.chatMessage("Циклическая ротация {00FF00}активна{FFFFFF} (Основной текст -> Доп. объявления -> ...).")
    end
    if ad.autoup then
        ad.chatMessage("Авто-подъём {00FF00}включён{FFFFFF}.")
    end
    if ad._pending_week_reset then
        ad.chatMessage(string.format("{FFA500}📊 Статистика за прошлую неделю: %d объявлений, %d /up'ов. Новая неделя началась!", 
            ad._pending_week_reset.ads_sent or 0, ad._pending_week_reset.ups_used or 0))
        ad._pending_week_reset = nil
    end
    while true do
        wait(0)
        menu.handler()
        ad.sender()
    end
end

--> Events
function sampev.onServerMessage(color, message)
    local nick = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)))
    
    if message:find("| Отправил "..nick.."%[") then
        if ad.status then
            ad.status_2_wait = false
            ad.ad_state = "idle"
            ad.up_sent = false
            ad.updateStats("ad")
            
            if ad.cycle_mode and #ad.dynamic_ads > 0 then
                if ad.is_main_text then
                    ad.is_main_text = false
                    ad.current_index = 1
                    ad.chatMessage(string.format("Следующее: доп. объявление #%d.", ad.current_index))
                else
                    ad.current_index = ad.current_index + 1
                    if ad.current_index > #ad.dynamic_ads then
                        ad.is_main_text = true
                        ad.current_index = 0
                        ad.chatMessage("Цикл ротации завершён. Следующим будет основной текст.")
                    else
                        ad.chatMessage(string.format("Следующее: доп. объявление #%d.", ad.current_index))
                    end
                end
            end
            
            if ad.one then
                ad.status = false
                ad.chatMessage("Скрипт {FF0000}отключён{FFFFFF} (режим одного объявления).")
            end
        end
    end
    
    -- Проверка на добавление в очередь
    if message:find("Ваше объявление было добавлено в очередь для публикации") then
        if ad.status then
            ad.ad_state = "queued"
        end
    end
    
    -- Проверка на модерацию объявления
    if message:find("Ваше объявление проверено и поставлено в очередь на публикацию") then
        if ad.status then
            ad.ad_state = "verified"
            if ad.autoup and not ad.up_sent then
                ad.up_sent = true
                ad.updateStats("up")
                lua_thread.create(function()
                    wait(600)
                    if ad.status and ad.autoup then
                        repeat wait(0) until os.clock() * 1000 - antiflood > 750
                        sampSendChat("/up")
                        ad.chatMessage("Объявление поднято (авто-подъём).")
                    end
                end)
            end
        end
    end

-- В sampev.onServerMessage, замени блок с задержкой на этот:
local delay = message:match("Пожалуйста, повторите ввод команды через .-(%d+) сек")
if delay then
    delay = tonumber(delay)
    -- Повторяем ТОЛЬКО если объявление ещё НЕ в очереди
    if ad.status and not ad.retry_scheduled and ad.last_sent_text ~= "" and ad.ad_state ~= "queued" and ad.ad_state ~= "verified" then
        ad.retry_scheduled = true
        ad.chatMessage(string.format("{FFA500}Антифлуд: повтор через %d сек...", delay))
        lua_thread.create(function()
            wait(delay * 1000 + 200)
            if ad.status and ad.ad_state ~= "queued" and ad.ad_state ~= "verified" then
                ad.status_2_wait = false
                sampSendChat("/ad "..ad.last_sent_text)
                ad.chatMessage("{00FF00}Повторная отправка выполнена")
            end
            ad.retry_scheduled = false
        end)
    end
    return false -- Скрываем сообщение сервера
end
end

-- Скрываем диалоги /up
function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    local clean_title = title:gsub("{%x+}", "")
    local clean_text = text:gsub("{%x+}", "")
    
    if clean_title:find("Ускоренная публикация") then
        if clean_text:find("доступна только для объявлений с номером более 10") then
            ad.chatMessage("{FFA500}/up не сработал — место в очереди меньше 10")
            return false
        end
        
        if clean_text:find("находится на %d+ месте") and clean_text:find("с номером более %d+") then
            local position = clean_text:match("на (%d+) месте")
            if position then
                local pos = tonumber(position)
                if pos <= 10 then
                    ad.chatMessage(string.format("{FFA500}/up не сработал — место в очереди: %d (нужно > 10)", pos))
                else
                    ad.chatMessage(string.format("{FFA500}Место в очереди: %d (/up должен сработать)", pos))
                end
            end
            return false
        end
        
        if clean_text:find("Вы повысили приоритет") or (clean_text:find("Теперь объявление находится") and clean_text:find("перв") and clean_text:find("мест")) then
            ad.chatMessage("{00FF00}Объявление успешно поднято! /up сработал!")
            return false
        end
    end
    return true
end

function sampev.onSendChat()
    antiflood = os.clock() * 1000
end
function sampev.onSendCommand()
    antiflood = os.clock() * 1000
end

--> Menu
menu = {
    id = 1921,
    id_edit = 1922,
    id_add = 1923,
    id_detail = 1924,
    id_edit_dynamic = 1925,
    id_delete_confirm = 1926,
    id_stats = 1927,
    list = {},
    func = {},
    selected_index = 0,
}

function menu.handler()
    local result, button, list, input = sampHasDialogRespond(menu.id)
    if result and button == 1 then
        if menu.func[list+1] ~= nil then
            menu.func[list+1](button, list, input)
        end
    end
    
    local result, button, list, input = sampHasDialogRespond(menu.id_edit)
    if result then
        if button == 1 then
            ad.text = input
            ad.saveConfig()
            ad.chatMessage(string.format("Основной текст объявления изменён: {FFFF00}%s", input))
            menu.show()
        else
            menu.show()
        end
    end
    
    local result, button, list, input = sampHasDialogRespond(menu.id_add)
    if result and button == 1 and input ~= "" then
        table.insert(ad.dynamic_ads, input)
        ad.saveConfig()
        ad.chatMessage(string.format("Добавлено объявление в ротацию: {FFFF00}%s{FFFFFF} [Всего: %d]", input, #ad.dynamic_ads))
        if #ad.dynamic_ads == 1 and not ad.cycle_mode then
            ad.cycle_mode = true
            ad.is_main_text = true
            ad.current_index = 0
            ad.saveConfig()
            ad.chatMessage("Циклическая ротация автоматически {00FF00}включена{FFFFFF}.")
        end
        menu.show()
    elseif result then
        menu.show()
    end
    
    -- Обработчик диалога деталей объявления
    local result, button, list, input = sampHasDialogRespond(menu.id_detail)
    if result then
        if button == 1 then
            local ad_text = ad.dynamic_ads[menu.selected_index]
            local ad_lines = 1
            if #ad_text > 90 then
                ad_lines = ad_lines + 1
            end
            
            local separator_line = ad_lines
            local action_line = separator_line + 1
            local edit_line = action_line + 2
            local delete_line = action_line + 3
            
            if list == edit_line then
                sampShowDialog(menu.id_edit_dynamic, "Редактирование объявления", 
                    "Введите новый текст объявления:", "Сохранить", "Назад", 1)
                lua_thread.create(function()
                    repeat wait(0) until sampIsDialogActive()
                    sampSetCurrentDialogEditboxText(ad.dynamic_ads[menu.selected_index])
                end)
            elseif list == delete_line then
                local preview = ad_text
                if #preview > 90 then
                    preview = preview:sub(1, 90) .. "..."
                end
                sampShowDialog(menu.id_delete_confirm, "Подтверждение удаления",
                    string.format("{FF0000}Вы уверены, что хотите удалить объявление?\n\n{FFFFFF}%s", preview),
                    "Удалить", "Отмена", 2)
            else
                menu.show()
            end
        else
            menu.show()
        end
    end
    
    -- Обработчик редактирования динамического объявления
    local result, button, list, input = sampHasDialogRespond(menu.id_edit_dynamic)
    if result and button == 1 and input ~= "" then
        ad.dynamic_ads[menu.selected_index] = input
        ad.saveConfig()
        ad.chatMessage(string.format("Объявление #%d изменено: {FFFF00}%s", menu.selected_index, input))
        menu.show()
    elseif result then
        menu.showDetailDialog(menu.selected_index)
    end
    
    -- Обработчик подтверждения удаления
    local result, button, list, input = sampHasDialogRespond(menu.id_delete_confirm)
    if result and button == 1 then
        local removed_text = ad.dynamic_ads[menu.selected_index]
        table.remove(ad.dynamic_ads, menu.selected_index)
        ad.saveConfig()
        ad.chatMessage(string.format("Объявление удалено из ротации: {FFFF00}%s{FFFFFF} [Осталось: %d]", removed_text, #ad.dynamic_ads))
        if #ad.dynamic_ads == 0 then
            ad.cycle_mode = false
            ad.current_index = 0
            ad.is_main_text = true
            ad.saveConfig()
            ad.chatMessage("Все дополнительные объявления удалены. Ротация {FF0000}отключена{FFFFFF}.")
        elseif not ad.is_main_text and ad.current_index > #ad.dynamic_ads then
            ad.is_main_text = true
            ad.current_index = 0
        end
        menu.show()
    elseif result then
        menu.showDetailDialog(menu.selected_index)
    end
    
    -- Обработчик диалога статистики
    local result, button, list, input = sampHasDialogRespond(menu.id_stats)
    if result then
        menu.show()
    end
end

function menu.showDetailDialog(index)
    menu.selected_index = index
    local ad_text = ad.dynamic_ads[index]
    
    local display_text
    if #ad_text > 90 then
        display_text = ad_text:sub(1, 90) .. "...\n{FFFF00}..." .. ad_text:sub(91)
    else
        display_text = ad_text
    end
    
    local dialog_text = string.format(
        "Объявление #%d:\n{FFFF00}%s{FFFFFF}\n\n-----------------------------------------------------\n\nВыберите действие:\n{00FF00}1. Редактировать объявление\n{FF0000}2. Удалить объявление",
        index, display_text
    )
    
    sampShowDialog(menu.id_detail, "Управление объявлением", dialog_text, "Выбрать", "Назад", 2)
end

function menu.show()
    menu.list = {}
    menu.func = {}

    menu.list[#menu.list+1] = string.format("{00FF00}Auto-AD by Marcus Kransov{FFFFFF}")
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = string.format("{8B4513}for Advance RolePlay Chocolate{FFFFFF}")
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "------------------------"
    menu.func[#menu.func+1] = function() end

    menu.list[#menu.list+1] = string.format("Скрипт: %s", (ad.status and "{06940f}ON" or "{d10000}OFF"))
    menu.func[#menu.func+1] = function(button, list, input)
        ad.status = not ad.status
        ad.status_2_wait = false
        ad.up_sent = false
        ad.retry_scheduled = false
        if ad.status then
            local mode_text = ""
            if ad.cycle_mode and #ad.dynamic_ads > 0 then
                mode_text = string.format(" | Ротация: основной + %d доп.", #ad.dynamic_ads)
            end
            if ad.autoup then
                mode_text = mode_text .. " | Авто-подъём: ВКЛ"
            end
            if ad.one then
                mode_text = mode_text .. " | Отключение после подачи: ВКЛ"
            end
            ad.chatMessage(string.format("Скрипт {00FF00}включён{FFFFFF}.%s", mode_text))
        else
            ad.chatMessage("Скрипт {FF0000}отключён{FFFFFF}.")
        end
        menu.show()
    end

    menu.list[#menu.list+1] = string.format("Отключить после подачи: %s", (ad.one and "{06940f}ON" or "{d10000}OFF"))
    menu.func[#menu.func+1] = function(button, list, input)
        ad.one = not ad.one
        ad.saveConfig()
        if ad.one then
            ad.chatMessage("Режим одного объявления {00FF00}включён{FFFFFF}. После отправки скрипт отключится.")
        else
            ad.chatMessage("Режим одного объявления {FF0000}отключён{FFFFFF}. Объявления будут отправляться непрерывно.")
        end
        menu.show()
    end

    menu.list[#menu.list+1] = string.format("Авто-подъем: %s", (ad.autoup and "{06940f}ON" or "{d10000}OFF"))
    menu.func[#menu.func+1] = function(button, list, input)
        ad.autoup = not ad.autoup
        ad.saveConfig()
        if ad.autoup then
            ad.chatMessage("Авто-подъём объявлений {00FF00}включён{FFFFFF}.")
        else
            ad.chatMessage("Авто-подъём объявлений {FF0000}отключён{FFFFFF}.")
        end
        menu.show()
    end

    menu.list[#menu.list+1] = string.format("Текст: %s", ad.text)
    menu.func[#menu.func+1] = function(button, list, input)
        sampShowDialog(menu.id_edit,"Auto-AD","Введите текст объявления без команды /ad","Выбрать","Назад",1)
        lua_thread.create(function()
            repeat wait(0) until sampIsDialogActive()
            sampSetCurrentDialogEditboxText(ad.text)
        end)
        return
    end
    
    menu.list[#menu.list+1] = "------------------------"
    menu.func[#menu.func+1] = function() end
    
    menu.list[#menu.list+1] = string.format("Цикл. ротация: %s (основной + %d доп.)", 
        (ad.cycle_mode and "{06940f}ON" or "{d10000}OFF"), #ad.dynamic_ads)
    menu.func[#menu.func+1] = function(button, list, input)
        if #ad.dynamic_ads > 0 then
            ad.cycle_mode = not ad.cycle_mode
            ad.saveConfig()
            if ad.cycle_mode then
                ad.is_main_text = true
                ad.current_index = 0
                ad.chatMessage(string.format("Циклическая ротация {00FF00}включена{FFFFFF}. Порядок: основной текст -> %d доп. объявлений -> основной...", #ad.dynamic_ads))
            else
                ad.current_index = 0
                ad.is_main_text = true
                ad.chatMessage("Циклическая ротация {FF0000}отключена{FFFFFF}. Будет отправляться только основной текст.")
            end
        else
            ad.chatMessage("{FF0000}Нет дополнительных объявлений для ротации!{FFFFFF} Добавьте хотя бы одно.")
        end
        menu.show()
    end
    
    if ad.cycle_mode and #ad.dynamic_ads > 0 then
        local current_info = ""
        if ad.is_main_text then
            current_info = "Основной текст"
        else
            local current_text = ad.dynamic_ads[ad.current_index]
            if current_text and #current_text > 25 then
                current_text = current_text:sub(1, 25) .. "..."
            end
            current_info = string.format("Доп. #%d: %s", ad.current_index, current_text or "???")
        end
        menu.list[#menu.list+1] = string.format("  {06940f}→ %s", current_info)
        menu.func[#menu.func+1] = function() end
    end
    
    if #ad.dynamic_ads > 0 then
        menu.list[#menu.list+1] = "-- Доп. объявления (клик для управления) --"
        menu.func[#menu.func+1] = function() end
        
        for i, ad_text in ipairs(ad.dynamic_ads) do
            local preview = ad_text
            if #preview > 45 then preview = preview:sub(1, 45) .. "..." end
            local marker = (not ad.is_main_text and ad.current_index == i) and "{06940f}→ " or "{a0a0a0}  "
            
            menu.list[#menu.list+1] = string.format("%s%d. %s", marker, i, preview)
            menu.func[#menu.func+1] = function(button, list, input)
                menu.showDetailDialog(i)
            end
        end
    end
    
    menu.list[#menu.list+1] = "{00ff00}-----[ + Добавить объявление в ротацию ]-----"
    menu.func[#menu.func+1] = function(button, list, input)
        sampShowDialog(menu.id_add, "Добавить объявление", "Введите текст для ротации:", "Добавить", "Отмена", 1)
    end
    
    menu.list[#menu.list+1] = "------------------------"
    menu.func[#menu.func+1] = function() end
    
    menu.list[#menu.list+1] = "{FFFF00}📊 Статистика{FFFFFF}"
    menu.func[#menu.func+1] = function()
        local session = ad.stats.session
        local today = ad.stats.today
        local week = ad.stats.week
        local total = ad.stats.total
        
        local session_time = ad.getSessionTime()
        local week_start = ad.stats.week_start or getMondayDate()
        local week_end = getSundayDate()
        
        local stat_text = string.format(
            "{00FF00}📊 За сессию (%s){FFFFFF}\t{FFFF00}%d объяв.\t{FFFF00}%d /up'ов\n{FFA500}📅 Сегодня (%s){FFFFFF}\t{FFFF00}%d объяв.\t{FFFF00}%d /up'ов\n{0099FF}📆 Неделя (%s - %s){FFFFFF}\t{FFFF00}%d объяв.\t{FFFF00}%d /up'ов\n{FF00FF}🏆 За всё время{FFFFFF}\t{FFFF00}%d объяв.\t{FFFF00}%d /up'ов",
            session_time, session.ads_sent, session.ups_used,
            ad.stats.today_date, today.ads_sent, today.ups_used,
            week_start, week_end, week.ads_sent, week.ups_used,
            total.ads_sent, total.ups_used)
        
        sampShowDialog(menu.id_stats, "📊 Статистика Auto-AD", stat_text, "Назад", "", 2)
    end
    
    menu.list[#menu.list+1] = "------------------------"
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "{A0A0A0}Auto-AD by Marcus_Kransov{FFFFFF}"
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "{A0A0A0}(based on the original by Serhiy Rubin){FFFFFF}"
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "{A0A0A0}for Advance RolePlay Chocolate{FFFFFF}"
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "{A0A0A0}Serhiy, we did it! /up is working!{FFFFFF}"
    menu.func[#menu.func+1] = function() end
    menu.list[#menu.list+1] = "{A0A0A0}But don't use it - 5,000 is too much!{FFFFFF}"
    menu.func[#menu.func+1] = function() end

    local text = ""
    for i = 1, #menu.list do
        text = string.format("%s%s\n", text, menu.list[i])
    end
    sampShowDialog(menu.id, "Auto-AD", text, "Выбрать", "Закрыть", 2)
end

-->> SCRIPT UTF-8
_utf8 = load([=[return function(utf8_func, in_encoding, out_encoding); if encoding == nil then; encoding = require("encoding"); encoding.default = "CP1251"; u8 = encoding.UTF8; end; if type(utf8_func) ~= "table" then; return false; end; if AnsiToUtf8 == nil or Utf8ToAnsi == nil then; AnsiToUtf8 = function(text); return u8(text); end; Utf8ToAnsi = function(text); return u8:decode(text); end; end; if _UTF8_FUNCTION_SAVE == nil then; _UTF8_FUNCTION_SAVE = {}; end; local change_var = "_G"; for s = 1, #utf8_func do; change_var = string.format('%s["%s"]', change_var, utf8_func[s]); end; if _UTF8_FUNCTION_SAVE[change_var] == nil then; _UTF8_FUNCTION = function(...); local pack = table.pack(...); readTable = function(t, enc); for k, v in next, t do; if type(v) == 'table' then; readTable(v, enc); else; if enc ~= nil and (enc == "AnsiToUtf8" or enc == "Utf8ToAnsi") then; if type(k) == "string" then; k = _G[enc](k); end; if type(v) == "string" then; t[k] = _G[enc](v); end; end; end; end; return t; end; return table.unpack(readTable({_UTF8_FUNCTION_SAVE[change_var](table.unpack(readTable(pack, in_encoding)))}, out_encoding)); end; local text = string.format("_UTF8_FUNCTION_SAVE['%s'] = %s; %s = _UTF8_FUNCTION;", change_var, change_var, change_var); load(text)(); _UTF8_FUNCTION = nil; end; return true; end]=])
function utf8(...)
    pcall(_utf8(), ...)
end

utf8({ "sampShowDialog" }, "Utf8ToAnsi")
utf8({ "sampSendChat" }, "Utf8ToAnsi")
utf8({ "sampAddChatMessage" }, "Utf8ToAnsi")
utf8({ "print" }, "Utf8ToAnsi")
utf8({ "sampSetCurrentDialogEditboxText" }, "Utf8ToAnsi")
utf8({ "sampHasDialogRespond" }, nil, "AnsiToUtf8")
utf8({ "sampev", "onShowDialog" }, "AnsiToUtf8", "Utf8ToAnsi")
utf8({ "sampev", "onServerMessage" }, "AnsiToUtf8", "Utf8ToAnsi")
