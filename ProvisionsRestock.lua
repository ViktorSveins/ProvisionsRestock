local addonName, addon = ...

local Merchant, Planner = addon.Merchant, addon.Planner
local MAX_TARGET = 9999
local LEGACY_TREE, REAGENT_ECONOMY_NODE = 1189, 110309
-- Forever bag capacities for runes while the item cache is cold.
local RUNE_STACKS = { [17031] = 10, [17032] = 10 }
local DEV_BATCH_SIZE = 5
local Live = {}
local visit

local function Target(value)
    local number = tonumber(value) or 0
    if number ~= number then return 0 end
    return math.min(MAX_TARGET, math.max(0, math.floor(number)))
end

local function IsItemID(itemID)
    return type(itemID) == "number" and itemID > 0 and itemID <= 2147483647 and itemID % 1 == 0
end

local function ItemKey(itemID)
    return "item:" .. itemID
end

local function MigrateSelectedItems(settings)
    local targets = {}
    local function Pin(itemID, target)
        if not IsItemID(itemID) then return end
        local key = ItemKey(itemID)
        if settings.pins[itemID] ~= true then
            settings.pins[itemID] = true
            -- Category refills and exact-item refills count bags differently.
            settings.auto[key] = nil
        end
        if target ~= nil and settings.targets[key] == nil then
            targets[key] = math.max(targets[key] or 0, Target(target))
        end
    end

    local preferred = settings.preferred
    if type(preferred) == "table" then
        Pin(preferred.food, settings.targets.food)
        Pin(preferred.water, settings.targets.water)
        preferred.food, preferred.water = nil, nil
    end
    local ammo = settings.auto.ammo
    if type(ammo) == "table" and settings.hidden.ammo ~= true then
        for itemID, enabled in pairs(ammo) do
            if enabled == true then Pin(itemID, settings.targets.ammo) end
        end
    end
    settings.auto.ammo = nil
    for key, target in pairs(targets) do
        settings.targets[key] = target
        settings.auto[key] = nil
    end
end

local function PrepareSettings(settings)
    for _, field in ipairs({ "targets", "auto", "ranks", "pins", "hidden" }) do
        if type(settings[field]) ~= "table" then settings[field] = {} end
    end
    MigrateSelectedItems(settings)
    settings.hidden.food, settings.hidden.water, settings.hidden.petFood, settings.hidden.ammo = nil, nil, nil, nil
    for _, family in ipairs(addon.Poisons) do
        settings.hidden["poison:" .. family.key] = nil
    end
    return settings
end

local function Initialize()
    if type(ProvisionsSettings) ~= "table" then ProvisionsSettings = {} end
    Live.settings = PrepareSettings(ProvisionsSettings)
end

function Live.KnowsSpell(spellID)
    return C_SpellBook.IsSpellKnown(spellID)
end

local function KnowsAny(context, spells)
    for _, spellID in ipairs(spells or {}) do
        if context.KnowsSpell(spellID) then return true end
    end
    return false
end

function Live.KnowsRecipe(spellID)
    if Live.KnowsSpell(spellID) then return true end
    local recipe = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo(spellID)
    return recipe and recipe.learned == true
end

function Live.HasReagentEconomy()
    local config = C_Traits and C_Traits.GetConfigIDByTreeID(LEGACY_TREE)
    if not config or config <= 0 then return false end
    local node = C_Traits.GetNodeInfo(config, REAGENT_ECONOMY_NODE)
    if node and node.entryIDsWithCommittedRanks then
        return #node.entryIDsWithCommittedRanks > 0
    end
    return node and (node.ranksPurchased or node.activeRank or 0) > 0
end

function Live.GetClass()
    return select(2, UnitClass("player"))
end

function Live.GetBagCount(itemID)
    return C_Item.GetItemCount(itemID, false) or 0
end

function Live.GetMoney()
    return GetMoney()
end

local function GetCharacter()
    local profile = addon.Dev and addon.Dev.GetActiveContext()
    if profile then
        PrepareSettings(profile.settings)
        return profile
    end
    if not Live.settings then Initialize() end
    return Live
end

local function KeepTarget(settings, key, itemID)
    if settings.targets[key] ~= nil then return Target(settings.targets[key]) end
    if not itemID then return 0 end

    local _, _, _, _, _, _, _, stackSize = C_Item.GetItemInfo(itemID)
    if type(stackSize) == "number" and stackSize > 0 then return Target(stackSize) end

    if visit and not visit.requestedItems[itemID] then
        visit.requestedItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return RUNE_STACKS[itemID] or 0
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
end

local function MissingStatus(reason, itemID)
    if itemID and reason == "Vendor missing an item" then
        return "Needs " .. ItemName(itemID)
    end
    return reason or "Unavailable"
end

local function GetRank(known, preferred, defaultIndex)
    for index, entry in ipairs(known) do
        if entry.rank.itemID == preferred then return index end
    end
    return defaultIndex
end

local function GetPurpose(context, entry, fallback)
    local uses = {}
    for _, purpose in ipairs(entry.purposes or {}) do
        if KnowsAny(context, purpose.spells) then uses[#uses + 1] = purpose.label end
    end
    if #uses > 0 then return table.concat(uses, " · ") end
    return entry.purpose or fallback
end

local function KnowsSupply(context, supply)
    return not KnowsAny(context, supply.unlessSpells) and (not supply.spells or KnowsAny(context, supply.spells))
end

local function IsDefaultItem(context, itemID)
    local class = context.GetClass()
    for _, supply in ipairs(addon.ClassSupplies[class] or {}) do
        if supply.kind == "direct" then
            if supply.itemID == itemID and KnowsSupply(context, supply) then return true end
            for _, variant in ipairs(supply.variants or {}) do
                if variant.itemID == itemID and KnowsAny(context, variant.spells) then return true end
            end
        end
    end
    return false
end

local function MakeRankChoice(row, key, known, index)
    row.familyKey = key
    row.knownRanks = known
    row.rankIndex = index
    row.rankCount = #known
    row.rankLabel = "Rank " .. known[index].index
end

local function NoBagMaterials()
    return 0
end

local function FindPoison(context, itemID)
    for _, family in ipairs(addon.Poisons) do
        if not family.gatheredOnly then
            for _, rank in ipairs(family.ranks) do
                if rank.itemID == itemID and context.KnowsRecipe(rank.spellID) then
                    return rank, family.purpose
                end
            end
        end
    end
end

local function BuildModel(offers, context, current)
    local settings = context.settings
    local rows, byKey = {}, {}
    local customizeRows, customizeByKey = {}, {}
    local classItems = {}
    local countCache = {}
    local function Count(itemID)
        if countCache[itemID] == nil then countCache[itemID] = context.GetBagCount(itemID) end
        return countCache[itemID]
    end
    local class = context.GetClass()
    local legacy, money = context.HasReagentEconomy(), context.GetMoney()
    local function Add(row, relevant, defaultKey)
        local shown = not defaultKey or settings.hidden[defaultKey] ~= true
        local existing = customizeByKey[row.key]
        if existing then
            if row.purpose and existing.purpose ~= row.purpose then
                existing.purpose = existing.purpose and (existing.purpose .. " · " .. row.purpose) or row.purpose
            end
            if defaultKey then existing.defaultKeys[#existing.defaultKeys + 1] = defaultKey end
            existing.shown = existing.shown or shown
            existing.relevant = existing.relevant or relevant
            return
        end
        row.target = KeepTarget(settings, row.key, row.itemID)
        row.have = row.have or Count(row.itemID)
        row.custom = row.custom == true
        row.shown, row.relevant = shown, relevant
        row.canHide = defaultKey ~= nil
        if defaultKey then row.defaultKeys = { defaultKey } end
        if row.itemID and offers[row.itemID] then row.name = offers[row.itemID].name end
        customizeRows[#customizeRows + 1], customizeByKey[row.key] = row, row
    end

    for _, supply in ipairs(addon.ClassSupplies[class] or {}) do
        if supply.itemID then classItems[supply.itemID] = true end
        local known, relevant = {}, false
        for _, candidate in ipairs(supply.variants or {}) do
            classItems[candidate.itemID] = true
            if KnowsAny(context, candidate.spells) then
                known[#known + 1] = { rank = candidate, index = candidate.rank }
                if offers[candidate.itemID] then relevant = true end
            end
        end
        local entry, rankIndex
        if #known > 0 then
            table.sort(known, function(a, b) return a.index < b.index end)
            rankIndex = GetRank(known, settings.ranks[supply.key], #known)
            entry = known[rankIndex].rank
        elseif not supply.variants and KnowsSupply(context, supply) then
            entry = supply
        end
        if entry and (entry.kind or supply.kind) == "direct" then
            local itemID = entry.itemID
            local row = {
                key = ItemKey(itemID), itemID = itemID, purpose = GetPurpose(context, entry, supply.purpose),
                autoAllowed = true, autoPaused = legacy,
                rankUnavailable = relevant and not offers[itemID],
            }
            if rankIndex then MakeRankChoice(row, supply.key, known, rankIndex) end
            local defaultKey = supply.key and "class:" .. supply.key or row.key
            Add(row, offers[itemID] ~= nil or relevant, defaultKey)
        end
    end

    local pins = {}
    for itemID, enabled in pairs(settings.pins) do
        if enabled == true and type(itemID) == "number" and itemID > 0 and itemID % 1 == 0 then
            pins[#pins + 1] = itemID
        end
    end
    table.sort(pins)
    for _, itemID in ipairs(pins) do
        if not IsDefaultItem(context, itemID) then
            local directOffer = offers[itemID]
            local rank, purpose
            if class == "ROGUE" and not directOffer then rank, purpose = FindPoison(context, itemID) end
            local relevant = directOffer ~= nil
            if rank then
                for _, reagent in ipairs(rank.reagents) do
                    if offers[reagent.itemID] then relevant = true break end
                end
            end
            -- A pinned class item must not bypass a Legacy pause.
            Add({ key = ItemKey(itemID), itemID = itemID, custom = true, rank = rank,
                purpose = purpose, autoAllowed = not rank, autoPaused = legacy and classItems[itemID] }, relevant)
        end
    end

    for _, row in ipairs(customizeRows) do
        if row.shown and row.relevant then rows[#rows + 1], byKey[row.key] = row, row end
    end

    for _, row in ipairs(rows) do
        local missing = math.max(0, row.target - row.have)
        local offer = row.itemID and offers[row.itemID]
        local required, crafts
        if row.rankUnavailable then
            row.status = row.rankLabel .. " unavailable here"
        elseif row.target > 0 then
            if missing == 0 then
                row.status = "Stocked"
            else
                if row.rank then
                    crafts = math.ceil(missing / row.rank.outputCount)
                    required = Planner.Recipe(row.rank, crafts)
                elseif row.itemID then
                    required = { [row.itemID] = Count(row.itemID) + missing }
                end
            end
        end

        if required then
            local plan, reason, itemID = Planner.Build(required, offers, Count)
            if row.rank then
                local ready = crafts
                for reagentID, amount in pairs(required) do
                    ready = math.min(ready, math.floor(Count(reagentID) * crafts / amount))
                end
                row.craftOutput = ready * row.rank.outputCount
                if ready > 0 and ready < crafts then
                    row.detail = string.format("%d craftable now", row.craftOutput)
                end
            end
            if plan and #plan.lines == 0 then
                row.status = "Ready to craft"
            elseif plan and plan.cost <= money then
                row.plan = plan
            else
                row.status = plan and "Not enough money" or MissingStatus(reason, itemID)
            end
        end

        if context.profileName and current and not row.rankUnavailable then
            local batch = row.rank and Planner.Recipe(row.rank, DEV_BATCH_SIZE)
                or (offer and { [row.itemID] = DEV_BATCH_SIZE })
            local plan, reason, itemID
            if batch then plan, reason, itemID = Planner.Build(batch, offers, NoBagMaterials) end
            if plan and #plan.lines > 0 and plan.cost <= money then
                row.devPlan = plan
                row.devQuantity = row.rank and DEV_BATCH_SIZE or plan.lines[1].quantity
            elseif batch then
                row.devReason = plan and "Not enough simulated money" or MissingStatus(reason, itemID)
            end
        end
        row.autoAllowed = row.autoAllowed == true and offer ~= nil and not offer.extendedCost and not row.autoPaused
        row.auto = row.target > 0 and (row.autoAllowed or row.autoPaused) and settings.auto[row.key] == true or false
    end

    return rows, byKey, {
        profileName = context.profileName, money = money,
        busy = current and current.merchant.IsBusy() or false, message = current and current.message,
    }, customizeRows, customizeByKey
end

local function Refresh()
    if not visit then return end
    local rows, byKey, view, customizeRows, customizeByKey = BuildModel(visit.merchant.Scan(), visit.context, visit)
    visit.rows, visit.customizeRows = byKey, customizeByKey
    addon.UI.Render(rows, view, customizeRows)
end

local function ScheduleRefresh()
    local current = visit
    if not current or current.refreshQueued then return end
    current.refreshQueued = true
    C_Timer.After(0, function()
        current.refreshQueued = false
        if visit == current then Refresh() end
    end)
end

local function Start(plan)
    local current = visit
    if not current or current.merchant.IsBusy() then return end
    local simulated = current.context.profileName ~= nil
    current.message = "Buying…"
    local started, reason = current.merchant.Start(plan.lines, function(ok, failure)
        if visit ~= current then return end
        current.message = ok and (simulated and "Simulated purchase" or "Purchased")
            or (failure or "Purchase stopped")
        ScheduleRefresh()
    end, ScheduleRefresh)
    if not started then current.message = reason or "Purchase unavailable" end
    Refresh()
end

local function AutoStock(current)
    if visit ~= current or current.autoTried or current.merchant.IsBusy() then return end
    local rows = BuildModel(current.merchant.Scan(), current.context, current)
    local lines, cost = {}, 0
    local money = current.context.GetMoney()
    for _, row in ipairs(rows) do
        if row.autoAllowed and row.auto and row.plan and current.autoTargets[row.key] == row.target then
            local line = row.plan.lines[1]
            if line and cost + line.cost <= money then
                lines[#lines + 1] = line
                cost = cost + line.cost
            end
        end
    end
    if #lines > 0 then
        current.autoTried = true
        Start({ lines = lines, cost = cost })
    end
end

local function SetKeep(row, value)
    local settings = visit.context.settings
    local key = row.key
    local target = Target(value)
    if target ~= row.target then visit.autoTargets[key] = nil end
    settings.targets[key] = target
    if target == 0 then settings.auto[key] = nil end
    visit.message = nil
    Refresh()
end

function addon.SetTarget(key, value)
    local row = visit and visit.rows[key]
    if not row or visit.merchant.IsBusy() then return end
    SetKeep(row, value)
end

function addon.SetAuto(key, enabled)
    local row = visit and visit.rows[key]
    if not row or not row.autoAllowed or visit.merchant.IsBusy() then return end
    local settings = visit.context.settings
    enabled = enabled == true and row.target > 0
    if enabled then
        settings.targets[key] = row.target
    end
    settings.auto[key] = enabled or nil
    visit.message = nil
    visit.autoTargets[key] = nil
    Refresh()
end

function addon.SetRank(key, direction)
    local row = visit and visit.rows[key]
    if not row or not row.knownRanks or visit.merchant.IsBusy() or (direction ~= -1 and direction ~= 1) then return end
    local rank = row.knownRanks[row.rankIndex + direction]
    if rank then
        visit.context.settings.ranks[row.familyKey] = rank.rank.itemID
        visit.message = nil
        Refresh()
    end
end

local function SelectedPlan(row, batch)
    if not row then return end
    if batch then return row.devPlan end
    return row.plan
end

function addon.Buy(key, batch)
    if not visit or visit.merchant.IsBusy() then return end
    if batch and (batch ~= DEV_BATCH_SIZE or not visit.context.profileName) then return end
    local row = visit.rows[key]
    local shown = SelectedPlan(row, batch)
    if not shown then return end
    -- A click is approval for the displayed order. If live data changes it,
    -- redraw so a second click approves the new quantities and price.
    visit.autoTried = true
    local _, byKey = BuildModel(visit.merchant.Scan(), visit.context, visit)
    local current = SelectedPlan(byKey[key], batch)
    if not Planner.SameOrder(shown, current) then
        visit.message = "Offer changed. Review and retry."
        Refresh()
        return
    end
    Start(current)
end

local function MerchantShow()
    if visit then return end
    local context = GetCharacter()
    local merchant = Merchant
    if context.profileName then
        merchant = addon.Dev.CreateMerchant(context)
        if not merchant then return end
    end
    local settings = context.settings
    local current = { autoTargets = {}, rows = {}, requestedItems = {}, context = context, merchant = merchant }
    for key, optIn in pairs(settings.auto) do
        local target = Target(settings.targets[key])
        if optIn == true and target > 0 then current.autoTargets[key] = target end
    end
    visit = current
    ScheduleRefresh()
    if next(current.autoTargets) then
        -- Merchant data can arrive just after show. A small, bounded window
        -- allows that update; bag changes never schedule a refill.
        C_Timer.After(0.25, function() AutoStock(current) end)
        C_Timer.After(1.25, function()
            AutoStock(current)
            current.autoTried = true
        end)
    end
end

local function MerchantClose()
    if not visit then return end
    local merchant = visit.merchant
    visit = nil
    merchant.Cancel()
    addon.UI.Hide()
end

function addon.IsMerchantOpen()
    return visit ~= nil or Merchant.IsOpen()
end

local function Print(message)
    print("|cffffcf69Provisions Restock|r " .. message)
end

local function ParseItem(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return end
    local linkedID = text:match("|Hitem:(%d+)")
    if linkedID then return tonumber(linkedID), text:match("|h%s*|r%s*(%d+)%s*$") end
    local itemID, quantity = text:match("^(%d+)%s*(%d*)%s*$")
    return tonumber(itemID), quantity
end

local function ActiveCharacter()
    return visit and visit.context or GetCharacter()
end

local function IsBuying()
    return visit and visit.merchant.IsBusy() or false
end

function addon.ShowCustomize()
    if not visit then
        Print("Open a vendor to customize")
        return
    end
    if not visit.customizeRows then Refresh() end
    addon.UI.SelectView("customize")
end

function addon.SetCustomizeTarget(key, value)
    local row = visit and visit.customizeRows and visit.customizeRows[key]
    if not row or IsBuying() then return end
    SetKeep(row, value)
end

function addon.SetDefaultShown(key, shown)
    local row = visit and visit.customizeRows and visit.customizeRows[key]
    if not row or not row.canHide or IsBuying() then return end
    shown = shown == true
    if row.shown == shown then return end

    local hidden = visit.context.settings.hidden
    for _, defaultKey in ipairs(row.defaultKeys) do
        hidden[defaultKey] = not shown and true or nil
    end
    visit.autoTargets[key] = nil
    for _, entry in ipairs(row.knownRanks or {}) do
        visit.autoTargets[ItemKey(entry.rank.itemID)] = nil
    end
    visit.message = nil
    Refresh()
end

function addon.AddCustomItem(item, quantity)
    if IsBuying() then return false, "Purchase in progress" end
    local itemID = ParseItem(item)
    if not IsItemID(itemID) then return false, "Enter an item link or ID" end
    local context = ActiveCharacter()
    if IsDefaultItem(context, itemID) then return false, "Already a default item" end
    local settings = context.settings
    local key = ItemKey(itemID)
    if settings.pins[itemID] ~= true then
        settings.auto[key] = nil
        if visit then visit.autoTargets[key] = nil end
    end
    settings.pins[itemID] = true
    if quantity and quantity ~= "" then
        settings.targets[key] = Target(quantity)
        settings.auto[key] = nil
        if visit then visit.autoTargets[key] = nil end
    end
    if visit then
        visit.message = nil
        ScheduleRefresh()
    end
    return true
end

function addon.RemoveCustomItem(key)
    if IsBuying() then return false, "Purchase in progress" end
    local itemID = type(key) == "string" and tonumber(key:match("^item:(%d+)$"))
    local context = ActiveCharacter()
    local settings = context.settings
    if not IsItemID(itemID) or not settings.pins[itemID] or IsDefaultItem(context, itemID) then
        return false, "Only custom items can be removed"
    end
    key = ItemKey(itemID)
    settings.pins[itemID], settings.targets[key], settings.auto[key] = nil, nil, nil
    if visit then
        visit.autoTargets[key] = nil
        visit.message = nil
        ScheduleRefresh()
    end
    return true
end

local function Slash(message)
    local command, argument = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        addon.ShowCustomize()
        return
    end
    if IsBuying() then
        Print("Wait for the current purchase to finish.")
        return
    end
    local itemID, quantity = ParseItem(argument)
    if command == "add" or command == "food" or command == "water" then
        if argument == "auto" then
            Print("Choose a specific item in Customize")
            return
        end
        local ok, reason = addon.AddCustomItem(itemID, quantity)
        Print(ok and ("Added " .. ItemName(itemID)) or reason)
    elseif command == "remove" then
        local ok, reason = addon.RemoveCustomItem(itemID and ItemKey(itemID))
        Print(ok and ("Removed " .. ItemName(itemID)) or reason)
    elseif command == "reserve" then
        Print("Set Keep for the item in Customize")
    else
        Print("/provisions · /provisions add <item> [Keep] · /provisions remove <item>")
    end
end

SLASH_PROVISIONS1 = "/provisions"
SlashCmdList.PROVISIONS = Slash

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" then
        if argument == addonName then Initialize() end
    elseif event == "MERCHANT_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and argument == Enum.PlayerInteractionType.Merchant) then
        MerchantShow()
    elseif event == "MERCHANT_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"
        and argument == Enum.PlayerInteractionType.Merchant) then
        MerchantClose()
    elseif visit then
        if event == "BAG_UPDATE_DELAYED" then visit.merchant.OnBagUpdate() end
        ScheduleRefresh()
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "BAG_UPDATE_DELAYED",
    "PLAYER_MONEY", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SPELLS_CHANGED",
    "TRAIT_CONFIG_UPDATED", "TRADE_SKILL_LIST_UPDATE" }) do
    events:RegisterEvent(event)
end
