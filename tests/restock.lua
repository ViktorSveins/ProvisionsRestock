local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function fixture(class, spells, saved, dev)
    local f = { offers = {}, bags = {}, stackSizes = {}, itemRequests = {}, purchases = {},
        now = 0, money = 100000, timers = {} }
    local addonName, addon = "ProvisionsRestock", {}
    ProvisionsSettings, SlashCmdList = saved, {}
    SLASH_PROVISIONSDEV1 = nil
    C_CurrencyInfo, GetCoinTextureString = nil, nil
    Enum = { PlayerInteractionType = { Merchant = 5 } }
    UnitClass = function() return class, class end
    UnitLevel = function() return 60 end
    GetInventoryItemID = function() return nil end
    GetMoney = function() return f.money end
    GetTime = function() return f.now end
    InCombatLockdown = function() return false end
    C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return f.open end }
    C_SpellBook = { IsSpellKnown = function(id) return spells[id] == true end }
    C_Traits = {
        GetConfigIDByTreeID = function() return 1 end,
        GetNodeInfo = function() return { ranksPurchased = f.legacy and 1 or 0 } end,
    }
    C_Item = {
        GetItemCount = function(id) return f.bags[id] or 0 end,
        GetItemNameByID = function(id) return "Item " .. id end,
        GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, f.stackSizes[id] end,
        RequestLoadItemDataByID = function(id) f.itemRequests[id] = true end,
    }
    C_MerchantFrame = { GetItemInfo = function(index) return f.offers[index] end }
    GetMerchantNumItems = function() return #f.offers end
    GetMerchantItemID = function(index) return f.offers[index] and f.offers[index].itemID end
    GetMerchantItemLink = function() return nil end
    GetMerchantItemMaxStack = function(index) return f.offers[index].maxStack end
    BuyMerchantItem = function(index, amount)
        local item = f.offers[index]
        equal(f.open, true)
        equal(amount % item.stackCount, 0)
        f.purchases[#f.purchases + 1] = { itemID = item.itemID, quantity = amount }
        f.money = f.money - item.price * amount / item.stackCount
        f.bags[item.itemID] = C_Item.GetItemCount(item.itemID) + amount
    end

    local function timer(delay, callback, repeating)
        local handle = { at = f.now + delay, delay = delay, repeating = repeating, callback = callback }
        function handle:Cancel() self.cancelled = true end
        f.timers[#f.timers + 1] = handle
        return handle
    end
    C_Timer = {
        After = function(delay, callback) timer(delay, callback, false) end,
        NewTicker = function(delay, callback) return timer(delay, callback, true) end,
    }
    CreateFrame = function()
        return {
            RegisterEvent = function() end,
            SetScript = function(_, _, callback) f.event = callback end,
        }
    end
    for _, file in ipairs({ "Data.lua", "Merchant.lua", "Planner.lua", "UI.lua", "ProvisionsRestock.lua" }) do
        assert(loadfile(file))(addonName, addon)
    end
    addon.UI.Render = function(rows, view, customizeRows)
        f.rows, f.customizeRows, f.view = {}, {}, view
        for _, row in ipairs(rows) do f.rows[row.key] = row end
        for _, row in ipairs(customizeRows or {}) do f.customizeRows[row.key] = row end
    end
    addon.UI.Hide = function() f.rows, f.customizeRows = {}, {} end
    addon.UI.SelectView = function(tab) f.selectedView = tab end
    if dev then assert(loadfile("DevProfiles.lua"))(addonName, addon) end

    function f:advance(duration)
        local untilTime = self.now + duration
        while true do
            local nextTimer
            for _, entry in ipairs(self.timers) do
                if not entry.cancelled and entry.at <= untilTime and (not nextTimer or entry.at < nextTimer.at) then
                    nextTimer = entry
                end
            end
            if not nextTimer then break end
            self.now = nextTimer.at
            nextTimer.at = nextTimer.at + nextTimer.delay
            if not nextTimer.repeating then nextTimer:Cancel() end
            nextTimer.callback()
        end
        self.now = untilTime
    end

    function f:offer(id, price, bundle, maxStack)
        self.offers[#self.offers + 1] = {
            itemID = id, name = "Item " .. id, price = price or 1, stackCount = bundle or 1,
            maxStack = maxStack or 20, isPurchasable = true, isUsable = true, numAvailable = -1,
        }
    end

    function f:show()
        self.open = true
        self.event(nil, "MERCHANT_SHOW")
        self:advance(0)
    end

    function f:close()
        self.open = false
        self.event(nil, "MERCHANT_CLOSED")
    end

    f.addon = addon
    f.event(nil, "ADDON_LOADED", addonName)
    return f
end

local tests = {}

function tests.explicit_auto_stock_only_applies_on_later_visits()
    local f = fixture("MAGE", { [10059] = true, [3561] = true })
    f:offer(17032)
    f:offer(17031)
    f:show()
    f.addon.SetTarget("item:17032", 5)
    f.addon.SetTarget("item:17031", 5)
    f:advance(2)
    equal(#f.purchases, 0)
    f.addon.SetAuto("item:17032", true)
    f:advance(2)
    equal(#f.purchases, 0)
    f:close()
    f:show()
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 17032)
    equal(f.purchases[1].quantity, 5)
    f.bags[17032] = 0
    f.event(nil, "BAG_UPDATE_DELAYED")
    f:advance(2)
    equal(#f.purchases, 1)
    f.addon.SetAuto("item:17032", false)
    f:close()
    f:show()
    f:advance(2)
    equal(#f.purchases, 1)
end

function tests.runes_default_to_one_bag_stack_without_auto_stock()
    local f = fixture("MAGE", { [10059] = true, [3561] = true })
    f:offer(17032)
    f:offer(17031)
    f:show()
    equal(f.rows["item:17032"].target, 10)
    equal(f.rows["item:17031"].target, 10)
    equal(f.rows["item:17032"].auto, false)
    equal(f.rows["item:17031"].auto, false)
    f:advance(2)
    equal(#f.purchases, 0)
    f.addon.SetTarget("item:17031", 0)
    f.addon.SetAuto("item:17032", true)
    f:advance(2)
    equal(#f.purchases, 0)
    f:close()
    f:show()
    equal(f.rows["item:17031"].target, 0)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 17032)
    equal(f.purchases[1].quantity, 10)
end

function tests.cold_item_data_populates_the_bag_stack_default()
    local f = fixture("SHAMAN", { [20608] = true })
    f:offer(17030)
    f:show()
    equal(f.rows["item:17030"].target, 0)
    equal(f.itemRequests[17030], true)
    f.stackSizes[17030] = 5
    f.event(nil, "ITEM_DATA_LOAD_RESULT", 17030)
    f:advance(2)
    equal(f.rows["item:17030"].target, 5)
    equal(f.rows["item:17030"].auto, false)
    equal(#f.purchases, 0)
end

function tests.saved_targets_restock_vendor_bundles_only_on_click()
    local f = fixture("MAGE", { [10059] = true }, {
        mode = "batch", targets = { water = 12, ["item:17032"] = 30 },
        preferred = { water = 8766 },
    })
    local waterKey = "item:8766"
    f.bags[17032] = 50
    f.bags[8766] = 6
    f:offer(17032)
    f:offer(8766, 2, 5)
    f:show()
    equal(f.rows["item:17032"].target, 30)
    equal(f.rows["item:17032"].plan, nil)
    equal(f.rows[waterKey].target, 12)
    equal(f.rows[waterKey].plan.lines[1].quantity, 10)
    equal(f.rows[waterKey].plan.cost, 4)
    assert(f.customizeRows[waterKey].custom)
    equal(f.rows.water, nil)
    f:advance(2)
    equal(#f.purchases, 0)
    f.addon.Buy(waterKey)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 8766)
    equal(f.purchases[1].quantity, 10)
    f:close()
    f:show()
    equal(f.rows[waterKey].target, 12)
    equal(f.rows[waterKey].status, "Stocked")
    assert(f.addon.RemoveCustomItem(waterKey))
    f:close()
    f:show()
    equal(f.rows[waterKey], nil)
    equal(f.customizeRows[waterKey], nil)
end

function tests.legacy_pauses_opted_in_ankh_but_allows_manual_backup()
    local f = fixture("SHAMAN", { [20608] = true }, {
        targets = { ["item:17030"] = 1 }, auto = { ["item:17030"] = true },
    })
    f.legacy = true
    f:offer(17030)
    f:show()
    f:advance(2)
    equal(#f.purchases, 0)
    f.addon.Buy("item:17030")
    f:advance(1)
    equal(#f.purchases, 1)
end

function tests.clearing_target_cancels_a_scheduled_refill_and_removes_opt_in()
    local f = fixture("SHAMAN", { [20608] = true }, {
        targets = { ["item:17030"] = 1 }, auto = { ["item:17030"] = true },
    })
    f:offer(17030)
    f:show()
    f.addon.SetTarget("item:17030", 0)
    f.addon.SetTarget("item:17030", 3)
    f:advance(2)
    f:close()
    f:show()
    f:advance(2)
    equal(#f.purchases, 0)
    equal(ProvisionsSettings.auto["item:17030"], nil)
end

function tests.row_buy_only_purchases_its_item_and_requotes_price_changes()
    local f = fixture("PALADIN", { [25898] = true, [19752] = true })
    f:offer(21177, 15, 5)
    f:offer(17033)
    f:show()
    f.addon.SetTarget("item:21177", 4)
    f.addon.SetTarget("item:17033", 2)
    equal(f.rows["item:21177"].plan.cost, 15)
    f.offers[1].price = 20
    f.addon.Buy("item:21177")
    f:advance(1)
    equal(#f.purchases, 0)
    equal(f.rows["item:21177"].plan.cost, 20)
    f.addon.Buy("item:21177")
    f.addon.Buy("item:21177")
    f:advance(1)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 21177)
    equal(f.purchases[1].quantity, 5)
end

function tests.closing_vendor_stops_remaining_stacks()
    local f = fixture("SHAMAN", { [20608] = true })
    f:offer(17030, 1, 1, 2)
    f:show()
    f.addon.SetTarget("item:17030", 5)
    f.addon.Buy("item:17030")
    f:advance(0.16)
    equal(#f.purchases, 1)
    f:close()
    f:advance(6)
    equal(#f.purchases, 1)
end

function tests.poison_restock_buys_only_missing_materials()
    local f = fixture("ROGUE", { [8681] = true, [3420] = true })
    local instant, crippling = "item:6947", "item:3775"
    f.bags[3371], f.bags[2928], f.bags[2930] = 1, 2, 2
    f:offer(3371)
    f:offer(2928)
    f:offer(2930)
    f:show()
    equal(next(f.rows), nil)
    assert(f.addon.AddCustomItem(6947, 2))
    assert(f.addon.AddCustomItem(3775, 2))
    f:advance(0)
    assert(f.customizeRows[instant].custom and f.customizeRows[crippling].custom)
    equal(f.rows[instant].plan.lines[1].itemID, 3371)
    equal(f.rows[instant].plan.lines[1].quantity, 1)
    equal(f.rows[instant].autoAllowed, false)
    f.addon.Buy(instant)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 3371)
    equal(f.purchases[1].quantity, 1)
    equal(f.rows[instant].status, "Ready to craft")
    equal(f.rows[instant].have, 0)
    equal(f.rows[instant].plan, nil)

    f:close()
    f:offer(6947, 10)
    f:show()
    equal(f.rows[instant].plan.lines[1].itemID, 6947)
end

function tests.exact_water_uses_only_the_selected_items_bag_count()
    local f = fixture("MAGE", {}, { targets = { water = 20 }, reserves = { water = 5 } })
    local key = "item:8766"
    f.bags[8079], f.bags[8766] = 20, 2
    f:offer(8766)
    f:show()
    equal(next(f.rows), nil)
    SlashCmdList.PROVISIONS("water 8766")
    f:advance(0)
    assert(f.customizeRows[key].custom)
    f.addon.SetCustomizeTarget(key, 5)
    equal(f.rows[key].have, 2)
    equal(f.rows[key].plan.lines[1].quantity, 3)
    f:advance(2)
    equal(#f.purchases, 0)
end

function tests.dual_use_food_is_one_exact_item()
    local f = fixture("MAGE", {})
    local key = "item:13724"
    f:offer(13724)
    f:show()
    equal(next(f.rows), nil)
    SlashCmdList.PROVISIONS("food 13724")
    f:advance(0)
    f.addon.SetTarget(key, 5)
    f.addon.Buy(key)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].quantity, 5)
    equal(f.rows[key].have, 5)
    equal(next(f.rows), key)
    equal(next(f.rows, key), nil)
end

function tests.customize_shows_direct_defaults_even_when_they_are_not_sold_here()
    local f = fixture("MAGE", { [10059] = true, [3561] = true, [130] = true })
    f.bags[17056] = 21
    f:offer(17032)
    f:show()
    equal(f.rows["item:17056"], nil)
    equal(f.rows["item:17031"], nil)
    SlashCmdList.PROVISIONS("")
    equal(f.selectedView, "customize")
    equal(f.customizeRows["item:17056"], nil)
    local teleportRune = assert(f.customizeRows["item:17031"])
    assert(teleportRune.canHide and teleportRune.shown and not teleportRune.custom)
    equal(f.customizeRows.food, nil)
    equal(f.customizeRows.water, nil)
    equal(f.addon.RemoveCustomItem("item:17031"), false)
end

function tests.customize_omits_gathered_supplies_across_classes()
    for _, entry in ipairs({
        { "PRIEST", { [1706] = true, [21562] = true }, 17028, { 17056 } },
        { "SHAMAN", { [20608] = true, [131] = true, [546] = true }, 17030, { 17057, 17058 } },
        { "WARLOCK", { [1122] = true, [1120] = true }, 5565, { 6265 } },
    }) do
        local f = fixture(entry[1], entry[2])
        f:offer(entry[3])
        f:show()
        assert(f.customizeRows["item:" .. entry[3]].canHide)
        for _, gathered in ipairs(entry[4]) do
            equal(f.customizeRows["item:" .. gathered], nil)
        end
    end
end

function tests.explicit_custom_consumables_stay_in_customize()
    local f = fixture("MAGE", {}, { hidden = { food = true, water = true } })
    f:offer(117)
    f:offer(159)
    f:show()
    equal(next(f.rows), nil)
    equal(f.customizeRows.food, nil)
    equal(f.customizeRows.water, nil)
    assert(f.addon.AddCustomItem(117))
    f:advance(0)
    assert(f.customizeRows["item:117"].custom)
    assert(f.rows["item:117"])
    equal(f.customizeRows.food, nil)
    equal(f.rows["item:159"], nil)
end

function tests.hidden_default_stays_visible_in_customize_and_pauses_auto_stock()
    local key = "item:17032"
    local f = fixture("MAGE", { [10059] = true }, {
        targets = { [key] = 10 }, auto = { [key] = true }, pins = { [17032] = true },
    })
    f:offer(17032)
    f:show()
    assert(f.rows[key].auto and f.customizeRows[key].shown)
    f.addon.SetDefaultShown(key, false)
    f:advance(2)
    equal(f.rows[key], nil)
    equal(f.customizeRows[key].shown, false)
    equal(ProvisionsSettings.auto[key], true)
    equal(#f.purchases, 0)
    f:close()
    f:show()
    f:advance(2)
    equal(f.rows[key], nil)
    equal(#f.purchases, 0)

    f.addon.SetDefaultShown(key, true)
    f:advance(2)
    assert(f.rows[key].auto and f.customizeRows[key].shown)
    equal(#f.purchases, 0)
    f:close()
    f:show()
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].quantity, 10)
end

function tests.hidden_default_follows_its_rank_family()
    local spells = { [20484] = true, [20748] = true }
    local f = fixture("DRUID", spells)
    f:offer(17034)
    f:offer(17038)
    f:show()
    equal(f.customizeRows["item:17038"].shown, true)
    f.addon.SetDefaultShown("item:17038", false)
    f:close()

    spells[20748] = nil
    f:show()
    equal(f.customizeRows["item:17034"].shown, false)
    equal(f.rows["item:17034"], nil)
end

function tests.custom_items_use_links_and_keep_settings_until_removed()
    local itemID, key = 4470, "item:4470"
    local itemLink = "|cffffffff|Hitem:4470:::::::::|h[Simple Wood]|h|r"
    local f = fixture("MAGE", { [10059] = true })
    f.stackSizes[itemID] = 20
    f:offer(itemID, 3)
    f:offer(17032)
    f:show()
    equal(f.rows[key], nil)
    equal(f.addon.AddCustomItem("17032"), false)
    assert(f.addon.AddCustomItem(itemLink))
    f:advance(0)
    assert(f.customizeRows[key].custom and not f.customizeRows[key].canHide)
    equal(f.rows[key].target, 20)
    equal(f.rows[key].auto, false)
    f.addon.SetCustomizeTarget(key, 7)
    f:advance(0)
    equal(f.rows[key].target, 7)
    f.addon.SetAuto(key, true)
    f:close()

    f.offers = {}
    f:offer(17032)
    f:show()
    equal(f.rows[key], nil)
    equal(f.customizeRows[key].target, 7)
    f:close()

    f:offer(itemID, 3)
    f:show()
    assert(f.addon.RemoveCustomItem(key))
    f:advance(2)
    equal(f.rows[key], nil)
    equal(f.customizeRows[key], nil)
    equal(ProvisionsSettings.pins[itemID], nil)
    equal(ProvisionsSettings.targets[key], nil)
    equal(ProvisionsSettings.auto[key], nil)
    equal(#f.purchases, 0)

    f:close()
    SlashCmdList.PROVISIONS("add 4470 6")
    f:show()
    equal(f.rows[key].target, 6)
    equal(f.rows[key].auto, false)
    f:close()
    SlashCmdList.PROVISIONS("remove 4470")
    f:show()
    equal(f.customizeRows[key], nil)
end

function tests.customize_changes_stay_in_the_active_profile()
    local f = fixture("ROGUE", { [1856] = true }, nil, true)
    local flash, custom = "item:5140", "item:4470"
    f:offer(5140)
    f:offer(4470)
    SlashCmdList.PROVISIONSDEV("use rogue-max")
    f:show()
    assert(f.addon.AddCustomItem("4470"))
    f.addon.SetDefaultShown(flash, false)
    f:advance(0)
    equal(f.rows[flash], nil)
    assert(f.customizeRows[custom].custom)
    f:close()

    SlashCmdList.PROVISIONSDEV("off")
    f:show()
    assert(f.rows[flash] and f.customizeRows[flash].shown)
    equal(f.customizeRows[custom], nil)
    equal(ProvisionsSettings.pins[4470], nil)
    f:close()

    SlashCmdList.PROVISIONSDEV("use rogue-max")
    f:show()
    equal(f.rows[flash], nil)
    equal(f.customizeRows[flash].shown, false)
    assert(f.rows[custom] and f.customizeRows[custom].custom)
    equal(#f.purchases, 0)
end

function tests.release_has_no_profiler_or_unselected_vendor_suggestions()
    local f = fixture("MAGE", {})
    equal(SlashCmdList.PROVISIONSDEV, nil)
    equal(SLASH_PROVISIONSDEV1, nil)
    UnitLevel = function() return 5 end
    f:offer(159)
    f:offer(8766)
    f:show()
    equal(next(f.rows), nil)
    f:close()
    UnitLevel = function() return 60 end
    f:show()
    equal(next(f.rows), nil)
    assert(f.addon.AddCustomItem(159))
    f:advance(0)
    equal(f.rows["item:159"].itemID, 159)
    equal(f.rows["item:8766"], nil)
end

function tests.dev_hunters_use_only_their_own_explicit_items()
    local f = fixture("MAGE", {}, nil, true)
    UnitLevel = function() return 5 end
    f:offer(159)
    f:offer(8766)
    f:offer(11285)
    f:offer(11284)
    f:offer(8952)
    for _, offer in ipairs(f.offers) do offer.isUsable = false end
    SlashCmdList.PROVISIONSDEV("use hunter-bow")
    f:show()
    equal(f.view.profileName, "hunter-bow")
    equal(next(f.rows), nil)
    equal(next(f.customizeRows), nil)
    assert(f.addon.AddCustomItem(11285, 200))
    assert(f.addon.AddCustomItem(8952, 10))
    f:advance(0)
    equal(f.rows["item:11285"].have, 80)
    equal(f.rows["item:11285"].autoAllowed, true)
    equal(f.rows["item:11285"].auto, false)
    equal(f.rows["item:8952"].have, 6)
    equal(f.rows["item:11284"], nil)
    SlashCmdList.PROVISIONSDEV("use hunter-gun")
    equal(f.addon.Dev.GetActiveContext().profileName, "hunter-bow")
    f:close()
    SlashCmdList.PROVISIONSDEV("use hunter-gun")
    f:show()
    equal(next(f.rows), nil)
    assert(f.addon.AddCustomItem(11284, 200))
    f:advance(0)
    equal(f.rows["item:11284"].have, 80)
    equal(f.rows["item:11284"].autoAllowed, true)
    equal(f.rows["item:11284"].auto, false)
    equal(f.rows["item:11285"], nil)
    equal(f.rows["item:8952"], nil)
    equal(#f.purchases, 0)
end

function tests.hunter_auto_stock_requires_exact_ammo_opt_in()
    local f = fixture("HUNTER", {}, { targets = { ammo = 200 }, auto = { ammo = true } })
    local key = "item:11285"
    f.bags[11285], f.bags[11284], f.bags[3030] = 80, 80, 200
    f:offer(11285, 90, 200)
    f:show()
    equal(next(f.rows), nil)
    assert(f.addon.AddCustomItem(11285, 200))
    f:advance(0)
    equal(f.rows[key].have, 80)
    equal(f.rows[key].autoAllowed, true)
    equal(f.rows[key].auto, false)
    f:advance(2)
    equal(#f.purchases, 0)
    f.addon.SetAuto(key, true)
    equal(f.rows[key].auto, true)
    f:advance(2)
    equal(#f.purchases, 0)

    f:close()
    f.offers = {}
    f:offer(3030, 27, 200)
    f:show()
    equal(next(f.rows), nil)
    f:advance(2)
    equal(#f.purchases, 0)
    f:close()
    f.offers = {}
    f:offer(11284, 90, 200)
    f:show()
    equal(next(f.rows), nil)
    f:advance(2)
    equal(#f.purchases, 0)

    f:close()
    f.offers = {}
    f:offer(11285, 90, 200)
    f:show()
    equal(f.rows[key].auto, true)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].itemID, 11285)
    equal(f.purchases[1].quantity, 200)
    f.addon.SetTarget(key, 0)
    equal(ProvisionsSettings.auto[key], nil)
end

function tests.ammo_migration_preserves_the_existing_exact_pin_and_refill()
    local key = "item:11285"
    local f = fixture("HUNTER", {}, {
        targets = { ammo = 450, [key] = 200 },
        auto = { ammo = { [11285] = true }, [key] = true },
        pins = { [11285] = true },
    })
    f.bags[11285] = 80
    f:offer(11285, 90, 200, 400)
    f:show()
    equal(next(f.rows), key)
    equal(next(f.rows, key), nil)
    equal(f.rows[key].target, 200)
    f:advance(2)
    equal(#f.purchases, 1)
    equal(f.purchases[1].quantity, 200)
    equal(f.money, 100000 - 90)
end

function tests.legacy_ammo_opt_ins_become_exact_pins_without_auto_stock()
    local arrowKey, bulletKey = "item:11285", "item:11284"
    local f = fixture("HUNTER", {}, {
        targets = { ammo = 200 }, auto = { ammo = { [11285] = true, [11284] = true, [3030] = false } },
    })
    f.bags[11285] = 80
    f:offer(11285, 90, 200)
    f:offer(11284, 90, 200)
    f:offer(3030, 27, 200)
    f:show()
    for _, key in ipairs({ arrowKey, bulletKey }) do
        assert(f.customizeRows[key].custom and f.rows[key].plan)
        equal(f.rows[key].auto, false)
        equal(f.rows[key].target, 200)
    end
    equal(f.rows["item:3030"], nil)
    equal(ProvisionsSettings.auto.ammo, nil)
    f:advance(2)
    f:close()
    f:show()
    f:advance(2)
    equal(#f.purchases, 0)
end

function tests.previously_hidden_ammo_does_not_become_a_pin()
    local f = fixture("HUNTER", {}, {
        targets = { ammo = 200 }, auto = { ammo = { [11285] = true } }, hidden = { ammo = true },
    })
    f:offer(11285, 90, 200)
    f:show()
    f:advance(2)
    equal(next(f.rows), nil)
    equal(next(f.customizeRows), nil)
    equal(#f.purchases, 0)
end

function tests.hunter_profile_can_auto_stock_without_live_purchases()
    local f = fixture("MAGE", {}, nil, true)
    local key = "item:11285"
    SlashCmdList.PROVISIONSDEV("use hunter-bow")
    local profile = f.addon.Dev.GetActiveContext()
    local initialCopper = profile.GetMoney()
    f.stackSizes[11285] = 200
    f:offer(11285, 90, 200)
    f.offers[1].isUsable = false
    f:show()
    assert(f.addon.AddCustomItem(11285))
    f:advance(0)
    equal(f.rows[key].target, 200)
    equal(f.rows[key].auto, false)
    f.addon.SetAuto(key, true)
    f:advance(2)
    equal(profile.GetBagCount(11285), 80)
    f:close()
    f:show()
    f:advance(2)
    equal(profile.GetBagCount(11285), 280)
    equal(profile.GetMoney(), initialCopper - 90)
    equal(f.money, 100000)
    equal(#f.purchases, 0)
    equal(ProvisionsSettings.auto[key], nil)
end

function tests.dev_rogue_knows_all_ranks_and_requires_an_exact_poison()
    local f = fixture("MAGE", {}, { targets = { ["item:5140"] = 2 } }, true)
    SlashCmdList.PROVISIONSDEV("use rogue-max")
    local profile = f.addon.Dev.GetActiveContext()
    profile.settings.targets = { ["poison:8928"] = 20 }
    for _, family in ipairs(f.addon.Poisons) do
        for _, rank in ipairs(family.ranks) do equal(profile.KnowsRecipe(rank.spellID), true) end
    end
    local startingMoney = profile.GetMoney()
    f:offer(5140, 2)
    f:offer(8924)
    f:offer(8925)
    f:offer(2928)
    f:offer(3371)
    f.offers[1].numAvailable = 8
    f:show()
    assert(f.customizeRows["item:5140"].canHide)
    equal(next(f.rows), "item:5140")
    equal(next(f.rows, "item:5140"), nil)
    local key = "item:6947"
    assert(f.addon.AddCustomItem(6947, 3))
    f:advance(0)
    assert(f.customizeRows[key].custom)
    equal(f.rows[key].rank.spellID, 8681)
    equal(f.rows[key].knownRanks, nil)
    equal(f.rows["item:8928"], nil)
    assert(f.rows[key].plan and f.rows[key].devPlan)
    f.addon.SetTarget("item:5140", 7)
    f.addon.Buy("item:5140")
    equal(profile.GetBagCount(5140), 7)
    equal(f.view.message, "Simulated purchase")
    f.addon.Buy("item:5140", 5)
    equal(profile.GetBagCount(5140), 12)
    equal(profile.GetMoney(), startingMoney - 16)
    equal(f.rows["item:5140"].devPlan, nil)
    equal(#f.purchases, 0)
    equal(f.bags[5140], nil)
    equal(f.money, 100000)
    equal(ProvisionsSettings.targets["item:5140"], 2)
    equal(ProvisionsSettings.ranks.instant, nil)
    f:close()
    f:show()
    assert(f.rows["item:5140"].devPlan)
    equal(f.rows[key].rank.spellID, 8681)
    SlashCmdList.PROVISIONSDEV("reset")
    equal(f.addon.Dev.GetActiveContext(), profile)
    f:close()
    SlashCmdList.PROVISIONSDEV("reset")
    equal(f.addon.Dev.GetActiveContext().GetBagCount(5140), 4)
    equal(f.addon.Dev.GetActiveContext().GetMoney(), startingMoney)
end

function tests.forever_currency_formatting_does_not_require_the_old_global()
    local f = fixture("MAGE", {}, nil, true)
    C_CurrencyInfo = {
        GetCoinTextureString = function(copper) return copper .. " coin texture" end,
    }
    equal(f.addon.UI.FormatMoney(500000), "500000 coin texture")
    SlashCmdList.PROVISIONSDEV("use rogue-max")
    equal(f.addon.Dev.GetActiveContext().profileName, "rogue-max")
    C_CurrencyInfo = {}
    equal(f.addon.UI.FormatMoney(23), "23 copper")
    equal(f.addon.UI.FormatMoney(0), "0 copper")
end

function tests.dev_auto_stock_waits_for_later_visit_and_off_restores_live_purchases()
    local f = fixture("ROGUE", { [1856] = true }, { targets = { ["item:5140"] = 2 } }, true)
    f:offer(5140, 2)
    SlashCmdList.PROVISIONSDEV("use rogue-max")
    local profile = f.addon.Dev.GetActiveContext()
    local startingMoney = profile.GetMoney()
    f:show()
    f.addon.SetTarget("item:5140", 10)
    f.addon.SetAuto("item:5140", true)
    f:advance(2)
    equal(profile.GetBagCount(5140), 4)
    f:close()
    f:show()
    f:advance(2)
    equal(profile.GetBagCount(5140), 10)
    equal(profile.GetMoney(), startingMoney - 12)
    equal(#f.purchases, 0)
    equal(f.money, 100000)
    equal(ProvisionsSettings.targets["item:5140"], 2)
    equal(ProvisionsSettings.auto["item:5140"], nil)
    f:close()
    SlashCmdList.PROVISIONSDEV("off")
    f:show()
    equal(f.view.profileName, nil)
    equal(f.rows["item:5140"].devPlan, nil)
    f.addon.Buy("item:5140", 5)
    f:advance(1)
    equal(#f.purchases, 0)
    f.addon.Buy("item:5140")
    f:advance(2)
    equal(f.bags[5140], 2)
    equal(profile.GetBagCount(5140), 10)
end

function tests.rejected_dev_order_leaves_all_simulated_state_untouched()
    local f = fixture("MAGE", {}, nil, true)
    SlashCmdList.PROVISIONSDEV("use rogue-max")
    local profile = f.addon.Dev.GetActiveContext()
    local startingMoney = profile.GetMoney()
    f:offer(3371, 2)
    f:offer(2928, 3)
    f.offers[1].numAvailable = 10
    f.offers[2].numAvailable = 5
    f.open = true
    local merchant = f.addon.Dev.CreateMerchant(profile)
    local offers = merchant.Scan()
    local lines = {
        assert(f.addon.Merchant.Quote(offers[3371], 4)),
        assert(f.addon.Merchant.Quote(offers[2928], 4)),
    }
    f.offers[2].numAvailable = 2
    local bought, reason = merchant.Start(lines, function() error("Rejected order was acknowledged") end)
    equal(bought, false)
    equal(reason, "Insufficient vendor stock")
    equal(merchant.Scan()[3371].stock, 10)
    equal(profile.GetBagCount(3371), 0)
    equal(profile.GetBagCount(2928), 0)
    equal(profile.GetMoney(), startingMoney)
    equal(#f.purchases, 0)
end

function tests.learned_rank_families_keep_unavailable_choice_visible()
    local f = fixture("DRUID", { [20484] = true, [20748] = true })
    f:offer(17034)
    f:show()
    equal(f.rows["item:17038"].status, "Rank 5 unavailable here")
    f.addon.SetRank("item:17038", -1)
    equal(f.rows["item:17034"].rankLabel, "Rank 1")
    equal(#f.purchases, 0)

    f = fixture("PRIEST", { [21562] = true, [21564] = true, [27683] = true })
    f:offer(17028)
    f:offer(17029)
    f:show()
    assert(f.rows["item:17029"].purpose:find("Shadow Protection", 1, true))
    f.addon.SetRank("item:17029", -1)
    equal(f.rows["item:17028"].rankLabel, "Rank 1")
    assert(f.rows["item:17029"])
end

local count = 0
for name, test in pairs(tests) do
    local ok, failure = pcall(test)
    if not ok then error(name .. " failed: " .. failure) end
    count = count + 1
end
print(("%d restock checks passed"):format(count))
