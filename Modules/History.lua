local _, addon = ...
local History = {}
addon.History = History

local Widgets = addon.Widgets
local Recipients = addon.Recipients
local Tips = addon.Tips

local historyPanel
local historyTotals
local tipTooltipRegistered = false

function History.ViewTip(panel, tip)
    local isHistory = panel == historyPanel
    local view = panel.view
    if not view then
        view = CreateFrame("Frame", panel:GetName() .. "TipView", UIParent, "BackdropTemplate")
        panel.view = view
        view:SetSize(440, 280)
        view:SetPoint("CENTER")
        view:SetFrameStrata("DIALOG")
        view:EnableMouse(true)
        view.title = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        view.title:SetPoint("TOP", 0, -17)
        Widgets.StyleTipWindow(view, view.title, 43)
        Widgets.AddCloseButton(view)
        local titleBar = Widgets.MakeWindowMovable(view, "viewer", 38)
        Widgets.BindCharacterMenu(titleBar, function() return view.characterName end)

        if isHistory then
            view.timestamp = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            view.timestamp:SetPoint("TOP", 0, -50)
        end
        view.setMessage = Widgets.CreateTextScroll(view, isHistory and -75 or -59, 18, 388)
    end
    view.characterName = tip.name
    local name = Recipients.DisplayCharacterName(tip.name):gsub("|", "||")
    local body
    if isHistory then
        local direction = tip.direction == "Sent" and "Sent to" or "Received from"
        local amount = tip.amount and ("   " .. Tips.CoinAmount(tip.amount)) or ""
        view.title:SetText(direction .. " " .. name .. amount)
        local timestamp = date("%Y-%m-%d %I:%M %p", tip.timestamp)
        if tip.direction == "Received" then
            timestamp = (tip.expires and "Arrived approx. " or "Opened ") .. timestamp
        end
        view.timestamp:SetText(timestamp)
        body = tip.message or (tip.collected and "This letter was collected unopened.")
    else
        view.title:SetText(("%s for %s"):format(Tips.CoinAmount(tip.amount), name))
        body = Tips.ReviewBody(tip)
    end
    view:Show()
    view:Raise()
    view.setMessage(body and body ~= "" and body or "No message")
end

function History.AddEntry(entry)
    table.insert(TippleHistory, entry)
    table.sort(TippleHistory, function(a, b)
        if a.timestamp == b.timestamp then return a.order > b.order end
        return a.timestamp > b.timestamp
    end)
    History.Changed()
end

local function AddTippleTooltip(tooltip)
    if tooltip ~= GameTooltip or not TippleOptions.showTipTooltip or tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if not Recipients.IsReadable(unit) or not unit then return end
    local isPlayer = UnitIsPlayer(unit)
    if not Recipients.IsReadable(isPlayer) or not isPlayer then return end
    local faction = Recipients.UnitFaction(unit)
    if not faction or faction ~= Recipients.UnitFaction("player") then return end
    local name, realm = UnitFullName(unit)
    if not Recipients.IsReadable(name) or not name or not Recipients.IsReadable(realm) then return end
    local key = Recipients.CharacterKey(name, realm)
    if not key then return end

    if not historyTotals then
        historyTotals = {}
        for _, entry in ipairs(TippleHistory) do
            if entry.amount and entry.amount > 0 then
                local entryKey = Recipients.CharacterKey(entry.name)
                if entryKey then
                    local totals = historyTotals[entryKey] or { Sent = 0, Received = 0 }
                    totals[entry.direction] = totals[entry.direction] + entry.amount
                    historyTotals[entryKey] = totals
                end
            end
        end
    end
    local totals = historyTotals[key]
    if not totals then return end
    tooltip:AddLine("Tipple", 1, 0.83, 0.54)
    if totals.Sent > 0 then
        tooltip:AddLine("  Total Sent: " .. Tips.CoinAmount(totals.Sent), 1, 1, 1)
    end
    if totals.Received > 0 then
        tooltip:AddLine("  Total Received: " .. Tips.CoinAmount(totals.Received), 1, 1, 1)
    end
end

function History.RegisterTooltip()
    if TippleOptions.showTipTooltip and not tipTooltipRegistered then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTippleTooltip)
        tipTooltipRegistered = true
    end
end

local function RefreshHistory()
    local panel = historyPanel
    if not panel or not panel:IsShown() then return end
    local totals = { Sent = 0, Received = 0 }
    local query = panel.search:GetText():lower():match("^%s*(.-)%s*$")
    local matching = {}
    for _, entry in ipairs(TippleHistory) do
        if entry.amount then
            totals[entry.direction] = totals[entry.direction] + entry.amount
        end
        if (panel.direction == "All" or panel.direction == entry.direction)
            and (query == "" or entry.name:lower():find(query, 1, true)
                or Recipients.DisplayCharacterName(entry.name):lower():find(query, 1, true)) then
            matching[#matching + 1] = entry
        end
    end
    panel.totals:SetText(("Total sent: %s   /   Total received: %s"):format(
        Tips.CoinAmount(totals.Sent), Tips.CoinAmount(totals.Received)))

    local count = #matching
    local pages = math.max(1, math.ceil(count / Widgets.rowsPerPage))
    panel.page = math.max(1, math.min(panel.page, pages))
    panel.summary:SetText(count == 0 and (#TippleHistory == 0 and "No tips recorded yet." or "No matching tips.")
        or ("%d recorded  /  Page %d of %d"):format(count, panel.page, pages))
    for direction, button in pairs(panel.filters) do
        button:SetEnabled(direction ~= panel.direction)
    end
    panel.previous:SetEnabled(panel.page > 1)
    panel.next:SetEnabled(panel.page < pages)
    for index, row in ipairs(panel.rows) do
        local tip = matching[(panel.page - 1) * Widgets.rowsPerPage + index]
        row.tip = tip
        row:SetShown(tip ~= nil)
        if tip then
            row.title:SetText((Recipients.DisplayCharacterName(tip.name):gsub("|", "||")))
            row.amount:SetText(tip.direction .. "   " .. (tip.amount and Tips.CoinAmount(tip.amount) or "Unknown amount"))
            row.timestamp:SetText(date("%Y-%m-%d", tip.timestamp))
            row.repeatTip:SetShown(tip.direction == "Sent" and tip.amount ~= nil and tip.amount > 0)
        end
    end
end

function History.Changed()
    historyTotals = nil
    RefreshHistory()
end

function History.Open()
    if not historyPanel then
        local panel = CreateFrame("Frame", "TippleHistoryPanel", UIParent, "BackdropTemplate")
        historyPanel = panel
        panel:SetSize(560, 430)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true)
        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -17)
        title:SetText("Tipple History")
        Widgets.StyleTipWindow(panel, title, 43)
        Widgets.MakeWindowMovable(panel, "history", 38)
        Widgets.AddCloseButton(panel)

        panel.totals = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        panel.totals:SetPoint("TOPLEFT", 20, -52)
        panel.totals:SetTextColor(0.85, 0.72, 0.54)
        panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        panel.summary:SetPoint("TOPLEFT", 20, -72)
        local searchLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        searchLabel:SetPoint("TOPLEFT", 20, -99)
        searchLabel:SetText("Player")
        panel.search = Widgets.MakeInput(panel, 200, 100)
        panel.search:SetPoint("LEFT", searchLabel, "RIGHT", 9, 0)
        panel.search:SetScript("OnEnterPressed", Widgets.ClearInputFocus)
        panel.search:SetScript("OnTextChanged", function()
            panel.page = 1
            RefreshHistory()
        end)
        panel.direction = "All"
        panel.filters = {}
        for index, direction in ipairs({ "All", "Sent", "Received" }) do
            local selectedDirection = direction
            local filter = Widgets.MakeTipButton(panel)
            filter:SetSize(78, 22)
            filter:SetPoint("TOPLEFT", 298 + (index - 1) * 82, -92)
            filter:SetText(direction)
            filter:SetScript("OnClick", function()
                panel.direction = selectedDirection
                panel.page = 1
                RefreshHistory()
            end)
            panel.filters[direction] = filter
        end
        panel:SetScript("OnHide", function() panel.search:ClearFocus() end)
        panel.rows = {}
        for index = 1, Widgets.rowsPerPage do
            local row = Widgets.CreateTipListRow(panel, index, -120)
            panel.rows[index] = row
            row.title:SetPoint("TOPLEFT", 10, -5)
            row.title:SetWidth(180)
            Widgets.BindCharacterLabel(row, row.title, function() return row.tip and row.tip.name end, 14)
            row.timestamp = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.timestamp:SetPoint("BOTTOMLEFT", 10, 5)
            row.amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.amount:SetPoint("LEFT", 197, 0)
            row.amount:SetWidth(152)
            row.amount:SetWordWrap(false)
            row.amount:SetJustifyH("LEFT")

            local view = Widgets.MakeTipButton(row)
            view:SetSize(70, 24)
            view:SetPoint("RIGHT", -6, 0)
            view:SetText("View")
            view:SetScript("OnClick", function()
                if row.tip then History.ViewTip(panel, row.tip) end
            end)
            row.repeatTip = Widgets.MakeTipButton(row)
            row.repeatTip:SetSize(76, 24)
            row.repeatTip:SetPoint("RIGHT", view, "LEFT", -5, 0)
            row.repeatTip:SetText("Tip Again")
            row.repeatTip:SetScript("OnClick", function()
                local tip = row.tip
                if tip and tip.direction == "Sent" and tip.amount and tip.amount > 0 then
                    addon.Editor.Open(tip.name, nil, nil, tip)
                end
            end)
        end
        Widgets.SetupListPaging(panel, RefreshHistory, "Newer", "Older")
    end
    historyPanel.page = 1
    historyPanel:Show()
    historyPanel:Raise()
    RefreshHistory()
end
