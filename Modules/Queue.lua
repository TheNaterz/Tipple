local _, addon = ...
local Queue = {}
addon.Queue = Queue

local Widgets = addon.Widgets
local Recipients = addon.Recipients
local Tips = addon.Tips

local queuePanel

function Queue.EditableIndex(tip)
    if tip ~= addon.Mail.GetSendingTip() then
        for index, queuedTip in ipairs(TippleQueue) do
            if queuedTip == tip then return index end
        end
    end
end

local function QueuedRecipientIndex(name)
    local key = Recipients.CharacterKey(name)
    if not key then return end
    for index, tip in ipairs(TippleQueue) do
        if Recipients.CharacterKey(tip.name) == key then return index end
    end
end

function Queue.ConsolidateSavedTips()
    local recipients, duplicates = {}, {}
    for index, tip in ipairs(TippleQueue) do
        local key = Recipients.CharacterKey(tip.name)
        if key then
            local group = recipients[key]
            if not group then
                recipients[key] = { index = index, tip = tip }
            elseif not group.blocked then
                local sameFaction = not group.tip.faction or not tip.faction or group.tip.faction == tip.faction
                local combined = sameFaction and Tips.CombineTips(group.tip, tip)
                if combined then
                    group.tip = combined
                    duplicates[index] = group
                else
                    group.blocked = true
                end
            end
        end
    end
    for _, group in pairs(recipients) do
        if not group.blocked then TippleQueue[group.index] = group.tip end
    end
    for index = #TippleQueue, 1, -1 do
        local group = duplicates[index]
        if group and not group.blocked then table.remove(TippleQueue, index) end
    end
end

function Queue.MailCost(postage)
    local total = #TippleQueue * postage
    for _, tip in ipairs(TippleQueue) do
        total = total + tip.amount
    end
    return total
end

function Queue.Store(tip, index)
    if not index then
        index = QueuedRecipientIndex(tip.name)
        if index then
            local existing = TippleQueue[index]
            if existing == addon.Mail.GetSendingTip() then
                return nil, "Wait for the current tip to finish sending."
            end
            local merged, reason = Tips.CombineTips(existing, tip)
            if not merged then return nil, reason end
            tip = merged
        end
    end
    if index then
        addon.Mail.TransferSkip(TippleQueue[index], tip)
        TippleQueue[index] = tip
    else
        table.insert(TippleQueue, tip)
    end
    return tip
end

function Queue.Changed()
    Queue.Refresh()
    addon.Mail.RefreshConfirmation()
end

local function ConfirmDeleteTip(tip)
    local frame = queuePanel.deleteConfirmation
    if not frame then
        frame = CreateFrame("Frame", "TippleDeleteConfirmation", UIParent, "BackdropTemplate")
        queuePanel.deleteConfirmation = frame
        frame:SetSize(390, 145)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -17)
        title:SetText("Delete queued tip")
        Widgets.StyleTipWindow(frame, title, 43)
        Widgets.AddCloseButton(frame)
        Widgets.MakeWindowMovable(frame, "deleteConfirmation", 38)
        frame.details = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        frame.details:SetPoint("TOP", 0, -58)
        frame.details:SetWidth(354)

        local delete = Widgets.MakeTipButton(frame, "delete")
        delete:SetSize(115, 25)
        delete:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 19)
        delete:SetText(DELETE)
        delete:SetScript("OnClick", function()
            local pendingTip = frame.tip
            frame:Hide()
            local index = Queue.EditableIndex(pendingTip)
            if index then
                table.remove(TippleQueue, index)
                addon.Mail.TransferSkip(pendingTip)
                addon.Editor.CloseIfEditing(pendingTip)
                Queue.Changed()
            end
        end)
        local cancel = Widgets.MakeTipButton(frame)
        cancel:SetSize(115, 25)
        cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 19)
        cancel:SetText(CANCEL)
        cancel:SetScript("OnClick", function() frame:Hide() end)
    end
    frame.tip = tip
    frame.details:SetText(("Delete the queued tip of %s for %s?"):format(
        Tips.CoinAmount(tip.amount), Recipients.DisplayCharacterName(tip.name)))
    frame:Show()
    frame:Raise()
end

function Queue.Refresh()
    if not queuePanel or not queuePanel:IsShown() then return end
    local count = #TippleQueue
    local sending = addon.Mail.GetSendingTip()
    local pages = math.max(1, math.ceil(count / Widgets.rowsPerPage))
    queuePanel.page = math.max(1, math.min(queuePanel.page, pages))
    queuePanel.summary:SetText(count == 0 and "No tips queued."
        or ("%d queued  /  Page %d of %d"):format(count, queuePanel.page, pages))
    local showCost = addon.Mail.IsOpen() and count > 0
    queuePanel.cost:SetShown(showCost)
    if showCost then
        queuePanel.cost:SetText("Queue incl. postage: " .. Tips.CoinAmount(Queue.MailCost(GetSendMailPrice())))
    end
    queuePanel.previous:SetEnabled(queuePanel.page > 1)
    queuePanel.next:SetEnabled(queuePanel.page < pages)
    for index, row in ipairs(queuePanel.rows) do
        local tip = TippleQueue[(queuePanel.page - 1) * Widgets.rowsPerPage + index]
        row.tip = tip
        row:SetShown(tip ~= nil)
        if tip then
            local name = Recipients.DisplayCharacterName(tip.name)
            row.title:SetText(("%s   %s%s"):format(name, Tips.CoinAmount(tip.amount),
                tip == sending and " (Sending)" or ""))
            row.edit:SetEnabled(tip ~= sending)
            row.delete:SetEnabled(tip ~= sending)
        end
    end
end

function Queue.Open(returnToConfirmation)
    if not queuePanel then
        local panel = CreateFrame("Frame", "TippleQueuePanel", UIParent, "BackdropTemplate")
        queuePanel = panel
        panel:SetSize(560, 402)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("HIGH")
        panel:EnableMouse(true)
        panel:SetScript("OnHide", function(self)
            if self.returnToConfirmation then
                self.returnToConfirmation = nil
                C_Timer.After(0, addon.Mail.Prompt)
            end
        end)
        panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        panel.title:SetPoint("TOP", 0, -17)
        panel.title:SetText("Tipple")
        Widgets.StyleTipWindow(panel, panel.title, 43)
        Widgets.AddCloseButton(panel)
        Widgets.MakeWindowMovable(panel, "queue", 38)
        panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        panel.summary:SetPoint("TOPLEFT", 20, -54)
        panel.summary:SetTextColor(0.85, 0.72, 0.54)
        panel.cost = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        panel.cost:SetPoint("TOPLEFT", 20, -72)
        local history = Widgets.MakeTipButton(panel)
        history:SetSize(116, 24)
        history:SetPoint("TOPRIGHT", -20, -48)
        history:SetText("Tipple History")
        history:SetScript("OnClick", addon.History.Open)
        panel.page = 1
        panel.rows = {}

        for index = 1, Widgets.rowsPerPage do
            local row = Widgets.CreateTipListRow(panel, index, -94)
            panel.rows[index] = row
            row.title:SetPoint("LEFT", 10, 0)
            row.title:SetWidth(274)

            row.delete = Widgets.MakeTipButton(row, "delete")
            row.delete:SetSize(70, 24)
            row.delete:SetPoint("RIGHT", -6, 0)
            row.delete:SetText(DELETE)
            row.delete:SetScript("OnClick", function()
                local tip = row.tip
                if tip and Queue.EditableIndex(tip) then ConfirmDeleteTip(tip) end
            end)

            row.edit = Widgets.MakeTipButton(row)
            row.edit:SetSize(70, 24)
            row.edit:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
            row.edit:SetText("Edit")
            row.edit:SetScript("OnClick", function()
                local tip = row.tip
                if tip and Queue.EditableIndex(tip) then addon.Editor.Open(tip.name, tip) end
            end)

            local view = Widgets.MakeTipButton(row)
            view:SetSize(70, 24)
            view:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
            view:SetText("View")
            view:SetScript("OnClick", function()
                local tip = row.tip
                if tip then addon.History.ViewTip(panel, tip) end
            end)
        end

        Widgets.SetupListPaging(panel, Queue.Refresh, "Previous", "Next")
    end
    queuePanel.returnToConfirmation = returnToConfirmation or queuePanel.returnToConfirmation
    queuePanel:Show()
    Queue.Refresh()
end
