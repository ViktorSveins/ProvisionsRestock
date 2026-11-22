local _, addon = ...

local Merchant = {}
addon.Merchant = Merchant

local MAX_UNITS = 2147483647
local MAX_COPPER = 9007199254740991
local PURCHASE_INTERVAL = 0.15
local DELIVERY_TIMEOUT = 4
local pending
local settling

local function IsInteger(value, minimum, maximum)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value >= minimum and value <= maximum and value == math.floor(value)
end

local function MerchantIsOpen()
    local interactions = C_PlayerInteractionManager
    local merchantType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant
    if interactions and interactions.IsInteractingWithNpcOfType and merchantType then
        return interactions.IsInteractingWithNpcOfType(merchantType)
    end
    return GetMerchantNumItems() > 0
end
Merchant.IsOpen = MerchantIsOpen

local function ReadOffer(index)
    local itemID = GetMerchantItemID(index)
    if not IsInteger(itemID, 1, MAX_UNITS) then return end

    local info = C_MerchantFrame.GetItemInfo(index)
    if not info or not IsInteger(info.price, 0, MAX_COPPER) then return end

    local bundleSize = IsInteger(info.stackCount, 1, MAX_UNITS) and info.stackCount or 1
    return {
        itemID = itemID,
        index = index,
        name = info.name,
        link = GetMerchantItemLink(index),
        icon = info.texture,
        bundleSize = bundleSize,
        price = info.price,
        stock = info.numAvailable,
        purchasable = info.isPurchasable == true,
        usable = info.isUsable == true,
        extendedCost = info.hasExtendedCost == true or info.currencyID ~= nil,
    }
end

local function IsCoinOffer(offer)
    return offer.purchasable and not offer.extendedCost
        and IsInteger(offer.stock, -1, MAX_UNITS)
        and (offer.stock == -1 or offer.stock >= offer.bundleSize)
end

function Merchant.Scan()
    local offers = {}
    for index = 1, GetMerchantNumItems() do
        local offer = ReadOffer(index)
        if offer then
            local existing = offers[offer.itemID]
            -- Prefer a buyable slot when the same item has multiple offers.
            if not existing or (IsCoinOffer(offer) and not IsCoinOffer(existing)) then
                offers[offer.itemID] = offer
            end
        end
    end
    return offers
end

function Merchant.Quote(offer, missing)
    if not offer then return nil, "Not sold here" end
    if offer.extendedCost then return nil, "Special currency required" end
    if not offer.purchasable then return nil, "Unavailable" end
    if not IsInteger(missing, 1, MAX_UNITS) then return nil, "Invalid quantity" end

    local bundleSize, price = offer.bundleSize, offer.price
    if not IsInteger(bundleSize, 1, MAX_UNITS) or not IsInteger(price, 0, MAX_COPPER)
        or not IsInteger(offer.stock, -1, MAX_UNITS) then
        return nil, "Vendor details unavailable"
    end

    local bundles = math.ceil(missing / bundleSize)
    local quantity = bundles * bundleSize
    if quantity > MAX_UNITS or price > math.floor(MAX_COPPER / bundles) then
        return nil, "Purchase quantity or cost is too large"
    end
    local cost = bundles * price
    if cost > MAX_COPPER then return nil, "Purchase cost is too large" end
    if offer.stock ~= -1 and quantity > offer.stock then
        return nil, "Insufficient vendor stock"
    end

    return {
        itemID = offer.itemID,
        index = offer.index,
        name = offer.name,
        link = offer.link,
        bundleSize = bundleSize,
        price = price,
        quantity = quantity,
        cost = cost,
    }
end

local function ValidateOffer(approved, amount, offer)
    if not offer or offer.index ~= approved.index or offer.itemID ~= approved.itemID
        or offer.bundleSize ~= approved.bundleSize
        or offer.price ~= approved.price then
        return nil, "Vendor offer changed"
    end

    local quote, reason = Merchant.Quote(offer, amount)
    if not quote then return nil, reason end
    if quote.quantity ~= amount then return nil, "Vendor bundle changed" end
    return quote
end

local function BagCount(itemID)
    local count = C_Item.GetItemCount(itemID)
    if IsInteger(count, 0, MAX_UNITS) then return count end
end

local function CanAfford(copper, cost)
    return IsInteger(copper, 0, MAX_COPPER) and copper >= cost
end

function Merchant.IsBusy()
    return pending ~= nil
end

function Merchant.Cancel()
    local purchase = pending
    pending = nil
    if purchase then
        -- Closing the merchant cancels queued work, while a sent order may still arrive.
        settling = purchase.delivery
        if purchase.timer then purchase.timer:Cancel() end
    end
end

local function HasSettlingDelivery()
    if not settling then return false end
    local count = BagCount(settling.itemID)
    if (count and count >= settling.expected) or GetTime() - settling.sentAt >= DELIVERY_TIMEOUT then
        settling = nil
    end
    return settling ~= nil
end

local function Finish(purchase, ok, reason)
    Merchant.Cancel()
    if purchase.callback then purchase.callback(ok, reason) end
end

local function ObserveDelivery(purchase)
    local delivery = purchase.delivery
    if not delivery then return end

    local line = purchase.lines[purchase.index]
    local count = BagCount(line.quote.itemID)
    if count == delivery.expected then
        line.bagCount = count
        line.remaining = line.remaining - delivery.quantity
        purchase.remainingCost = purchase.remainingCost - delivery.cost
        purchase.delivery = nil
        if line.remaining == 0 then
            purchase.index = purchase.index + 1
        end
        if not purchase.lines[purchase.index] then
            Finish(purchase, true)
        elseif purchase.onUpdate then
            purchase.onUpdate()
        end
    elseif count and count > delivery.expected then
        Finish(purchase, false, "Bag contents changed during purchase")
    elseif GetTime() - delivery.sentAt >= DELIVERY_TIMEOUT then
        Finish(purchase, false, "Purchase could not be confirmed. Check your bags, money and vendor stock.")
    end
end

function Merchant.OnBagUpdate()
    HasSettlingDelivery()
    if pending then ObserveDelivery(pending) end
end

local function Tick(purchase)
    -- A canceled timer callback must never run against a later merchant session.
    if pending ~= purchase then return end
    if not MerchantIsOpen() then return Finish(purchase, false, "Merchant closed") end
    if InCombatLockdown() then return Finish(purchase, false, "Purchasing stopped in combat") end
    if purchase.delivery then return ObserveDelivery(purchase) end

    local line = purchase.lines[purchase.index]
    local quote, reason = ValidateOffer(line.quote, line.remaining, ReadOffer(line.quote.index))
    if not quote then return Finish(purchase, false, reason) end
    if not CanAfford(GetMoney(), purchase.remainingCost) then return Finish(purchase, false, "Not enough money") end
    if BagCount(quote.itemID) ~= line.bagCount then
        return Finish(purchase, false, "Bag contents changed before purchase")
    end

    local maxStack = GetMerchantItemMaxStack(quote.index)
    if not IsInteger(maxStack, quote.bundleSize, MAX_UNITS) then maxStack = quote.bundleSize end
    local maxPerCall = math.floor(maxStack / quote.bundleSize) * quote.bundleSize
    local quantity = math.min(line.remaining, maxPerCall)
    purchase.delivery = {
        itemID = quote.itemID,
        expected = line.bagCount + quantity,
        quantity = quantity,
        cost = (quantity / quote.bundleSize) * quote.price,
        sentAt = GetTime(),
    }
    local ok = pcall(BuyMerchantItem, quote.index, quantity)
    if not ok and pending == purchase then
        Finish(purchase, false, "The client refused the purchase")
    end
end

function Merchant.ValidateOrder(lines, readOffer, getCount, getMoney)
    local order, items = {}, {}
    local cost = 0
    for _, approved in ipairs(lines) do
        if not IsInteger(approved.itemID, 1, MAX_UNITS) or not IsInteger(approved.index, 1, MAX_UNITS) then
            return nil, "Invalid vendor item"
        end
        if items[approved.itemID] then return nil, "Duplicate item in purchase" end
        local quote, reason = ValidateOffer(approved, approved.quantity, readOffer(approved))
        if not quote then return nil, reason end
        if quote.cost ~= approved.cost or quote.cost > MAX_COPPER - cost then
            return nil, "Purchase cost changed"
        end

        local count = getCount(quote.itemID)
        if not IsInteger(count, 0, MAX_UNITS) or quote.quantity > MAX_UNITS - count then
            return nil, "Invalid bag quantity"
        end
        items[quote.itemID] = true
        cost = cost + quote.cost
        order[#order + 1] = { quote = quote, remaining = quote.quantity, bagCount = count }
    end
    if #order == 0 then return nil, "Nothing to buy" end
    if not CanAfford(getMoney(), cost) then return nil, "Not enough money" end
    return { lines = order, cost = cost }
end

local function ReadApprovedOffer(approved)
    return ReadOffer(approved.index)
end

function Merchant.Start(lines, callback, onUpdate)
    if pending then return false, "Purchase in progress" end
    if not MerchantIsOpen() then return false, "Merchant closed" end
    if InCombatLockdown() then return false, "Leave combat to purchase" end
    if HasSettlingDelivery() then return false, "Previous purchase is still settling" end

    local approved, reason = Merchant.ValidateOrder(lines, ReadApprovedOffer, BagCount, GetMoney)
    if not approved then return false, reason end
    local purchase = {
        lines = approved.lines, index = 1, remainingCost = approved.cost, callback = callback, onUpdate = onUpdate,
    }
    pending = purchase
    purchase.timer = C_Timer.NewTicker(PURCHASE_INTERVAL, function() Tick(purchase) end)
    return true
end
