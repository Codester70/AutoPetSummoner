-- AutoPetSummoner_Config.lua v1.0.4
local panel = CreateFrame("Frame", "AutoPetSummonerOptionsPanel")
panel.name = "Auto Pet Summoner"

local useSettingsAPI = Settings and Settings.RegisterCanvasLayoutCategory

local function CreateConfigUI()
    if useSettingsAPI then
        local canvas = CreateFrame("Frame", nil)
        canvas.name = panel.name

        local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Auto Pet Summoner")

        local sub = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        sub:SetText("Automatically summons a random vanity pet every X minutes.")

        local enable = CreateFrame("CheckButton", nil, canvas, "InterfaceOptionsCheckButtonTemplate")
        enable.Text:SetText("Enable auto-summon")
        enable:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -12)

        local fav = CreateFrame("CheckButton", nil, canvas, "InterfaceOptionsCheckButtonTemplate")
        fav.Text:SetText("Use only favorited pets")
        fav:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -10)

        local inst = CreateFrame("CheckButton", nil, canvas, "InterfaceOptionsCheckButtonTemplate")
        inst.Text:SetText("Disable in instances")
        inst:SetPoint("TOPLEFT", fav, "BOTTOMLEFT", 0, -10)

        local resummon = CreateFrame("CheckButton", nil, canvas, "InterfaceOptionsCheckButtonTemplate")
        resummon.Text:SetText("Resummon even if a pet is already out")
        resummon:SetPoint("TOPLEFT", inst, "BOTTOMLEFT", 0, -10)

        local slider = CreateFrame("Slider", "AutoPetSummonerIntervalSlider", canvas, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", resummon, "BOTTOMLEFT", 0, -30)
        slider:SetMinMaxValues(1, 60)
        slider:SetValueStep(1)
        _G[slider:GetName() .. "Low"]:SetText("1")
        _G[slider:GetName() .. "High"]:SetText("60")
        _G[slider:GetName() .. "Text"]:SetText("Minutes between summons")

        local apply = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
        apply:SetText("Apply & Summon Now")
        apply:SetSize(180, 22)
        apply:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -16)

        canvas:SetScript("OnShow", function()
            AutoPetDB = AutoPetDB or {}
            enable:SetChecked(AutoPetDB.enabled)
            fav:SetChecked(AutoPetDB.favoritesOnly or false)
            inst:SetChecked(AutoPetDB.disableInInstances)
            resummon:SetChecked(AutoPetDB.resummonIfPetOut)
            slider:SetValue(AutoPetDB.intervalMinutes or 10)
            _G[slider:GetName() .. "Text"]:SetText("Minutes between summons: " .. (AutoPetDB.intervalMinutes or 10))
        end)

        enable:SetScript("OnClick", function(self)
            AutoPetDB.enabled = self:GetChecked()
            if AutoPetSummoner_Refresh then AutoPetSummoner_Refresh() end
        end)
        fav:SetScript("OnClick", function(self) AutoPetDB.favoritesOnly = self:GetChecked() end)
        inst:SetScript("OnClick", function(self) AutoPetDB.disableInInstances = self:GetChecked() end)
        resummon:SetScript("OnClick", function(self) AutoPetDB.resummonIfPetOut = self:GetChecked() end)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            AutoPetDB.intervalMinutes = value
            _G[self:GetName() .. "Text"]:SetText("Minutes between summons: " .. value)
        end)

        apply:SetScript("OnClick", function()
            if AutoPetSummoner_Refresh then AutoPetSummoner_Refresh() end
            if SlashCmdList and SlashCmdList.AUTOPET then SlashCmdList.AUTOPET("now") end
        end)

        local category = Settings.RegisterCanvasLayoutCategory(canvas, "Auto Pet Summoner")
        AutoPetSummoner_CategoryID = category and category.ID or nil
        Settings.RegisterAddOnCategory(category)
    end
end

CreateConfigUI()
