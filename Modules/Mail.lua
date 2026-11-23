local _, addon = ...
local Mail = {}
addon.Mail = Mail

local Widgets = addon.Widgets
local Recipients = addon.Recipients
local Tips = addon.Tips

local mailboxOpen = false
local sending
local confirmation
local sentThisVisit = 0
local skippedTips = {}
local promptsStopped = false

function Mail.IsOpen()
    return mailboxOpen
end

function Mail.GetSendingTip()
    return sending
end

function Mail.TransferSkip(previous, replacement)
    if not skippedTips[previous] then return end
    skippedTips[previous] = nil
    if replacement then skippedTips[replacement] = true end
end

local function HideConfirmation()
    if confirmation then
        confirmation.tip = nil
        confirmation:Hide()
    end
end

function Mail.RefreshConfirmation()
    if mailboxOpen and confirmation and confirmation:IsShown() then
        HideConfirmation()
        C_Timer.After(0, Mail.Prompt)
    end
end

local function StopSending(message)
    local tip = sending
    sending = nil
    if tip and mailboxOpen and SendMailNameEditBox:GetText() == tip.name
        and SendMailSubjectEditBox:GetText() == Tips.mailSubject
        and SendMailBodyEditBox:GetText() == Tips.MailBody(tip) then
        SendMailFrame_Reset()
    end
    addon.Queue.Refresh()
    addon.Notice(message)
end

local function SendTip(tip)
    if not mailboxOpen or not MailFrame or not MailFrame:IsShown()
        or sending or not addon.Queue.EditableIndex(tip) or skippedTips[tip] then return end
    if not Recipients.IsSameFactionRecipient(tip) then
        addon.Notice("Tipple could not verify a same-faction recipient. The tip is still queued.")
        return
    end

    for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(slot) then
            addon.Notice("Tipple paused because you have outgoing mail attachments.")
            return
        end
    end
    if SendMailNameEditBox:GetText() ~= "" or SendMailSubjectEditBox:GetText() ~= ""
        or SendMailBodyEditBox:GetText() ~= "" or MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        addon.Notice("Tipple paused because you have a mail draft.")
        return
    end
    local postage = GetSendMailPrice()
    if tip.amount + postage > GetMoney() then
        addon.Notice(("You need %s for the tip and postage."):format(Tips.CoinAmount(tip.amount + postage)))
        return
    end

    -- Let Blizzard handle the protected send and any confirmation for attached money.
    local ok = pcall(function()
        MailFrameTab_OnClick(nil, 2)
        SendMailNameEditBox:ClearFocus()
        SendMailRadioButton_OnClick(1)
        SendMailNameEditBox:SetText(tip.name)
        SendMailSubjectEditBox:SetText(Tips.mailSubject)
        if SendMailNameEditBox:GetText() ~= tip.name or SendMailSubjectEditBox:GetText() ~= Tips.mailSubject then
            SendMailFrame_Reset()
            addon.Notice("The mailbox did not keep the recipient or subject. The tip is still queued.")
            return
        end
        local body = Tips.MailBody(tip)
        SendMailBodyEditBox:SetText(body)
        if SendMailBodyEditBox:GetText() ~= body then
            SendMailFrame_Reset()
            addon.Notice("The game changed the mail body. The tip is still queued.")
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
            addon.Notice(("The mailbox accepted %s of the requested %s. The tip is still queued."):format(
                Tips.CoinAmount(attached), Tips.CoinAmount(tip.amount)))
            return
        end
        -- Programmatic edits may not have refreshed the button yet.
        SendMailFrame_CanSend()
        if not SendMailMailButton:IsEnabled() or not SendMailSendMoneyButton:GetChecked() then
            SendMailFrame_Reset()
            addon.Notice("The mailbox would not enable sending money for this draft. The tip is still queued.")
            return
        end
        sending = tip
        addon.Queue.Refresh()
        SendMailMailButton:Click()
    end)
    if not ok then
        StopSending("The game blocked the send. The tip is still queued.")
    end
end

function Mail.Prompt()
    if not mailboxOpen or promptsStopped or sending or not MailFrame or not MailFrame:IsShown() then return end
    local tip, queueIndex
    for index, queuedTip in ipairs(TippleQueue) do
        if not skippedTips[queuedTip] then
            if Recipients.IsSameFactionRecipient(queuedTip) then
                tip, queueIndex = queuedTip, index
                break
            end
            skippedTips[queuedTip] = true
            addon.Notice("Tipple could not verify a same-faction recipient. The tip is still queued.")
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
        Widgets.StyleTipWindow(frame, frame.title, 43)
        Widgets.AddCloseButton(frame)
        Widgets.MakeWindowMovable(frame, "confirmation", 38)
        frame:SetScript("OnHide", function(self)
            if self.tip then
                promptsStopped = true
                self.tip = nil
            end
        end)
        local queue = Widgets.MakeTipButton(frame)
        queue:SetSize(105, 24)
        queue:SetPoint("TOPLEFT", 44, -10)
        queue:SetFrameLevel(frame:GetFrameLevel() + 2)
        queue:SetText("View Queue")
        queue:SetScript("OnClick", function()
            HideConfirmation()
            addon.Queue.Open(true)
        end)
        frame.details = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        frame.details:SetPoint("TOPLEFT", 18, -56)
        frame.details:SetWidth(444)
        frame.details:SetJustifyH("LEFT")
        Widgets.BindCharacterLabel(frame, frame.details, function() return frame.tip and frame.tip.name end, 18)
        frame.setMessage = Widgets.CreateTextScroll(frame, -159, 60, 428, true)

        local send = Widgets.MakeTipButton(frame, "primary")
        send:SetSize(100, 25)
        send:SetPoint("BOTTOM", frame, "BOTTOM", -165, 19)
        send:SetText("Send Tip")
        send:SetScript("OnClick", function()
            local pendingTip = frame.tip
            HideConfirmation()
            SendTip(pendingTip)
        end)
        local edit = Widgets.MakeTipButton(frame)
        edit:SetSize(100, 25)
        edit:SetPoint("BOTTOM", frame, "BOTTOM", -55, 19)
        edit:SetText("Edit")
        edit:SetScript("OnClick", function()
            local pendingTip = frame.tip
            if not pendingTip or not addon.Queue.EditableIndex(pendingTip) then return end
            HideConfirmation()
            addon.Editor.Open(pendingTip.name, pendingTip, true)
        end)
        local later = Widgets.MakeTipButton(frame)
        later:SetSize(100, 25)
        later:SetPoint("BOTTOM", frame, "BOTTOM", 55, 19)
        later:SetText("Later")
        later:SetScript("OnClick", function()
            if frame.tip then skippedTips[frame.tip] = true end
            HideConfirmation()
            Mail.Prompt()
        end)
        local exit = Widgets.MakeTipButton(frame)
        exit:SetSize(100, 25)
        exit:SetPoint("BOTTOM", frame, "BOTTOM", 165, 19)
        exit:SetText("Exit")
        exit:SetScript("OnClick", function() frame:Hide() end)
    end
    local postage = GetSendMailPrice()
    confirmation.tip = tip
    confirmation.title:SetText(("Tipple - %d/%d"):format(sentThisVisit + queueIndex, sentThisVisit + #TippleQueue))
    confirmation.details:SetText(("Send tip of %s to %s?\n\nPostage: %s\nThis tip incl. postage: %s\nQueue incl. postage: %s"):format(
        Tips.CoinAmount(tip.amount), (Recipients.DisplayCharacterName(tip.name):gsub("|", "||")),
        Tips.CoinAmount(postage), Tips.CoinAmount(tip.amount + postage), Tips.CoinAmount(addon.Queue.MailCost(postage))))
    confirmation:Show()
    confirmation.setMessage(Tips.ReviewBody(tip))
end

function Mail.Open()
    mailboxOpen = true
    sentThisVisit = 0
    skippedTips = {}
    promptsStopped = false
end

function Mail.Close()
    mailboxOpen = false
    HideConfirmation()
end

function Mail.SendSucceeded()
    if not sending then return end
    local tip = sending
    sending = nil
    local index = addon.Queue.EditableIndex(tip)
    if index then table.remove(TippleQueue, index) end
    sentThisVisit = sentThisVisit + 1
    addon.History.AddEntry({
        direction = "Sent",
        name = tip.name,
        faction = tip.faction,
        message = Tips.ReviewBody(tip),
        amount = tip.amount,
        timestamp = GetServerTime(),
        order = #TippleHistory + 1,
    })
    addon.Queue.Refresh()
    addon.Notice(("Sent %s to %s."):format(Tips.CoinAmount(tip.amount), Recipients.DisplayCharacterName(tip.name)))
    C_Timer.After(0, Mail.Prompt)
end

function Mail.ReportBlocked(actionName)
    local action = Recipients.IsReadable(actionName) and type(actionName) == "string" and actionName or "an unnamed action"
    local message = ("WoW blocked %s."):format((action:gsub("|", "||")))
    if sending then
        StopSending(message .. " The tip is still queued.")
    else
        addon.Notice(message)
    end
end

function Mail.SendFailed()
    if sending then
        StopSending("The send did not complete. The tip is still queued.")
    end
end
