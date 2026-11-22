local _, addon = ...

local Planner = {}
addon.Planner = Planner

function Planner.Build(required, offers, count)
    local ordered = {}
    for itemID in pairs(required) do
        ordered[#ordered + 1] = itemID
    end
    table.sort(ordered)

    local plan = { lines = {}, cost = 0 }
    for _, itemID in ipairs(ordered) do
        local missing = required[itemID] - count(itemID)
        if missing > 0 then
            local offer = offers[itemID]
            if not offer then return nil, "Vendor missing an item", itemID end
            local line, reason = addon.Merchant.Quote(offer, missing)
            if not line then return nil, reason, itemID end
            plan.lines[#plan.lines + 1] = line
            plan.cost = plan.cost + line.cost
        end
    end
    return plan
end

function Planner.Recipe(rank, crafts)
    local required = {}
    for _, reagent in ipairs(rank.reagents) do
        local itemID = reagent.itemID
        required[itemID] = (required[itemID] or 0) + reagent.count * crafts
    end
    return required
end

function Planner.SameOrder(first, second)
    if not first or not second or #first.lines ~= #second.lines or first.cost ~= second.cost then
        return false
    end
    for index, line in ipairs(first.lines) do
        local other = second.lines[index]
        if line.itemID ~= other.itemID or line.quantity ~= other.quantity or line.cost ~= other.cost
            or line.bundleSize ~= other.bundleSize or line.price ~= other.price then
            return false
        end
    end
    return true
end
