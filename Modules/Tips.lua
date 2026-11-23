local _, addon = ...
local Tips = {}
addon.Tips = Tips

Tips.mailBodyLimit = 500
Tips.signature = "- Sent with Tipple"
Tips.mailSubject = "You've Been Tipped!"

Tips.denominations = {
    { value = 10000, atlas = "coin-gold", width = 78 },
    { value = 100, atlas = "coin-silver", width = 48 },
    { value = 1, atlas = "coin-copper", width = 48 },
}

function Tips.CoinCount(amount, index, denomination)
    local count = math.floor(amount / denomination.value)
    return index == 1 and count or count % 100
end

function Tips.ParseAmount(fields)
    local amount = 0
    for index, denomination in ipairs(Tips.denominations) do
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

function Tips.CoinAmount(amount)
    local parts = {}
    for index, denomination in ipairs(Tips.denominations) do
        local count = Tips.CoinCount(amount, index, denomination)
        if count > 0 then
            parts[#parts + 1] = ("%d|A:%s:13:13|a"):format(count, denomination.atlas)
        end
    end
    return #parts > 0 and table.concat(parts, " ") or "0"
end

function Tips.SetAmountFields(fields, amount)
    for index, denomination in ipairs(Tips.denominations) do
        local count = Tips.CoinCount(amount, index, denomination)
        fields[index]:SetText(count > 0 and tostring(count) or "")
    end
end

local function FormatClock(hour, minute)
    return ("%02d:%02d %s"):format((hour + 11) % 12 + 1, minute, hour < 12 and "AM" or "PM")
end

function Tips.QueueContext()
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
    local calendar = C_DateAndTime.GetCurrentCalendarTime()
    return ("%04d-%02d-%02d %s Server Time - %s"):format(calendar.year, calendar.month,
        calendar.monthDay, FormatClock(calendar.hour, calendar.minute), zone)
end

function Tips.MailFooter(tip)
    return tip.context and (tip.context .. "\n\n" .. Tips.signature) or Tips.signature
end

function Tips.TipMessageFits(tip)
    local message = tip.message or ""
    local bytes = #Tips.MailFooter(tip) + (message ~= "" and #message + 2 or 0)
    return bytes <= Tips.mailBodyLimit
end

function Tips.CombineTips(first, added)
    local amount = first.amount + added.amount
    if amount > (MAX_MONEY_AMOUNT or 99999999999) then
        return nil, "The combined amount exceeds the limit for one letter."
    end
    local parts = {}
    for _, text in ipairs({ first.message or "", added.context or "", added.message or "" }) do
        if text ~= "" then parts[#parts + 1] = text end
    end
    local tip = {
        name = first.name,
        amount = amount,
        message = table.concat(parts, "\n\n"),
        context = first.context,
        faction = added.faction or first.faction,
    }
    if not Tips.TipMessageFits(tip) then
        return nil, "The combined message is too long. Shorten this message or edit the queued tip."
    end
    return tip
end

function Tips.ReviewBody(tip)
    local message = tip.message or ""
    local footer = Tips.MailFooter(tip)
    -- Older queued messages may have used the full limit. Keep the footer and cut at a UTF-8 boundary.
    local lastByte = Tips.mailBodyLimit - #footer - 2
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

function Tips.MailBody(tip)
    local body = Tips.ReviewBody(tip)
    return body ~= "" and (body .. "\n\n" .. Tips.signature) or Tips.signature
end
