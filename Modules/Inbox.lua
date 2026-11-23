local _, addon = ...
local Inbox = {}
addon.Inbox = Inbox

local Mail = addon.Mail
local Recipients = addon.Recipients
local Tips = addon.Tips

local inboxHooked
local inboxScanPending = false
local inboxTips = {}
local pendingCollection

local function ReadInboxTipHeader(index, opened)
    local _, _, sender, subject, amount, cod, daysLeft, items, _, returned = GetInboxHeaderInfo(index)
    if not Recipients.IsReadable(sender) or not sender or not Recipients.IsReadable(subject)
        or (subject ~= Tips.mailSubject and (not opened or subject ~= "Tip"))
        or not Recipients.IsReadable(returned) or returned
        or not Recipients.IsReadable(cod) or (cod and cod > 0)
        or not Recipients.IsReadable(items) or (items and items > 0) then return end
    if not Recipients.IsReadable(amount) then amount = nil end
    local now = GetServerTime()
    local expires
    if Recipients.IsReadable(daysLeft) and type(daysLeft) == "number" then
        expires = now + daysLeft * 86400
    end
    return {
        index = index,
        name = sender,
        subject = subject,
        amount = amount,
        expires = expires,
        timestamp = expires and math.min(now, math.floor(expires - 30 * 86400 + 0.5)) or now,
    }
end

local function SameInboxTip(a, b)
    return a.name == b.name
        and (not a.subject or not b.subject or a.subject == b.subject)
        and (a.expires == b.expires or (a.expires and b.expires and math.abs(a.expires - b.expires) < 3))
end

local function RecordReceivedTip(tip, message, collected)
    local hasMoney = tip.amount and tip.amount > 0
    local entry = tip.entry
    if not entry then
        for _, previous in ipairs(TippleHistory) do
            if previous.direction == "Received" and SameInboxTip(tip, previous)
                and (not hasMoney or (not previous.collected
                    and (not previous.amount or previous.amount == 0 or previous.amount == tip.amount)))
                and (not message or not previous.message or previous.message == message) then
                entry = previous
                break
            end
        end
    end
    if not entry then
        entry = {
            direction = "Received", name = tip.name, amount = tip.amount, subject = tip.subject,
            timestamp = tip.timestamp, expires = tip.expires, message = message, collected = collected,
            order = #TippleHistory + 1,
        }
        addon.History.AddEntry(entry)
    else
        if hasMoney then entry.amount = tip.amount end
        if message then entry.message = message end
        if collected then entry.collected = true end
        entry.subject = tip.subject
        addon.History.Changed()
    end
    tip.entry = entry
end

local function RecordOpenedTip(mail)
    if not Mail.IsOpen() or not mail:IsShown() or not mail:IsValidMailID() then return end
    local index = InboxFrame.openMailID
    -- Older Tipple mail uses a generic subject, so verify its footer when the player opens it.
    local tip = ReadInboxTipHeader(index, true)
    if not tip then return end
    local cached = inboxTips[index]
    if cached and SameInboxTip(tip, cached) then
        tip.entry = cached.entry
    elseif tip.subject == Tips.mailSubject and tip.amount and tip.amount > 0 then
        cached = tip
        inboxTips[index] = cached
    end
    local body = GetInboxText(index)
    if not Recipients.IsReadable(body) or not body then return end
    if body:sub(-#Tips.signature) ~= Tips.signature then
        if cached and SameInboxTip(tip, cached) then cached.rejected = true end
        return
    end
    local message = body:sub(1, #body - #Tips.signature):gsub("\r?\n\r?\n$", "")
    RecordReceivedTip(tip, message)
    if cached and SameInboxTip(tip, cached) then cached.entry = tip.entry end
end

local function ScanInboxHeaders()
    if not Mail.IsOpen() then return end
    local snapshot = {}
    for index = 1, GetInboxNumItems() do
        local tip = ReadInboxTipHeader(index)
        if tip and tip.amount and tip.amount > 0 then
            local cached = inboxTips[index]
            if cached and cached.amount == tip.amount and SameInboxTip(tip, cached)
                and not (cached.entry and cached.entry.collected) then
                tip.entry, tip.rejected = cached.entry, cached.rejected
            end
            snapshot[index] = tip
        end
    end
    inboxTips = snapshot
end

function Inbox.ScheduleScan()
    if not Mail.IsOpen() or inboxScanPending then return end
    inboxScanPending = true
    C_Timer.After(0, function()
        inboxScanPending = false
        ScanInboxHeaders()
    end)
end

local function TrackInboxCollection(index)
    if not Mail.IsOpen() or pendingCollection then return end
    -- Collection can clear the attachment before the post-hook sees it.
    local tip = inboxTips[index] or ReadInboxTipHeader(index)
    if tip and tip.amount and tip.amount > 0 and not tip.rejected then
        if tip.entry and tip.entry.collected then tip.entry = nil end
        pendingCollection = tip
    end
end

function Inbox.Initialize()
    hooksecurefunc("TakeInboxMoney", TrackInboxCollection)
    hooksecurefunc("AutoLootMailItem", TrackInboxCollection)
end

function Inbox.Open()
    pendingCollection = nil
    ScanInboxHeaders()
end

function Inbox.Close()
    inboxTips = {}
end

function Inbox.CollectionSucceeded()
    if not pendingCollection then return end
    local tip = pendingCollection
    pendingCollection = nil
    if inboxTips[tip.index] == tip then inboxTips[tip.index] = nil end
    RecordReceivedTip(tip, nil, true)
end

function Inbox.CollectionFailed()
    pendingCollection = nil
end

function Inbox.InstallOpenMailHook()
    if Mail.IsOpen() and OpenMailFrame and not inboxHooked then
        hooksecurefunc(OpenMailFrame, "Update", RecordOpenedTip)
        OpenMailFrame:HookScript("OnShow", RecordOpenedTip)
        inboxHooked = true
    end
end
