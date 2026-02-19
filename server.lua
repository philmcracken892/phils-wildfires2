local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

-- =============================================
-- VARIABLES
-- =============================================
local activeFireCounts = {}
local globalFireData = {}
local fireIdCounter = 0
local extinguishedCooldowns = {}
local activeHoses = {}
local fireStats = {
    totalFires = 0,
    totalObjectsFired = 0,
    totalExtinguished = 0,
    activeFiresByPlayer = {},
    randomFires = 0,
    explosionsTriggered = 0,
    hydrantsUsed = 0
}

-- =============================================
-- HELPER FUNCTIONS
-- =============================================
local function GetActiveFireCount()
    local count = 0
    for _ in pairs(globalFireData) do
        count = count + 1
    end
    return count
end

local function GetOnlinePlayersCount()
    return #GetPlayers()
end

local function GetOnlinePlayersList()
    local players = RSGCore.Functions.GetRSGPlayers()
    local playerList = {}
    
    for _, player in pairs(players) do
        if player and player.PlayerData then
            table.insert(playerList, {
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                id = player.PlayerData.source,
                job = player.PlayerData.job.label or player.PlayerData.job.name
            })
        end
    end
    
    return playerList
end

local function IsFirefighterOnDuty()
    local players = RSGCore.Functions.GetRSGPlayers()
    
    for _, player in pairs(players) do
        if player and player.PlayerData and player.PlayerData.job then
            if player.PlayerData.job.name == Config.FirefighterJob.JobName then
                if player.PlayerData.job.onduty == nil or player.PlayerData.job.onduty == true then
                    return true, player.PlayerData.source
                end
            end
        end
    end
    
    return false, nil
end

local function GetOnlineFirefighters()
    local firefighters = {}
    local players = RSGCore.Functions.GetRSGPlayers()
    
    for _, player in pairs(players) do
        if player and player.PlayerData and player.PlayerData.job then
            if player.PlayerData.job.name == Config.FirefighterJob.JobName then
                if player.PlayerData.job.onduty == nil or player.PlayerData.job.onduty == true then
                    table.insert(firefighters, {
                        name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                        id = player.PlayerData.source,
                        grade = player.PlayerData.job.grade.name or "Unknown"
                    })
                end
            end
        end
    end
    
    return firefighters
end

local function GetOnlineFirefightersText()
    local firefighters = GetOnlineFirefighters()
    if #firefighters == 0 then
        return "None"
    end
    
    local text = ""
    for i, ff in ipairs(firefighters) do
        text = text .. "• " .. ff.name .. " (" .. ff.grade .. ")"
        if i < #firefighters then
            text = text .. "\n"
        end
    end
    return text
end

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================
local function Debug(message)
    if Config.Debug then
        ----print('[FIRE-DEBUG] ' .. tostring(message))
    end
end

function SendDiscordLog(title, description, color, fields)
    if not Config.DiscordLogging.Enabled then return end
    if not Config.DiscordLogging.Webhook or Config.DiscordLogging.Webhook == "" then return end
    
    local onlinePlayers = #GetPlayers()
    local firefighters = GetOnlineFirefighters()
    local firefighterCount = #firefighters
    local activeFireCount = GetActiveFireCount()
    
    local firefighterText = "None"
    if firefighterCount > 0 then
        firefighterText = ""
        for i, ff in ipairs(firefighters) do
            firefighterText = firefighterText .. ff.name .. " (" .. ff.grade .. ")"
            if i < firefighterCount then
                firefighterText = firefighterText .. ", "
            end
        end
    end
    
    local allFields = {
        {
            ["name"] = "Players Online",
            ["value"] = tostring(onlinePlayers),
            ["inline"] = true
        },
        {
            ["name"] = "Firefighters Online",
            ["value"] = tostring(firefighterCount),
            ["inline"] = true
        },
        {
            ["name"] = "Active Fires",
            ["value"] = tostring(activeFireCount),
            ["inline"] = true
        }
    }
    
    if firefighterCount > 0 then
        allFields[#allFields + 1] = {
            ["name"] = "On-Duty Firefighters",
            ["value"] = firefighterText,
            ["inline"] = false
        }
    end
    
    if fields and type(fields) == "table" then
        for _, field in ipairs(fields) do
            allFields[#allFields + 1] = {
                ["name"] = field.name or "Unknown",
                ["value"] = tostring(field.value) or "N/A",
                ["inline"] = field.inline or false
            }
        end
    end
    
    local embed = {
        {
            ["title"] = title or "Fire System",
            ["description"] = description or "",
            ["type"] = "rich",
            ["color"] = color or 15158332,
            ["fields"] = allFields,
            ["footer"] = {
                ["text"] = os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }
    
    local payload = json.encode({
        ["username"] = Config.DiscordLogging.BotName or "Fire System",
        ["avatar_url"] = Config.DiscordLogging.AvatarUrl or "",
        ["embeds"] = embed
    })
    
    PerformHttpRequest(Config.DiscordLogging.Webhook, function(err, text, headers) end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

local function GetPlayerName(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player then
        return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    end
    return 'Unknown'
end

local function GetPlayerIdentifier(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player then
        return Player.PlayerData.citizenid
    end
    return nil
end

local function IsPlayerAdmin(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    
    for _, job in ipairs(Config.AdminJobs) do
        if Player.PlayerData.job.name == job then
            return true
        end
    end
    
    for _, group in ipairs(Config.AdminGroups) do
        if RSGCore.Functions.HasPermission(src, group) then
            return true
        end
    end
    
    return false
end

local function IsPlayerFirefighter(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    return Player.PlayerData.job.name == Config.FirefighterJob.JobName
end

local function PayFirefighter(src, isStructureFire)
    if not Config.FirefighterJob.Enabled then return end
    if not IsPlayerFirefighter(src) then return end
    
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local payment = Config.FirefighterJob.PayPerFire
    if isStructureFire then
        payment = payment + Config.FirefighterJob.BonusForLargeFires
    end
    
    Player.Functions.AddMoney('cash', payment)
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = '?? Payment Received',
        description = string.format('You earned $%d for extinguishing the fire!', payment),
        type = 'success',
        duration = 5000
    })
end

local function GenerateFireId()
    fireIdCounter = fireIdCounter + 1
    return fireIdCounter
end

-- =============================================
-- HOSE COMMAND REGISTRATION
-- =============================================
RSGCore.Commands.Add('hose', 'Toggle fire hose (Firefighter Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerFirefighter(src) and not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'Only firefighters can use the fire hose!',
            type = 'error',
            duration = 3000
        })
        return
    end
end)

RSGCore.Commands.Add('firehose', 'Toggle fire hose (Firefighter Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerFirefighter(src) and not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'Only firefighters can use the fire hose!',
            type = 'error',
            duration = 3000
        })
        return
    end
end)

-- =============================================
-- FIRE COUNT TRACKING
-- =============================================
RegisterNetEvent('fire:reportActiveFires', function(count)
    local src = source
    activeFireCounts[src] = count
end)

RegisterNetEvent('fire:checkActiveFires', function()
    -- Client will respond with fire count
end)

RegisterNetEvent('hose:server:startHose', function(cartNetId)
    local src = source
    activeHoses[src] = {
        cartNetId = cartNetId,
        active = true
    }
    
    TriggerClientEvent('hose:client:syncHose', -1, src, cartNetId, true)
end)

RegisterNetEvent('hose:server:stopHose', function()
    local src = source
    activeHoses[src] = nil
    
    TriggerClientEvent('hose:client:syncHose', -1, src, nil, false)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if activeHoses[src] then
        activeHoses[src] = nil
        TriggerClientEvent('hose:client:syncHose', -1, src, nil, false)
    end
    activeFireCounts[src] = nil
    fireStats.activeFiresByPlayer[src] = nil
end)

RegisterNetEvent('hose:server:requestSync', function()
    local src = source
    for playerId, hoseData in pairs(activeHoses) do
        if hoseData.active then
            TriggerClientEvent('hose:client:syncHose', src, playerId, hoseData.cartNetId, true)
        end
    end
end)

-- =============================================
-- FIRE BROADCASTING SYSTEM
-- =============================================
RegisterNetEvent('fire:server:broadcastFire', function(fireCoords, fireType, fireId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local playerName = GetPlayerName(src)
    local citizenId = GetPlayerIdentifier(src)
    local coordsText = string.format("X: %.2f, Y: %.2f, Z: %.2f", fireCoords.x, fireCoords.y, fireCoords.z)
    
    globalFireData[fireId] = {
        coords = fireCoords,
        fireType = fireType,
        starterId = src,
        starterName = playerName,
        citizenId = citizenId,
        startTime = os.time(),
        isStructure = fireType == 'object'
    }
    
    if Config.TrackStatistics then
        fireStats.totalFires = fireStats.totalFires + 1
        fireStats.activeFiresByPlayer[src] = (fireStats.activeFiresByPlayer[src] or 0) + 1
    end
    
    SendDiscordLog(
        "Fire Started",
        "A new fire has been started by a player.",
        Config.DiscordLogging.Colors.FireStarted,
        {
            { name = "Player", value = playerName, inline = true },
            { name = "Player ID", value = tostring(src), inline = true },
            { name = "Citizen ID", value = citizenId or "N/A", inline = true },
            { name = "Location", value = coordsText, inline = false },
            { name = "Fire Type", value = fireType or "Ground Fire", inline = true }
        }
    )
    
    if Config.NotifyAllPlayers then
        TriggerClientEvent('fire:client:fireNotification', -1, {
            coords = fireCoords,
            fireType = fireType,
            starterName = Config.ShowFireStarter and playerName or nil,
            starterId = src,
            fireId = fireId,
            createBlip = true,
            area = "Fire Location"
        })
    end
    
    Debug("Fire started by " .. playerName .. " at " .. coordsText)
end)

RegisterNetEvent('fire:server:broadcastObjectFire', function(objectCoords, objectType, fireId)
    local src = source
    local playerName = GetPlayerName(src)
    local coordsText = string.format("X: %.2f, Y: %.2f, Z: %.2f", objectCoords.x, objectCoords.y, objectCoords.z)
    
    if Config.TrackStatistics then
        fireStats.totalObjectsFired = fireStats.totalObjectsFired + 1
    end
    
    globalFireData[fireId] = {
        coords = objectCoords,
        fireType = 'object',
        objectType = objectType,
        starterId = src,
        starterName = playerName,
        startTime = os.time(),
        isStructure = true
    }
    
    SendDiscordLog(
        "Object Fire",
        "An object has caught fire!",
        Config.DiscordLogging.Colors.ObjectFire,
        {
            { name = " Object", value = objectType or "Unknown", inline = true },
            { name = " Near Player", value = playerName, inline = true },
            { name = " Location", value = coordsText, inline = false }
        }
    )
    
    if Config.NotifyAllPlayers then
        TriggerClientEvent('fire:client:objectFireNotification', -1, {
            coords = objectCoords,
            objectType = objectType,
            starterId = src,
            fireId = fireId
        })
    end
    
    Debug("Object fire: " .. (objectType or "Unknown") .. " at " .. coordsText)
end)

RegisterNetEvent('fire:server:broadcastExtinguished', function(fireCoords, fireId, isStructure)
    local src = source
    local playerName = GetPlayerName(src)
    local coordsText = string.format("X: %.2f, Y: %.2f, Z: %.2f", fireCoords.x, fireCoords.y, fireCoords.z)
    
    ----print("[FIRE SYSTEM] Fire extinguish request from " .. playerName)
    ----print("[FIRE SYSTEM] Fire ID: " .. tostring(fireId))
    
    local currentTime = os.time()
    if extinguishedCooldowns[src] and (currentTime - extinguishedCooldowns[src]) < 5 then
        ----print("[FIRE SYSTEM] Extinguish blocked - cooldown active")
        return
    end
    extinguishedCooldowns[src] = currentTime
    
    local wasStructure = isStructure
    
    -- Remove fire from tracking
    if fireId and globalFireData[fireId] then
        ----print("[FIRE SYSTEM] Removing fire #" .. tostring(fireId) .. " from globalFireData")
        wasStructure = globalFireData[fireId].isStructure
        globalFireData[fireId] = nil
    else
        ----print("[FIRE SYSTEM] WARNING: Fire ID " .. tostring(fireId) .. " not found in globalFireData")
        -- Try to find and remove fire by coordinates
        for id, data in pairs(globalFireData) do
            if data.coords then
                local dist = #(vector3(data.coords.x, data.coords.y, data.coords.z) - vector3(fireCoords.x, fireCoords.y, fireCoords.z))
                if dist < 50.0 then
                    ----print("[FIRE SYSTEM] Found matching fire #" .. tostring(id) .. " by coordinates - removing")
                    globalFireData[id] = nil
                    break
                end
            end
        end
    end
    
    -- Count remaining fires
    local remainingFires = 0
    for _ in pairs(globalFireData) do
        remainingFires = remainingFires + 1
    end
    ----print("[FIRE SYSTEM] Remaining active fires: " .. tostring(remainingFires))
    
    if Config.TrackStatistics then
        fireStats.totalExtinguished = fireStats.totalExtinguished + 1
    end
    
    PayFirefighter(src, wasStructure)
    
    SendDiscordLog(
        "Fire Extinguished",
        "A fire has been extinguished.",
        Config.DiscordLogging.Colors.FireExtinguished,
        {
            { name = "Extinguished By", value = playerName, inline = true },
            { name = "Location", value = coordsText, inline = false },
            { name = "Remaining Fires", value = tostring(remainingFires), inline = true }
        }
    )
    
    TriggerClientEvent('fire:client:fireExtinguishedNotification', -1, {
        coords = fireCoords,
        extinguisherName = playerName,
        fireId = fireId,
        removeBlip = true
    })
    
    ----print("[FIRE SYSTEM] Fire extinguished by " .. playerName)
end)

Citizen.CreateThread(function()
    while true do
        Wait(60000)
        local currentTime = os.time()
        for playerId, cooldownTime in pairs(extinguishedCooldowns) do
            if (currentTime - cooldownTime) > 30 then
                extinguishedCooldowns[playerId] = nil
            end
        end
    end
end)

-- =============================================
-- HYDRANT USAGE BROADCAST
-- =============================================
RegisterNetEvent('fire:server:hydrantUsed', function(coords)
    local src = source
    local playerName = GetPlayerName(src)
    
    if Config.TrackStatistics then
        fireStats.hydrantsUsed = fireStats.hydrantsUsed + 1
    end
    
    SendDiscordLog(
        "Hydrant Activated",
        "A fire hydrant has been used.",
        3447003,
        {
            { name = " Used By", value = playerName, inline = true },
            { name = "Location", value = string.format("X: %.2f, Y: %.2f, Z: %.2f", coords.x, coords.y, coords.z), inline = false }
        }
    )
    
    TriggerClientEvent('fire:client:hydrantNotification', -1, {
        coords = coords,
        userName = playerName
    })
end)

-- =============================================
-- EXPLOSION BROADCAST
-- =============================================
RegisterNetEvent('fire:server:explosionTriggered', function(coords)
    local src = source
    local playerName = GetPlayerName(src)
    
    if Config.TrackStatistics then
        fireStats.explosionsTriggered = fireStats.explosionsTriggered + 1
    end
    
    SendDiscordLog(
        "Explosion Triggered",
        "An explosives box has been detonated!",
        Config.DiscordLogging.Colors.Explosion,
        {
            { name = "Triggered By", value = playerName, inline = true },
            { name = "Location", value = string.format("X: %.2f, Y: %.2f, Z: %.2f", coords.x, coords.y, coords.z), inline = false }
        }
    )
    
    TriggerClientEvent('fire:client:explosionNotification', -1, {
        coords = coords,
        userName = playerName
    })
end)

-- =============================================
-- RANDOM FIRE SYSTEM
-- =============================================
-- =============================================
-- RANDOM FIRE SYSTEM (FIXED)
-- =============================================
Citizen.CreateThread(function()
    -- Wait for server to fully start
    Wait(10000)
    
    ----print("[FIRE SYSTEM] Random fire system started")
    ----print("[FIRE SYSTEM] Interval: " .. tostring(Config.RandomFireInterval) .. "ms")
    ----print("[FIRE SYSTEM] Enabled: " .. tostring(Config.RandomFireEnabled))
    ----print("[FIRE SYSTEM] Max Fires: " .. tostring(Config.MaxFires))
    
    while true do
        Wait(Config.RandomFireInterval)
        
        ----print("[FIRE SYSTEM] ========== RANDOM FIRE CHECK ==========")
        
        -- Check if enabled
        if not Config.RandomFireEnabled then
            ----print("[FIRE SYSTEM] Random fires DISABLED - skipping")
            goto continue
        end
        
        -- Check if firefighter is online
        local firefighterOnline, firefighterId = IsFirefighterOnDuty()
        ----print("[FIRE SYSTEM] Firefighter online: " .. tostring(firefighterOnline))
        
        if not firefighterOnline then
            ----print("[FIRE SYSTEM] No firefighter on duty - skipping")
            goto continue
        end
        
        -- Count active fires from globalFireData (server-side tracking)
        local activeFireCount = 0
        for fireId, fireData in pairs(globalFireData) do
            activeFireCount = activeFireCount + 1
            ----print("[FIRE SYSTEM] Active fire #" .. tostring(fireId) .. " at " .. tostring(fireData.area or "Unknown"))
        end
        
        ----print("[FIRE SYSTEM] Active fires: " .. tostring(activeFireCount) .. " / Max: " .. tostring(Config.MaxFires))
        
        -- Check if we can spawn more fires
        if activeFireCount >= Config.MaxFires then
            ----print("[FIRE SYSTEM] Max fires reached - skipping")
            goto continue
        end
        
        -- Check if we have spawn locations
        if not Config.FireSpawnLocations or #Config.FireSpawnLocations == 0 then
            ----print("[FIRE SYSTEM] ERROR: No fire spawn locations configured!")
            goto continue
        end
        
        -- Spawn a new random fire
        local randomIndex = math.random(1, #Config.FireSpawnLocations)
        local fireLocation = Config.FireSpawnLocations[randomIndex]
        local newFireId = GenerateFireId()
        
        ----print("[FIRE SYSTEM] Spawning fire #" .. tostring(newFireId) .. " at " .. tostring(fireLocation.area))
        
        -- Track statistics
        if Config.TrackStatistics then
            fireStats.randomFires = fireStats.randomFires + 1
            fireStats.totalFires = fireStats.totalFires + 1
        end
        
        -- Store fire data
        globalFireData[newFireId] = {
            coords = fireLocation.coords,
            fireType = "Random Fire",
            area = fireLocation.area,
            starterId = 0,
            starterName = "Natural Cause",
            startTime = os.time()
        }
        
        -- Send Discord notification
        SendDiscordLog(
            "Random Fire Event",
            "A random fire has started!",
            Config.DiscordLogging.Colors.RandomFire,
            {
                { name = "Location", value = fireLocation.area, inline = true },
                { name = "Coordinates", value = string.format("X: %.2f, Y: %.2f, Z: %.2f", 
                    fireLocation.coords.x, fireLocation.coords.y, fireLocation.coords.z), inline = false }
            }
        )
        
        -- Alert all players
        TriggerClientEvent('fire:client:fireAlert', -1, fireLocation.coords, fireLocation.area, newFireId)
        
        ----print("[FIRE SYSTEM] Fire #" .. tostring(newFireId) .. " spawned successfully!")
        ----print("[FIRE SYSTEM] ======================================")
        
        ::continue::
    end
end)

-- =============================================
-- ITEM HANDLING - MATCHES
-- =============================================
RSGCore.Functions.CreateUseableItem(Config.MatchesItem, function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if not Player then return end

    local hasItem = Player.Functions.GetItemByName(Config.MatchesItem)
    if not hasItem or hasItem.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('not_sv_1'),
            description = locale('not_sv_2'),
            type = 'error',
            duration = 3000
        })
        return
    end

    TriggerClientEvent('fire:startFire', src)
end)

RSGCore.Functions.CreateCallback('fire:isFirefighterOnline', function(source, cb)
    local isOnline, firefighterId = IsFirefighterOnDuty()
    cb(isOnline, firefighterId)
end)

RSGCore.Functions.CreateCallback('fire:getOnlineFirefighters', function(source, cb)
    local firefighters = GetOnlineFirefighters()
    cb(firefighters)
end)



-- =============================================
-- ITEM HANDLING - HYDRANT
-- =============================================
RSGCore.Functions.CreateUseableItem("hydrant", function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local hasItem = Player.Functions.GetItemByName('hydrant')
    if not hasItem or hasItem.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'You don\'t have a hydrant',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local removed = Player.Functions.RemoveItem('hydrant', 1)
    if removed then
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['hydrant'], 'remove', 1)
        TriggerClientEvent('fire:client:placeItem', src, 'hydrant')
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'Failed to use hydrant',
            type = 'error',
            duration = 3000
        })
    end
end)

-- =============================================
-- REMOVE ITEM EVENT
-- =============================================
RegisterNetEvent('fire:removeItem', function(item, amount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if not Player then return end

    local hasItem = Player.Functions.GetItemByName(item)
    if not hasItem or hasItem.amount < amount then return end

    Player.Functions.RemoveItem(item, amount)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'remove', amount)
    
    Debug("Removed " .. amount .. "x " .. item .. " from player " .. src)
end)

RegisterNetEvent('fire:server:pickupItem', function(itemName, giveBack)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    if giveBack then
        local added = Player.Functions.AddItem(itemName, 1)
        if added then
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'add', 1)
            TriggerClientEvent('ox_lib:notify', src, {
                title = '? Item Picked Up',
                description = 'Item added to inventory',
                type = 'success',
                duration = 3000
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = '?? Item Removed',
            description = 'Equipment has been stored away.',
            type = 'info',
            duration = 3000
        })
    end
end)

-- =============================================
-- SET PLAYER ON FIRE
-- =============================================
RegisterNetEvent('fire:setPlayerOnFire', function(targetServerId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local Target = RSGCore.Functions.GetPlayer(targetServerId)

    if not Player then return end

    if not Target then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('not_sv_1'),
            description = locale('not_sv_4') or 'Invalid target player.',
            type = 'error',
            duration = 3000
        })
        return
    end

    local hasItem = Player.Functions.GetItemByName(Config.MatchesItem)
    if not hasItem or hasItem.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('not_sv_1'),
            description = locale('not_sv_2') or 'You need matches to start a fire.',
            type = 'error',
            duration = 3000
        })
        return
    end

    local targetPed = GetPlayerPed(targetServerId)
    local targetCoords = GetEntityCoords(targetPed)

    if Config.ConsumeMatches then
        Player.Functions.RemoveItem(Config.MatchesItem, 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.MatchesItem], 'remove', 1)
    end

    TriggerClientEvent('fire:client:setPlayerOnFire', targetServerId, targetCoords)
    TriggerClientEvent('fire:client:setPlayerOnFire', src, targetCoords)
    
    SendDiscordLog(
        "Player Set On Fire",
        "A player has set another player on fire!",
        15158332,
        {
            { name = " Attacker", value = GetPlayerName(src), inline = true },
            { name = " Victim", value = GetPlayerName(targetServerId), inline = true }
        }
    )
    
    Debug(GetPlayerName(src) .. " set " .. GetPlayerName(targetServerId) .. " on fire")
end)

-- =============================================
-- STATISTICS & ADMIN COMMANDS
-- =============================================
RegisterNetEvent('fire:server:updateStats', function(statType, amount)
    local src = source
    amount = amount or 1
    
    if not Config.TrackStatistics then return end
    
    if statType == 'created' then
        fireStats.totalFires = fireStats.totalFires + amount
        fireStats.activeFiresByPlayer[src] = (fireStats.activeFiresByPlayer[src] or 0) + amount
    elseif statType == 'extinguished' then
        fireStats.totalExtinguished = fireStats.totalExtinguished + amount
    elseif statType == 'object' then
        fireStats.totalObjectsFired = fireStats.totalObjectsFired + amount
    end
end)

RSGCore.Commands.Add('firestats', 'Check fire statistics (Admin Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'You do not have permission to use this command.',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = '?? Fire Statistics',
        description = string.format(
            '?? Total Fires: %d\n?? Objects Burned: %d\n?? Extinguished: %d\n?? Random Fires: %d\n?? Explosions: %d\n?? Hydrants Used: %d',
            fireStats.totalFires,
            fireStats.totalObjectsFired,
            fireStats.totalExtinguished,
            fireStats.randomFires,
            fireStats.explosionsTriggered,
            fireStats.hydrantsUsed
        ),
        type = 'info',
        duration = 15000
    })
end)

RSGCore.Commands.Add('listfires', 'List all active fires (Admin Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'You do not have permission to use this command.',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local fireCount = 0
    local fireList = "Active Fires:\n"
    
    for id, data in pairs(globalFireData) do
        fireCount = fireCount + 1
        fireList = fireList .. string.format("?? #%d - %s (%s)\n", id, data.area or "Unknown", data.starterName or "Unknown")
    end
    
    if fireCount == 0 then
        fireList = "? No active fires."
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = '?? Active Fires (' .. fireCount .. ')',
        description = fireList,
        type = 'info',
        duration = 15000
    })
end)

RSGCore.Commands.Add('extinguishall', 'Extinguish all fires (Admin Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'You do not have permission to use this command.',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    TriggerClientEvent('fire:client:extinguishAll', -1)
    globalFireData = {}
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Fires Extinguished',
        description = 'All fires have been extinguished.',
        type = 'success',
        duration = 5000
    })
    
    SendDiscordLog(
        "All Fires Extinguished",
        "An admin has extinguished all fires.",
        Config.DiscordLogging.Colors.FireExtinguished,
        {
            { name = "Admin", value = GetPlayerName(src), inline = true }
        }
    )
end)

RSGCore.Commands.Add('spawnhydrant', 'Spawn a fire hydrant at your location (Firefighter Only)', {}, false, function(source, args)
    local src = source
    
    if not IsPlayerFirefighter(src) and not IsPlayerAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '? Error',
            description = 'Only firefighters can use this command.',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    TriggerClientEvent('fire:admin:spawnEquipment', src, 'hydrant')
end)

-- =============================================
-- EXPORTS
-- =============================================
exports('getFireStats', function()
    return fireStats
end)

exports('getActiveFires', function()
    return globalFireData
end)

exports('getFireCount', function()
    local count = 0
    for _ in pairs(globalFireData) do
        count = count + 1
    end
    return count
end)

exports('getOnlineFirefighters', function()
    return GetOnlineFirefighters()
end)

exports('isFirefighterOnDuty', function()
    return IsFirefighterOnDuty()
end)

-- =============================================
-- CLEANUP
-- =============================================
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        TriggerClientEvent('fire:client:extinguishAll', -1)
        globalFireData = {}
        activeFireCounts = {}
    end
end)
