
AuctionatorHistory = select(2, ...)

function AuctionatorHistory:OnInitialize()
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
end

-- This method is hooked to be called when Hide() is called for the ItemRefTooltip.
function AuctionatorHistory:OnTooltipHide(tip)
    local historyButton = _G["auctionatorHistoryButton"]
    if (historyButton ~= nil) then
        -- Hide the history button in case the next clicked hyperlink is not an item
        -- which means we don't want it to show up.
        historyButton:Hide()
    end
end

-- This method is hooked to be called when SetHyperlink() is called for the ItemRefTooltip
-- (which is the tooltip for items that have been clicked).
function AuctionatorHistory:OnTooltipSetItem(tip, linkString)
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
    tip:AddLine("  ")
    tip:SetHeight(tip:GetHeight() + 50)
    historyButton:SetPoint("BOTTOMLEFT", 8, 8)

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
        tip:SetHeight(tip:GetHeight() + 12)
        for _, itemId in ipairs(dbKeys) do
            local itemHistory = Auctionator.Database:GetPriceHistory(itemId)
            for _, itemHistoryTable in ipairs(itemHistory) do
                local date = itemHistoryTable['date']
                local priceStr = Auctionator.Utilities.CreatePaddedMoneyString(itemHistoryTable['minSeen']) .. " (available: " .. itemHistoryTable['available'] .. ")"
                tip:AddDoubleLine(date, priceStr)
                tip:SetHeight(tip:GetHeight() + 12)
            end
        end
        tip:SetHeight(tip:GetHeight() + 2)
        tip:Show()
    end)
end

-- Initialize the addon, when the PLAYER_LOGIN event is triggered.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addon)
	if (event == "PLAYER_LOGIN") then
		AuctionatorHistory:OnInitialize()
	end
end)
