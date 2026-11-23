local _, addon = ...
local Widgets = {}
addon.Widgets = Widgets

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

function Widgets.StyleTipWindow(window, title, headerHeight)
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

function Widgets.AddCloseButton(window)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() window:Hide() end)
end

function Widgets.MakeTipButton(parent, style)
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

function Widgets.MakeWindowMovable(window, key, titleHeight)
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

function Widgets.BindCharacterMenu(area, getName)
    area:EnableMouse(true)
    area:HookScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local name = getName()
        if not name or name == "" or name == UNKNOWN then return end
        local _, realm = name:match("^([^%-]+)%-(.+)$")
        UnitPopup_OpenMenu("FRIEND", { name = name, server = realm, ownerFrame = self })
    end)
end

function Widgets.BindCharacterLabel(parent, label, getName, height)
    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", label, "TOPLEFT")
    area:SetPoint("TOPRIGHT", label, "TOPRIGHT")
    area:SetHeight(height)
    Widgets.BindCharacterMenu(area, getName)
    return area
end

function Widgets.FocusOnClick(area, field)
    area:EnableMouse(true)
    area:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            FocusTipWindow(field)
            if not field:HasFocus() then field:SetFocus() end
        end
    end)
end

function Widgets.ClearInputFocus(field)
    field:ClearHighlightText()
    field:ClearFocus()
end

function Widgets.MakeInput(parent, width, maxBytes)
    local field = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    field:SetSize(width, 26)
    field:SetAutoFocus(false)
    field:SetMaxBytes(maxBytes)
    field:SetHitRectInsets(-4, -4, -2, -2)
    Widgets.FocusOnClick(field, field)
    field:SetScript("OnEscapePressed", Widgets.ClearInputFocus)
    return field
end

function Widgets.CreateTextScroll(window, top, bottom, width, hideUnusedScrollbar)
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

Widgets.rowsPerPage = 6

function Widgets.CreateTipListRow(panel, index, top)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(520, 40)
    row:SetPoint("TOPLEFT", 20, top - (index - 1) * 42)
    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(0.59, 0.37, 0.17, index % 2 == 1 and 0.16 or 0.08)
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.title:SetTextColor(0.97, 0.85, 0.65)
    row.title:SetWordWrap(false)
    row.title:SetJustifyH("LEFT")
    return row
end

function Widgets.SetupListPaging(panel, refresh, previousText, nextText)
    panel.previous = Widgets.MakeTipButton(panel)
    panel.previous:SetSize(90, 24)
    panel.previous:SetPoint("BOTTOMLEFT", 20, 16)
    panel.previous:SetText(previousText)
    panel.previous:SetScript("OnClick", function()
        panel.page = panel.page - 1
        refresh()
    end)
    panel.next = Widgets.MakeTipButton(panel)
    panel.next:SetSize(90, 24)
    panel.next:SetPoint("BOTTOMRIGHT", -20, 16)
    panel.next:SetText(nextText)
    panel.next:SetScript("OnClick", function()
        panel.page = panel.page + 1
        refresh()
    end)
end
