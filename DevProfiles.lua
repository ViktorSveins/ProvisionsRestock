local _, addon = ...

local Merchant = addon.Merchant
local Dev = {}
addon.Dev = Dev

local function AllPoisonRecipes()
    local recipes = {}
    for _, family in ipairs(addon.Poisons) do
        for _, rank in ipairs(family.ranks) do
            recipes[#recipes + 1] = rank.spellID
        end
    end
    return recipes
end

-- Add named profiles here. Spell and recipe lists contain IDs.
-- Bag contents map item IDs to units. Copper and settings live until /reload.
local profiles = {
    ["rogue-max"] = {
        class = "ROGUE",
        level = 60,
        spells = { 1856, 1857 },
        recipes = AllPoisonRecipes(),
        reagentEconomy = false,
        bags = { [5140] = 4, [8928] = 31, [8924] = 16, [8925] = 4, [3818] = 2 },
        copper = 500000,
    },
    ["hunter-bow"] = {
        class = "HUNTER",
        level = 60,
        spells = { 6991 },
        ammoType = "arrow",
        reagentEconomy = false,
        bags = { [11285] = 80, [2512] = 200, [8952] = 6 },
        copper = 500000,
    },
    ["hunter-gun"] = {
        class = "HUNTER",
        level = 60,
        ammoType = "bullet",
        reagentEconomy = false,
        bags = { [11284] = 80, [2516] = 200 },
        copper = 500000,
    },
}

local sessions = {}
local activeName

local function Copy(source)
    local destination = {}
    for key, value in pairs(source or {}) do destination[key] = value end
    return destination
end

local function IndexIDs(ids)
    local indexed = {}
    for _, id in ipairs(ids or {}) do indexed[id] = true end
    return indexed
end

local function NewSession(name)
    local profile = profiles[name]
    local state = { bags = Copy(profile.bags), copper = profile.copper or 0 }
    local spells = IndexIDs(profile.spells)
    local recipes = IndexIDs(profile.recipes)
    state.context = {
        profileName = name,
        settings = {},
        GetClass = function() return profile.class end,
        GetLevel = function() return profile.level end,
        KnowsSpell = function(id) return spells[id] == true end,
        KnowsRecipe = function(id) return recipes[id] == true or spells[id] == true end,
        GetAmmoType = function() return profile.ammoType end,
        HasReagentEconomy = function() return profile.reagentEconomy == true end,
        GetBagCount = function(id) return state.bags[id] or 0 end,
        GetMoney = function() return state.copper end,
    }
    return state
end

function Dev.GetActiveContext()
    return activeName and sessions[activeName].context or nil
end

local function IsFiniteStock(stock)
    return type(stock) == "number" and not (issecretvalue and issecretvalue(stock)) and stock >= 0
end

function Dev.CreateMerchant(context)
    local state = sessions[context.profileName]
    assert(state and state.context == context, "Unknown Provisions Restock development context")
    local merchant = {}
    local purchased = {}
    local canceled = false

    local function IsOpen()
        return not canceled and Merchant.IsOpen()
    end

    function merchant.Scan()
        local offers = {}
        if not IsOpen() then return offers end

        for id, native in pairs(Merchant.Scan()) do
            local offer = Copy(native)
            if IsFiniteStock(offer.stock) then
                offer.stock = math.max(0, offer.stock - (purchased[id] or 0))
            end
            offers[id] = offer
        end
        return offers
    end

    function merchant.Start(lines, callback)
        if not IsOpen() then return false, "Merchant closed" end
        if InCombatLockdown() then return false, "Leave combat to purchase" end

        local offers = merchant.Scan()
        local validated, reason = Merchant.ValidateOrder(lines, function(approved)
            local offer = offers[approved.itemID]
            if offer and offer.index == approved.index then return offer end
        end, context.GetBagCount, context.GetMoney)
        if not validated then return false, reason end

        -- Validation finishes before any change. No native purchase, bag or
        -- wallet operation runs from this adapter.
        for _, line in ipairs(validated.lines) do
            local id = line.quote.itemID
            local offer = offers[id]
            state.bags[id] = line.bagCount + line.remaining
            if IsFiniteStock(offer.stock) then
                purchased[id] = (purchased[id] or 0) + line.remaining
            end
        end
        state.copper = state.copper - validated.cost

        if callback then callback(true) end
        return true
    end

    function merchant.IsBusy() return false end
    function merchant.OnBagUpdate() end
    function merchant.Cancel() canceled = true end
    return merchant
end

local function Print(message)
    print("|cffffcf69Provisions Restock Dev|r " .. message)
end

local function List()
    local names = {}
    for name in pairs(profiles) do names[#names + 1] = name end
    table.sort(names)
    Print(table.concat(names, ", "))
end

local function Status()
    local context = Dev.GetActiveContext()
    if not context then
        Print("Live character")
        return
    end

    local funds = addon.UI.FormatMoney(context.GetMoney())
    Print(string.format("Simulation · %s · %s %d · %s",
        context.profileName, context.GetClass(), context.GetLevel(), funds))
end

local function Slash(message)
    local command, name = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "list" then return List() end
    if command == "status" then return Status() end

    if command ~= "use" and command ~= "reset" and command ~= "off" then
        Print("/provisionsdev list · use <name> · status · reset · off")
        return
    end
    if addon.IsMerchantOpen() then
        Print("Close the merchant first")
        return
    end

    if command == "use" then
        if not profiles[name] then
            Print("Unknown profile. Use /provisionsdev list")
            return
        end
        sessions[name] = sessions[name] or NewSession(name)
        activeName = name
    elseif command == "reset" then
        if not activeName then return Status() end
        sessions[activeName] = NewSession(activeName)
    else
        activeName = nil
    end
    Status()
end

SLASH_PROVISIONSDEV1 = "/provisionsdev"
SlashCmdList.PROVISIONSDEV = Slash
