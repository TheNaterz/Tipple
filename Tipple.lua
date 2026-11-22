local addonName = ...
local events = CreateFrame("Frame")
local mailboxOpen = false
local sending
local recipient
local form
local editingTip
local queuePanel
local confirmation
local historyPanel
local historyTotals
local tipTooltipRegistered = false
local knownFactions = {}
local inboxHooked
local sentThisVisit = 0
local skippedTips = {}
local promptsStopped = false
local RefreshQueue
local RefreshHistory
local PromptTip
local OpenQueue
local mailBodyLimit = 500
local signature = "- Sent with Tipple"
local mailSubject = "You've Been Tipped!"
local windowFocusOrder = {}
local nextWindowFocus = 0
local escapeProxy

local function FocusTipWindow(frame)
    while frame and not frame:IsForbidden() do
        if windowFocusOrder[frame] then
            nextWindowFocus = nextWindowFocus + 1
            windowFocusOrder[frame] = nextWindowFocus
            return
        end
        frame = frame:GetParent()
    end
end

local function GetFocusedTipWindow()
    local activeWindow, latestFocus
    for window, focus in pairs(windowFocusOrder) do
        if window:IsVisible() and (not latestFocus or focus > latestFocus) then
            activeWindow, latestFocus = window, focus
        end
    end
    return activeWindow
end

local function UpdateEscapeProxy()
    escapeProxy:SetShown(GetFocusedTipWindow() ~= nil)
end

local function SetupEscapeProxy()
    escapeProxy = CreateFrame("Frame", "TippleEscapeProxy", UIParent)
    escapeProxy:Hide()
    table.insert(UISpecialFrames, escapeProxy:GetName())
    escapeProxy:SetScript("OnHide", function()
        local window = GetFocusedTipWindow()
        if not window then return end
        -- Let Blizzard finish closing special windows before touching Tipple UI.
        C_Timer.After(0, function()
            if window:IsVisible() then window:Hide() end
            UpdateEscapeProxy()
        end)
    end)
end

local function Notice(message)
    print("|cffffd100Tipple|r " .. message)
end

local function StyleTipWindow(window, title, headerHeight)
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    window:SetBackdropColor(0.24, 0.17, 0.11, 0.98)
    window:SetBackdropBorderColor(0.67, 0.48, 0.25)

    local header = window:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(headerHeight - 6)
    header:SetColorTexture(0.25, 0.13, 0.06, 0.75)

    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 18, -headerHeight)
    rule:SetPoint("TOPRIGHT", -18, -headerHeight)
    rule:SetHeight(1)
    rule:SetColorTexture(0.72, 0.53, 0.28, 0.72)

    local coin = window:CreateTexture(nil, "ARTWORK")
    coin:SetSize(17, 17)
    coin:SetPoint("LEFT", header, "LEFT", 10, 0)
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    title:SetTextColor(1, 0.83, 0.54)
end

local function AddCloseButton(window)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() window:Hide() end)
end

local function MakeTipButton(parent, style)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    button:SetBackdropBorderColor(0.68, 0.48, 0.24, 0.9)
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)

    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    if style == "primary" then
        fill:SetColorTexture(0.37, 0.22, 0.08)
    elseif style == "delete" then
        fill:SetColorTexture(0.29, 0.10, 0.08)
    else
        fill:SetColorTexture(0.19, 0.13, 0.09)
    end
    button:SetNormalTexture(fill)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(fill)
    highlight:SetColorTexture(0.95, 0.68, 0.33, 0.22)
    button:SetHighlightTexture(highlight)
    local pressed = button:CreateTexture(nil, "BACKGROUND")
    pressed:SetAllPoints(fill)
    pressed:SetColorTexture(0.13, 0.08, 0.05)
    button:SetPushedTexture(pressed)
    button:HookScript("OnMouseDown", FocusTipWindow)
    return button
end

local function MakeWindowMovable(window, key, titleHeight)
    local positions = TippleOptions.windowPositions
    local position = positions[key]
    if not escapeProxy then SetupEscapeProxy() end
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    windowFocusOrder[window] = 0
    FocusTipWindow(window)
    window:HookScript("OnShow", function(self)
        FocusTipWindow(self)
        UpdateEscapeProxy()
    end)
    window:HookScript("OnHide", UpdateEscapeProxy)
    window:HookScript("OnMouseDown", FocusTipWindow)
    UpdateEscapeProxy()
    if position then
        window:ClearAllPoints()
        window:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    end

    local titleBar = CreateFrame("Frame", nil, window)
    titleBar:SetPoint("TOPLEFT", 8, -4)
    titleBar:SetPoint("TOPRIGHT", -40, -4)
    titleBar:SetHeight(titleHeight)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:HookScript("OnMouseDown", FocusTipWindow)

    local dragging
    titleBar:SetScript("OnDragStart", function()
        dragging = true
        window:StartMoving()
    end)
    local function FinishDrag()
        if not dragging then return end
        dragging = false
        window:StopMovingOrSizing()
        local x, y = window:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        if x and centerX then
            positions[key] = { x = x - centerX, y = y - centerY }
        end
    end
    titleBar:SetScript("OnDragStop", FinishDrag)
    titleBar:SetScript("OnHide", FinishDrag)
    return titleBar
end

local function BindCharacterMenu(area, getName)
    area:EnableMouse(true)
    area:HookScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local name = getName()
        if not name or name == "" or name == UNKNOWN then return end
        local _, realm = name:match("^([^%-]+)%-(.+)$")
        UnitPopup_OpenMenu("FRIEND", { name = name, server = realm, ownerFrame = self })
    end)
end

local function BindCharacterLabel(parent, label, getName, height)
    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", label, "TOPLEFT")
    area:SetPoint("TOPRIGHT", label, "TOPRIGHT")
    area:SetHeight(height)
    BindCharacterMenu(area, getName)
    return area
end

local function DisplayCharacterName(name)
    return (name:gsub("%-", " "))
end

local function IsReadable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function MailName(name, realm)
    if not IsReadable(name) or not name or name == "" or name == UNKNOWN then return end
    if IsReadable(realm) and realm and realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return name
end

local function UnitFaction(unit)
    local faction = UnitFactionGroup(unit)
    if IsReadable(faction) and (faction == "Alliance" or faction == "Horde") then return faction end
end

local function PlayerLocationFaction(location)
    if not IsReadable(location) or not location or not location:IsValid() then return end
    local raceID = C_PlayerInfo.GetRace(location)
    if not IsReadable(raceID) or not raceID then return end
    local faction = C_CreatureInfo.GetFactionInfo(raceID)
    if IsReadable(faction) and faction and IsReadable(faction.groupTag) then
        return faction.groupTag
    end
end

local function PlayerMailName(unit)
    local player = UnitIsPlayer(unit)
    local self = UnitIsUnit(unit, "player")
    if IsReadable(player) and player and IsReadable(self) and not self then
        return MailName(UnitFullName(unit))
    end
end

local function RecipientFaction(name, savedFaction)
    local key = name:lower()
    local function CheckUnit(unit)
        local unitName = PlayerMailName(unit)
        if unitName and unitName:lower() == key then return UnitFaction(unit) end
    end
    local faction = CheckUnit("target") or CheckUnit("focus") or CheckUnit("mouseover")
    if faction then return faction end
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            faction = CheckUnit("raid" .. index)
            if faction then return faction end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            faction = CheckUnit("party" .. index)
            if faction then return faction end
        end
    end
    return knownFactions[key] or savedFaction
end

local function IsSameFactionRecipient(tip)
    local playerFaction = UnitFaction("player")
    return playerFaction and RecipientFaction(tip.name, tip.faction) == playerFaction
end

local function ClubMemberFaction(member, guild)
    if not IsReadable(member) or not member then return end
    local faction = member.faction
    if IsReadable(faction) then
        if faction == Enum.PvPFaction.Alliance then return "Alliance" end
        if faction == Enum.PvPFaction.Horde then return "Horde" end
        if faction ~= nil then return end
    else
        return
    end
    if IsReadable(guild) and guild and IsReadable(guild.crossFaction) and guild.crossFaction == false then
        return UnitFaction("player")
    end
end

local function GuildRecipientFaction(name)
    if not IsInGuild() then return end
    local clubID = C_Club.GetGuildClubId()
    if not IsReadable(clubID) or not clubID then return end
    local memberIDs = C_Club.GetClubMembers(clubID)
    if not IsReadable(memberIDs) or not memberIDs then return end
    local key = name:lower()
    for _, memberID in ipairs(memberIDs) do
        if IsReadable(memberID) then
            local member = C_Club.GetMemberInfo(clubID, memberID)
            if IsReadable(member) and member then
                local memberName = MailName(member.name)
                if memberName and memberName:lower() == key then
                    return ClubMemberFaction(member, C_Club.GetClubInfo(clubID))
                end
            end
        end
    end
end

local denominations = {
    { value = 10000, atlas = "coin-gold", width = 78 },
    { value = 100, atlas = "coin-silver", width = 48 },
    { value = 1, atlas = "coin-copper", width = 48 },
}

local function CoinCount(amount, index, denomination)
    local count = math.floor(amount / denomination.value)
    return index == 1 and count or count % 100
end

local function ParseAmount(fields)
    local amount = 0
    for index, denomination in ipairs(denominations) do
        local text = fields[index]:GetText()
        local count = text == "" and 0 or tonumber(text:match("^%d+$"))
        if not count or (index > 1 and count > 99) then return nil, fields[index] end
        amount = amount + count * denomination.value
    end
    if amount > 0 and amount <= (MAX_MONEY_AMOUNT or 99999999999) then
        return amount
    end
    return nil, fields[1]
end

local function CoinAmount(amount)
    local parts = {}
    for index, denomination in ipairs(denominations) do
        local count = CoinCount(amount, index, denomination)
        if count > 0 then
            parts[#parts + 1] = ("%d|A:%s:13:13|a"):format(count, denomination.atlas)
        end
    end
    return #parts > 0 and table.concat(parts, " ") or "0"
end

local function FormatClock(hour, minute)
    return ("%02d:%02d %s"):format((hour + 11) % 12 + 1, minute, hour < 12 and "AM" or "PM")
end

local function QueueContext()
    local zone = GetRealZoneText()
    local inInstance = IsInInstance()
    if inInstance then
        local instance = GetInstanceInfo()
        if instance and instance ~= "" then zone = instance end
    end
    if not zone or zone == "" then zone = "Unknown area" end
    local subzone = GetSubZoneText()
    if subzone and subzone ~= "" and subzone ~= zone then
        zone = zone .. " / " .. subzone
    end
    local hour, minute = GetGameTime()
    return FormatClock(hour, minute) .. " Server Time - " .. zone
end

local function MailFooter(tip)
    return tip.context and (tip.context .. "\n\n" .. signature) or signature
end

local function ReviewBody(tip)
    local message = tip.message or ""
    local footer = MailFooter(tip)
    -- Older queued messages may have used the full limit. Keep the footer and cut at a UTF-8 boundary.
    local lastByte = mailBodyLimit - #footer - 2
    if #message > lastByte then
        while lastByte > 0 do
            local nextByte = message:byte(lastByte + 1)
            if nextByte < 128 or nextByte >= 192 then break end
            lastByte = lastByte - 1
        end
        message = message:sub(1, lastByte)
    end
    if not tip.context then return message end
    return message ~= "" and (tip.context .. "\n\n" .. message) or tip.context
end

local function MailBody(tip)
    local body = ReviewBody(tip)
    return body ~= "" and (body .. "\n\n" .. signature) or signature
end

local function FocusOnClick(area, field)
    area:EnableMouse(true)
    area:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            FocusTipWindow(field)
            if not field:HasFocus() then field:SetFocus() end
        end
    end)
end

local function ClearInputFocus(field)
    field:ClearHighlightText()
    field:ClearFocus()
end

local function MakeInput(parent, width, maxBytes)
    local field = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    field:SetSize(width, 26)
    field:SetAutoFocus(false)
    field:SetMaxBytes(maxBytes)
    field:SetHitRectInsets(-4, -4, -2, -2)
    FocusOnClick(field, field)
    field:SetScript("OnEscapePressed", ClearInputFocus)
    return field
end

local function EditableTipIndex(tip)
    if tip ~= sending then
        for index, queuedTip in ipairs(TippleQueue) do
            if queuedTip == tip then return index end
        end
    end
end

local function HideConfirmation()
    if confirmation then
        confirmation.tip = nil
        confirmation:Hide()
    end
end

local function QueueChanged()
    RefreshQueue()
    if mailboxOpen and confirmation and confirmation:IsShown() then
        HideConfirmation()
        C_Timer.After(0, PromptTip)
    end
end

local function OpenForm(name, tipToEdit, returnToConfirmation)
    if not form then
        form = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        form:SetSize(360, 392)
        form:SetPoint("CENTER")
        form:SetFrameStrata("DIALOG")
        form:EnableMouse(true)
        form.title = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        form.title:SetPoint("TOP", 0, -17)
        StyleTipWindow(form, form.title, 43)
        AddCloseButton(form)
        local titleBar = MakeWindowMovable(form, "editor", 42)
        BindCharacterMenu(titleBar, function() if not editingTip then return recipient end end)
        form.amountLabel = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        form.amountLabel:SetText("Amount")
        local amountFields = {}
        form.amountFields = amountFields
        local previousIcon
        for index, denomination in ipairs(denominations) do
            local field = MakeInput(form, denomination.width, 12)
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
        form.recipientMenu = BindCharacterLabel(form, form.recipient, function()
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
        editor:SetMaxBytes(mailBodyLimit)
        scroll:SetScrollChild(editor)
        FocusOnClick(editor, editor)
        FocusOnClick(scroll, editor)
        FocusOnClick(messageBox, editor)
        editor:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
        editor:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        editor:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
        editor:SetScript("OnEscapePressed", ClearInputFocus)
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
        form.context:SetPoint("TOPLEFT", 24, -335)
        form.context:SetWidth(310)
        form.context:SetJustifyH("LEFT")
        form:SetScript("OnHide", function(self)
            editingTip = nil
            if self.returnToConfirmation then
                self.returnToConfirmation = nil
                C_Timer.After(0, PromptTip)
            end
        end)

        form.error = form:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
        form.error:SetPoint("BOTTOM", 0, 52)

        local function SaveTip()
            local index, name = nil, recipient
            if editingTip then
                index = EditableTipIndex(editingTip)
                if not index then
                    form.error:SetText("This tip is no longer available to edit.")
                    return
                end
                name = editingTip.name
            end
            local amount, invalidField = ParseAmount(amountFields)
            if not amount then
                form.error:SetText("Amount is empty.")
                invalidField:SetFocus()
                return
            end
            local savedFaction = editingTip and editingTip.faction
            local faction = RecipientFaction(name, savedFaction)
            if not faction or faction ~= UnitFaction("player") then
                form.error:SetText("Tipple requires a verified same-faction recipient.")
                return
            end
            local tip = { name = name, amount = amount, message = editor:GetText(), faction = faction }
            if includeContext:GetChecked() then
                if editingTip then tip.context = editingTip.context else tip.context = QueueContext() end
            end
            local maxMessageBytes = mailBodyLimit - #MailFooter(tip) - 2
            if #tip.message > maxMessageBytes and tip.message ~= "" then
                form.error:SetText("Shorten your message to leave room for the footer.")
                editor:SetFocus()
                return
            end
            if editingTip and skippedTips[editingTip] then
                skippedTips[editingTip] = nil
                skippedTips[tip] = true
            end
            form:Hide()
            if index then
                TippleQueue[index] = tip
                QueueChanged()
            else
                table.insert(TippleQueue, tip)
                Notice(("Queued %s for %s."):format(CoinAmount(amount), DisplayCharacterName(name)))
                QueueChanged()
            end
        end

        local queue = MakeTipButton(form, "primary")
        queue:SetSize(115, 25)
        queue:SetPoint("BOTTOMRIGHT", form, "BOTTOM", -5, 19)
        queue:SetText("Queue Tip")
        form.save = queue
        queue:SetScript("OnClick", SaveTip)
        for _, field in ipairs(amountFields) do field:SetScript("OnEnterPressed", SaveTip) end

        local cancel = MakeTipButton(form)
        cancel:SetSize(115, 25)
        cancel:SetPoint("BOTTOMLEFT", form, "BOTTOM", 5, 19)
        cancel:SetText(CANCEL)
        cancel:SetScript("OnClick", function() form:Hide() end)
    end

    recipient = name
    editingTip = tipToEdit
    form.returnToConfirmation = returnToConfirmation or form.returnToConfirmation
    local offset = tipToEdit and 54 or 0
    form:SetHeight(392 + offset)
    form.title:SetText(tipToEdit and "Edit tip" or ("Tip " .. DisplayCharacterName(name)))
    form.save:SetText(tipToEdit and "Save Changes" or "Queue Tip")
    form.recipient:SetShown(tipToEdit ~= nil)
    form.recipientLabel:SetShown(tipToEdit ~= nil)
    form.recipientMenu:SetShown(tipToEdit ~= nil)
    form.recipient:SetText(tipToEdit and (DisplayCharacterName(tipToEdit.name):gsub("|", "||")) or "")
    form.amountLabel:SetPoint("TOPLEFT", 24, -58 - offset)
    form.messageLabel:SetPoint("TOPLEFT", 24, -112 - offset)
    for index, denomination in ipairs(denominations) do
        local count = tipToEdit and CoinCount(tipToEdit.amount, index, denomination) or 0
        form.amountFields[index]:SetText(count > 0 and tostring(count) or "")
    end
    form.messageEditor:SetText(tipToEdit and tipToEdit.message or "")
    form.messageEditor:SetCursorPosition(0)
    form.messageScroll:SetVerticalScroll(0)
    local context = tipToEdit and tipToEdit.context
    form.includeContext:SetShown(not tipToEdit or context ~= nil)
    form.includeContext:SetChecked(context ~= nil)
    form.context:SetText(context and context:gsub("|", "||") or "")
    form.error:SetText("")
    form:Show()
    form.amountFields[1]:SetFocus()
end

local function AddTipEntry(_, menu, context)
    if not context or (IsReadable(context.isSelf) and context.isSelf) then return end
    local name, faction
    if IsReadable(context.unit) and context.unit then
        name = PlayerMailName(context.unit)
        if not name then return end
        faction = UnitFaction(context.unit)
        if faction then knownFactions[name:lower()] = faction end
        local friendly = UnitIsFriend("player", context.unit)
        if not IsReadable(friendly) or not friendly then return end
    else
        local realm = context.server
        if not IsReadable(realm) or not realm or realm == "" then
            realm = context.surname
        end
        name = MailName(context.name, realm)
        if not name then return end
        local playerName = MailName(UnitFullName("player"))
        if playerName and playerName:lower() == name:lower() then return end
        local guild
        if IsReadable(context.isGuildMember) and context.isGuildMember then
            guild = context.clubInfo
        end
        faction = ClubMemberFaction(context.clubMemberInfo, guild) or GuildRecipientFaction(name)
        local lineID = IsReadable(context.lineID) and tonumber(context.lineID)
        if not faction and lineID and lineID > 0 then
            faction = PlayerLocationFaction(context.playerLocation)
        end
        faction = faction or RecipientFaction(name)
    end
    if faction then knownFactions[name:lower()] = faction end
    if faction and faction == UnitFaction("player") then
        menu:CreateButton("Tipple", function() OpenForm(name) end)
    end
end

for _, tag in ipairs({
    "PLAYER", "PARTY", "PARTY1", "RAID", "RAID_PLAYER",
    "FRIEND", "FRIEND_OFFLINE", "PLAYER_OFFLINE", "CHAT_ROSTER", "COMMUNITIES_MEMBER",
    "COMMUNITIES_GUILD_MEMBER", "GUILD", "GUILD_OFFLINE",
}) do
    Menu.ModifyMenu("MENU_UNIT_" .. tag, AddTipEntry)
end

local function StopSending(message)
    local tip = sending
    sending = nil
    if tip and mailboxOpen and SendMailNameEditBox:GetText() == tip.name
        and SendMailSubjectEditBox:GetText() == mailSubject
        and SendMailBodyEditBox:GetText() == MailBody(tip) then
        SendMailFrame_Reset()
    end
    RefreshQueue()
    Notice(message)
end

local function SendTip(tip)
    if not mailboxOpen or not MailFrame or not MailFrame:IsShown()
        or sending or not EditableTipIndex(tip) or skippedTips[tip] then return end
    if not IsSameFactionRecipient(tip) then
        Notice("Tipple could not verify a same-faction recipient. The tip is still queued.")
        return
    end

    for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(slot) then
            Notice("Tipple paused because you have outgoing mail attachments.")
            return
        end
    end
    if SendMailNameEditBox:GetText() ~= "" or SendMailSubjectEditBox:GetText() ~= ""
        or SendMailBodyEditBox:GetText() ~= "" or MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        Notice("Tipple paused because you have a mail draft.")
        return
    end
    local postage = GetSendMailPrice()
    if tip.amount + postage > GetMoney() then
        Notice(("You need %s for the tip and postage."):format(CoinAmount(tip.amount + postage)))
        return
    end

    -- Let Blizzard handle the protected send and any confirmation for attached money.
    local ok = pcall(function()
        MailFrameTab_OnClick(nil, 2)
        SendMailNameEditBox:ClearFocus()
        SendMailRadioButton_OnClick(1)
        SendMailNameEditBox:SetText(tip.name)
        SendMailSubjectEditBox:SetText(mailSubject)
        if SendMailNameEditBox:GetText() ~= tip.name or SendMailSubjectEditBox:GetText() ~= mailSubject then
            SendMailFrame_Reset()
            Notice("The mailbox did not keep the recipient or subject. The tip is still queued.")
            return
        end
        local body = MailBody(tip)
        SendMailBodyEditBox:SetText(body)
        if SendMailBodyEditBox:GetText() ~= body then
            SendMailFrame_Reset()
            Notice("The game changed the mail body. The tip is still queued.")
            return
        end
        -- Blizzard charges postage separately from the attached money.
        MoneyInputFrame_SetCopper(SendMailMoney, tip.amount)
        local attached = MoneyInputFrame_GetCopper(SendMailMoney)
        if attached ~= tip.amount and not SendMailMoney.goldOnly then
            SendMailMoney.gold:SetText(tostring(math.floor(tip.amount / 10000)))
            SendMailMoney.silver:SetText(tostring(math.floor(tip.amount / 100) % 100))
            SendMailMoney.copper:SetText(tostring(tip.amount % 100))
            attached = MoneyInputFrame_GetCopper(SendMailMoney)
        end
        if attached ~= tip.amount then
            SendMailFrame_Reset()
            Notice(("The mailbox accepted %s of the requested %s. The tip is still queued."):format(
                CoinAmount(attached), CoinAmount(tip.amount)))
            return
        end
        -- Programmatic edits may not have refreshed the button yet.
        SendMailFrame_CanSend()
        if not SendMailMailButton:IsEnabled() or not SendMailSendMoneyButton:GetChecked() then
            SendMailFrame_Reset()
            Notice("The mailbox would not enable sending money for this draft. The tip is still queued.")
            return
        end
        sending = tip
        RefreshQueue()
        SendMailMailButton:Click()
    end)
    if not ok then
        StopSending("The game blocked the send. The tip is still queued.")
    end
end

local function CreateTextScroll(window, top, bottom, width, hideUnusedScrollbar)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    local scrollbar = scroll.ScrollBar
    scroll:EnableMouse(true)
    scroll:HookScript("OnMouseDown", FocusTipWindow)
    if scrollbar then scrollbar:HookScript("OnMouseDown", FocusTipWindow) end
    local function UpdateScrollbar(_, _, verticalRange)
        if scrollbar then scrollbar:SetShown(verticalRange > 0) end
    end
    if hideUnusedScrollbar then
        scroll.scrollBarHideable = true
        scroll:HookScript("OnScrollRangeChanged", UpdateScrollbar)
    end
    scroll:SetPoint("TOPLEFT", 18, top)
    scroll:SetPoint("BOTTOMRIGHT", -34, bottom)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT")
    body:SetPoint("TOPRIGHT")
    body:SetJustifyH("LEFT")
    body:SetTextColor(0.95, 0.84, 0.67)
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(true)
    return function(message)
        body:SetText((message:gsub("|", "||")))
        local padding = hideUnusedScrollbar and 0 or 4
        content:SetHeight(math.max(body:GetStringHeight() + padding, 1))
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(0)
        if hideUnusedScrollbar then
            UpdateScrollbar(nil, nil, scroll:GetVerticalScrollRange())
        end
    end
end

PromptTip = function()
    if not mailboxOpen or promptsStopped or sending or not MailFrame or not MailFrame:IsShown() then return end
    local tip, queueIndex
    for index, queuedTip in ipairs(TippleQueue) do
        if not skippedTips[queuedTip] then
            if IsSameFactionRecipient(queuedTip) then
                tip, queueIndex = queuedTip, index
                break
            end
            skippedTips[queuedTip] = true
            Notice("Tipple could not verify a same-faction recipient. The tip is still queued.")
        end
    end
    if not tip then return end
    if not confirmation then
        local frame = CreateFrame("Frame", "TippleSendConfirmation", UIParent, "BackdropTemplate")
        confirmation = frame
        frame:SetSize(480, 320)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        frame.title:SetPoint("TOP", 0, -17)
        StyleTipWindow(frame, frame.title, 43)
        AddCloseButton(frame)
        MakeWindowMovable(frame, "confirmation", 38)
        frame:SetScript("OnHide", function(self)
            if self.tip then
                promptsStopped = true
                self.tip = nil
            end
        end)
        local queue = MakeTipButton(frame)
        queue:SetSize(105, 24)
        queue:SetPoint("TOPLEFT", 44, -10)
        queue:SetFrameLevel(frame:GetFrameLevel() + 2)
        queue:SetText("View Queue")
        queue:SetScript("OnClick", function()
            HideConfirmation()
            OpenQueue(true)
        end)
        frame.details = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        frame.details:SetPoint("TOPLEFT", 18, -56)
        frame.details:SetWidth(444)
        frame.details:SetJustifyH("LEFT")
        BindCharacterLabel(frame, frame.details, function() return frame.tip and frame.tip.name end, 18)
        frame.setMessage = CreateTextScroll(frame, -145, 60, 428, true)

        local send = MakeTipButton(frame, "primary")
        send:SetSize(100, 25)
        send:SetPoint("BOTTOM", frame, "BOTTOM", -165, 19)
        send:SetText("Send Tip")
        send:SetScript("OnClick", function()
            local pendingTip = frame.tip
            HideConfirmation()
            SendTip(pendingTip)
        end)
        local edit = MakeTipButton(frame)
        edit:SetSize(100, 25)
        edit:SetPoint("BOTTOM", frame, "BOTTOM", -55, 19)
        edit:SetText("Edit")
        edit:SetScript("OnClick", function()
            local pendingTip = frame.tip
            if not pendingTip or not EditableTipIndex(pendingTip) then return end
            HideConfirmation()
            OpenForm(pendingTip.name, pendingTip, true)
        end)
        local later = MakeTipButton(frame)
        later:SetSize(100, 25)
        later:SetPoint("BOTTOM", frame, "BOTTOM", 55, 19)
        later:SetText("Later")
        later:SetScript("OnClick", function()
            if frame.tip then skippedTips[frame.tip] = true end
            HideConfirmation()
            PromptTip()
        end)
        local exit = MakeTipButton(frame)
        exit:SetSize(100, 25)
        exit:SetPoint("BOTTOM", frame, "BOTTOM", 165, 19)
        exit:SetText("Exit")
        exit:SetScript("OnClick", function() frame:Hide() end)
    end
    local postage = GetSendMailPrice()
    confirmation.tip = tip
    confirmation.title:SetText(("Tipple - %d/%d"):format(sentThisVisit + queueIndex, sentThisVisit + #TippleQueue))
    confirmation.details:SetText(("Send tip of %s to %s?\n\nPostage: %s\nTotal to send: %s"):format(
        CoinAmount(tip.amount), (DisplayCharacterName(tip.name):gsub("|", "||")),
        CoinAmount(postage), CoinAmount(tip.amount + postage)))
    confirmation:Show()
    confirmation.setMessage(ReviewBody(tip))
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
        StyleTipWindow(frame, title, 43)
        AddCloseButton(frame)
        MakeWindowMovable(frame, "deleteConfirmation", 38)
        frame.details = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        frame.details:SetPoint("TOP", 0, -58)
        frame.details:SetWidth(354)

        local delete = MakeTipButton(frame, "delete")
        delete:SetSize(115, 25)
        delete:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 19)
        delete:SetText(DELETE)
        delete:SetScript("OnClick", function()
            local pendingTip = frame.tip
            frame:Hide()
            local index = EditableTipIndex(pendingTip)
            if index then
                table.remove(TippleQueue, index)
                skippedTips[pendingTip] = nil
                if editingTip == pendingTip then form:Hide() end
                QueueChanged()
            end
        end)
        local cancel = MakeTipButton(frame)
        cancel:SetSize(115, 25)
        cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 19)
        cancel:SetText(CANCEL)
        cancel:SetScript("OnClick", function() frame:Hide() end)
    end
    frame.tip = tip
    frame.details:SetText(("Delete the queued tip of %s for %s?"):format(
        CoinAmount(tip.amount), DisplayCharacterName(tip.name)))
    frame:Show()
    frame:Raise()
end

local function ViewTip(tip)
    local view = queuePanel.view
    if not view then
        view = CreateFrame("Frame", "TippleTipView", UIParent, "BackdropTemplate")
        queuePanel.view = view
        view:SetSize(440, 280)
        view:SetPoint("CENTER")
        view:SetFrameStrata("DIALOG")
        view:EnableMouse(true)
        view.title = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        view.title:SetPoint("TOP", 0, -17)
        StyleTipWindow(view, view.title, 43)
        AddCloseButton(view)
        local titleBar = MakeWindowMovable(view, "viewer", 38)
        BindCharacterMenu(titleBar, function() return view.characterName end)

        view.setMessage = CreateTextScroll(view, -59, 18, 388)
    end
    view.characterName = tip.name
    view.title:SetText(("%s for %s"):format(CoinAmount(tip.amount), DisplayCharacterName(tip.name)))
    local body = ReviewBody(tip)
    view:Show()
    view.setMessage(body ~= "" and body or "No message")
end

local function AddHistoryEntry(entry)
    table.insert(TippleHistory, entry)
    historyTotals = nil
    table.sort(TippleHistory, function(a, b)
        if a.timestamp == b.timestamp then return a.order > b.order end
        return a.timestamp > b.timestamp
    end)
    RefreshHistory()
end

local function HistoryCharacterKey(name, realm)
    local character, suffix = name:match("^([^%-]+)%-(.+)$")
    if character then
        name, realm = character, suffix
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then return end
    return (name .. "-" .. realm:gsub("%s+", "")):lower()
end

local function AddTippleTooltip(tooltip)
    if tooltip ~= GameTooltip or not TippleOptions.showTipTooltip or tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if not IsReadable(unit) or not unit then return end
    local isPlayer = UnitIsPlayer(unit)
    if not IsReadable(isPlayer) or not isPlayer then return end
    local faction = UnitFaction(unit)
    if not faction or faction ~= UnitFaction("player") then return end
    local name, realm = UnitFullName(unit)
    if not IsReadable(name) or not name or not IsReadable(realm) then return end
    local key = HistoryCharacterKey(name, realm)
    if not key then return end

    if not historyTotals then
        historyTotals = {}
        for _, entry in ipairs(TippleHistory) do
            if entry.amount and entry.amount > 0 then
                local entryKey = HistoryCharacterKey(entry.name)
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
        tooltip:AddLine("  Total Sent: " .. CoinAmount(totals.Sent), 1, 1, 1)
    end
    if totals.Received > 0 then
        tooltip:AddLine("  Total Received: " .. CoinAmount(totals.Received), 1, 1, 1)
    end
end

local function RegisterTipTooltip()
    if TippleOptions.showTipTooltip and not tipTooltipRegistered then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTippleTooltip)
        tipTooltipRegistered = true
    end
end

local function RecordOpenedTip(mail)
    if not mailboxOpen or not mail:IsValidMailID() then return end
    local index = InboxFrame.openMailID
    local _, _, sender, subject, amount, _, daysLeft, _, _, returned = GetInboxHeaderInfo(index)
    if not IsReadable(sender) or not sender or not IsReadable(subject)
        or (subject ~= mailSubject and subject ~= "Tip") or not IsReadable(returned) or returned then return end
    local body = GetInboxText(index)
    if not IsReadable(body) or not body or body:sub(-#signature) ~= signature then return end
    local message = body:sub(1, #body - #signature):gsub("\r?\n\r?\n$", "")
    local now = GetServerTime()
    local expires
    if IsReadable(daysLeft) and type(daysLeft) == "number" then
        expires = now + daysLeft * 86400
    end
    for _, entry in ipairs(TippleHistory) do
        if entry.direction == "Received" and entry.name == sender and entry.message == message
            and ((expires and entry.expires and math.abs(expires - entry.expires) < 3)
                or (not expires and not entry.expires)) then return end
    end
    AddHistoryEntry({
        direction = "Received",
        name = sender,
        message = message,
        amount = IsReadable(amount) and amount or nil,
        timestamp = expires and math.min(now, math.floor(expires - 30 * 86400 + 0.5)) or now,
        expires = expires,
        order = #TippleHistory + 1,
    })
end

RefreshHistory = function()
    if not historyPanel or not historyPanel:IsShown() then return end
    local count = #TippleHistory
    local page = math.max(1, math.min(historyPanel.page, count))
    historyPanel.page = page
    local entry = TippleHistory[page]
    historyPanel.previous:SetEnabled(page > 1)
    historyPanel.next:SetEnabled(page < count)
    if not entry then
        historyPanel.details:SetText("No tips recorded yet.")
        historyPanel.setMessage("")
        return
    end
    local direction = entry.direction == "Sent" and "Sent to" or "Received from"
    local timestamp = date("%Y-%m-%d %I:%M %p", entry.timestamp)
    if entry.direction == "Received" then
        timestamp = (entry.expires and "Arrived approx. " or "Opened ") .. timestamp
    end
    local amount = entry.amount and entry.amount > 0 and ("  /  " .. CoinAmount(entry.amount)) or ""
    historyPanel.details:SetText(("%s %s%s\n%s  /  %d of %d"):format(
        direction, (DisplayCharacterName(entry.name):gsub("|", "||")), amount, timestamp, page, count))
    historyPanel.setMessage(entry.message ~= "" and entry.message or "No message")
end

local function OpenHistory()
    if not historyPanel then
        local panel = CreateFrame("Frame", "TippleHistoryPanel", UIParent, "BackdropTemplate")
        historyPanel = panel
        panel:SetSize(480, 320)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true)
        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -17)
        title:SetText("Tipple History")
        StyleTipWindow(panel, title, 43)
        MakeWindowMovable(panel, "history", 38)
        AddCloseButton(panel)
        panel.details = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        panel.details:SetPoint("TOPLEFT", 18, -56)
        panel.details:SetWidth(444)
        panel.details:SetJustifyH("LEFT")
        BindCharacterLabel(panel, panel.details, function()
            local entry = TippleHistory[panel.page]
            return entry and entry.name
        end, 18)
        panel.setMessage = CreateTextScroll(panel, -105, 60, 428)

        panel.previous = MakeTipButton(panel)
        panel.previous:SetSize(90, 24)
        panel.previous:SetPoint("BOTTOMLEFT", 18, 19)
        panel.previous:SetText("Newer")
        panel.previous:SetScript("OnClick", function()
            panel.page = panel.page - 1
            RefreshHistory()
        end)
        panel.next = MakeTipButton(panel)
        panel.next:SetSize(90, 24)
        panel.next:SetPoint("BOTTOMRIGHT", -18, 19)
        panel.next:SetText("Older")
        panel.next:SetScript("OnClick", function()
            panel.page = panel.page + 1
            RefreshHistory()
        end)
    end
    historyPanel.page = 1
    historyPanel:Show()
    RefreshHistory()
end

local rowsPerPage = 6

RefreshQueue = function()
    if not queuePanel or not queuePanel:IsShown() then return end
    local count = #TippleQueue
    local pages = math.max(1, math.ceil(count / rowsPerPage))
    queuePanel.page = math.max(1, math.min(queuePanel.page, pages))
    queuePanel.summary:SetText(count == 0 and "No tips queued."
        or ("%d queued  /  Page %d of %d"):format(count, queuePanel.page, pages))
    queuePanel.previous:SetEnabled(queuePanel.page > 1)
    queuePanel.next:SetEnabled(queuePanel.page < pages)
    for index, row in ipairs(queuePanel.rows) do
        local tip = TippleQueue[(queuePanel.page - 1) * rowsPerPage + index]
        row.tip = tip
        row:SetShown(tip ~= nil)
        if tip then
            local name = DisplayCharacterName(tip.name)
            row.title:SetText(("%s   %s%s"):format(name, CoinAmount(tip.amount),
                tip == sending and " (Sending)" or ""))
            row.edit:SetEnabled(tip ~= sending)
            row.delete:SetEnabled(tip ~= sending)
        end
    end
end

OpenQueue = function(returnToConfirmation)
    if not queuePanel then
        local panel = CreateFrame("Frame", "TippleQueuePanel", UIParent, "BackdropTemplate")
        queuePanel = panel
        panel:SetSize(560, 384)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("HIGH")
        panel:EnableMouse(true)
        panel:SetScript("OnHide", function(self)
            if self.returnToConfirmation then
                self.returnToConfirmation = nil
                C_Timer.After(0, PromptTip)
            end
        end)
        panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        panel.title:SetPoint("TOP", 0, -17)
        panel.title:SetText("Tipple")
        StyleTipWindow(panel, panel.title, 43)
        AddCloseButton(panel)
        MakeWindowMovable(panel, "queue", 38)
        panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        panel.summary:SetPoint("TOPLEFT", 20, -54)
        panel.summary:SetTextColor(0.85, 0.72, 0.54)
        local history = MakeTipButton(panel)
        history:SetSize(116, 24)
        history:SetPoint("TOPRIGHT", -20, -48)
        history:SetText("Tipple History")
        history:SetScript("OnClick", OpenHistory)
        panel.page = 1
        panel.rows = {}

        for index = 1, rowsPerPage do
            local row = CreateFrame("Frame", nil, panel)
            panel.rows[index] = row
            row:SetSize(520, 40)
            row:SetPoint("TOPLEFT", 20, -76 - (index - 1) * 42)
            local band = row:CreateTexture(nil, "BACKGROUND")
            band:SetAllPoints()
            band:SetColorTexture(0.59, 0.37, 0.17, index % 2 == 1 and 0.16 or 0.08)
            row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            row.title:SetPoint("LEFT", 10, 0)
            row.title:SetTextColor(0.97, 0.85, 0.65)
            row.title:SetWidth(274)
            row.title:SetWordWrap(false)
            row.title:SetJustifyH("LEFT")

            row.delete = MakeTipButton(row, "delete")
            row.delete:SetSize(70, 24)
            row.delete:SetPoint("RIGHT", -6, 0)
            row.delete:SetText(DELETE)
            row.delete:SetScript("OnClick", function()
                local tip = row.tip
                if tip and EditableTipIndex(tip) then ConfirmDeleteTip(tip) end
            end)

            row.edit = MakeTipButton(row)
            row.edit:SetSize(70, 24)
            row.edit:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
            row.edit:SetText("Edit")
            row.edit:SetScript("OnClick", function()
                local tip = row.tip
                if tip and EditableTipIndex(tip) then OpenForm(tip.name, tip) end
            end)

            local view = MakeTipButton(row)
            view:SetSize(70, 24)
            view:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
            view:SetText("View")
            view:SetScript("OnClick", function()
                local tip = row.tip
                if tip then ViewTip(tip) end
            end)
        end

        panel.previous = MakeTipButton(panel)
        panel.previous:SetSize(90, 24)
        panel.previous:SetPoint("BOTTOMLEFT", 20, 16)
        panel.previous:SetText("Previous")
        panel.previous:SetScript("OnClick", function()
            panel.page = panel.page - 1
            RefreshQueue()
        end)
        panel.next = MakeTipButton(panel)
        panel.next:SetSize(90, 24)
        panel.next:SetPoint("BOTTOMRIGHT", -20, 16)
        panel.next:SetText("Next")
        panel.next:SetScript("OnClick", function()
            panel.page = panel.page + 1
            RefreshQueue()
        end)
    end
    queuePanel.returnToConfirmation = returnToConfirmation or queuePanel.returnToConfirmation
    queuePanel:Show()
    RefreshQueue()
end

SLASH_TIPPLE1 = "/tipple"
SlashCmdList.TIPPLE = function(message)
    if message:match("^%s*history%s*$") then
        OpenHistory()
    else
        OpenQueue()
    end
end

local function SetupOptions()
    local panel = CreateFrame("Frame")
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Tipple")
    Settings.RegisterAddOnCategory(category)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("Tipple")

    local open = MakeTipButton(panel, "primary")
    open:SetSize(160, 26)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    open:SetText("Open Tip Queue")
    open:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        OpenQueue()
    end)

    local button = CreateFrame("Button", "TippleMinimapButton", Minimap)
    button:SetSize(30, 30)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function PositionButton()
        local angle = TippleOptions.minimapAngle or math.rad(135)
        local x = math.cos(angle) * (Minimap:GetWidth() / 2 + 3)
        local y = math.sin(angle) * (Minimap:GetHeight() / 2 + 3)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            if not centerX then return end
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            TippleOptions.minimapAngle = math.atan2(y / scale - centerY, x / scale - centerX)
            PositionButton()
        end)
    end)
    local function StopDragging(self)
        self:SetScript("OnUpdate", nil)
    end
    button:SetScript("OnDragStop", StopDragging)
    button:SetScript("OnHide", StopDragging)
    button:SetScript("OnShow", PositionButton)
    Minimap:HookScript("OnSizeChanged", PositionButton)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Settings.OpenToCategory(category:GetID())
        else
            OpenQueue()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tipple")
        GameTooltip:AddLine("Left-click to open the tip queue", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local showButton = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showButton:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -12)
    local label = showButton:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", showButton, "RIGHT", 2, 0)
    label:SetText("Show minimap button")
    showButton:SetHitRectInsets(0, -label:GetStringWidth() - 2, 0, 0)
    showButton:SetChecked(not TippleOptions.hideMinimapButton)
    showButton:SetScript("OnClick", function(self)
        local shown = self:GetChecked()
        TippleOptions.hideMinimapButton = not shown
        button:SetShown(shown)
    end)

    local showTooltip = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showTooltip:SetPoint("TOPLEFT", showButton, "BOTTOMLEFT", 0, -4)
    local tooltipLabel = showTooltip:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tooltipLabel:SetPoint("LEFT", showTooltip, "RIGHT", 2, 0)
    tooltipLabel:SetText("Show tip totals on player tooltips")
    showTooltip:SetHitRectInsets(0, -tooltipLabel:GetStringWidth() - 2, 0, 0)
    showTooltip:SetChecked(TippleOptions.showTipTooltip == true)
    showTooltip:SetScript("OnClick", function(self)
        TippleOptions.showTipTooltip = self:GetChecked()
        RegisterTipTooltip()
    end)
    PositionButton()
    button:SetShown(not TippleOptions.hideMinimapButton)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        TippleQueue = TippleQueue or {}
        TippleHistory = TippleHistory or {}
        TippleOptions = TippleOptions or {}
        TippleOptions.windowPositions = TippleOptions.windowPositions or {}
        events:UnregisterEvent("ADDON_LOADED")
        SetupOptions()
        RegisterTipTooltip()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 == Enum.PlayerInteractionType.MailInfo then
        mailboxOpen = true
        sentThisVisit = 0
        skippedTips = {}
        promptsStopped = false
        C_Timer.After(0, function()
            if mailboxOpen and OpenMailFrame and not inboxHooked then
                hooksecurefunc(OpenMailFrame, "Update", RecordOpenedTip)
                inboxHooked = true
            end
            PromptTip()
        end)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg1 == Enum.PlayerInteractionType.MailInfo then
        mailboxOpen = false
        HideConfirmation()
    elseif event == "MAIL_SEND_SUCCESS" and sending then
        local tip = sending
        sending = nil
        local index = EditableTipIndex(tip)
        if index then table.remove(TippleQueue, index) end
        sentThisVisit = sentThisVisit + 1
        AddHistoryEntry({
            direction = "Sent",
            name = tip.name,
            message = ReviewBody(tip),
            amount = tip.amount,
            timestamp = GetServerTime(),
            order = #TippleHistory + 1,
        })
        RefreshQueue()
        Notice(("Sent %s to %s."):format(CoinAmount(tip.amount), DisplayCharacterName(tip.name)))
        C_Timer.After(0, PromptTip)
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if not IsReadable(arg1) or arg1 ~= addonName then return end
        local action = IsReadable(arg2) and type(arg2) == "string" and arg2 or "an unnamed action"
        local message = ("WoW blocked %s."):format((action:gsub("|", "||")))
        if sending then
            StopSending(message .. " The tip is still queued.")
        else
            Notice(message)
        end
    elseif sending and (event == "MAIL_FAILED" or event == "SECURE_TRANSFER_CANCEL") then
        StopSending("The send did not complete. The tip is still queued.")
    end
end)

for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MAIL_SEND_SUCCESS", "MAIL_FAILED", "SECURE_TRANSFER_CANCEL",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    events:RegisterEvent(event)
end
