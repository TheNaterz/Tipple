local _, addon = ...
local Editor = {}
addon.Editor = Editor

local Widgets = addon.Widgets
local Recipients = addon.Recipients
local Tips = addon.Tips

local recipient
local form
local editingTip

function Editor.Open(name, tipToEdit, returnToConfirmation, previousTip)
    if not form then
        form = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        form:SetSize(360, 392)
        form:SetPoint("CENTER")
        form:SetFrameStrata("DIALOG")
        form:EnableMouse(true)
        form.title = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        form.title:SetPoint("TOP", 0, -17)
        Widgets.StyleTipWindow(form, form.title, 43)
        Widgets.AddCloseButton(form)
        local titleBar = Widgets.MakeWindowMovable(form, "editor", 42)
        Widgets.BindCharacterMenu(titleBar, function() if not editingTip then return recipient end end)
        form.amountLabel = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        form.amountLabel:SetText("Amount")
        local amountFields = {}
        form.amountFields = amountFields
        local previousIcon
        for index, denomination in ipairs(Tips.denominations) do
            local field = Widgets.MakeInput(form, denomination.width, 12)
            amountFields[index] = field
            field:SetNumeric(true)
            if previousIcon then
                field:SetPoint("LEFT", previousIcon, "RIGHT", 15, 0)
            else
                field:SetPoint("TOPLEFT", form.amountLabel, "BOTTOMLEFT", 4, -5)
            end
            local icon = form:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetAtlas(denomination.atlas)
            icon:SetPoint("LEFT", field, "RIGHT", 5, 0)
            previousIcon = icon
        end
        form.recipientLabel = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        form.recipientLabel:SetPoint("TOPLEFT", 24, -58)
        form.recipientLabel:SetText("Recipient")
        form.recipient = form:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        form.recipient:SetPoint("TOPLEFT", form.recipientLabel, "BOTTOMLEFT", 0, -8)
        form.recipient:SetWidth(310)
        form.recipient:SetJustifyH("LEFT")
        form.recipientMenu = Widgets.BindCharacterLabel(form, form.recipient, function()
            return editingTip and editingTip.name
        end, 18)
        form.messageLabel = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        form.messageLabel:SetText("Message (optional)")

        local messageBox = CreateFrame("Frame", nil, form, "BackdropTemplate")
        messageBox:SetPoint("TOPLEFT", form.messageLabel, "BOTTOMLEFT", 0, -5)
        messageBox:SetSize(312, 112)
        messageBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        messageBox:SetBackdropColor(0, 0, 0, 0.55)
        messageBox:SetBackdropBorderColor(0.64, 0.46, 0.27, 0.8)

        local scroll = CreateFrame("ScrollFrame", nil, messageBox, "UIPanelScrollFrameTemplate")
        form.messageScroll = scroll
        scroll:SetPoint("TOPLEFT", 8, -7)
        scroll:SetPoint("BOTTOMRIGHT", -27, 7)
        local editor = CreateFrame("EditBox", nil, scroll)
        form.messageEditor = editor
        editor:SetSize(277, 98)
        editor:SetFontObject(GameFontHighlight)
        editor:SetMultiLine(true)
        editor:SetAutoFocus(false)
        editor:SetMaxBytes(Tips.mailBodyLimit)
        scroll:SetScrollChild(editor)
        Widgets.FocusOnClick(editor, editor)
        Widgets.FocusOnClick(scroll, editor)
        Widgets.FocusOnClick(messageBox, editor)
        editor:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
        editor:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        editor:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
        editor:SetScript("OnEscapePressed", Widgets.ClearInputFocus)
        editor:SetScript("OnTabPressed", function() amountFields[1]:SetFocus() end)

        for index, field in ipairs(amountFields) do
            local nextField = amountFields[index + 1] or editor
            field:SetScript("OnTabPressed", function() nextField:SetFocus() end)
        end

        local includeContext = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
        includeContext:SetPoint("TOPLEFT", messageBox, "BOTTOMLEFT", -4, -6)
        local contextLabel = includeContext:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        contextLabel:SetPoint("LEFT", includeContext, "RIGHT", 2, 0)
        contextLabel:SetText("Include current time and area")
        includeContext:SetHitRectInsets(0, -contextLabel:GetStringWidth() - 2, 0, 0)
        form.includeContext = includeContext
        form.context = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        form.context:SetPoint("TOPLEFT", includeContext, "BOTTOMLEFT", 4, -3)
        form.context:SetWidth(310)
        form.context:SetJustifyH("LEFT")
        form:SetScript("OnHide", function(self)
            editingTip = nil
            if self.returnToConfirmation then
                self.returnToConfirmation = nil
                C_Timer.After(0, addon.Mail.Prompt)
            end
        end)

        form.error = form:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
        form.error:SetPoint("BOTTOM", 0, 52)
        form.error:SetWidth(312)
        form.error:SetJustifyH("CENTER")

        local function SaveTip()
            local index, name = nil, recipient
            local wasEditing = editingTip ~= nil
            if wasEditing then
                index = addon.Queue.EditableIndex(editingTip)
                if not index then
                    form.error:SetText("This tip is no longer available to edit.")
                    return
                end
                name = editingTip.name
            end
            local amount, invalidField = Tips.ParseAmount(amountFields)
            if not amount then
                form.error:SetText("Amount is empty.")
                invalidField:SetFocus()
                return
            end
            local savedFaction = editingTip and editingTip.faction or form.draftFaction
            local faction = Recipients.RecipientFaction(name, savedFaction)
            if not faction or faction ~= Recipients.UnitFaction("player") then
                form.error:SetText("Tipple requires a verified same-faction recipient.")
                return
            end
            local tip = { name = name, amount = amount, message = editor:GetText(), faction = faction }
            if includeContext:GetChecked() then
                if editingTip then tip.context = editingTip.context else tip.context = Tips.QueueContext() end
            end
            if not Tips.TipMessageFits(tip) then
                form.error:SetText("Shorten your message to leave room for the footer.")
                editor:SetFocus()
                return
            end
            local saved, reason = addon.Queue.Store(tip, index)
            if not saved then
                form.error:SetText(reason)
                return
            end
            tip = saved
            form:Hide()
            if not wasEditing then
                addon.Notice(("Queued %s for %s."):format(Tips.CoinAmount(tip.amount), Recipients.DisplayCharacterName(name)))
            end
            addon.Queue.Changed()
        end

        local queue = Widgets.MakeTipButton(form, "primary")
        queue:SetSize(115, 25)
        queue:SetPoint("BOTTOMRIGHT", form, "BOTTOM", -5, 19)
        queue:SetText("Queue Tip")
        form.save = queue
        queue:SetScript("OnClick", SaveTip)
        for _, field in ipairs(amountFields) do field:SetScript("OnEnterPressed", SaveTip) end

        local cancel = Widgets.MakeTipButton(form)
        cancel:SetSize(115, 25)
        cancel:SetPoint("BOTTOMLEFT", form, "BOTTOM", 5, 19)
        cancel:SetText(CANCEL)
        cancel:SetScript("OnClick", function() form:Hide() end)
    end

    recipient = name
    editingTip = tipToEdit
    form.draftFaction = previousTip and previousTip.faction
    form.returnToConfirmation = returnToConfirmation or form.returnToConfirmation
    local offset = tipToEdit and 54 or 0
    form:SetHeight(392 + offset)
    form.title:SetText(tipToEdit and "Edit tip" or ("Tip " .. Recipients.DisplayCharacterName(name)))
    form.save:SetText(tipToEdit and "Save Changes" or "Queue Tip")
    form.recipient:SetShown(tipToEdit ~= nil)
    form.recipientLabel:SetShown(tipToEdit ~= nil)
    form.recipientMenu:SetShown(tipToEdit ~= nil)
    form.recipient:SetText(tipToEdit and (Recipients.DisplayCharacterName(tipToEdit.name):gsub("|", "||")) or "")
    form.amountLabel:SetPoint("TOPLEFT", 24, -58 - offset)
    form.messageLabel:SetPoint("TOPLEFT", 24, -112 - offset)
    local sourceTip = tipToEdit or previousTip
    Tips.SetAmountFields(form.amountFields, sourceTip and sourceTip.amount or 0)
    form.messageEditor:SetText(tipToEdit and tipToEdit.message or "")
    form.messageEditor:SetCursorPosition(0)
    form.messageScroll:SetVerticalScroll(0)
    local context = tipToEdit and tipToEdit.context
    form.includeContext:SetShown(not tipToEdit or context ~= nil)
    form.includeContext:SetChecked(context ~= nil)
    form.context:SetText(context and context:gsub("|", "||") or "")
    form.error:SetText("")
    form:Show()
    form:Raise()
    form.amountFields[1]:SetFocus()
end

function Editor.CloseIfEditing(tip)
    if editingTip == tip then form:Hide() end
end
