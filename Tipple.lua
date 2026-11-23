local addonName, addon = ...
local Inbox, Mail, Queue, History = addon.Inbox, addon.Mail, addon.Queue, addon.History
local events = CreateFrame("Frame")

function addon.Notice(message)
    print("|cffffd100Tipple|r " .. message)
end

addon.Recipients.RegisterMenus()

SLASH_TIPPLE1 = "/tipple"
SlashCmdList.TIPPLE = function(message)
    if message:match("^%s*history%s*$") then
        History.Open()
    else
        Queue.Open()
    end
end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        TippleQueue = TippleQueue or {}
        TippleHistory = TippleHistory or {}
        TippleOptions = TippleOptions or {}
        TippleOptions.windowPositions = TippleOptions.windowPositions or {}
        events:UnregisterEvent("ADDON_LOADED")
        addon.Options.Initialize()
        History.RegisterTooltip()
        Inbox.Initialize()
        if IsLoggedIn() then
            Queue.ConsolidateSavedTips()
            events:UnregisterEvent("PLAYER_LOGIN")
        end
    elseif event == "PLAYER_LOGIN" then
        Queue.ConsolidateSavedTips()
        events:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 == Enum.PlayerInteractionType.MailInfo then
        Mail.Open()
        Queue.Refresh()
        Inbox.Open()
        C_Timer.After(0, function()
            Inbox.InstallOpenMailHook()
            Mail.Prompt()
        end)
    elseif event == "MAIL_INBOX_UPDATE" then
        Inbox.ScheduleScan()
    elseif event == "MAIL_SUCCESS" then
        Inbox.CollectionSucceeded()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg1 == Enum.PlayerInteractionType.MailInfo then
        Mail.Close()
        Inbox.Close()
        Queue.Refresh()
    elseif event == "MAIL_SEND_SUCCESS" then
        Mail.SendSucceeded()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if addon.Recipients.IsReadable(arg1) and arg1 == addonName then
            Mail.ReportBlocked(arg2)
        end
    elseif event == "MAIL_FAILED" or event == "SECURE_TRANSFER_CANCEL" then
        Inbox.CollectionFailed()
        Mail.SendFailed()
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "SECURE_TRANSFER_CANCEL",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    events:RegisterEvent(event)
end
