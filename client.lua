local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

-- =============================================
-- VARIABLES
-- =============================================
local activeFires = {}
local fireId = 0
local blipEntries = {}
local burningObjects = {}
local FlammableObjects = {}
local isExtinguishing = false
local extinguishedFires = {}
local lastExtinguishNotification = 0
local EXTINGUISH_NOTIFICATION_COOLDOWN = 5000

-- GPS Variables
local currentGPSFire = nil
local gpsActive = false

-- Placeable Items System
local placedItems = {}
local isPlacingItem = false
local trackedVehicles = {}

-- Notification cooldowns
local lastHydrantNotification = 0
function TableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function GetPlayerFireCount()
    return TableCount(activeFires)
end
-- =============================================
-- INITIALIZE
-- =============================================
Citizen.CreateThread(function()
    for objectName, data in pairs(Config.FlammableObjects) do
        local hash = GetHashKey(objectName)
        FlammableObjects[hash] = data
    end
end)

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================
local function Debug(message)
    if Config.Debug then
        print('[FIRE-DEBUG] ' .. tostring(message))
    end
end

function TableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function GenerateFireId()
    fireId = fireId + 1
    return fireId
end

local function GetDistanceText(distance)
    if distance < 1000 then
        return string.format("%.0fm", distance)
    else
        return string.format("%.1fkm", distance / 1000)
    end
end

-- =============================================
-- CHECK IF PLAYER IS FIREFIGHTER
-- =============================================
local function IsFirefighter()
    local PlayerData = RSGCore.Functions.GetPlayerData()
    
    if not PlayerData then return false end
    if not PlayerData.job then return false end
    
    local playerJob = PlayerData.job.name
    local requiredJob = Config.FirefighterJob and Config.FirefighterJob.JobName or 'firefighter'
    
    return playerJob == requiredJob
end

local function SetFireWaypoint(pos, label)
    if pos and pos.x and pos.y and pos.z then
        ClearGpsMultiRoute()
        StartGpsMultiRoute(6, true, true)
        AddPointToGpsMultiRoute(pos.x, pos.y, pos.z)
        SetGpsMultiRouteRender(true)
        
        gpsActive = true
        currentGPSFire = pos

        CreateThread(function()
            local playerPed = PlayerPedId()
            local arrived = false
            
            while not arrived and gpsActive do
                local coords = GetEntityCoords(playerPed)
                local dist = #(vector3(pos.x, pos.y, pos.z) - coords)
                
                if dist < 10.0 then
                    ClearGpsMultiRoute()
                    SetGpsMultiRouteRender(false)
                    arrived = true
                    gpsActive = false
                    currentGPSFire = nil
                    
                    TriggerEvent('ox_lib:notify', {
                        title = 'Arrived at Fire',
                        description = 'You have arrived at the fire location',
                        type = 'info',
                        duration = 5000
                    })
                end
                Wait(1000)
            end
        end)
    end
end

local function ClearFireWaypoint()
    if gpsActive then
        ClearGpsMultiRoute()
        SetGpsMultiRouteRender(false)
        gpsActive = false
        currentGPSFire = nil
    end
end

-- =============================================
-- CREATE FIRE BLIP (FIXED FOR REDM)
-- =============================================
local function CreateFireBlip(coords, area, blipFireId)
    if not Config.AddGPSRoute then return nil end
    
    -- Check if blip already exists for this fire
    for _, entry in ipairs(blipEntries) do
        if entry.fireId == blipFireId then
            return entry
        end
    end
    
    -- Create blip using BlipAddForCoords
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
    
    if not blip or blip == 0 then
        -- Try alternative method
        blip = Citizen.InvokeNative(0x554D9D53F696D002, joaat("BLIP_STYLE_ENEMY"), coords.x, coords.y, coords.z)
    end
    
    if blip and blip ~= 0 then
        -- Set blip sprite
        Citizen.InvokeNative(0x74F74D3207ED525C, blip, Config.BlipSprite or 1754365229, true)
        
        -- Set blip scale
        Citizen.InvokeNative(0xD38744167B2FA257, blip, Config.BlipScale or 0.9)
        
        -- Set blip color to red
        Citizen.InvokeNative(0x0D6375FF1491DC27, blip, "BLIP_MODIFIER_MP_COLOR_32") -- Red color
        
        -- Set blip name
        local blipName = area or "FIRE"
        local varString = CreateVarString(10, "LITERAL_STRING", blipName)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, varString)
        
        -- Make blip flash if enabled
        if Config.BlipFlash then
            Citizen.InvokeNative(0xAA662B71D36A809E, blip, true)
        end
        
        -- Set blip to show on map
        Citizen.InvokeNative(0x662D364ABF16DE2F, blip, 2) -- BLIP_ADD_MODIFIER
        
        local blipEntry = {
            handle = blip,
            coords = coords,
            fireId = blipFireId,
            area = area,
            createdAt = GetGameTimer()
        }
        
        table.insert(blipEntries, blipEntry)
        
        return blipEntry
    end
    
    return nil
end

-- =============================================
-- REMOVE FIRE BLIP (FIXED FOR REDM)
-- =============================================
local function RemoveFireBlip(blipFireId)
    for i = #blipEntries, 1, -1 do
        local blipEntry = blipEntries[i]
        if blipEntry.fireId == blipFireId then
            if blipEntry.handle then
                -- Stop flash
                Citizen.InvokeNative(0xAA662B71D36A809E, blipEntry.handle, false)
                -- Remove blip
                RemoveBlip(blipEntry.handle)
            end
            table.remove(blipEntries, i)
            return true
        end
    end
    return false
end

-- =============================================
-- REMOVE BLIP BY COORDINATES
-- =============================================
local function RemoveFireBlipByCoords(coords, radius)
    radius = radius or 50.0
    local coordsVec = vector3(coords.x, coords.y, coords.z)
    local removed = false
    
    for i = #blipEntries, 1, -1 do
        local blipEntry = blipEntries[i]
        if blipEntry.coords and #(coordsVec - blipEntry.coords) < radius then
            if blipEntry.handle then
                Citizen.InvokeNative(0xAA662B71D36A809E, blipEntry.handle, false)
                RemoveBlip(blipEntry.handle)
            end
            table.remove(blipEntries, i)
            removed = true
        end
    end
    
    return removed
end

-- =============================================
-- REMOVE ALL FIRE BLIPS
-- =============================================
local function RemoveAllFireBlips()
    for i = #blipEntries, 1, -1 do
        local blipEntry = blipEntries[i]
        if blipEntry.handle then
            Citizen.InvokeNative(0xAA662B71D36A809E, blipEntry.handle, false)
            RemoveBlip(blipEntry.handle)
        end
    end
    blipEntries = {}
end

-- =============================================
-- GET NEARBY ENTITIES
-- =============================================
function GetNearbyPeds(coords, radius, maxPeds)
    local peds = {}
    local handle, ped = FindFirstPed()
    local success = true
    
    repeat
        if DoesEntityExist(ped) and ped ~= PlayerPedId() then
            local pedCoords = GetEntityCoords(ped)
            if #(pedCoords - coords) <= radius then
                table.insert(peds, ped)
            end
        end
        success, ped = FindNextPed(handle)
    until not success or #peds >= maxPeds
    
    EndFindPed(handle)
    return peds
end

function GetNearbyVehicles(coords, radius, maxVehicles)
    local vehicles = {}
    local handle, veh = FindFirstVehicle()
    local success = true
    
    repeat
        if DoesEntityExist(veh) then
            local vehCoords = GetEntityCoords(veh)
            if #(vehCoords - coords) <= radius then
                table.insert(vehicles, veh)
            end
        end
        success, veh = FindNextVehicle(handle)
    until not success or #vehicles >= maxVehicles
    
    EndFindVehicle(handle)
    return vehicles
end

-- =============================================
-- FIRE EFFECTS
-- =============================================
local function ApplyScreenEffect(distance)
    if not Config.UseScreenEffects then return end
    
    if distance < 20.0 then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.5)
    elseif distance < 50.0 then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.2)
    end
end

-- =============================================
-- SILENT FIRE EXTINGUISH
-- =============================================
function ExtinguishFireSilent(fireIdToExtinguish)
    if not activeFires[fireIdToExtinguish] then
        return false
    end
    
    local fireData = activeFires[fireIdToExtinguish]
    
    if fireData.fireHandles then
        for _, fireHandle in ipairs(fireData.fireHandles) do
            if fireHandle and fireHandle ~= 0 then
                if fireData.isVfx then
                    StopParticleFxLooped(fireHandle, false)
                else
                    RemoveScriptFire(fireHandle)
                end
            end
        end
    end
    
    RemoveFireBlip(fireIdToExtinguish)
    activeFires[fireIdToExtinguish] = nil
    
    return true
end

-- =============================================
-- EXTINGUISH FIRES IN RANGE
-- =============================================
local function ExtinguishFiresInRange(x, y, z, radius)
    Citizen.InvokeNative(0xDB38F247BD421708, x, y, z, radius)
    
    local nearbyPeds = GetNearbyPeds(vector3(x, y, z), radius, 10)
    for _, ped in ipairs(nearbyPeds) do
        if DoesEntityExist(ped) and IsEntityOnFire(ped) then
            Citizen.InvokeNative(0x8390751DC40C1E98, ped)
        end
    end
    
    local nearbyVehicles = GetNearbyVehicles(vector3(x, y, z), radius, 5)
    for _, veh in ipairs(nearbyVehicles) do
        if DoesEntityExist(veh) and IsEntityOnFire(veh) then
            Citizen.InvokeNative(0x8390751DC40C1E98, veh)
        end
    end
    
    local fireCoords = vector3(x, y, z)
    local firesExtinguished = 0
    
    for fireIdToCheck, fireData in pairs(activeFires) do
        if #(fireCoords - fireData.coords) <= radius then
            if not extinguishedFires[fireIdToCheck] then
                ExtinguishFireSilent(fireIdToCheck)
                extinguishedFires[fireIdToCheck] = true
                firesExtinguished = firesExtinguished + 1
            else
                ExtinguishFireSilent(fireIdToCheck)
            end
        end
    end
    
    for object, objectData in pairs(burningObjects) do
        if #(fireCoords - objectData.coords) <= radius then
            for _, fireHandle in ipairs(objectData.fireHandles) do
                if objectData.isVfx then
                    StopParticleFxLooped(fireHandle, false)
                else
                    RemoveScriptFire(fireHandle)
                end
            end
            burningObjects[object] = nil
        end
    end
    
    local currentTime = GetGameTimer()
    if firesExtinguished > 0 and (currentTime - lastExtinguishNotification) > EXTINGUISH_NOTIFICATION_COOLDOWN then
        lastExtinguishNotification = currentTime
        TriggerServerEvent('fire:server:broadcastExtinguished', fireCoords, nil, false)
    end
end

-- =============================================
-- OBJECT FIRE SYSTEM
-- =============================================
local function GetObjectFirePoints(object, objectHash)
    local objectCoords = GetEntityCoords(object)
    local firePoints = {}
    
    local objConfig = FlammableObjects[objectHash] or { firePoints = 4, intensity = 10.0, explosionDamage = 1.0 }
    local numPoints = objConfig.firePoints or 4
    
    for i = 1, numPoints do
        local angle = (360 / numPoints) * i
        local radius = 1.0 + (math.random() * 2.0)
        local height = -0.5 + (math.random() * 2.5)
        
        local firePoint = vector3(
            objectCoords.x + math.cos(math.rad(angle)) * radius,
            objectCoords.y + math.sin(math.rad(angle)) * radius,
            objectCoords.z + height
        )
        
        table.insert(firePoints, firePoint)
    end
    
    table.insert(firePoints, vector3(objectCoords.x, objectCoords.y, objectCoords.z + 2.0))
    table.insert(firePoints, vector3(objectCoords.x + 1.0, objectCoords.y, objectCoords.z + 1.5))
    table.insert(firePoints, vector3(objectCoords.x - 1.0, objectCoords.y, objectCoords.z + 1.5))
    
    return firePoints
end

local function SetObjectOnFire(object, objectHash, sourceFireIntensity, notifyPlayers)
    if not DoesEntityExist(object) then return false end
    if burningObjects[object] then return false end
    if TableCount(burningObjects) >= Config.FireSpread.MaxBurningObjects then return false end
    
    local objConfig = FlammableObjects[objectHash] or {
        name = "Unknown Object",
        burnTime = 60000,
        intensity = 10.0,
        firePoints = 4,
        explosionDamage = 1.0
    }
    
    local objectCoords = GetEntityCoords(object)
    local firePoints = GetObjectFirePoints(object, objectHash)
    local fireHandles = {}
    local isVfx = false
    
    AddExplosion(objectCoords.x, objectCoords.y, objectCoords.z + 1.0, 5, objConfig.explosionDamage, true, false, 3.0, false)
    
    for _, firePoint in ipairs(firePoints) do
        local fireIntensity = math.min(objConfig.intensity, (sourceFireIntensity or 10) * 1.2)
        local fireHandle = StartScriptFire(firePoint.x, firePoint.y, firePoint.z, fireIntensity, false)
        
        if fireHandle and fireHandle ~= 0 then
            table.insert(fireHandles, fireHandle)
        else
            RequestNamedPtfxAsset('scr_ind1')
            local timeout = 0
            while not HasNamedPtfxAssetLoaded('scr_ind1') and timeout < 3000 do
                Wait(50)
                timeout = timeout + 50
            end
            
            if HasNamedPtfxAssetLoaded('scr_ind1') then
                local particle = StartParticleFxLoopedAtCoord('scr_ind1_fire', firePoint.x, firePoint.y, firePoint.z, 0.0, 0.0, 0.0, 2.5, false, false, false)
                if particle then
                    table.insert(fireHandles, particle)
                    isVfx = true
                end
            end
        end
    end
    
    if #fireHandles == 0 then
        return false
    end
    
    local objectFireId = GenerateFireId()
    
    burningObjects[object] = {
        id = objectFireId,
        objectHash = objectHash,
        objectName = objConfig.name,
        coords = objectCoords,
        fireHandles = fireHandles,
        intensity = objConfig.intensity,
        startTime = GetGameTimer(),
        burnTime = objConfig.burnTime,
        isVfx = isVfx
    }
    
    if notifyPlayers ~= false then
        TriggerServerEvent('fire:server:broadcastObjectFire', objectCoords, objConfig.name, objectFireId)
    end
    
    SetTimeout(objConfig.burnTime, function()
        if burningObjects[object] then
            for _, fireHandle in ipairs(burningObjects[object].fireHandles) do
                if burningObjects[object].isVfx then
                    StopParticleFxLooped(fireHandle, false)
                else
                    RemoveScriptFire(fireHandle)
                end
            end
            
            AddExplosion(objectCoords.x, objectCoords.y, objectCoords.z, 5, objConfig.explosionDamage * 0.8, true, false, 2.5, false)
            
            if DoesEntityExist(object) then
                SetEntityAlpha(object, 100, false)
                SetEntityHealth(object, 0)
                
                SetTimeout(5000, function()
                    if DoesEntityExist(object) then
                        SetEntityAsNoLongerNeeded(object)
                        DeleteEntity(object)
                    end
                end)
            end
            
            burningObjects[object] = nil
        end
    end)
    
    return true
end

-- =============================================
-- FIRE SPREAD SYSTEM
-- =============================================
local function CheckObjectsNearFire(fireCoords, fireIntensity)
    if not Config.FireSpread.Enabled then return end
    if fireIntensity < Config.FireSpread.MinIgnitionIntensity then return end
    
    local objects = {}
    local handle, object = FindFirstObject()
    local finished = false
    
    repeat
        if DoesEntityExist(object) then
            local objectCoords = GetEntityCoords(object)
            local distance = #(fireCoords - objectCoords)
            
            if distance <= Config.FireSpread.SpreadRadius then
                local objectHash = GetEntityModel(object)
                if FlammableObjects[objectHash] and not burningObjects[object] then
                    table.insert(objects, {entity = object, hash = objectHash, distance = distance})
                end
            end
        end
        finished, object = FindNextObject(handle)
    until not finished
    
    EndFindObject(handle)
    
    for _, objData in ipairs(objects) do
        if objData.distance <= Config.FireSpread.IgnitionRadius then
            if math.random() <= Config.FireSpread.SpreadChance then
                SetObjectOnFire(objData.entity, objData.hash, fireIntensity, true)
            end
        end
    end
    
    if TableCount(activeFires) < Config.FireSpread.MaxTotalFires then
        for i = 1, 3 do
            if math.random() <= Config.FireSpread.GroundSpreadChance then
                local angle = math.random() * 360
                local distance = 1.0 + (math.random() * (Config.FireSpread.GroundSpreadRadius - 1.0))
                local newFireCoords = vector3(
                    fireCoords.x + math.cos(math.rad(angle)) * distance,
                    fireCoords.y + math.sin(math.rad(angle)) * distance,
                    fireCoords.z
                )
                
                local foundGround, groundZ = GetGroundZFor_3dCoord(newFireCoords.x, newFireCoords.y, newFireCoords.z + 1.0, false)
                if foundGround then
                    newFireCoords = vector3(newFireCoords.x, newFireCoords.y, groundZ + 0.2)
                    CreateFire(newFireCoords, false, nil)
                end
            end
        end
    end
end

-- =============================================
-- MAIN FIRE CREATION - BALANCED & RELIABLE
-- =============================================
function CreateFire(coords, notifyPlayers, serverFireId)
    if TableCount(activeFires) >= Config.FireSpread.MaxTotalFires then
        return nil
    end
    
    local currentFireId = serverFireId or GenerateFireId()
    
    if activeFires[currentFireId] then
        return currentFireId
    end
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    local fireCoords = foundGround and vector3(coords.x, coords.y, groundZ + 0.2) or vector3(coords.x, coords.y, coords.z + 0.5)
    
    local fireHandles = {}
    local particleHandles = {}
    local isVfx = false
    local maxIntensity = Config.MaxFireIntensity or 15
    
    -- Function to spawn fire points
    local function SpawnFirePoints()
        local handles = {}
        
        -- CENTER FIRE (1)
        local mainFire = StartScriptFire(fireCoords.x, fireCoords.y, fireCoords.z, maxIntensity, false)
        if mainFire and mainFire ~= 0 then
            table.insert(handles, mainFire)
        end
        
        -- INNER RING - 4 fires
        for i = 1, 4 do
            local angle = (360 / 4) * i
            local distance = 1.5
            local innerCoords = vector3(
                fireCoords.x + math.cos(math.rad(angle)) * distance,
                fireCoords.y + math.sin(math.rad(angle)) * distance,
                fireCoords.z
            )
            local innerFire = StartScriptFire(innerCoords.x, innerCoords.y, innerCoords.z, maxIntensity, false)
            if innerFire and innerFire ~= 0 then
                table.insert(handles, innerFire)
            end
        end
        
        -- OUTER RING - 6 fires
        for i = 1, 6 do
            local angle = (360 / 6) * i + 30
            local distance = 3.0
            local outerCoords = vector3(
                fireCoords.x + math.cos(math.rad(angle)) * distance,
                fireCoords.y + math.sin(math.rad(angle)) * distance,
                fireCoords.z
            )
            local outerFire = StartScriptFire(outerCoords.x, outerCoords.y, outerCoords.z, maxIntensity * 0.8, false)
            if outerFire and outerFire ~= 0 then
                table.insert(handles, outerFire)
            end
        end
        
        -- VERTICAL - 2 layers, 2 fires each
        for layer = 1, 2 do
            local layerZ = fireCoords.z + (layer * 1.5)
            for i = 1, 2 do
                local angle = (180 * i) + (layer * 45)
                local layerCoords = vector3(
                    fireCoords.x + math.cos(math.rad(angle)) * 1.0,
                    fireCoords.y + math.sin(math.rad(angle)) * 1.0,
                    layerZ
                )
                local layerFire = StartScriptFire(layerCoords.x, layerCoords.y, layerCoords.z, maxIntensity * 0.7, false)
                if layerFire and layerFire ~= 0 then
                    table.insert(handles, layerFire)
                end
            end
        end
        
        return handles
    end
    
    -- Function to spawn particles
    local function SpawnParticles()
        local particles = {}
        
        RequestNamedPtfxAsset('scr_ind1')
        local timeout = 0
        while not HasNamedPtfxAssetLoaded('scr_ind1') and timeout < 3000 do
            Wait(100)
            timeout = timeout + 100
        end
        
        if HasNamedPtfxAssetLoaded('scr_ind1') then
            -- 2 smoke columns
            for i = 1, 2 do
                local smokeCoords = vector3(
                    fireCoords.x + math.random(-1, 1),
                    fireCoords.y + math.random(-1, 1),
                    fireCoords.z + 3
                )
                local smoke = StartParticleFxLoopedAtCoord('scr_ind1_fire', smokeCoords.x, smokeCoords.y, smokeCoords.z, 0.0, 0.0, 0.0, 2.5, false, false, false)
                if smoke then
                    table.insert(particles, smoke)
                end
            end
            
            -- 3 ground flames
            for i = 1, 3 do
                local groundCoords = vector3(
                    fireCoords.x + math.random(-2, 2),
                    fireCoords.y + math.random(-2, 2),
                    fireCoords.z
                )
                local ground = StartParticleFxLoopedAtCoord('scr_ind1_fire', groundCoords.x, groundCoords.y, groundCoords.z, 0.0, 0.0, 0.0, 2.0, false, false, false)
                if ground then
                    table.insert(particles, ground)
                end
            end
        end
        
        return particles
    end
    
    -- Spawn fires and particles
    fireHandles = SpawnFirePoints()
    particleHandles = SpawnParticles()
    
    if #fireHandles > 0 then
        isVfx = #particleHandles > 0
    end
    
    if #fireHandles == 0 then
        return nil
    end
    
    activeFires[currentFireId] = {
        id = currentFireId,
        coords = fireCoords,
        fireHandles = fireHandles,
        particleHandles = particleHandles,
        isVfx = isVfx,
        startTime = GetGameTimer(),
        intensity = maxIntensity,
        isActive = true
    }
    
    if notifyPlayers ~= false then
        TriggerServerEvent('fire:server:broadcastFire', fireCoords, 'ground', currentFireId)
    end
    
    CheckObjectsNearFire(fireCoords, maxIntensity)
    
    -- FIRE MAINTENANCE THREAD
    CreateThread(function()
        local refreshInterval = 15000 -- Refresh every 15 seconds
        local startTime = GetGameTimer()
        local duration = Config.FireDuration or 1200000
        
        while activeFires[currentFireId] and activeFires[currentFireId].isActive do
            Wait(refreshInterval)
            
            if not activeFires[currentFireId] then
                break
            end
            
            local elapsed = GetGameTimer() - startTime
            if elapsed >= duration then
                ExtinguishFire(currentFireId, false)
                break
            end
            
            local fireData = activeFires[currentFireId]
            if fireData then
                -- Remove old fires
                for _, handle in ipairs(fireData.fireHandles) do
                    if handle and handle ~= 0 then
                        RemoveScriptFire(handle)
                    end
                end
                
                -- Respawn fires
                local newHandles = SpawnFirePoints()
                activeFires[currentFireId].fireHandles = newHandles
            end
        end
    end)
    
    -- Fire spread
    if Config.FireSpread.Enabled then
        SetTimeout(Config.FireSpread.SpreadInterval, function()
            local function spreadTimer()
                if activeFires[currentFireId] and activeFires[currentFireId].isActive then
                    CheckObjectsNearFire(activeFires[currentFireId].coords, activeFires[currentFireId].intensity)
                    SetTimeout(Config.FireSpread.SpreadInterval, spreadTimer)
                end
            end
            spreadTimer()
        end)
    end
    
    return currentFireId
end



-- =============================================
-- FIRE EXTINGUISHING
-- =============================================
local function GetNearestFire(coords)
    local nearestFire = nil
    local nearestDistance = Config.ExtinguishDistance
    
    for id, fireData in pairs(activeFires) do
        local distance = #(coords - fireData.coords)
        if distance < nearestDistance then
            nearestDistance = distance
            nearestFire = { id = id, data = fireData, distance = distance }
        end
    end
    
    return nearestFire
end

function ExtinguishFire(fireIdToExtinguish, notifyServer)
    if not activeFires[fireIdToExtinguish] then
        return false
    end
    
    local fireData = activeFires[fireIdToExtinguish]
    
    -- Mark as inactive to stop maintenance thread
    fireData.isActive = false
    
    -- Remove all fire handles
    if fireData.fireHandles then
        for _, fireHandle in ipairs(fireData.fireHandles) do
            if fireHandle and fireHandle ~= 0 then
                if fireData.isVfx then
                    StopParticleFxLooped(fireHandle, false)
                else
                    RemoveScriptFire(fireHandle)
                end
            end
        end
    end
    
    -- Remove particle handles specifically
    if fireData.particleHandles then
        for _, particle in ipairs(fireData.particleHandles) do
            if particle and particle ~= 0 then
                StopParticleFxLooped(particle, false)
            end
        end
    end
    
    -- Also extinguish any native fires in the area
    Citizen.InvokeNative(0xDB38F247BD421708, fireData.coords.x, fireData.coords.y, fireData.coords.z, 15.0)
    
    RemoveFireBlip(fireIdToExtinguish)
    
    if notifyServer ~= false then
        local currentTime = GetGameTimer()
        if (currentTime - lastExtinguishNotification) > EXTINGUISH_NOTIFICATION_COOLDOWN then
            lastExtinguishNotification = currentTime
            TriggerServerEvent('fire:server:broadcastExtinguished', fireData.coords, fireIdToExtinguish, false)
        end
    end
    
    activeFires[fireIdToExtinguish] = nil
    extinguishedFires[fireIdToExtinguish] = true
    
    return true
end

-- =============================================
-- PLACEABLE ITEMS SYSTEM
-- =============================================
local function SpawnProp(propName, coords)
    local propHash = GetHashKey(propName)
    
    RequestModel(propHash)
    local timeout = 0
    while not HasModelLoaded(propHash) and timeout < 5000 do
        Wait(100)
        timeout = timeout + 100
    end
    
    if not HasModelLoaded(propHash) then
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'Failed to load prop model: ' .. propName,
            type = 'error',
            duration = 3000
        })
        return nil
    end
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if foundGround then
        coords = vector3(coords.x, coords.y, groundZ)
    end
    
    local prop = CreateObject(propHash, coords.x, coords.y, coords.z, true, true, false)
    
    if prop and prop ~= 0 and DoesEntityExist(prop) then
        PlaceObjectOnGroundProperly(prop)
        FreezeEntityPosition(prop, true)
        SetEntityAsMissionEntity(prop, true, true)
        return prop
    else
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'Failed to create prop object',
            type = 'error',
            duration = 3000
        })
        return nil
    end
end

local function SetupItemInteractions(prop, itemData)
    if not DoesEntityExist(prop) then return end
    if not exports['ox_target'] then return end
    
    local itemConfig = Config.PlaceableItems[itemData.itemType]
    local useIcon = itemData.itemType == 'explosivesbox' and 'fas fa-bomb' or 'fas fa-hand-holding-water'
    local useLabel = itemData.itemType == 'explosivesbox' and 'Detonate ' or 'Use '
    local targetName = string.format('use_%s_%s_%s', itemData.itemType, itemData.id, tostring(prop))
    
    local options = {
        {
            name = targetName,
            icon = useIcon,
            label = useLabel .. itemConfig.label,
            onSelect = function() UseFloorItemWithAnimation(itemData) end,
            distance = itemConfig.interactDistance
        }
    }
    
    if itemConfig.canPickup then
        table.insert(options, {
            name = string.format('pickup_%s_%s_%s', itemData.itemType, itemData.id, tostring(prop)),
            icon = 'fas fa-hand-paper',
            label = 'Pick Up ' .. itemConfig.label,
            onSelect = function() PickUpItem(itemData) end,
            distance = itemConfig.interactDistance
        })
    end
    
    exports['ox_target']:addLocalEntity(prop, options)
end

local function PlaceItemOnGround(itemName)
    if not Config.PlaceableItems[itemName] then return end
    if isPlacingItem then return end
    isPlacingItem = true

    local ped = PlayerPedId()
    
    lib.notify({
        title = 'Placing Item',
        description = 'Placing ' .. Config.PlaceableItems[itemName].label .. '...',
        type = 'inform'
    })
    
    Wait(Config.CrouchAnimationDuration)
    ClearPedTasks(ped)

    local coords = GetEntityCoords(ped)
    local forwardVector = GetEntityForwardVector(ped)
    local placeCoords = coords + forwardVector * 1.5
    local prop = SpawnProp(Config.PlaceableItems[itemName].prop, placeCoords)

    if prop then
        local itemData = {
            prop = prop,
            itemType = itemName,
            coords = placeCoords,
            id = #placedItems + 1
        }
        table.insert(placedItems, itemData)
        SetupItemInteractions(prop, itemData)
        
        lib.notify({
            title = 'Item Placed',
            description = 'You placed a ' .. Config.PlaceableItems[itemName].label,
            type = 'success'
        })
    else
        lib.notify({
            title = 'Error',
            description = 'Failed to place ' .. Config.PlaceableItems[itemName].label,
            type = 'error'
        })
    end
    isPlacingItem = false
end

function PickUpItem(itemData)
    if DoesEntityExist(itemData.prop) then
        exports['ox_target']:removeLocalEntity(itemData.prop)
        DeleteEntity(itemData.prop)
        
        for i, item in ipairs(placedItems) do
            if item.id == itemData.id then
                table.remove(placedItems, i)
                break
            end
        end
        
        local itemConfig = Config.PlaceableItems[itemData.itemType]
        local giveBack = itemConfig and itemConfig.returnOnPickup or false
        
        TriggerServerEvent('fire:server:pickupItem', itemData.itemType, giveBack)
    end
end

function UseFloorItemWithAnimation(itemData)
    local ped = PlayerPedId()
    local animConfig = Config.PlaceableItems[itemData.itemType].animation
    
    RequestAnimDict(animConfig.dict)
    while not HasAnimDictLoaded(animConfig.dict) do
        Wait(0)
    end
    
    TaskPlayAnim(ped, animConfig.dict, animConfig.clip, 8.0, -8.0, 5000, 1, 0, false, false, false)
    
    lib.notify({
        title = 'Using ' .. Config.PlaceableItems[itemData.itemType].label,
        description = 'Activating...',
        type = 'inform'
    })
    
    Citizen.SetTimeout(1500, function()
        local ex = Config.PlaceableItems[itemData.itemType].explosion
        local coords = GetEntityCoords(itemData.prop)
        local explosionCoords = vector3(
            coords.x + ex.offset.x,
            coords.y + ex.offset.y,
            coords.z + ex.offset.z
        )
        
        if itemData.itemType == 'explosivesbox' then
            lib.notify({
                title = 'EXPLOSIVES ARMED',
                description = 'Timer activated! Take cover!',
                type = 'error'
            })
            
            TriggerServerEvent('fire:server:explosionTriggered', coords)
            
            Citizen.SetTimeout(ex.timer or 15000, function()
                if DoesEntityExist(itemData.prop) then
                    AddExplosion(explosionCoords.x, explosionCoords.y, explosionCoords.z, ex.id, ex.damage or 2.0, true, false, 1.0)
                    
                    CreateFire(explosionCoords, true, nil)
                    
                    if DoesEntityExist(itemData.prop) then
                        exports['ox_target']:removeLocalEntity(itemData.prop)
                        DeleteEntity(itemData.prop)
                    end
                    
                    for i, item in ipairs(placedItems) do
                        if item.id == itemData.id then
                            table.remove(placedItems, i)
                            break
                        end
                    end
                end
            end)
        else
            TriggerServerEvent('fire:server:hydrantUsed', coords)
            
            local startTime = GetGameTimer()
            Citizen.CreateThread(function()
                while GetGameTimer() - startTime < ex.duration do
                    if DoesEntityExist(itemData.prop) then
                        AddExplosion(explosionCoords.x, explosionCoords.y, explosionCoords.z, ex.id, 1.5, true, false, 0.0)
                        ExtinguishFiresInRange(explosionCoords.x, explosionCoords.y, explosionCoords.z, ex.radius)
                    else
                        break
                    end
                    Wait(ex.interval)
                end
                
                if Config.PlaceableItems[itemData.itemType].singleUse then
                    if DoesEntityExist(itemData.prop) then
                        exports['ox_target']:removeLocalEntity(itemData.prop)
                        DeleteEntity(itemData.prop)
                    end
                    
                    for i, item in ipairs(placedItems) do
                        if item.id == itemData.id then
                            table.remove(placedItems, i)
                            break
                        end
                    end
                    
                    lib.notify({
                        title = 'Item Used',
                        description = 'The ' .. Config.PlaceableItems[itemData.itemType].label .. ' is empty.',
                        type = 'inform'
                    })
                end
            end)
        end
    end)
end

-- =============================================
-- HOSE SYSTEM
-- =============================================
local isHoseActive = false
local hoseThread = nil
local attachedCart = nil
local syncedHoses = {}

local HoseConfig = {
    waterExplosionType = 10,
    extinguishRange = 25.0,
    extinguishRadius = 10.0,
    sprayInterval = 300,
    startDistance = 3.0,
    maxCartDistance = 30.0,
    cartOffsetX = 0.0,
    cartOffsetY = 0.0,
    cartOffsetZ = 0.8,
    hoseThickness = 15,
    hoseSpread = 0.02,
    hoseColorR = 139,
    hoseColorG = 0,
    hoseColorB = 0,
    hoseAlpha = 255,
    hoseSag = 0.8,
}

local BoneIDs = {
    r_hand = 22798,
}

local cachedPlayerPed = nil
local cachedHandBoneIndex = nil

local function IsFirefighterForHose()
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then
        return false
    end
    local requiredJob = Config.FirefighterJob and Config.FirefighterJob.JobName or 'firefighter'
    return PlayerData.job.name == requiredJob
end

local function FindNearbyFireCart()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local cartHash = GetHashKey('cart05')
    
    local handle, vehicle = FindFirstVehicle()
    local success = true
    local nearestCart = nil
    local nearestDist = HoseConfig.maxCartDistance
    
    repeat
        if DoesEntityExist(vehicle) then
            if GetEntityModel(vehicle) == cartHash then
                local dist = #(playerCoords - GetEntityCoords(vehicle))
                if dist < nearestDist then
                    nearestDist = dist
                    nearestCart = vehicle
                end
            end
        end
        success, vehicle = FindNextVehicle(handle)
    until not success
    EndFindVehicle(handle)
    
    return nearestCart
end

local function GetHandCoords()
    local ped = PlayerPedId()
    
    if ped ~= cachedPlayerPed then
        cachedPlayerPed = ped
        cachedHandBoneIndex = GetPedBoneIndex(ped, BoneIDs.r_hand)
    end
    
    if cachedHandBoneIndex and cachedHandBoneIndex ~= -1 then
        return GetWorldPositionOfEntityBone(ped, cachedHandBoneIndex)
    end
    return GetEntityCoords(ped)
end

local function GetGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    return found and groundZ or (z - 1.0)
end

local function GetCartAttachPoint(cart)
    return GetOffsetFromEntityInWorldCoords(
        cart,
        HoseConfig.cartOffsetX,
        HoseConfig.cartOffsetY,
        HoseConfig.cartOffsetZ
    )
end

local function DrawThickHose(startPos, endPos)
    local spread = HoseConfig.hoseSpread
    local thickness = HoseConfig.hoseThickness
    local dirX = endPos.x - startPos.x
    local dirY = endPos.y - startPos.y
    local dirZ = endPos.z - startPos.z
    local sagAmount = HoseConfig.hoseSag
    local segments = 8
    local r, g, b, a = HoseConfig.hoseColorR, HoseConfig.hoseColorG, HoseConfig.hoseColorB, HoseConfig.hoseAlpha
    
    for i = 1, thickness do
        local angle = (i / thickness) * 6.283185
        local offsetX = math.cos(angle) * spread
        local offsetY = math.sin(angle) * spread
        local offsetZ = math.sin(angle) * spread * 0.5
        
        for seg = 1, segments do
            local t1 = (seg - 1) / segments
            local t2 = seg / segments
            
            local sag1 = math.sin(t1 * 3.141593) * sagAmount
            local sag2 = math.sin(t2 * 3.141593) * sagAmount
            
            DrawLine(
                startPos.x + dirX * t1 + offsetX,
                startPos.y + dirY * t1 + offsetY,
                startPos.z + dirZ * t1 - sag1 + offsetZ,
                startPos.x + dirX * t2 + offsetX,
                startPos.y + dirY * t2 + offsetY,
                startPos.z + dirZ * t2 - sag2 + offsetZ,
                r, g, b, a
            )
        end
    end
end

local function SprayWater()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    local headingRad = math.rad(heading)
    
    local forwardX = -math.sin(headingRad)
    local forwardY = math.cos(headingRad)
    local rightX = math.cos(headingRad)
    local rightY = math.sin(headingRad)
    
    local playerZ = playerCoords.z
    local spreadWidth = 0.8
    
    for sprayDist = HoseConfig.startDistance, HoseConfig.extinguishRange, 2.5 do
        local centerX = playerCoords.x + forwardX * sprayDist
        local centerY = playerCoords.y + forwardY * sprayDist
        local groundZ = GetGroundZ(centerX, centerY, playerZ) + 0.15
        
        local leftX = centerX - rightX * spreadWidth
        local leftY = centerY - rightY * spreadWidth
        AddExplosion(leftX, leftY, GetGroundZ(leftX, leftY, playerZ) + 0.15, HoseConfig.waterExplosionType, 1.5, true, false, 0.0)
        
        AddExplosion(centerX, centerY, groundZ, HoseConfig.waterExplosionType, 1.5, true, false, 0.0)
        
        local rightPosX = centerX + rightX * spreadWidth
        local rightPosY = centerY + rightY * spreadWidth
        AddExplosion(rightPosX, rightPosY, GetGroundZ(rightPosX, rightPosY, playerZ) + 0.15, HoseConfig.waterExplosionType, 1.5, true, false, 0.0)
        
        ExtinguishFiresInRange(centerX, centerY, groundZ, HoseConfig.extinguishRadius)
        Citizen.InvokeNative(0xDB38F247BD421708, centerX, centerY, groundZ, HoseConfig.extinguishRadius)
    end
end

local StopHose

local function StartHose()
    if isHoseActive then return end
    
    if not IsFirefighterForHose() then
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'Only firefighters can use the fire hose!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local cart = FindNearbyFireCart()
    
    if not cart then
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'No fire cart nearby!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    attachedCart = cart
    isHoseActive = true
    cachedPlayerPed = nil
    cachedHandBoneIndex = nil
    
    SetEntityInvincible(PlayerPedId(), true)
    
    TriggerServerEvent('hose:server:startHose', NetworkGetNetworkIdFromEntity(cart))
    
    TriggerEvent('ox_lib:notify', {
        title = 'Fire Hose Active',
        description = 'Spraying water! /hose to stop.',
        type = 'success',
        duration = 4000
    })
    
    CreateThread(function()
        while isHoseActive do
            if attachedCart and DoesEntityExist(attachedCart) then
                DrawThickHose(GetCartAttachPoint(attachedCart), GetHandCoords())
            end
            Wait(0)
        end
    end)
    
    hoseThread = CreateThread(function()
        local lastSpray = 0
        
        while isHoseActive do
            local playerPed = PlayerPedId()
            local currentTime = GetGameTimer()
            
            SetEntityInvincible(playerPed, true)
            
            if IsPedDeadOrDying(playerPed, true) or IsPedInAnyVehicle(playerPed, false) then
                StopHose()
                break
            end
            
            if not attachedCart or not DoesEntityExist(attachedCart) then
                StopHose()
                break
            end
            
            local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(attachedCart))
            
            if dist > HoseConfig.maxCartDistance then
                TriggerEvent('ox_lib:notify', {
                    title = 'Hose Disconnected',
                    description = 'Too far from fire cart!',
                    type = 'error',
                    duration = 3000
                })
                StopHose()
                break
            end
            
            if currentTime - lastSpray > HoseConfig.sprayInterval then
                SprayWater()
                lastSpray = currentTime
            end
            
            Wait(0)
        end
    end)
end

StopHose = function()
    if not isHoseActive then return end
    
    isHoseActive = false
    attachedCart = nil
    cachedPlayerPed = nil
    cachedHandBoneIndex = nil
    
    SetEntityInvincible(PlayerPedId(), false)
    
    TriggerServerEvent('hose:server:stopHose')
    
    TriggerEvent('ox_lib:notify', {
        title = 'Hose Deactivated',
        description = 'Hose stopped',
        type = 'info',
        duration = 2000
    })
end

local function ToggleHose()
    if isHoseActive then
        StopHose()
    else
        StartHose()
    end
end

RegisterNetEvent('hose:client:syncHose', function(playerId, cartNetId, isActive)
    if playerId == GetPlayerServerId(PlayerId()) then return end
    
    if isActive and cartNetId then
        syncedHoses[playerId] = {
            cartNetId = cartNetId,
            active = true
        }
    else
        syncedHoses[playerId] = nil
    end
end)

CreateThread(function()
    while true do
        for playerId, hoseData in pairs(syncedHoses) do
            if hoseData.active then
                local cart = NetworkGetEntityFromNetworkId(hoseData.cartNetId)
                local playerServerId = playerId
                
                local targetPed = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == playerServerId then
                        targetPed = GetPlayerPed(player)
                        break
                    end
                end
                
                if targetPed and DoesEntityExist(targetPed) and cart and DoesEntityExist(cart) then
                    local cartAttachPoint = GetOffsetFromEntityInWorldCoords(cart, HoseConfig.cartOffsetX, HoseConfig.cartOffsetY, HoseConfig.cartOffsetZ)
                    local boneIndex = GetPedBoneIndex(targetPed, BoneIDs.r_hand)
                    local handCoords
                    
                    if boneIndex and boneIndex ~= -1 then
                        handCoords = GetWorldPositionOfEntityBone(targetPed, boneIndex)
                    else
                        handCoords = GetEntityCoords(targetPed)
                    end
                    
                    DrawThickHose(cartAttachPoint, handCoords)
                else
                    syncedHoses[playerId] = nil
                end
            end
        end
        Wait(0)
    end
end)

RegisterCommand('hose', function()
    ToggleHose()
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if isHoseActive then
            StopHose()
        end
        syncedHoses = {}
    end
end)

exports('toggleHose', ToggleHose)
exports('startHose', StartHose)
exports('stopHose', StopHose)
exports('isHoseActive', function() return isHoseActive end)

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('hose:server:requestSync')
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('hose:server:requestSync')
end)

-- =============================================
-- FIRE CART SYSTEM
-- =============================================
local function TriggerVehicleWaterSpray(vehicle, waterConfig)
    if not DoesEntityExist(vehicle) then return end
    
    local startTime = GetGameTimer()

    Citizen.CreateThread(function()
        while GetGameTimer() - startTime < waterConfig.duration do
            if DoesEntityExist(vehicle) then
                local sprayCoords = GetOffsetFromEntityInWorldCoords(vehicle, waterConfig.offset.x, waterConfig.offset.y, waterConfig.offset.z)
                AddExplosion(sprayCoords.x, sprayCoords.y, sprayCoords.z, waterConfig.id, 1.5, true, false, 0.0)
                ExtinguishFiresInRange(sprayCoords.x, sprayCoords.y, sprayCoords.z, waterConfig.radius)
            else
                break
            end
            Wait(waterConfig.interval)
        end
        
        lib.notify({
            title = 'Fire Cart',
            description = 'Water spray system deactivated',
            type = 'inform'
        })
    end)
end

function UseFireCart(vehicle)
    if not DoesEntityExist(vehicle) then
        lib.notify({
            title = 'Error',
            description = 'Vehicle no longer exists',
            type = 'error'
        })
        return
    end
    
    local ped = PlayerPedId()
    local vehicleConfig = Config.FireVehicles['cart05']
    
    RequestAnimDict(vehicleConfig.animation.dict)
    while not HasAnimDictLoaded(vehicleConfig.animation.dict) do
        Wait(0)
    end
    
    TaskPlayAnim(ped, vehicleConfig.animation.dict, vehicleConfig.animation.clip, 8.0, -8.0, vehicleConfig.animation.duration, 1, 0, false, false, false)
    
    lib.notify({
        title = 'Fire Cart Activated',
        description = 'Water spray system engaged!',
        type = 'success'
    })
    
    Citizen.SetTimeout(1500, function()
        TriggerVehicleWaterSpray(vehicle, vehicleConfig.waterEffect)
    end)
end

local function AddVehicleTarget(vehicle)
    if not DoesEntityExist(vehicle) then return end
    if trackedVehicles[vehicle] then return end
    
    local vehicleConfig = Config.FireVehicles['cart05']
    local targetName = string.format('use_fire_cart_%s', vehicle)
    
    exports['ox_target']:addLocalEntity(vehicle, {
        {
            name = targetName,
            icon = 'fas fa-fire-extinguisher',
            label = 'Use ' .. vehicleConfig.label,
            onSelect = function() UseFireCart(vehicle) end,
            distance = vehicleConfig.interactDistance
        }
    })
    
    trackedVehicles[vehicle] = true
end

Citizen.CreateThread(function()
    Wait(2000)
    
    local cart05Hash = GetHashKey('cart05')
    
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local vehicles = GetNearbyVehicles(playerCoords, 50.0, 20)
        
        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) and not trackedVehicles[vehicle] then
                local modelHash = GetEntityModel(vehicle)
                
                if modelHash == cart05Hash then
                    AddVehicleTarget(vehicle)
                end
            end
        end
        
        for veh, _ in pairs(trackedVehicles) do
            if not DoesEntityExist(veh) then
                trackedVehicles[veh] = nil
            end
        end
        
        Wait(1000)
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(60000)
        extinguishedFires = {}
    end
end)

-- =============================================
-- NOTIFICATION HANDLERS
-- =============================================
RegisterNetEvent('fire:client:fireNotification', function(data)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - data.coords)
    
    if Config.NotifyRadius > 0 and distance > Config.NotifyRadius then
        return
    end
    
    if data.createBlip and Config.AddGPSRoute then
        CreateFireBlip(data.coords, data.area or "Fire", data.fireId)
    end
    
    if IsFirefighter() and data.fireId then
        SetFireWaypoint(data.coords, "Fire Location")
    end
    
    local distanceText = Config.ShowDistance and (" Distance: " .. GetDistanceText(distance)) or ""
    local starterText = data.starterName and (data.starterName .. " started a fire!") or "A fire has started!"
    
    TriggerEvent('ox_lib:notify', {
        title = 'FIRE STARTED!',
        description = starterText .. distanceText,
        type = 'error',
        duration = 8000,
        position = 'top'
    })
    
    ApplyScreenEffect(distance)
    PlaySoundFrontend("CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true, 1)
end)

RegisterNetEvent('fire:client:objectFireNotification', function(data)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - data.coords)
    
    if Config.NotifyRadius > 0 and distance > Config.NotifyRadius then
        return
    end
    
    if Config.AddGPSRoute then
        CreateFireBlip(data.coords, data.objectType or "Structure Fire", data.fireId)
    end
    
    if IsFirefighter() and data.fireId then
        SetFireWaypoint(data.coords, "Structure Fire")
    end
    
    local distanceText = Config.ShowDistance and (" Distance: " .. GetDistanceText(distance)) or ""
    
    TriggerEvent('ox_lib:notify', {
        title = 'STRUCTURE FIRE!',
        description = string.format('A %s is on fire and may explode!%s',
            data.objectType or 'structure',
            distanceText
        ),
        type = 'error',
        duration = 10000,
        position = 'top'
    })
    
    ApplyScreenEffect(distance)
    PlaySoundFrontend("CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true, 1)
end)

RegisterNetEvent('fire:client:fireExtinguishedNotification', function(data)
    -- Remove fire from local tracking
    if data.fireId then
        -- Try direct ID match first
        if activeFires[data.fireId] then
            local fireData = activeFires[data.fireId]
            
            -- Mark as inactive
            if fireData.isActive ~= nil then
                fireData.isActive = false
            end
            
            -- Remove fire handles
            if fireData.fireHandles then
                for _, fireHandle in ipairs(fireData.fireHandles) do
                    if fireHandle and fireHandle ~= 0 then
                        if fireData.isVfx then
                            StopParticleFxLooped(fireHandle, false)
                            RemoveParticleFx(fireHandle, false)
                        else
                            RemoveScriptFire(fireHandle)
                        end
                    end
                end
            end
            
            -- Remove particle handles
            if fireData.particleHandles then
                for _, particle in ipairs(fireData.particleHandles) do
                    if particle and particle ~= 0 then
                        StopParticleFxLooped(particle, false)
                    end
                end
            end
            
            -- Extinguish native fires in area
            if fireData.coords then
                Citizen.InvokeNative(0xDB38F247BD421708, fireData.coords.x, fireData.coords.y, fireData.coords.z, 15.0)
            end
            
            activeFires[data.fireId] = nil
        end
        
        -- Remove blip by ID
        RemoveFireBlip(data.fireId)
    end
    
    -- Also try to find and remove by coordinates
    if data.coords then
        local coordsVec = vector3(data.coords.x, data.coords.y, data.coords.z)
        
        -- Remove any fires near these coordinates
        for fireIdToCheck, fireData in pairs(activeFires) do
            if fireData.coords and #(coordsVec - fireData.coords) < 50.0 then
                -- Mark as inactive
                if fireData.isActive ~= nil then
                    fireData.isActive = false
                end
                
                if fireData.fireHandles then
                    for _, fireHandle in ipairs(fireData.fireHandles) do
                        if fireHandle and fireHandle ~= 0 then
                            if fireData.isVfx then
                                StopParticleFxLooped(fireHandle, false)
                                RemoveParticleFx(fireHandle, false)
                            else
                                RemoveScriptFire(fireHandle)
                            end
                        end
                    end
                end
                
                if fireData.particleHandles then
                    for _, particle in ipairs(fireData.particleHandles) do
                        if particle and particle ~= 0 then
                            StopParticleFxLooped(particle, false)
                        end
                    end
                end
                
                RemoveFireBlip(fireIdToCheck)
                activeFires[fireIdToCheck] = nil
            end
        end
        
        -- Remove blips by coordinates
        RemoveFireBlipByCoords(data.coords, 50.0)
        
        -- Extinguish native fires in area
        Citizen.InvokeNative(0xDB38F247BD421708, data.coords.x, data.coords.y, data.coords.z, 20.0)
    end
    
    -- Clear GPS if this was the target
    if gpsActive and data.coords then
        local coordsVec = vector3(data.coords.x, data.coords.y, data.coords.z)
        if currentGPSFire and #(coordsVec - currentGPSFire) < 50.0 then
            ClearFireWaypoint()
        end
    end
    
    -- Show notification
    if data.extinguisherName then
        lib.notify({
            title = 'Fire Extinguished',
            description = data.extinguisherName .. ' put out a fire!',
            type = 'success',
            duration = 5000
        })
    end
end)

RegisterNetEvent('fire:client:hydrantNotification', function(data)
    local currentTime = GetGameTimer()
    
    if (currentTime - lastHydrantNotification) < 10000 then
        return
    end
    lastHydrantNotification = currentTime
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - data.coords)
    
    if distance > 100.0 then return end
    
    TriggerEvent('ox_lib:notify', {
        title = 'Hydrant Activated',
        description = (data.userName or 'Someone') .. ' activated a fire hydrant!',
        type = 'info',
        duration = 5000
    })
end)

RegisterNetEvent('fire:client:explosionNotification', function(data)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - data.coords)
    
    if distance > 500.0 then return end
    
    local distanceText = GetDistanceText(distance)
    
    TriggerEvent('ox_lib:notify', {
        title = 'EXPLOSION!',
        description = string.format('An explosion occurred! Distance: %s', distanceText),
        type = 'error',
        duration = 8000
    })
    
    ApplyScreenEffect(distance)
end)

RegisterNetEvent('fire:client:fireAlert', function(coords, area, alertFireId)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - coords)
    
    if Config.AddGPSRoute then
        CreateFireBlip(coords, area or "Fire", alertFireId)
    end
    
    if IsFirefighter() then
        SetFireWaypoint(coords, "Fire at " .. (area or "Unknown"))
    end
    
    -- Pass the server fire ID to CreateFire for proper sync
    local createdFireId = CreateFire(coords, false, alertFireId)
    
    TriggerEvent('ox_lib:notify', {
        title = 'FIRE ALERT!',
        description = string.format('Fire reported at %s! Distance: %s',
            area or 'Unknown Location',
            GetDistanceText(distance)
        ),
        type = 'error',
        duration = 10000,
        position = 'top'
    })
    
    PlaySoundFrontend("CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true, 1)
end)

RegisterNetEvent('fire:startFire', function()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    if GetPlayerFireCount() >= Config.MaxFires then
        TriggerEvent('ox_lib:notify', {
            title = locale('not_cl_1'),
            description = locale('not_cl_2'),
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local heading = GetEntityHeading(playerPed)
    local forwardX = math.sin(math.rad(-heading))
    local forwardY = math.cos(math.rad(-heading))
    local fireCoords = vector3(
        coords.x + forwardX * Config.FirePlaceDistance,
        coords.y + forwardY * Config.FirePlaceDistance,
        coords.z
    )
    
    if Config.UseAnimations then
        TaskStartScenarioInPlace(playerPed, GetHashKey("WORLD_HUMAN_CROUCH_INSPECT"), -1, true, "StartScenario", 0, false)
        Wait(Config.LightFireTime)
        ClearPedTasks(playerPed)
    end
    
    local createdFireId = CreateFire(fireCoords, true, nil)
    
    if createdFireId then
        TriggerEvent('ox_lib:notify', {
            title = locale('not_cl_1'),
            description = locale('not_cl_3') .. ' Fire may spread!',
            type = 'success',
            duration = 3000
        })
        
        if Config.ConsumeMatches then
            TriggerServerEvent('fire:removeItem', Config.MatchesItem, 1)
        end
    else
        TriggerEvent('ox_lib:notify', {
            title = locale('not_cl_1'),
            description = locale('not_cl_4'),
            type = 'error',
            duration = 3000
        })
    end
end)

RegisterNetEvent('fire:tryExtinguish', function()
    if isExtinguishing then return end
    
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    local nearestFire = GetNearestFire(coords)
    
    if not nearestFire then
        TriggerEvent('ox_lib:notify', {
            title = 'Fire System',
            description = 'No fire nearby to extinguish.',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    isExtinguishing = true
    
    if Config.UseAnimations then
        TaskStartScenarioInPlace(playerPed, GetHashKey("WORLD_HUMAN_CROUCH_INSPECT"), -1, true, "StartScenario", 0, false)
        Wait(Config.ExtinguishTime)
        ClearPedTasks(playerPed)
    end
    
    if ExtinguishFire(nearestFire.id, true) then
        TriggerEvent('ox_lib:notify', {
            title = 'Fire Extinguished',
            description = 'You successfully extinguished the fire!',
            type = 'success',
            duration = 3000
        })
        
        if Config.ConsumeWater then
            TriggerServerEvent('fire:removeItem', Config.WaterItem, Config.WaterAmount)
        end
    else
        TriggerEvent('ox_lib:notify', {
            title = 'Fire System',
            description = 'Failed to extinguish fire.',
            type = 'error',
            duration = 3000
        })
    end
    
    isExtinguishing = false
end)

RegisterNetEvent('fire:client:placeItem', function(itemName)
    PlaceItemOnGround(itemName)
end)

RegisterNetEvent('fire:client:setPlayerOnFire', function(coords)
    CreateFire(coords, false, nil)
end)

RegisterNetEvent('fire:admin:spawnFire', function()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    local createdFireId = CreateFire(coords, true, nil)
    
    if createdFireId then
        TriggerEvent('ox_lib:notify', {
            title = 'Admin Fire',
            description = 'Fire spawned at your location.',
            type = 'success',
            duration = 3000
        })
    end
end)

RegisterNetEvent('fire:admin:spawnEquipment', function(itemName)
    if not Config.PlaceableItems[itemName] then
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'Invalid equipment type: ' .. tostring(itemName),
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    
    local forwardX = -math.sin(math.rad(heading))
    local forwardY = math.cos(math.rad(heading))
    local spawnCoords = vector3(coords.x + forwardX * 2.0, coords.y + forwardY * 2.0, coords.z)
    
    local itemConfig = Config.PlaceableItems[itemName]
    local prop = SpawnProp(itemConfig.prop, spawnCoords)
    
    if prop and DoesEntityExist(prop) then
        local itemData = {
            prop = prop,
            itemType = itemName,
            coords = GetEntityCoords(prop),
            id = #placedItems + 1
        }
        table.insert(placedItems, itemData)
        
        SetupItemInteractions(prop, itemData)
        
        TriggerEvent('ox_lib:notify', {
            title = 'Equipment Spawned',
            description = itemConfig.label .. ' spawned at your location.',
            type = 'success',
            duration = 3000
        })
    else
        TriggerEvent('ox_lib:notify', {
            title = 'Error',
            description = 'Failed to spawn ' .. itemConfig.label,
            type = 'error',
            duration = 3000
        })
    end
end)

RegisterNetEvent('fire:client:extinguishAll', function()
    -- Clear GPS
    ClearFireWaypoint()
    
    -- Extinguish all active fires
    for fireIdToExtinguish, fireData in pairs(activeFires) do
        -- Mark as inactive
        if fireData.isActive ~= nil then
            fireData.isActive = false
        end
        
        if fireData.fireHandles then
            for _, fireHandle in ipairs(fireData.fireHandles) do
                if fireHandle and fireHandle ~= 0 then
                    if fireData.isVfx then
                        StopParticleFxLooped(fireHandle, false)
                    else
                        RemoveScriptFire(fireHandle)
                    end
                end
            end
        end
        
        if fireData.particleHandles then
            for _, particle in ipairs(fireData.particleHandles) do
                if particle and particle ~= 0 then
                    StopParticleFxLooped(particle, false)
                end
            end
        end
        
        -- Extinguish native fires
        if fireData.coords then
            Citizen.InvokeNative(0xDB38F247BD421708, fireData.coords.x, fireData.coords.y, fireData.coords.z, 20.0)
        end
    end
    
    -- Remove all burning objects
    for object, objectData in pairs(burningObjects) do
        for _, fireHandle in ipairs(objectData.fireHandles) do
            if objectData.isVfx then
                StopParticleFxLooped(fireHandle, false)
            else
                RemoveScriptFire(fireHandle)
            end
        end
    end
    
    -- Remove ALL blips
    RemoveAllFireBlips()
    
    -- Clear tables
    activeFires = {}
    burningObjects = {}
    
    TriggerEvent('ox_lib:notify', {
        title = 'Fire System',
        description = 'All fires have been extinguished.',
        type = 'success',
        duration = 3000
    })
end)

RegisterNetEvent('fire:checkActiveFires', function()
    TriggerServerEvent('fire:reportActiveFires', GetPlayerFireCount())
end)

RegisterCommand('ignite', function(source, args, rawCommand)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    local closestObject = nil
    local closestDistance = 10.0
    
    local handle, object = FindFirstObject()
    local finished = false
    
    repeat
        if DoesEntityExist(object) then
            local objectCoords = GetEntityCoords(object)
            local distance = #(coords - objectCoords)
            
            if distance < closestDistance then
                local objectHash = GetEntityModel(object)
                if FlammableObjects[objectHash] then
                    closestDistance = distance
                    closestObject = object
                end
            end
        end
        finished, object = FindNextObject(handle)
    until not finished
    
    EndFindObject(handle)
    
    if closestObject then
        local objectHash = GetEntityModel(closestObject)
        if SetObjectOnFire(closestObject, objectHash, 15.0, true) then
            TriggerEvent('ox_lib:notify', {
                title = 'Fire System',
                description = 'Object set on fire! Fire will spread!',
                type = 'success',
                duration = 3000
            })
        else
            TriggerEvent('ox_lib:notify', {
                title = 'Fire System',
                description = 'Failed to ignite object.',
                type = 'error',
                duration = 3000
            })
        end
    else
        TriggerEvent('ox_lib:notify', {
            title = 'Fire System',
            description = 'No flammable objects nearby.',
            type = 'error',
            duration = 3000
        })
    end
end, false)

-- =============================================
-- EXPORTS
-- =============================================
exports('createFire', function(coords, notify)
    return CreateFire(coords, notify, nil)
end)

exports('extinguishFire', function(fireIdToExtinguish)
    return ExtinguishFire(fireIdToExtinguish, true)
end)

exports('extinguishFiresInRange', function(x, y, z, radius)
    return ExtinguishFiresInRange(x, y, z, radius)
end)

exports('getActiveFires', function()
    return activeFires
end)

exports('getFireCount', function()
    return GetPlayerFireCount()
end)

exports('setObjectOnFire', function(object)
    if DoesEntityExist(object) then
        local objectHash = GetEntityModel(object)
        return SetObjectOnFire(object, objectHash, 15.0, true)
    end
    return false
end)

exports('placeItem', function(itemName)
    PlaceItemOnGround(itemName)
end)

-- =============================================
-- CLEANUP
-- =============================================
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        ClearFireWaypoint()
        
        -- Clean up fires
        for fireIdToClean, fireData in pairs(activeFires) do
            if fireData.isActive ~= nil then
                fireData.isActive = false
            end
            
            if fireData.fireHandles then
                for _, fireHandle in ipairs(fireData.fireHandles) do
                    if fireHandle and fireHandle ~= 0 then
                        if fireData.isVfx then
                            StopParticleFxLooped(fireHandle, false)
                        else
                            RemoveScriptFire(fireHandle)
                        end
                    end
                end
            end
            
            if fireData.particleHandles then
                for _, particle in ipairs(fireData.particleHandles) do
                    if particle and particle ~= 0 then
                        StopParticleFxLooped(particle, false)
                    end
                end
            end
        end
        
        -- Clean up burning objects
        for object, objectData in pairs(burningObjects) do
            for _, fireHandle in ipairs(objectData.fireHandles) do
                if objectData.isVfx then
                    StopParticleFxLooped(fireHandle, false)
                else
                    RemoveScriptFire(fireHandle)
                end
            end
        end
        
        -- Remove ALL blips properly
        RemoveAllFireBlips()
        
        -- Clean up placed items
        for _, item in ipairs(placedItems) do
            if DoesEntityExist(item.prop) then
                exports['ox_target']:removeLocalEntity(item.prop)
                DeleteEntity(item.prop)
            end
        end
        
        -- Clean up tracked vehicles
        for vehicle, _ in pairs(trackedVehicles) do
            if DoesEntityExist(vehicle) then
                exports['ox_target']:removeLocalEntity(vehicle)
            end
        end
        
        -- Clear all tables
        activeFires = {}
        burningObjects = {}
        blipEntries = {}
        placedItems = {}
        trackedVehicles = {}
    end
end)