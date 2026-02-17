Config = {}

-- =============================================
-- FIRE SETTINGS
-- =============================================
Config.FireDuration = 1200000 -- 20 minutes (in milliseconds)
Config.MaxFireIntensity = 10
Config.MaxFires = 50
Config.ExtinguishDistance = 4.0
Config.FirePlaceDistance = 2.0

-- =============================================
-- RANDOM FIRE SETTINGS
-- =============================================
Config.RandomFireInterval = 7200000 --- 2 hrs
Config.RandomFireEnabled = true
---Time	Milliseconds	Code Example
--1 second	1,000	Config.RandomFireInterval = 1000
--5 seconds	5,000	Config.RandomFireInterval = 5000
--10 seconds	10,000	Config.RandomFireInterval = 10000
--30 seconds	30,000	Config.RandomFireInterval = 30000
--1 minute	60,000	Config.RandomFireInterval = 60000
--2 minutes	120,000	Config.RandomFireInterval = 120000
--5 minutes	300,000	Config.RandomFireInterval = 300000
--10 minutes	600,000	Config.RandomFireInterval = 600000
--15 minutes	900,000	Config.RandomFireInterval = 900000
--20 minutes	1,200,000	Config.RandomFireInterval = 1200000
--30 minutes	1,800,000	Config.RandomFireInterval = 1800000
--45 minutes	2,700,000	Config.RandomFireInterval = 2700000
--1 hour	3,600,000	Config.RandomFireInterval = 3600000
--2 hours	7,200,000	Config.RandomFireInterval = 7200000
--3 hours	10,800,000	Config.RandomFireInterval = 10800000
--4 hours	14,400,000	Config.RandomFireInterval = 14400000
--6 hours	21,600,000	Config.RandomFireInterval = 21600000
--12 hours	43,200,000	Config.RandomFireInterval = 43200000
--24 hours	86,400,000	Config.RandomFireInterval = 86400000
-- =============================================
-- NOTIFICATION SETTINGS
-- =============================================
Config.NotifyAllPlayers = true
Config.NotifyRadius = 0 -- 0 = notify everyone, otherwise distance in meters
Config.ShowDistance = true
Config.UseScreenEffects = true
Config.ShowFireStarter = true -- Show who started the fire

-- =============================================
-- BLIP SETTINGS
-- =============================================
Config.AddGPSRoute = true
Config.BlipScale = 0.8
Config.BlipColor = 'RED'
Config.BlipDuration = 300000 -- 5 minutes
Config.AddGPSRoute = true
Config.BlipSprite = 1754365229  -- Fire blip sprite hash
Config.BlipScale = 0.9
Config.BlipColor = 'RED'
Config.BlipDuration = 300000 -- 5 minutes
Config.BlipFlash = true -- Make blip flash
Config.ShowBlipForAllPlayers = false -- Show blip to everyone
Config.FirefighterOnlyGPS = true -- Set to true if only firefighters should get GPS route
-- =============================================
-- FIRE SPAWN LOCATIONS (Random Fires)
-- =============================================
Config.FireSpawnLocations = {
    { coords = vector3(-295.66, 690.57, 113.39), area = "Valentine Warehouse" },
    { coords = vector3(1294.42, -1302.48, 77.04), area = "Bank of Rhodes" },
    { coords = vector3(2835.52, -1413.55, 45.39), area = "Saint Denis Docks" },
    { coords = vector3(-3705.89, -2604.23, -13.30), area = "Armadillo Saloon" },
    { coords = vector3(2934.66, 1307.07, 44.48), area = "Annesburg Train Station" },
    { coords = vector3(-1799.47, -379.27, 160.32), area = "Strawberry General Store" },
    { coords = vector3(1024.25, -1771.1, 47.6), area = "Braithwaite Manor" },
    { coords = vector3(-755.54, -1268.75, 44.02), area = "Blackwater Saloon" },
    { coords = vector3(2618.89, -1229.67, 53.71), area = "Saint Denis Market" },
    { coords = vector3(-329.89, 792.33, 116.26), area = "Valentine Saloon" },
	{ coords = vector3(-792.33, -1321.83, 43.64), area = "Blackwater store" },
	{ coords = vector3(-969.98, -1176.76, 57.96), area = "Blackwater church" }
}

-- =============================================
-- ITEM SETTINGS
-- =============================================
Config.ConsumeMatches = true
Config.ConsumeWater = true
Config.MatchesItem = 'matches'
Config.WaterItem = 'water'
Config.WaterAmount = 1

-- =============================================
-- ANIMATION SETTINGS
-- =============================================
Config.UseAnimations = true
Config.LightFireTime = 4000
Config.ExtinguishTime = 4000
Config.CrouchAnimationDuration = 1000

-- =============================================
-- FIRE SPREAD SETTINGS
-- =============================================
Config.FireSpread = {
    Enabled = true,
    SpreadRadius = 8.0,
    SpreadChance = 0.6,
    SpreadInterval = 3000,
    IgnitionRadius = 3.0,
    MinIgnitionIntensity = 5.0,
    GroundSpreadRadius = 6.0,
    GroundSpreadChance = 0.5,
    MaxTotalFires = 50,
    MaxBurningObjects = 20
}

-- =============================================
-- FLAMMABLE OBJECTS
-- =============================================
Config.FlammableObjects = {
    -- Buildings
    ['p_building_saloon01x'] = { 
        name = "Saloon",
        burnTime = 120000, 
        intensity = 15.0, 
        firePoints = 8, 
        explosionDamage = 2.0 
    },
    ['p_building_barn01x'] = { 
        name = "Barn",
        burnTime = 180000, 
        intensity = 20.0, 
        firePoints = 12, 
        explosionDamage = 2.5 
    },
    ['p_building_house_small_01x'] = { 
        name = "Small House",
        burnTime = 150000, 
        intensity = 18.0, 
        firePoints = 10, 
        explosionDamage = 2.2 
    },
    ['p_building_store01x'] = { 
        name = "Store",
        burnTime = 200000, 
        intensity = 25.0, 
        firePoints = 15, 
        explosionDamage = 2.8 
    },
    ['p_building_bank01x'] = { 
        name = "Bank",
        burnTime = 300000, 
        intensity = 30.0, 
        firePoints = 20, 
        explosionDamage = 3.0 
    },
    
    -- Trees
    ['p_tree_pine_ponderosa_01'] = { 
        name = "Pine Tree",
        burnTime = 60000, 
        intensity = 12.0, 
        firePoints = 6, 
        explosionDamage = 1.5 
    },
    ['p_tree_pine_ponderosa_02'] = { 
        name = "Pine Tree",
        burnTime = 60000, 
        intensity = 12.0, 
        firePoints = 6, 
        explosionDamage = 1.5 
    },
    ['p_tree_oak_01'] = { 
        name = "Oak Tree",
        burnTime = 80000, 
        intensity = 15.0, 
        firePoints = 8, 
        explosionDamage = 1.8 
    },
    
    -- Bushes and Vegetation
    ['p_bush_ferngroup_01'] = { 
        name = "Fern Bush",
        burnTime = 30000, 
        intensity = 8.0, 
        firePoints = 3, 
        explosionDamage = 1.0 
    },
    ['p_bush_sweetbay_01'] = { 
        name = "Sweetbay Bush",
        burnTime = 25000, 
        intensity = 6.0, 
        firePoints = 2, 
        explosionDamage = 0.8 
    },
    ['p_grass_mixed_01'] = { 
        name = "Grass",
        burnTime = 15000, 
        intensity = 4.0, 
        firePoints = 1, 
        explosionDamage = 0.5 
    },
    
    -- Vehicles and Carts
    ['wagon02x'] = { 
        name = "Wagon",
        burnTime = 90000, 
        intensity = 20.0, 
        firePoints = 8, 
        explosionDamage = 2.0 
    },
    ['wagon03x'] = { 
        name = "Wagon",
        burnTime = 90000, 
        intensity = 20.0, 
        firePoints = 8, 
        explosionDamage = 2.0 
    },
    ['cart01'] = { 
        name = "Cart",
        burnTime = 45000, 
        intensity = 12.0, 
        firePoints = 4, 
        explosionDamage = 1.5 
    },
    ['cart02'] = { 
        name = "Cart",
        burnTime = 45000, 
        intensity = 12.0, 
        firePoints = 4, 
        explosionDamage = 1.5 
    },
    
    -- Hay and Farm Items
    ['p_haybaleroundgrass01x'] = { 
        name = "Hay Bale",
        burnTime = 180000, 
        intensity = 25.0, 
        firePoints = 10, 
        explosionDamage = 2.5 
    },
    ['p_cs_strawbale01x'] = { 
        name = "Straw Bale",
        burnTime = 120000, 
        intensity = 20.0, 
        firePoints = 8, 
        explosionDamage = 2.0 
    },
    
    -- Camp Items
    ['p_tent_scout01x'] = { 
        name = "Tent",
        burnTime = 45000, 
        intensity = 15.0, 
        firePoints = 5, 
        explosionDamage = 1.5 
    },
    ['p_campfire01x'] = { 
        name = "Campfire",
        burnTime = 30000, 
        intensity = 8.0, 
        firePoints = 2, 
        explosionDamage = 1.0 
    },
    
    -- Miscellaneous
    ['p_barrel_moonshine01x'] = { 
        name = "Moonshine Barrel",
        burnTime = 60000, 
        intensity = 18.0, 
        firePoints = 6, 
        explosionDamage = 2.2 
    },
    ['p_fence_wood01x'] = { 
        name = "Wooden Fence",
        burnTime = 90000, 
        intensity = 12.0, 
        firePoints = 4, 
        explosionDamage = 1.5 
    },
    ['p_crate01x'] = { 
        name = "Crate",
        burnTime = 60000, 
        intensity = 10.0, 
        firePoints = 3, 
        explosionDamage = 1.2 
    }
}

-- =============================================
-- PLACEABLE ITEMS (Hydrant, Explosives)
-- =============================================
Config.PlaceableItems = {
    ['hydrant'] = {
        prop = 'p_firehydrantnbx01x',
        animation = {
            dict = 'SCRIPT_RE@GOLD_PANNER@GOLD_SUCCESS',
            clip = 'SEARCH01'
        },
        explosion = {
            id = 10, -- EXP_TAG_DIR_WATER_HYDRANT (Water spray)
            offset = vector3(0.0, 0.0, 0.2),
            duration = 5000,
            interval = 500,
            radius = 25.0
        },
        label = 'Fire Hydrant',
        interactDistance = 5.0,
        canPickup = true
    }
    
}



-- =============================================
-- FIRE FIGHTING VEHICLES
-- =============================================
Config.FireVehicles = {
    ['cart05'] = {
        model = 'cart05',
        label = 'Fire Cart',
        interactDistance = 3.0,
        waterEffect = {
            id = 10, -- Water explosion type
            offset = vector3(0.0, 0.0, 0.8), -- LEFT and DOWN
            duration = 8000,
            interval = 500,
            radius = 25.0
        },
        animation = {
            dict = 'script_re@gold_panner@gold_success',
            clip = 'search01',
            duration = 8000
        }
    }
}

-- =============================================
-- DISCORD LOGGING
-- =============================================
Config.DiscordLogging = {
    Enabled = true, -- Change to true
    Webhook = "",
    BotName = "Fire System",
    AvatarUrl = "",
    Colors = {
        FireStarted = 15158332, -- Red
        FireExtinguished = 3066993, -- Green
        ObjectFire = 15105570, -- Orange
        RandomFire = 10181046, -- Purple
        Explosion = 15548997 -- Yellow
    }
}

-- =============================================
-- STATISTICS TRACKING
-- =============================================
Config.TrackStatistics = true
Config.SaveStatistics = false -- Save to database (requires additional setup)

-- =============================================
-- ADMIN SETTINGS
-- =============================================
Config.AdminJobs = { 'police', 'sheriff', 'fireman' }
Config.AdminGroups = { 'admin', 'mod', 'superadmin' }

-- =============================================
-- FIREFIGHTER JOB SETTINGS
-- =============================================
Config.FirefighterJob = {
    Enabled = true,
    JobName = 'fireman',
    PayPerFire = 5, -- Payment for extinguishing fires
    BonusForLargeFires = 100 -- Extra payment for structure fires
}

-- =============================================
-- DEBUG MODE
-- =============================================
Config.Debug = false