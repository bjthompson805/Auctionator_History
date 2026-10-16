
AuctionatorHistory = select(2, ...)

-- The horn icon used by Recount's "report" button.
local REPORT_ICON = "Interface\\Buttons\\UI-GuildButton-MOTD-Up"

-- Limits for the "number of entries to report" slider (same range as Recount).
local MAX_REPORT_LINES = 25
local DEFAULT_REPORT_LINES = 10

-- Space between the tooltip's last line and its button, and below the button.
local BUTTON_GAP = 6
local BUTTON_BOTTOM_MARGIN = 8

-- C_ChatInfo.SendChatMessage replaces the global in newer clients.
local SendChatMessage = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function AuctionatorHistory:OnInitialize()
    AuctionatorHistoryDB = AuctionatorHistoryDB or {}
    AuctionatorHistoryDB.reportLines = AuctionatorHistoryDB.reportLines or DEFAULT_REPORT_LINES

    hooksecurefunc(
        ItemRefTooltip,
        "SetHyperlink",
        function(tip, linkString) AuctionatorHistory:OnTooltipSetItem(tip, linkString); end
    )

    hooksecurefunc(
        ItemRefTooltip,
        "Hide",
        function(tip) AuctionatorHistory:OnTooltipHide(tip); end
    )

    -- Other addons (e.g. Auctionator and idTip) add lines and call Show() after
    -- the SetHyperlink hook above runs. Show() shrinks the tooltip back to fit
    -- just its text, so make room for the button again after every Show().
    hooksecurefunc(
        ItemRefTooltip,
        "Show",
        function(tip) AuctionatorHistory:RequestTooltipFit(tip); end
    )
end

-- Makes the tooltip tall enough to fit the button showing at its bottom (if
-- any) below its last line of text, so the button never covers any text.
function AuctionatorHistory:FitTooltipToButton(tip)
    local button = _G["auctionatorHistoryReportButton"]
    if (button == nil or not button:IsShown()) then
        button = _G["auctionatorHistoryButton"]
    end
    if (button == nil or not button:IsShown()) then return; end

    local lastLine = _G[tip:GetName() .. "TextLeft" .. tip:NumLines()]
    local tipTop = tip:GetTop()
    local lineBottom = lastLine and lastLine:GetBottom()
    if (tipTop == nil or lineBottom == nil) then return; end

    local height = (tipTop - lineBottom) + BUTTON_GAP + button:GetHeight() + BUTTON_BOTTOM_MARGIN
    if (math.abs(tip:GetHeight() - height) > 0.5) then
        tip:SetHeight(height)
    end
end

function AuctionatorHistory:RequestTooltipFit(tip)
    AuctionatorHistory:FitTooltipToButton(tip)

    -- Check again on the next frame, in case the tooltip is laid out again
    -- later in this frame without another Show() call.
    C_Timer.After(0, function() AuctionatorHistory:FitTooltipToButton(tip); end)
end

-- This method is hooked to be called when Hide() is called for the ItemRefTooltip.
function AuctionatorHistory:OnTooltipHide(tip)
    local historyButton = _G["auctionatorHistoryButton"]
    if (historyButton ~= nil) then
        -- Hide the history button in case the next clicked hyperlink is not an item
        -- which means we don't want it to show up.
        historyButton:Hide()
    end

    AuctionatorHistory:HideReportButton()
end

-- This method is hooked to be called when SetHyperlink() is called for the ItemRefTooltip
-- (which is the tooltip for items that have been clicked).
function AuctionatorHistory:OnTooltipSetItem(tip, linkString)
    -- The tooltip can switch to a new link without being hidden first, and the
    -- new link's history has not been shown yet, so hide the report button.
    AuctionatorHistory:HideReportButton()

    -- Do not show the history button for hyperlinks that are not items.
    local linkType = strsplit(":", linkString)
    if linkType ~= "item" then return; end

    -- Create the history button
    local historyButton = _G["auctionatorHistoryButton"]
    if (historyButton == nil) then
        -- Create the button
        historyButton = CreateFrame("Button", "auctionatorHistoryButton", tip, "UIPanelButtonTemplate")
    else
        -- Show the previously created button
        historyButton:Show()
    end
    
    historyButton:SetWidth(130)
    historyButton:SetHeight(22)
    historyButton:SetText("Auctionator History")

    -- Place the history button on tooltips for items that have been clicked
    historyButton:SetPoint("BOTTOMLEFT", 8, BUTTON_BOTTOM_MARGIN)
    AuctionatorHistory:RequestTooltipFit(tip)

    -- Setup clicking of the history button
    historyButton:RegisterForClicks("AnyUp")
    historyButton:SetScript("OnClick", function (self, button, down)
        AuctionatorHistory:ShowHistory(tip, historyButton)
    end)
end

-- This method is called when the "Auctionator History" button is clicked.
function AuctionatorHistory:ShowHistory(tip, historyButton)
    local _, itemLink = tip:GetItem()
    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        historyButton:Hide()
        tip:SetWidth(512)
        tip:AddDoubleLine("Date", "Price")
        local reportEntries = {}
        for _, itemId in ipairs(dbKeys) do
            local itemHistory = Auctionator.Database:GetPriceHistory(itemId)
            for _, itemHistoryTable in ipairs(itemHistory) do
                local date = itemHistoryTable['date']
                local priceStr = Auctionator.Utilities.CreatePaddedMoneyString(itemHistoryTable['minSeen']) .. " (available: " .. itemHistoryTable['available'] .. ")"
                tip:AddDoubleLine(date, priceStr)
                table.insert(reportEntries, itemHistoryTable)
            end
        end

        if #reportEntries > 0 then
            AuctionatorHistory:ShowReportButton(tip, itemLink, reportEntries)
        end

        -- Show() resizes the tooltip to fit the new lines, and then the Show()
        -- hook makes room for the report button below them.
        tip:Show()
    end)
end

-- Prints a message from this addon to the chat frame (not sent to anyone).
local function PrintMessage(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Auctionator History:|r " .. message)
end

-- Formats a copper amount as plain text (e.g. "12g 5s 3c"), because the coin
-- icons used in the tooltip cannot be sent in chat messages.
local function FormatMoneyForChat(amount)
    amount = math.floor(amount)
    local gold = math.floor(amount / 10000)
    local silver = math.floor(amount / 100) % 100
    local copper = amount % 100

    local parts = {}
    if gold > 0 then table.insert(parts, gold .. "g") end
    if silver > 0 then table.insert(parts, silver .. "s") end
    if copper > 0 or #parts == 0 then table.insert(parts, copper .. "c") end
    return table.concat(parts, " ")
end

-- This method shows the report (horn) button at the bottom of the scan history.
function AuctionatorHistory:ShowReportButton(tip, itemLink, entries)
    local reportButton = _G["auctionatorHistoryReportButton"]
    if (reportButton == nil) then
        -- Same button style as the "Auctionator History" button, with the horn inside.
        reportButton = CreateFrame("Button", "auctionatorHistoryReportButton", tip, "UIPanelButtonTemplate")
        reportButton:SetWidth(32)
        reportButton:SetHeight(22)
        reportButton:RegisterForClicks("AnyUp")

        local icon = reportButton:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(REPORT_ICON)
        icon:SetWidth(16)
        icon:SetHeight(16)
        icon:SetPoint("CENTER", 0, 0)

        -- Nudge the horn while the button is held down, the way button text moves.
        -- HookScript keeps the template's own pressed-look handlers intact.
        reportButton:HookScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
        reportButton:HookScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 0) end)
        reportButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Report History")
            GameTooltip:AddLine("Send this item's Auctionator history to chat.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        reportButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    reportButton:SetPoint("BOTTOMLEFT", 8, BUTTON_BOTTOM_MARGIN)
    reportButton:SetScript("OnClick", function(self, button, down)
        AuctionatorHistory:ShowReportWindow(itemLink, entries)
    end)
    reportButton:Show()
end

function AuctionatorHistory:HideReportButton()
    local reportButton = _G["auctionatorHistoryReportButton"]
    if (reportButton ~= nil) then
        reportButton:Hide()
    end
end

-- The places a report can be sent to: {label, chat type, condition to be listed}.
-- These mirror Recount's report locations.
local ReportLocations = {
    {SAY or "Say", "SAY"},
    {PARTY or "Party", "PARTY", function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end},
    {INSTANCE_CHAT or "Instance", "INSTANCE_CHAT", function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end},
    {RAID or "Raid", "RAID", function() return IsInRaid() end},
    {GUILD or "Guild", "GUILD", function() return IsInGuild() end},
    {OFFICER or "Officer", "OFFICER", function() return IsInGuild() end},
    {"RealID", "REALID"},
    {WHISPER or "Whisper", "WHISPER"},
    {"Whisper Target", "WHISPER_TARGET"},
}

-- The currently listed report locations: {label, chat type, channel number}.
local ReportList = {}

local function BuildReportList()
    ReportList = {}

    for _, location in ipairs(ReportLocations) do
        if location[3] == nil or location[3]() then
            table.insert(ReportList, {location[1], location[2]})
        end
    end

    -- GetChannelList() returns (id, name, disabled) for each joined channel.
    local channels = {GetChannelList()}
    for i = 1, #channels / 3 do
        local channelId, channelName = channels[i * 3 - 2], channels[i * 3 - 1]
        table.insert(ReportList, {channelId .. ". " .. channelName, "CHANNEL", channelId})
    end
end

-- Layout of the report window.
local REPORT_ROWS_TOP = 122
local REPORT_ROW_HEIGHT = 20
local REPORT_BOTTOM_HEIGHT = 80

-- This method creates the report window, using the default UI's dialog look.
function AuctionatorHistory:CreateReportWindow()
    local frame = CreateFrame("Frame", "AuctionatorHistoryReportFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(250)
    frame:SetHeight(300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Close the window with the Escape key, like other default UI windows.
    table.insert(UISpecialFrames, frame:GetName())

    -- Title header
    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(256)
    header:SetHeight(64)
    header:SetPoint("TOP", 0, 12)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("Report History")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)

    -- The item being reported
    frame.itemText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.itemText:SetPoint("TOP", 0, -30)
    frame.itemText:SetWidth(210)
    frame.itemText:SetWordWrap(false)

    -- Number of entries to report
    local slider = CreateFrame("Slider", "AuctionatorHistoryReportSlider", frame, "OptionsSliderTemplate")
    frame.slider = slider
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(1, MAX_REPORT_LINES)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetWidth(190)
    slider:SetHeight(16)
    slider:SetPoint("TOP", 0, -68)
    _G[slider:GetName() .. "Low"]:SetText("1")
    _G[slider:GetName() .. "High"]:SetText(tostring(MAX_REPORT_LINES))
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        AuctionatorHistoryDB.reportLines = value
        _G[self:GetName() .. "Text"]:SetText("Report Last: " .. value)
    end)
    slider:SetValue(AuctionatorHistoryDB.reportLines)
    -- OnValueChanged does not fire if the value did not change, so set the label too.
    _G[slider:GetName() .. "Text"]:SetText("Report Last: " .. AuctionatorHistoryDB.reportLines)

    local reportToText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reportToText:SetPoint("TOPLEFT", 20, -(REPORT_ROWS_TOP - 20))
    reportToText:SetText("Report To:")

    -- Whisper name
    frame.whisperBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.whisperBox:SetWidth(130)
    frame.whisperBox:SetHeight(20)
    frame.whisperBox:SetPoint("BOTTOMRIGHT", -24, 50)
    frame.whisperBox:SetAutoFocus(false)
    frame.whisperBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.whisperBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local whisperText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whisperText:SetPoint("RIGHT", frame.whisperBox, "LEFT", -10, 0)
    whisperText:SetText((WHISPER or "Whisper") .. ":")

    -- Report button
    local sendButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendButton:SetWidth(100)
    sendButton:SetHeight(22)
    sendButton:SetPoint("BOTTOM", 0, 18)
    sendButton:SetText("Report")
    sendButton:SetScript("OnClick", function()
        if AuctionatorHistory:SendReport() then
            frame:Hide()
        end
    end)

    frame.rows = {}
    frame:Hide()
    self.reportWindow = frame
end

-- This method adds one more radio button row to the "Report To" list.
function AuctionatorHistory:AddReportRow()
    local frame = self.reportWindow
    local index = #frame.rows + 1

    local row = CreateFrame("Frame", nil, frame)
    row:SetWidth(210)
    row:SetHeight(REPORT_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 20, -(REPORT_ROWS_TOP + REPORT_ROW_HEIGHT * (index - 1)))

    row.radio = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
    row.radio:SetPoint("LEFT", 0, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.radio, "RIGHT", 4, 0)

    -- Let the label be clicked too, not just the radio button itself.
    row.radio:SetHitRectInsets(0, -180, 0, 0)

    row.radio:SetScript("OnClick", function(self)
        for _, otherRow in ipairs(frame.rows) do
            otherRow.radio:SetChecked(false)
        end
        self:SetChecked(true)
        AuctionatorHistoryDB.reportChannel = ReportList[index][1]
    end)

    table.insert(frame.rows, row)
end

-- This method is called when the report (horn) button is clicked.
function AuctionatorHistory:ShowReportWindow(itemLink, entries)
    if self.reportWindow == nil then
        self:CreateReportWindow()
    end

    local frame = self.reportWindow
    self.reportItemLink = itemLink
    self.reportEntries = entries
    frame.itemText:SetText(itemLink)

    BuildReportList()

    for _ = #frame.rows + 1, #ReportList do
        self:AddReportRow()
    end

    for i, row in ipairs(frame.rows) do
        if i <= #ReportList then
            row.label:SetText(ReportList[i][1])
            row.radio:SetChecked(ReportList[i][1] == AuctionatorHistoryDB.reportChannel)
            row:Show()
        else
            row:Hide()
        end
    end

    frame:SetHeight(REPORT_ROWS_TOP + REPORT_ROW_HEIGHT * #ReportList + REPORT_BOTTOM_HEIGHT)
    frame:Show()
end

-- Returns the bnetAccountID of the friend selected in the friends list, if online.
local function GetSelectedBNetFriend()
    local index = BNGetSelectedFriend and BNGetSelectedFriend()
    if index == nil or index == 0 or BNGetNumFriends() == 0 then
        PrintMessage("No RealID/BattleTag friend selected in the friends list.")
        return nil
    end

    local bnetAccountID, isOnline
    if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        local accountInfo = C_BattleNet.GetFriendAccountInfo(index)
        if accountInfo then
            bnetAccountID = accountInfo.bnetAccountID
            isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline
        end
    else
        local _
        bnetAccountID, _, _, _, _, _, _, isOnline = BNGetFriendInfo(index)
    end

    if not isOnline then
        PrintMessage("The selected RealID/BattleTag friend is not online.")
        return nil
    end
    return bnetAccountID
end

-- This method sends the report to the selected chat. Returns true if it was sent.
function AuctionatorHistory:SendReport()
    local frame = self.reportWindow
    local chatType, target

    for i, row in ipairs(frame.rows) do
        if i <= #ReportList and row.radio:GetChecked() then
            chatType = ReportList[i][2]
            target = ReportList[i][3]
        end
    end

    if chatType == nil then
        PrintMessage("Choose where to report to first.")
        return false
    elseif chatType == "REALID" then
        target = GetSelectedBNetFriend()
        if target == nil then return false end
    elseif chatType == "WHISPER" then
        target = strtrim(frame.whisperBox:GetText() or "")
        if target == "" then
            PrintMessage("Enter a name to whisper.")
            return false
        end
    elseif chatType == "WHISPER_TARGET" then
        chatType = "WHISPER"
        if not UnitExists("target") then
            PrintMessage("No target selected.")
            return false
        elseif not UnitIsPlayer("target") then
            PrintMessage("Your target isn't a player.")
            return false
        end
        target = GetUnitName("target", true)
    end

    local entries = self.reportEntries
    local count = math.min(AuctionatorHistoryDB.reportLines, #entries)

    local lines = {}
    table.insert(lines, "Auctionator History for " .. self.reportItemLink .. " (last " .. count .. " scans):")
    for i = 1, count do
        local entry = entries[i]
        local line = i .. ". " .. entry['date'] .. ": " .. FormatMoneyForChat(entry['minSeen'])
        if entry['available'] ~= nil then
            line = line .. " (available: " .. entry['available'] .. ")"
        end
        table.insert(lines, line)
    end

    for _, line in ipairs(lines) do
        if chatType == "REALID" then
            BNSendWhisper(target, line)
        else
            SendChatMessage(line, chatType, nil, target)
        end
    end
    return true
end

-- Initialize the addon, when the PLAYER_LOGIN event is triggered.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addon)
	if (event == "PLAYER_LOGIN") then
		AuctionatorHistory:OnInitialize()
	end
end)
