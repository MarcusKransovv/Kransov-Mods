script_name('Kransov Mods Manager')
script_author('Marcus Kransov')
script_version('1.0.0')
script_description('Менеджер скриптов студии Kransov Mods')

require 'lib.moonloader'

local imgui = require 'imgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local json = require 'json'
local dlstatus = require('moonloader').download_status

-- ============================================
-- НАСТРОЙКИ
-- ============================================
local CATALOG_URL = 'https://raw.githubusercontent.com/MarcusKransovv/Kransov-Mods/refs/heads/main/catalog.json'
local STUDIO_NAME = 'Kransov Mods'
local AUTHOR = 'Marcus Kransov'
local VK_URL = 'https://vk.com/marcuskransov'

-- ============================================
-- СОСТОЯНИЯ
-- ============================================
local window_state = imgui.ImBool(false)
local catalog = nil
local catalog_loaded = false
local catalog_error = false
local esc_bind_registered = false
local delete_confirm = {}

local sw, sh = getScreenResolution()

-- ============================================
-- ФУНКЦИИ
-- ============================================
local function loadCatalog()
    catalog_error = false
    local fpath = os.tmpname()
    local file_download = false

    downloadUrlToFile(CATALOG_URL, fpath, function(id, status, p1, p2)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            file_download = true
        end
    end)

    local waited = 0
    while not file_download and waited < 100 do
        wait(100)
        waited = waited + 1
    end

    if file_download then
        local file = io.open(fpath, 'r')
        if file then
            local content = file:read('*all')
            file:close()
            os.remove(fpath)
            local success, data = pcall(json.decode, content)
            if success and data and data.scripts then
                -- Конвертируем все строки из userdata если нужно
                for i, script in ipairs(data.scripts) do
                    script.name = tostring(script.name)
                    script.version = tostring(script.version)
                    script.description = tostring(script.description or '')
                    script.history = tostring(script.history or '')
                    script.last_update = tostring(script.last_update or '')
                    script.link = tostring(script.link)
                end
                catalog = data
                catalog_loaded = true
                return true
            end
        end
    end

    catalog_error = true
    return false
end
local function getScriptFileName(script)
    local filename = tostring(script.filename or '')

    if filename ~= '' and filename ~= 'nil' then
        return filename
    end

    local name = tostring(script.name or 'script')
    name = name:gsub('[\\/:*?"<>|]', '')
    name = name:gsub('%s+', '-'):lower()

    return name .. '.lua'
end
local function getScriptPath(script)
    return getWorkingDirectory() .. '\\' .. getScriptFileName(script)
end
local function isScriptInstalled(script)
    return doesFileExist(getScriptPath(script))
end
local function installScript(script)
    sampAddChatMessage(string.format('{FFA500}[%s]{FFFFFF} Устанавливаю: %s...', STUDIO_NAME, tostring(script.name)), -1)

    lua_thread.create(function()
        local temp_path = os.tmpname()
        local download_finished = false
        local download_success = false

        -- Скачиваем файл
        downloadUrlToFile(tostring(script.link), temp_path, function(id, status, p1, p2)
                if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                    download_success = true
                end

                if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                    download_finished = true
                end
            end
        )

        -- Ждём окончания загрузки максимум 30 секунд
        local waited = 0

        while not download_finished and waited < 300 do
            wait(100)
            waited = waited + 1
        end

        -- Таймаут
        if not download_finished then
            os.remove(temp_path)

            sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} Таймаут загрузки: %s', STUDIO_NAME, tostring(script.name)), -1)

            return
        end

        -- Ошибка скачивания
        if not download_success then
            os.remove(temp_path)

            sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} Не удалось скачать файл.', STUDIO_NAME), -1)
            sampAddChatMessage(string.format('{A0A0A0}URL: %s', tostring(script.link)), -1)

            return
        end

        -- Открываем скачанный временный файл
        local input = io.open(temp_path, 'rb')

        if not input then
            os.remove(temp_path)

            sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} Не удалось открыть скачанный файл.', STUDIO_NAME), -1)
            sampAddChatMessage(string.format('{A0A0A0}Временный файл: %s', temp_path), -1)

            return
        end

        local content = input:read('*all')
        input:close()
        os.remove(temp_path)

        -- Проверяем содержимое
        if not content or #content == 0 then
            sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} Скачанный файл пуст.', STUDIO_NAME), -1)
            return
        end

        -- Получаем конечный путь
        local target_path = getScriptPath(script)
        -- Записываем файл
        local output = io.open(target_path, 'wb')

        if not output then
            sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} Не удалось создать файл!', STUDIO_NAME), -1)
            sampAddChatMessage(string.format('{A0A0A0}Путь: %s', target_path), -1)
            return
        end

        output:write(content)
        output:close()

        -- Финальная проверка
        if not doesFileExist(target_path) then
            sampAddChatMessage(
            string.format('{FF0000}[%s]{FFFFFF} Файл записан, но не найден после записи!', STUDIO_NAME), -1)
            return
        end

        -- Успешная установка
        sampAddChatMessage(
        string.format('{00FF00}[%s]{FFFFFF} %s v%s установлен!', STUDIO_NAME, tostring(script.name),
            tostring(script.version)), -1)
        sampAddChatMessage(string.format('{A0A0A0}Файл: %s', target_path), -1)
        sampAddChatMessage('{A0A0A0}Перезапустите игру или перезагрузите MoonLoader для активации.', -1)
    end)
end
local function deleteScript(script)
    local script_file = getWorkingDirectory() .. '\\' .. getScriptFileName(script)
    if doesFileExist(script_file) then
        os.remove(script_file)
        sampAddChatMessage(string.format('{FF0000}[%s]{FFFFFF} %s удалён!', STUDIO_NAME, script.name), -1)
    else
        sampAddChatMessage(string.format('{FFA500}[%s]{FFFFFF} Файл %s не найден', STUDIO_NAME, getScriptFileName(script)), -1)
    end
end

-- ============================================
-- IMGUI ОТРИСОВКА
-- ============================================
function imgui.OnDrawFrame()
    if window_state.v then
        imgui.SetNextWindowSize(imgui.ImVec2(650, 500), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

        imgui.Begin(u8(STUDIO_NAME .. ' | Каталог скриптов'), window_state,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar)
        imgui.CenterText(u8(STUDIO_NAME .. ' | Каталог скриптов'))
        imgui.Separator()
        imgui.BeginChild('catalog_scroll', imgui.ImVec2(0, 0), true)

        -- Заголовок
        imgui.TextColored(imgui.ImVec4(0.90, 0.62, 0.00, 1.00), u8('СКРИПТЫ СТУДИИ ' .. STUDIO_NAME:upper()))
        imgui.Separator()

        if not catalog_loaded and not catalog_error then
            imgui.TextColored(imgui.ImVec4(0.90, 0.62, 0.00, 1.00), u8('Загрузка каталога с GitHub...'))
            if imgui.Button(u8('Повторить загрузку'), imgui.ImVec2(-1, 25)) then
                lua_thread.create(function()
                    loadCatalog()
                end)
            end
        elseif catalog_error then
            imgui.TextColored(imgui.ImVec4(0.80, 0.00, 0.00, 1.00), u8('Не удалось загрузить каталог'))
            imgui.TextDisabled(u8('Проверьте интернет-соединение или ссылку в CATALOG_URL, и попробуйте снова.'))
            if imgui.Button(u8('Повторить попытку'), imgui.ImVec2(-1, 25)) then
                lua_thread.create(function()
                    loadCatalog()
                end)
            end
        elseif catalog and catalog.scripts then
            for i, script in ipairs(catalog.scripts) do
                local installed = isScriptInstalled(script)
                local status_color = installed and imgui.ImVec4(0.00, 0.80, 0.00, 1.00) or
                imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
                local status_text = installed and u8('[Установлен]') or u8('[Не установлен]')

                -- Название скрипта
                imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, 1.00),
                    string.format(u8 '%d. %s', i, tostring(script.name)))

                -- Статус
                imgui.SameLine()
                imgui.TextColored(status_color, status_text)

                -- Версия
                imgui.SameLine()
                imgui.TextDisabled('v' .. tostring(script.version))

                -- Кнопка установки
                if not installed then
                    imgui.SameLine()
                    if imgui.Button(u8('[Установить]##install_' .. i), imgui.ImVec2(100, 20)) then
                        installScript(script)
                    end
                end

                    if installed then
                        imgui.SameLine()
                        
                        local script_file = getScriptFileName(script)
                        local confirm_data = delete_confirm[script_file]
                        
                        if confirm_data and confirm_data.time > os.clock() then
                            -- Идёт отсчёт
                            local remaining = math.ceil(confirm_data.time - os.clock())
                            
                            imgui.TextColored(imgui.ImVec4(1.00, 0.50, 0.00, 1.00), u8(string.format('Удалить через %d...', remaining)))
                            imgui.SameLine()
                            
                            if imgui.Button(u8('[Отмена]##cancel_' .. i), imgui.ImVec2(70, 20)) then
                                delete_confirm[script_file] = nil
                            end
                        elseif confirm_data and confirm_data.time <= os.clock() then
                            -- Таймер закончился, теперь подтверждение доступно
                            if imgui.Button(u8('[ПОДТВЕРДИТЬ]##confirm_' .. i), imgui.ImVec2(110, 20)) then
                                deleteScript(script)
                                delete_confirm[script_file] = nil
                            end

                            imgui.SameLine()

                            if imgui.Button(u8('[Отмена]##cancel_' .. i), imgui.ImVec2(70, 20)) then
                                delete_confirm[script_file] = nil
                            end
                        else
                            -- Обычная кнопка
                            if imgui.Button(u8('[Удалить]##delete_' .. i), imgui.ImVec2(80, 20)) then
                                delete_confirm[script_file] = {time = os.clock() + 5}
                            end
                        end
                    end

                -- Описание под названием
                imgui.TextDisabled('  ' .. tostring(script.description or ''))

                -- История изменений
                if imgui.CollapsingHeader(u8('История изменений ##' .. i)) then
                    if script.history then
                        -- Разбиваем историю на строки
                        local history_text = tostring(script.history)

                        -- Ищем строки "Версия X.X.X - дата" и делаем их по центру
                        for line in history_text:gmatch('[^\n]+') do
                            local clean_line = line:gsub('^%s+', ''):gsub('%s+$', '')

                            if clean_line:find('^Версия') or clean_line:find('^Version') then
                                -- Строка с версией и датой — по центру, цветная
                                imgui.CenterTextColored(imgui.ImVec4(0.90, 0.62, 0.00, 1.00), clean_line)
                            elseif clean_line:find('^%-') then
                                -- Строки с изменениями — с отступом
                                imgui.TextColored(imgui.ImVec4(0.80, 0.80, 0.80, 1.00), '  ' .. clean_line)
                            elseif clean_line:find('^%s*$') then
                                -- Пустая строка — пропускаем
                            else
                                -- Обычный текст
                                imgui.Text(clean_line)
                            end
                        end

                        imgui.Separator()
                        imgui.CenterTextDisabled(u8('Последнее обновление: ') ..
                        tostring(script.last_update or 'неизвестно'))
                        imgui.CenterTextDisabled(u8('Файл: ') .. tostring(getScriptFileName(script)))
                    else
                        imgui.TextDisabled(u8('История не указана'))
                    end
                    imgui.Separator()
                    imgui.TextDisabled(u8('Последнее обновление: ') ..
                    tostring(script.last_update or 'неизвестно') ..
                    ' | ' .. u8('Файл: ') .. tostring(getScriptFileName(script)))
                end

                imgui.Separator()
            end
            imgui.NewLine()
            imgui.CenterTextDisabled(u8('Студия ' ..
            STUDIO_NAME .. ' | Автор: ' .. AUTHOR .. ' | VK: ' .. VK_URL .. ' | Discord: marcuskransov'))
            imgui.CenterTextDisabled(u8('Все скрипты с открытым исходным кодом. Личных данных не собираем.'))

            imgui.NewLine()
            imgui.CenterTextColored(imgui.ImVec4(0.90, 0.62, 0.00, 1.00), u8('=== ПРОЗРАЧНОСТЬ ==='))
            imgui.Separator()
            imgui.TextWrapped(u8(
            'Весь исходный код нашего менеджера опубликован в репозитории. Все директории открыты. Никаких скрытых файлов, никаких "чёрных ящиков".'))
            imgui.CenterSelectable(u8('—> Открыть репозиторий на GitHub <—'),
                'https://github.com/MarcusKransovv/Kransov-Mods')
            imgui.Spacing()
            imgui.TextWrapped(u8(
            'Почему файл скомпилирован? Потому что какая-то чушка может поменять ссылки в коде на установщик вируса. Компиляция — это защита ВАС, а не скрытие кода. Для особо мнительных баягузов — могу лично в Discord на демонстрации экрана показать исходный код этого файла. Без проблем.'))
            imgui.NewLine()
            imgui.CenterTextDisabled(u8(
            'Прозрачность — наш конёк. Мы не скрываем код, не шифруем, не прячем. Всё открыто.\nЕсли вы сомневаетесь — проверяйте сами. Нам плевать. (c) Kransov Mods, 2026'))

            imgui.NewLine()
            imgui.Separator()
            imgui.CenterTextColored(imgui.ImVec4(0.60, 0.60, 0.60, 1.00),
                u8('Пользуясь нашими скриптами, вы автоматически соглашаетесь с лицензией MIT.'))
            imgui.CenterTextColored(imgui.ImVec4(0.60, 0.60, 0.60, 1.00),
                u8('Это значит: нам похуй, претензий к Маркусу Крансову нет, скрипты "как есть".'))
            imgui.CenterSelectable(u8('—> Читать лицензию (MIT License) <—'),
                'https://raw.githubusercontent.com/MarcusKransovv/Kransov-Mods/refs/heads/main/LICENSE%20%5BEN%5CRU%5D')
            imgui.CenterTextColored(imgui.ImVec4(0.40, 0.40, 0.40, 1.00),
                u8('Жалобы принимаются в ChatGPT. Он нам перешлёт. Мы посмеёмся.'))
        end
        imgui.EndChild()
        imgui.End()
    end
end

-- ============================================
-- MAIN
-- ============================================
function main()
    if not isSampfuncsLoaded() or not isSampLoaded() then return end
    while not isSampAvailable() do wait(100) end

    imgui.Process = false

    sampRegisterChatCommand('kransov', function()
        window_state.v = not window_state.v
        imgui.Process = window_state.v
    end)
    sampRegisterChatCommand('km', function()
        window_state.v = not window_state.v
        imgui.Process = window_state.v
    end)

    sampAddChatMessage(
    string.format('{FFA500}[%s]{FFFFFF} Менеджер загружен! {FFFF00}/kransov{FFFFFF} или {FFFF00}/km{FFFFFF} — каталог',
        STUDIO_NAME), -1)

    -- Загружаем каталог
    lua_thread.create(function()
        wait(500)
        loadCatalog()
    end)

    while true do
        wait(0)

        if window_state.v and isKeyJustPressed(VK_ESCAPE) then
            window_state.v = false
            imgui.Process = false
            consumeWindowMessage(true, false)
        end
    end
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local size = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - size.x / 2)
    imgui.Text(text)
end

function imgui.CenterTextColored(color, text)
    local width = imgui.GetWindowWidth()
    local size = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((width - size.x) / 2)
    imgui.TextColored(color, text)
end

function imgui.CenterTextDisabled(text)
    local width = imgui.GetWindowWidth()
    local size = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((width - size.x) / 2)
    imgui.TextDisabled(text)
end

function imgui.CenterSelectable(label, url)
    local width = imgui.GetWindowWidth()
    local size = imgui.CalcTextSize(label)
    imgui.SetCursorPosX((width - size.x) / 2)
    if imgui.Selectable(label, false) then
        if url then
            os.execute('start ' .. url)
        end
        return true
    end
    return false
end

function onWindowMessage(msg, wparam, lparam)
    if msg == 0x100 or msg == 0x101 then
        -- 0x1B = VK_ESCAPE
        if wparam == 0x1B and window_state.v then
            -- Блокируем ESC от игры
            consumeWindowMessage(true, false)

            -- Закрываем окно при отпускании клавиши
            if msg == 0x101 then
                window_state.v = false
                imgui.Process = false
            end
        end
    end
end
