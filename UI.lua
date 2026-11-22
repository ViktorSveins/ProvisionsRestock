local addonName, addon = ...

local UI = {}
addon.UI = UI

local PANEL_WIDTH = 336
local MIN_PANEL_WIDTH = 280
local MARGIN = 11
local LIST_TOP = 64
local LIST_BOTTOM = 30
local CUSTOMIZE_TOP = 90
local CUSTOMIZE_ROW_HEIGHT = 43
local SCROLLBAR_WIDTH = 12
local BUY_INSET = 4
local BUY_WIDTH = 46
local BATCH_WIDTH = 64
local COLUMN_GAP = 6
local KEEP_WIDTH = 38
local COUNT_WIDTH = 36
local KEEP_INSET = BUY_INSET + BUY_WIDTH + COLUMN_GAP
local COUNT_INSET = KEEP_INSET + KEEP_WIDTH + COLUMN_GAP
local TAB_GAP = 6

local panel

local function Text(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Button(parent, caption, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(caption)
    button:SetMotionScriptsWhileDisabled(true)
    return button
end

local function CheckButton(parent, size)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetSize(size, size)
    button:SetMotionScriptsWhileDisabled(true)
    return button
end

function UI.FormatMoney(amount)
    local formatter = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
    return formatter and formatter(amount, 12) or ("%d copper"):format(amount)
end

local function Price(amount)
    return amount == 0 and "Free" or UI.FormatMoney(amount)
end

local function ItemName(itemID)
    return itemID and (C_Item.GetItemNameByID(itemID) or ("Item %d"):format(itemID))
end

local function HideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function ShowTooltip(owner, title, note, plan, titleItemID)
    if not title then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(title, 1, 1, 1)
    if note and note ~= "" then GameTooltip:AddLine(note, 0.83, 0.83, 0.83, true) end
    if plan then
        for _, entry in ipairs(plan.lines) do
            local label = entry.itemID == titleItemID and ("Qty %d"):format(entry.quantity)
                or ("%d × %s"):format(entry.quantity, entry.name or ItemName(entry.itemID))
            GameTooltip:AddDoubleLine(label, Price(entry.cost), 1, 1, 1, 1, 1, 1)
        end
        if #plan.lines > 1 then
            GameTooltip:AddDoubleLine("Total", Price(plan.cost), 1, 0.82, 0, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function AttachTooltip(owner, show)
    owner:SetScript("OnEnter", show)
    owner:SetScript("OnLeave", HideTooltip)
    owner:HookScript("OnHide", HideTooltip)
end

local function RefreshTooltip(owner)
    if owner:IsVisible() and GameTooltip:IsOwned(owner) then
        owner:GetScript("OnEnter")(owner)
    end
end

local function DisplayName(data)
    return data.name or ItemName(data.itemID) or "Supply"
end

local function HasText(value)
    return type(value) == "string" and value ~= ""
end

local function RowNote(data)
    local name = DisplayName(data)
    local lines, seen = {}, { [name] = true }
    for _, key in ipairs({ "purpose", "detail" }) do
        local line = data[key]
        if HasText(line) and not seen[line] then
            lines[#lines + 1] = line
            seen[line] = true
        end
    end
    if data.autoPaused then lines[#lines + 1] = "Auto paused by Reagent Economy" end
    return table.concat(lines, "\n")
end

local function RowStatus(data)
    if data.plan then
        local quantity = data.rank and "Mats" or ("+%d"):format(data.plan.lines[1].quantity)
        return quantity .. " · " .. Price(data.plan.cost)
    end
    if data.status == "Ready to craft" then return ("%d craftable"):format(data.craftOutput) end
    if data.rankUnavailable then return "Not sold here" end
    if data.status ~= "Stocked" then return data.status or "" end
    return ""
end

local function ResetEdit(row)
    local input = row.target
    input.editKey = nil
    if not input.endingEdit and input:HasFocus() then input:ClearFocus() end
    local target = row.data and row.data.target or 0
    input:SetText(target > 0 and tostring(target) or "")
end

local function ClearTargetFocus(page)
    for _, row in ipairs((page or panel.restock).rows) do
        if row.target:HasFocus() then
            row.target:ClearFocus()
            return true
        end
    end
end

local function CreateTargetInput(row, commit)
    local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    input:SetSize(KEEP_WIDTH, 19)
    input:SetJustifyH("CENTER")
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(4)
    input:SetScript("OnEditFocusGained", function(self)
        self.editKey = row.data and row.data.key
        self:HighlightText()
    end)
    input:SetScript("OnEditFocusLost", function(self)
        if self.endingEdit then return end
        self.endingEdit = true
        local key = self.editKey
        self.editKey = nil
        self:HighlightText(0, 0)
        if key and self:IsVisible() and row.data and row.data.key == key then
            local value = self:GetText()
            local target = value == "" and 0 or tonumber(value)
            if target then commit(key, target) end
        end
        ResetEdit(row)
        self.endingEdit = nil
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function() ResetEdit(row) end)
    input:HookScript("OnHide", function() ResetEdit(row) end)
    return input
end

local function CreateIcon(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 8, -9)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    local rim = row:CreateTexture(nil, "OVERLAY")
    rim:SetAtlas("ui-hud-actionbar-iconframe")
    rim:SetSize(36, 36)
    rim:SetPoint("CENTER", icon)
    return icon
end

local function SetIcon(row, data)
    row.icon:SetTexture(data.itemID and C_Item.GetItemIconByID(data.itemID) or 134400)
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row:HookScript("OnHide", ResetEdit)
    AttachTooltip(row, function(owner)
        local data = row.data
        if data then ShowTooltip(owner, DisplayName(data), RowNote(data)) end
    end)

    local shade = row:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", 1, -2)
    shade:SetPoint("BOTTOMRIGHT", -1, 3)
    shade:SetColorTexture(0.16, 0.14, 0.11, 0.28)

    row.icon = CreateIcon(row)
    row.name = Text(row)
    row.name:SetWordWrap(true)
    row.name:SetMaxLines(2)
    row.name:SetPoint("TOPLEFT", 44, -10)

    row.rankNext = Button(row, ">", 18, 18)
    row.rankText = Text(row, "GameFontNormalSmall")
    row.rankText:SetPoint("RIGHT", row.rankNext, "LEFT", -3, 0)
    row.rankPrevious = Button(row, "<", 18, 18)
    row.rankPrevious:SetPoint("RIGHT", row.rankText, "LEFT", -3, 0)
    for _, button in ipairs({ row.rankPrevious, row.rankNext }) do
        button:SetScript("OnClick", function(self)
            if not row.data then return end
            ResetEdit(row)
            addon.SetRank(row.data.key, self == row.rankPrevious and -1 or 1)
        end)
    end

    row.auto = CheckButton(row, 17)
    row.auto.caption = Text(row.auto)
    row.auto.caption:SetPoint("LEFT", row.auto, "RIGHT", 1, 0)
    row.auto.caption:SetText("Auto stock")
    row.auto:SetHitRectInsets(0, -54, 0, 0)
    row.auto:SetScript("OnClick", function(self)
        if not row.data or not row.data.autoAllowed then return end
        local key, itemID, checked = row.data.key, row.data.itemID, self:GetChecked() == true
        ClearTargetFocus()
        if row.data and row.data.key == key and row.data.itemID == itemID then addon.SetAuto(key, checked) end
    end)
    AttachTooltip(row.auto, function(owner)
        local data = row.data
        if not data then return end
        local note = data.target == 0 and "Set Keep first" or "Refill to Keep on later visits"
        ShowTooltip(owner, "Auto stock", note)
    end)

    row.autoPaused = Text(row, "GameFontNormalSmall")
    row.autoPaused:SetText("Auto paused")
    row.autoPaused:SetTextColor(1, 0.74, 0.38)

    row.count = Text(row)
    row.count:SetWidth(COUNT_WIDTH)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("TOPRIGHT", -COUNT_INSET, -13)
    row.name:SetPoint("TOPRIGHT", row.count, "TOPLEFT", -5, 3)
    row.buy = Button(row, "Buy", BUY_WIDTH, 21)
    row.buy:SetPoint("TOPRIGHT", -BUY_INSET, -8)
    row.buy:SetScript("OnClick", function()
        if not row.data then return end
        local key = row.data.key
        if ClearTargetFocus() then return end
        if row.data and row.data.key == key and row.data.plan then addon.Buy(key) end
    end)
    AttachTooltip(row.buy, function(owner)
        local data = row.data
        if not data then return end
        local note = not data.plan and RowStatus(data) or nil
        ShowTooltip(owner, DisplayName(data), note, data.plan, data.itemID)
    end)

    row.target = CreateTargetInput(row, function(key, target) addon.SetTarget(key, target) end)
    row.target:SetPoint("RIGHT", row.buy, "LEFT", -COLUMN_GAP, 0)
    row.status = Text(row)

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetColorTexture(0.38, 0.32, 0.22, 0.55)
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", 5, 1)
    row.divider:SetPoint("BOTTOMRIGHT", -5, 1)
    return row
end

local function CreateDevBatch(row)
    local button = Button(row, "Test ×5", BATCH_WIDTH, 19)
    button:SetScript("OnClick", function()
        if not row.data then return end
        local key = row.data.key
        if ClearTargetFocus() then return end
        if row.data and row.data.key == key and row.data.devPlan then addon.Buy(key, 5) end
    end)
    AttachTooltip(button, function(owner)
        if not row.data then return end
        ShowTooltip(owner, "Simulated batch", row.data.devReason, row.data.devPlan)
    end)
    return button
end

local function Layout(data, simulated)
    local status = RowStatus(data)
    local rank = (data.rankCount or 0) > 1
    local batch = simulated and (data.devPlan or data.devReason)
    local auto = data.autoAllowed or data.autoPaused
    local controlY = 32
    local autoY = auto and (rank and controlY + 20 or controlY)
    local devY
    if batch then
        devY = autoY and autoY + 20 or (rank and controlY + 20 or controlY)
    end
    local lastControl = devY or autoY or (rank and controlY)
    return {
        status = status, rank = rank, controlY = controlY, autoY = autoY, devY = devY,
        height = lastControl and lastControl + 23 or (status ~= "" and 51 or 43),
    }
end

local function UpdateRow(row, data, busy, layout)
    if not row.data or row.data.key ~= data.key or row.data.rankIndex ~= data.rankIndex then
        ResetEdit(row)
    end
    row.data = data
    local canBuy = data.plan ~= nil and not busy
    local hasTarget = (data.target or 0) > 0

    row.buy:SetEnabled(canBuy)
    row.target:EnableMouse(not busy)
    row.auto:SetShown(data.autoAllowed == true and not data.autoPaused)
    row.auto:SetChecked(data.auto == true)
    row.auto:SetEnabled(not busy and hasTarget)
    row.auto:SetAlpha(hasTarget and 1 or 0.65)
    if layout.autoY then
        row.auto:ClearAllPoints()
        row.auto:SetPoint("TOPRIGHT", -(BUY_INSET + 54), -layout.autoY)
    end
    SetIcon(row, data)

    row.rankPrevious:SetShown(layout.rank)
    row.rankText:SetShown(layout.rank)
    row.rankNext:SetShown(layout.rank)
    if layout.rank then
        row.rankNext:ClearAllPoints()
        row.rankNext:SetPoint("TOPRIGHT", -BUY_INSET, -layout.controlY)
        row.rankText:SetText(tostring(data.knownRanks[data.rankIndex].index))
        row.rankPrevious:SetEnabled(not busy and data.rankIndex > 1)
        row.rankNext:SetEnabled(not busy and data.rankIndex < data.rankCount)
    end
    row.name:SetText(DisplayName(data))

    row.count:SetText(tostring(data.have or 0))
    row.status:ClearAllPoints()
    row.status:SetPoint("TOPLEFT", 44, -(layout.controlY + 4))
    if layout.rank then
        row.status:SetPoint("TOPRIGHT", row.rankPrevious, "TOPLEFT", -6, -4)
    else
        local inset = BUY_INSET
        if layout.autoY then inset = inset + 72 end
        if layout.devY == layout.controlY then inset = inset + BATCH_WIDTH + COLUMN_GAP end
        row.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", -inset, -(layout.controlY + 4))
    end
    if data.plan then
        row.status:SetTextColor(1, 0.82, 0.33)
    elseif data.status == "Ready to craft" then
        row.status:SetTextColor(0.49, 0.8, 0.42)
    else
        row.status:SetTextColor(0.7, 0.7, 0.7)
    end
    row.status:SetText(layout.status)
    row.autoPaused:SetShown(data.autoPaused == true)
    if data.autoPaused then
        row.autoPaused:ClearAllPoints()
        row.autoPaused:SetPoint("TOPRIGHT", -BUY_INSET, -(layout.autoY + 4))
    end
    if layout.devY then
        row.devBatch = row.devBatch or CreateDevBatch(row)
        row.devBatch:ClearAllPoints()
        row.devBatch:SetPoint("TOPRIGHT", -BUY_INSET, -layout.devY)
        row.devBatch:SetText(("Test ×%d"):format(data.devQuantity or 5))
        row.devBatch:SetEnabled(not busy and data.devPlan ~= nil)
        row.devBatch:Show()
        RefreshTooltip(row.devBatch)
    elseif row.devBatch then
        row.devBatch:Hide()
    end
    if busy or not row.target:HasFocus() then ResetEdit(row) end
    RefreshTooltip(row)
    RefreshTooltip(row.buy)
    RefreshTooltip(row.auto)
end

local function RestoreChrome(frame)
    if not frame.joinedChrome then return end
    for _, texture in ipairs(frame.joinedChrome.textures) do texture:Show() end
    for _, bridge in pairs(frame.bridges) do bridge:Hide() end
    frame.joinedChrome = nil
end

local function RestoreMerchantClose(frame)
    local original = frame.merchantClose
    if not original then return end
    original.button:ClearAllPoints()
    for _, point in ipairs(original.points) do
        original.button:SetPoint(unpack(point, 1, 5))
    end
    frame.merchantClose = nil
end

local function DockMerchantClose(frame)
    local button = frame.host == MerchantFrame and frame.host.CloseButton
    if frame.merchantClose or not button or button:IsProtected() or not button:IsShown() then return end

    local points = {}
    for index = 1, button:GetNumPoints() do
        points[index] = { button:GetPoint(index) }
    end
    if #points == 0 then return end
    frame.merchantClose = { button = button, points = points }
    -- Keep the original parent so Blizzard's click handler closes the merchant.
    button:ClearAllPoints()
    -- Match the merchant's X inset against the extension's border artwork.
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 2)
end

local function SpanSeam(texture, left, right)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", left, "TOPRIGHT", -1, 0)
    texture:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 1, 0)
    texture:Show()
end

local function JoinChrome(frame, host)
    if frame.joinedChrome and frame.joinedChrome.host == host then return true end
    RestoreChrome(frame)
    local native, extension = host.NineSlice, frame.NineSlice
    if host ~= MerchantFrame or not native or not extension or not host.Bg or not frame.Bg
        or not host.TopTileStreaks or not frame.TopTileStreaks then
        return false
    end

    local innerTrim = {}
    for _, parts in ipairs({
        { native, "RightEdge", "TopRightCorner", "BottomRightCorner" },
        { extension, "LeftEdge", "TopLeftCorner", "BottomLeftCorner" },
    }) do
        for index = 2, #parts do
            local texture = parts[1][parts[index]]
            if not texture or not texture:IsShown() then return false end
            innerTrim[#innerTrim + 1] = texture
        end
    end
    if not native.TopEdge or not native.BottomEdge or not extension.TopEdge or not extension.BottomEdge then
        return false
    end
    local topAtlas, bottomAtlas = native.TopEdge:GetAtlas(), native.BottomEdge:GetAtlas()
    if not topAtlas or not bottomAtlas
        or topAtlas ~= extension.TopEdge:GetAtlas() or bottomAtlas ~= extension.BottomEdge:GetAtlas() then
        return false
    end
    local backdrop, streaks = host.Bg:GetTexture(), host.TopTileStreaks:GetAtlas()
    if not backdrop or backdrop ~= frame.Bg:GetTexture() or not streaks
        or streaks ~= frame.TopTileStreaks:GetAtlas() then
        return false
    end

    -- Replace the interior outer trim with continuous rails. The two inset
    -- borders stay in place as the divider, and the merchant owns its close button.
    local bridges = frame.bridges
    bridges.top:SetAtlas(topAtlas)
    bridges.bottom:SetAtlas(bottomAtlas)
    bridges.backdrop:SetTexture(backdrop)
    bridges.streaks:SetAtlas(streaks)
    SpanSeam(bridges.top, native.TopEdge, extension.TopEdge)
    SpanSeam(bridges.bottom, native.BottomEdge, extension.BottomEdge)
    SpanSeam(bridges.backdrop, host.Bg, frame.Bg)
    SpanSeam(bridges.streaks, host.TopTileStreaks, frame.TopTileStreaks)
    for _, texture in ipairs(innerTrim) do texture:Hide() end
    frame.joinedChrome = { host = host, textures = innerTrim }
    return true
end

local function UpdateDock()
    local host = panel.host
    local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local roomLeft = (host:GetLeft() or 0)
    local roomRight = UIParent:GetWidth() / scale - (host:GetRight() or 0)
    local onLeft = roomRight < PANEL_WIDTH + 8 and roomLeft > roomRight
    local available = (onLeft and roomLeft or roomRight) - 8
    local joined = not onLeft and available >= MIN_PANEL_WIDTH and JoinChrome(panel, host)
    if not joined then RestoreChrome(panel) end
    panel:SetSize(math.max(MIN_PANEL_WIDTH, math.min(PANEL_WIDTH, available)), host:GetHeight())
    panel:ClearAllPoints()
    panel:SetPoint(onLeft and "TOPRIGHT" or "TOPLEFT", host, onLeft and "TOPLEFT" or "TOPRIGHT",
        (onLeft or joined) and 0 or -5, 0)
    if onLeft then
        RestoreMerchantClose(panel)
    else
        DockMerchantClose(panel)
    end
end

local function AnchorReopen(frame)
    local host = frame.host
    local buyback = host == MerchantFrame and MerchantFrameTab2
    frame.reopen:ClearAllPoints()
    if buyback and buyback:IsShown() then
        frame.reopen:SetPoint("LEFT", buyback, "RIGHT", TAB_GAP, 0)
    else
        frame.reopen:SetPoint("RIGHT", host, "BOTTOMRIGHT", -12, -15)
    end
end

local function UpdateListSize(frame, contentHeight)
    local rowsHeight = math.max(1, contentHeight)
    local scrollHeight = math.max(1, frame:GetHeight() - frame.listTop - LIST_BOTTOM)
    local range = math.max(0, rowsHeight - scrollHeight)
    local width = frame:GetWidth() - MARGIN * 2 - (range > 0 and SCROLLBAR_WIDTH or 0)

    frame.scroll:SetSize(width, scrollHeight)
    frame.scrollChild:SetSize(width, rowsHeight)
    frame.scrollbar:SetHeight(scrollHeight)
    frame.scrollbar:SetShown(range > 0)
    frame.scrollRange = range
    frame.scrollbar:SetMinMaxValues(0, math.max(1, range))
    frame.scrollbar:SetValue(math.min(frame.scrollbar:GetValue(), range))
    frame.scroll:SetVerticalScroll(frame.scrollbar:GetValue())
    return width
end

local function CreateList(frame, top)
    frame.listTop = top
    local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 5, -(top - 4))
    inset:SetPoint("BOTTOMRIGHT", -6, LIST_BOTTOM - 4)
    frame.scroll = CreateFrame("ScrollFrame", nil, inset)
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN, -top)
    frame.scroll:EnableMouseWheel(true)
    frame.scrollChild = CreateFrame("Frame", nil, frame.scroll)
    frame.scrollChild:SetSize(1, 1)
    frame.scroll:SetScrollChild(frame.scrollChild)
    frame.scrollbar = CreateFrame("Slider", nil, inset)
    frame.scrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -MARGIN, -top)
    frame.scrollbar:SetSize(11, 1)
    frame.scrollbar:SetOrientation("VERTICAL")
    frame.scrollbar:SetMinMaxValues(0, 1)
    frame.scrollbar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    frame.scrollbar:GetThumbTexture():SetSize(11, 22)
    local track = frame.scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.35)
    frame.scrollbar:SetScript("OnValueChanged", function(_, value) frame.scroll:SetVerticalScroll(value) end)
    frame.scroll:SetScript("OnMouseWheel", function(_, delta)
        local nextValue = frame.scrollbar:GetValue() - delta * 40
        frame.scrollbar:SetValue(math.max(0, math.min(frame.scrollRange or 0, nextValue)))
    end)
    frame.scrollbar:SetValue(0)
end

local function CreateColumnHeadings(frame, showColumn)
    local itemHeading = Text(frame, "GameFontNormalSmall")
    itemHeading:SetPoint("BOTTOMLEFT", frame.scroll, "TOPLEFT", 44, 9)
    itemHeading:SetText("Item")
    local columns = { { "Bags", COUNT_WIDTH, COUNT_INSET }, { "Keep", KEEP_WIDTH, KEEP_INSET } }
    if showColumn then columns[#columns + 1] = { "Show", BUY_WIDTH, BUY_INSET } end
    for _, column in ipairs(columns) do
        local heading = Text(frame, "GameFontNormalSmall")
        heading:SetJustifyH("CENTER")
        heading:SetWidth(column[2])
        heading:SetPoint("BOTTOMRIGHT", frame.scroll, "TOPRIGHT", -column[3], 9)
        heading:SetText(column[1])
    end
end

local function ProfileStatus(view)
    if not view.profileName then return "" end
    local status = "Simulation · " .. view.profileName
    if type(view.money) == "number" then status = status .. " · " .. UI.FormatMoney(view.money) end
    return status
end

local function CreatePage(parent, top, showColumn)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page.rows = {}
    CreateList(page, top)
    CreateColumnHeadings(page, showColumn)
    return page
end

local function SetMessage(message)
    panel.status:SetShown(HasText(message))
    panel.status:SetText(message or "")
end

local function TryAdd(page, cursorOnly)
    local kind, itemID
    if GetCursorInfo then kind, itemID = GetCursorInfo() end
    local hasItem = not (issecretvalue and (issecretvalue(kind) or issecretvalue(itemID)))
        and kind == "item" and type(itemID) == "number"
    if cursorOnly and not hasItem then return end

    local value = hasItem and itemID or page.input:GetText()
    if value == "" then
        page.input:SetFocus()
        return
    end
    local ok, reason = addon.AddCustomItem(value)
    if ok then
        if hasItem and ClearCursor then ClearCursor() end
        page.input:SetText("")
        page.input:ClearFocus()
        page.scrollbar:SetValue(0)
    end
    page.message = not ok and reason or nil
    SetMessage(page.message)
end

local itemLinkHooked, stackSplitHooked, pendingSplit

local function HideCapturedStackSplit(frame, _, owner)
    local click = pendingSplit
    if click and owner and owner.GetBagID and owner.GetID
        and owner:GetBagID() == click.bag and owner:GetID() == click.slot then
        pendingSplit = nil
        if not frame:IsProtected() then frame:Hide() end
    end
end

local function CaptureItemLink(link, location)
    local page = panel and panel.customize
    if not page or not panel.view or not page:IsVisible() or not page.input:HasFocus() or panel.view.busy
        or not IsModifiedClick("CHATLINK") then return end
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
    local itemID = link:match("|Hitem:(%d+)")
    if not itemID then return end
    page.input:SetText(itemID)
    page.input:SetCursorPosition(#itemID)

    -- Bag buttons can fall through to Shift-click stack splitting after a link click.
    if type(location) ~= "table" or not location.IsBagAndSlot or not location:IsBagAndSlot()
        or not IsModifiedClick("SPLITSTACK") or not StackSplitFrame or not StackSplitFrame.OpenStackSplitFrame then return end
    if not stackSplitHooked then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", HideCapturedStackSplit)
        stackSplitHooked = true
    end
    local bag, slot = location:GetBagAndSlot()
    local click = { bag = bag, slot = slot }
    pendingSplit = click
    C_Timer.After(0, function()
        if pendingSplit == click then pendingSplit = nil end
    end)
end

local function CreateCustomizePage(parent)
    local page = CreatePage(parent, CUSTOMIZE_TOP, true)
    page:Hide()
    page.add = Button(page, "Add", BUY_WIDTH, 20)
    page.add:SetPoint("TOPRIGHT", -MARGIN, -47)
    page.add:SetScript("OnClick", function() TryAdd(page) end)
    page.add:SetScript("OnReceiveDrag", function() TryAdd(page, true) end)
    page.input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.input:SetAutoFocus(false)
    page.input:SetMaxLetters(255)
    page.input:SetHeight(20)
    page.input:SetPoint("LEFT", page, "TOPLEFT", MARGIN + 6, -57)
    page.input:SetPoint("RIGHT", page.add, "LEFT", -COLUMN_GAP, 0)
    page.input:SetScript("OnEnterPressed", function() TryAdd(page) end)
    page.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    page.hint = Text(page, "GameFontHighlightSmall")
    page.hint:SetTextColor(0.58, 0.58, 0.58)
    page.hint:SetPoint("LEFT", page.input, "LEFT", 5, 0)
    page.hint:SetText("Shift-click a bag item or enter ID")
    page.input:SetScript("OnTextChanged", function(self)
        page.hint:SetShown(self:GetText() == "")
        if page.message then
            page.message = nil
            if page:IsVisible() then SetMessage() end
        end
    end)
    page.input:SetScript("OnEditFocusGained", function()
        if not itemLinkHooked and hooksecurefunc and HandleModifiedItemClick then
            hooksecurefunc("HandleModifiedItemClick", CaptureItemLink)
            itemLinkHooked = true
        end
    end)
    page:HookScript("OnHide", function()
        pendingSplit = nil
        page.input:ClearFocus()
        page.input:SetText("")
        page.message = nil
    end)
    return page
end

local function CreateCustomizeRow(page)
    local row = CreateFrame("Frame", nil, page.scrollChild)
    row:EnableMouse(true)
    row:HookScript("OnHide", ResetEdit)
    row.icon = CreateIcon(row)
    row.name = Text(row)
    row.name:SetWordWrap(true)
    row.name:SetMaxLines(2)
    row.name:SetPoint("TOPLEFT", 44, -10)
    row.count = Text(row)
    row.count:SetWidth(COUNT_WIDTH)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("TOPRIGHT", -COUNT_INSET, -13)
    row.name:SetPoint("TOPRIGHT", row.count, "TOPLEFT", -5, 3)
    row.target = CreateTargetInput(row, function(key, target) addon.SetCustomizeTarget(key, target) end)
    row.target:SetPoint("TOPRIGHT", -KEEP_INSET, -8)

    row.show = CheckButton(row, 19)
    row.show:SetPoint("TOPRIGHT", -(BUY_INSET + (BUY_WIDTH - 19) / 2), -8)
    AttachTooltip(row.show, function(owner) ShowTooltip(owner, "Show in Restock") end)
    row.show:SetScript("OnClick", function(self)
        local key, shown = row.data.key, self:GetChecked() == true
        ClearTargetFocus(page)
        if row.data and row.data.key == key then addon.SetDefaultShown(key, shown) end
    end)

    row.remove = Button(row, "Remove", BUY_WIDTH, 19)
    row.remove:SetPoint("TOPRIGHT", -BUY_INSET, -8)
    row.remove:SetScript("OnClick", function()
        local key = row.data.key
        ClearTargetFocus(page)
        local ok, reason = addon.RemoveCustomItem(key)
        page.message = not ok and reason or nil
        SetMessage(page.message)
    end)

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetColorTexture(0.38, 0.32, 0.23, 0.55)
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", 5, 1)
    row.divider:SetPoint("BOTTOMRIGHT", -5, 1)
    AttachTooltip(row, function(owner)
        if row.data then ShowTooltip(owner, row.name:GetText(), RowNote(row.data)) end
    end)
    return row
end

local function HideExtraRows(page, first)
    for index = first, #page.rows do
        local row = page.rows[index]
        ResetEdit(row)
        row.data = nil
        row:Hide()
    end
end

local function RenderCustomize(page, dataRows, view)
    local rows = {}
    for _, data in ipairs(dataRows) do
        if data.custom then rows[#rows + 1] = data end
    end
    for _, data in ipairs(dataRows) do
        if not data.custom then rows[#rows + 1] = data end
    end
    page.add:SetEnabled(not view.busy)
    page.input:EnableMouse(not view.busy)
    if view.busy then page.input:ClearFocus() end
    local width = UpdateListSize(page, #rows * CUSTOMIZE_ROW_HEIGHT)
    for index, data in ipairs(rows) do
        local row = page.rows[index]
        if not row then
            row = CreateCustomizeRow(page)
            page.rows[index] = row
        elseif row.data and row.data.key ~= data.key then
            ResetEdit(row)
        end
        row.data = data
        row:SetSize(width, CUSTOMIZE_ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * CUSTOMIZE_ROW_HEIGHT)
        SetIcon(row, data)
        row.name:SetText(DisplayName(data))
        row:SetAlpha(data.canHide and not data.shown and 0.65 or 1)
        row.count:SetText(tostring(data.have or 0))
        row.show:SetShown(data.canHide == true)
        row.show:SetChecked(data.shown == true)
        row.show:SetEnabled(not view.busy)
        row.remove:SetShown(data.custom == true)
        row.remove:SetEnabled(not view.busy)
        row.target:EnableMouse(not view.busy)
        if view.busy or not row.target:HasFocus() then ResetEdit(row) end
        row.divider:SetShown(index < #rows)
        row:Show()
        RefreshTooltip(row)
    end
    HideExtraRows(page, #rows + 1)
end

local function CreatePanel(host)
    local frame = CreateFrame("Frame", addonName .. "VendorPanel", host, "DefaultPanelTemplate")
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame.mode = "restock"
    frame.collapsed = false
    frame.TitleContainer.TitleText:SetText("Provisions Restock")
    frame.bridges = {
        top = frame.NineSlice:CreateTexture(nil, "OVERLAY"),
        bottom = frame.NineSlice:CreateTexture(nil, "OVERLAY"),
        backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -6),
        streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -5),
    }
    for _, bridge in pairs(frame.bridges) do
        bridge:SetHorizTile(true)
        bridge:Hide()
    end
    frame.bridges.backdrop:SetVertTile(true)
    local restockTab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    frame.restockTab = restockTab
    restockTab:SetPoint("CENTER", frame, "BOTTOMLEFT", 50, -15)
    restockTab:SetText("Restock")
    PanelTemplates_TabResize(restockTab, 0)
    AttachTooltip(restockTab, function(owner)
        if frame.mode == "restock" then ShowTooltip(owner, "Collapse Provisions Restock") end
    end)
    restockTab:SetScript("OnClick", function()
        if frame.mode == "restock" then
            frame.collapsed = true
            UI.Render(frame.latestRows, frame.view, frame.customizeRows)
        else
            UI.SelectView("restock")
        end
    end)

    frame.restock = CreatePage(frame, LIST_TOP)
    frame.customize = CreateCustomizePage(frame)
    frame.profile = Text(frame, "GameFontNormalSmall")
    frame.profile:SetPoint("TOPLEFT", MARGIN + 4, -31)
    frame.profile:SetPoint("TOPRIGHT", -MARGIN, -31)
    frame.profile:SetTextColor(1, 0.74, 0.38)
    frame.empty = Text(frame.restock.scrollChild)
    frame.empty:SetPoint("TOPLEFT", 7, -7)
    frame.empty:SetText("No matching supplies")
    frame.empty:Hide()
    frame.customizeTab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    frame.customizeTab:SetPoint("LEFT", restockTab, "RIGHT", TAB_GAP, 0)
    frame.customizeTab:SetText("Customize")
    PanelTemplates_TabResize(frame.customizeTab, 0)
    frame.customizeTab:SetScript("OnClick", function() UI.SelectView("customize") end)
    frame.status = Text(frame, "GameFontNormalSmall")
    frame.status:SetPoint("BOTTOMLEFT", MARGIN, 8)
    frame.status:SetPoint("BOTTOMRIGHT", -MARGIN, 8)

    -- The native template inserts itself into its parent's Tabs array.
    -- Keep the collapsed button out of the merchant's Merchant/Buyback tabs.
    frame.reopenHolder = CreateFrame("Frame", nil, host)
    frame.reopenHolder:SetAllPoints(host)
    frame.reopen = CreateFrame("Button", nil, frame.reopenHolder, "PanelTabButtonTemplate")
    frame.reopen:SetText("Restock")
    PanelTemplates_TabResize(frame.reopen, 0)
    PanelTemplates_DeselectTab(frame.reopen)
    frame.reopen:Hide()
    AttachTooltip(frame.reopen, function(owner)
        ShowTooltip(owner, "Expand Provisions Restock")
    end)
    frame.reopen:SetScript("OnClick", function()
        UI.SelectView("restock")
    end)

    frame:HookScript("OnHide", function()
        RestoreChrome(frame)
        RestoreMerchantClose(frame)
    end)
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function()
        if frame:IsShown() and frame.view then UI.Render(frame.latestRows, frame.view, frame.customizeRows) end
    end)
    return frame
end

local function RenderRestock(page, rows, view)
    local layouts, contentHeight = {}, 0
    for index, data in ipairs(rows) do
        local layout = Layout(data, view.profileName ~= nil)
        layouts[index] = layout
        contentHeight = contentHeight + layout.height
    end
    local width = UpdateListSize(page, #rows == 0 and 24 or contentHeight)
    panel.empty:SetShown(#rows == 0)
    SetMessage(view.message or (view.busy and "Buying…"))

    local y = 0
    for index, data in ipairs(rows) do
        local row = page.rows[index]
        if not row then
            row = CreateRow(page.scrollChild)
            page.rows[index] = row
        end
        local layout = layouts[index]
        row:SetSize(width, layout.height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        UpdateRow(row, data, view.busy, layout)
        row.divider:SetShown(index < #rows)
        row:Show()
        y = y + layout.height
    end
    HideExtraRows(page, #rows + 1)
end

function UI.Render(rows, view, customizeRows)
    local host = view.host or MerchantFrame
    if not host then
        UI.Hide()
        return
    end
    panel = panel or CreatePanel(host)
    if panel.host and panel.host ~= host then
        RestoreChrome(panel)
        RestoreMerchantClose(panel)
        panel:SetParent(host)
        panel.reopenHolder:SetParent(host)
        panel.reopenHolder:SetAllPoints(host)
    end
    panel.host, panel.latestRows, panel.view, panel.customizeRows = host, rows, view, customizeRows
    panel:SetFrameStrata(host:GetFrameStrata())
    panel:SetFrameLevel(host:GetFrameLevel() + 1)
    local collapsed = panel.collapsed or (#rows == 0 and not panel.openedThisVisit)
    panel:SetShown(not collapsed)
    panel.reopen:SetShown(collapsed)
    if collapsed then
        AnchorReopen(panel)
        return
    end
    panel.openedThisVisit = true

    UpdateDock()
    panel.profile:SetText(ProfileStatus(view))
    local customizing = panel.mode == "customize"
    if panel.selectedMode ~= panel.mode then
        panel.selectedMode = panel.mode
        if customizing then
            PanelTemplates_DeselectTab(panel.restockTab)
            panel.restockTab:SetNormalFontObject(GameFontNormalSmall)
            PanelTemplates_SelectTab(panel.customizeTab)
        else
            PanelTemplates_DeselectTab(panel.customizeTab)
            PanelTemplates_SelectTab(panel.restockTab)
            panel.restockTab:SetNormalFontObject(GameFontHighlightSmall)
            panel.restockTab:Enable()
        end
    end
    panel.restock:SetShown(not customizing)
    panel.customize:SetShown(customizing)
    if customizing then
        RenderCustomize(panel.customize, customizeRows or {}, view)
        SetMessage(panel.customize.message or (view.busy and "Buying…"))
    else
        RenderRestock(panel.restock, rows, view)
    end
end

function UI.SelectView(mode)
    if not panel or not panel.view or (mode ~= "restock" and mode ~= "customize") then return end
    panel.mode, panel.collapsed, panel.openedThisVisit = mode, false, true
    UI.Render(panel.latestRows, panel.view, panel.customizeRows)
end

function UI.Hide()
    if not panel then return end
    RestoreChrome(panel)
    RestoreMerchantClose(panel)
    panel:Hide()
    panel.reopen:Hide()
    panel.restock.scrollbar:SetValue(0)
    panel.customize.scrollbar:SetValue(0)
    panel.mode, panel.view, panel.openedThisVisit = "restock", nil, nil
end
