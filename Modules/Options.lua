local _, addon = ...
local Options = {}
addon.Options = Options

local Widgets = addon.Widgets

StaticPopupDialogs["TIPPLE_WIPE_ALL_DATA"] = {
    text = "Permanently wipe Tipple history, queued tips, and settings for this character?\n\nThe UI will reload after you confirm.",
    button1 = "Wipe All Data",
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        if addon.Mail.GetSendingTip() then
            addon.Notice("Wait for the current tip to finish sending before wiping Tipple data.")
            return
        end
        TippleQueue = {}
        TippleHistory = {}
        TippleOptions = { windowPositions = {} }
        ReloadUI()
    end,
}

function Options.Initialize()
    local panel = CreateFrame("Frame")
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Tipple")
    Settings.RegisterAddOnCategory(category)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("Tipple")

    local open = Widgets.MakeTipButton(panel, "primary")
    open:SetSize(160, 26)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    open:SetText("Open Tip Queue")
    open:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        addon.Queue.Open()
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
            addon.Queue.Open()
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
        addon.History.RegisterTooltip()
    end)

    local wipe = Widgets.MakeTipButton(panel, "delete")
    wipe:SetSize(160, 26)
    wipe:SetPoint("TOPLEFT", showTooltip, "BOTTOMLEFT", 4, -20)
    wipe:SetText("Wipe All Data")
    wipe:SetScript("OnClick", function()
        StaticPopup_Show("TIPPLE_WIPE_ALL_DATA")
    end)
    PositionButton()
    button:SetShown(not TippleOptions.hideMinimapButton)
end
