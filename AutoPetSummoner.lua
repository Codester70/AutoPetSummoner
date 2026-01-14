-- AutoPetSummoner.lua v1.0.7
local ADDON = ...
AutoPetDB = AutoPetDB or {}

local f = CreateFrame("Frame", "AutoPetSummonerFrame")
local ticker, retryHandle, lastAttempt = nil, nil, 0
local retryReason = nil

local DEFAULTS = {
    enabled = true,
    intervalMinutes = 10,
    favoritesOnly = false,
    disableInInstances = true,
    summonOnLogin = true,
    resummonIfPetOut = false,
    debug = false,
    mountdebug = false,
    _lastSummonAt = 0,
}

local function dprint(msg, force)
    if (AutoPetDB.debug or force) and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff6cf0ff[AutoPet]|r " .. tostring(msg))
    end
end

local function mprint(msg)
    if AutoPetDB.mountdebug and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffa0e7ff[AutoPet:Mount]|r " .. tostring(msg))
    end
end

local function ApplyDefaults()
    for k, v in pairs(DEFAULTS) do
        if AutoPetDB[k] == nil then AutoPetDB[k] = v end
    end
end

local function GetPetNiceName(guid)
    if not guid or not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then
        return nil
    end
    local speciesID, customName, level, xp, maxXp, displayID, favorite, name = C_PetJournal.GetPetInfoByPetID(guid)
    return customName or name or ("<unknown:" .. tostring(guid) .. ">")
end

local function CaptureSummonedPet(source)
    local guid = C_PetJournal and C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID() or nil
    if guid and guid ~= AutoPetDB.lastSummonedGUID then
        AutoPetDB.lastSummonedGUID = guid
        AutoPetDB.lastSummonTime = time()
        dprint(("Tracked last pet (%s): %s [%s]"):format(tostring(source), GetPetNiceName(guid) or "?", tostring(guid)),
            false)
    end
end

local function IsMountedStrict()
    local mounted = IsMounted and IsMounted()
    local inVehicle = UnitInVehicle and UnitInVehicle("player")
    local flying = IsFlying and IsFlying()
    return (mounted or inVehicle or flying) and true or false
end

local function InRestrictedState()
    if InCombatLockdown and InCombatLockdown() then return true, "combat" end
    if IsMountedStrict() then return true, "mounted" end
    if AutoPetDB.disableInInstances and IsInInstance and IsInInstance() then return true, "instance" end
    return false
end

local function IntervalSeconds()
    return math.max(1, (AutoPetDB.intervalMinutes or DEFAULTS.intervalMinutes) * 60)
end

local function HasPetOut()
    return C_PetJournal and C_PetJournal.GetSummonedPetGUID and (C_PetJournal.GetSummonedPetGUID() ~= nil)
end

local function CancelRetry()
    if retryHandle and retryHandle.Cancel then retryHandle:Cancel() end
    retryHandle = nil
end

local function ScheduleSingleRetry(delay, why)
    CancelRetry()

    -- Only retry for states that will actually change
    if why ~= "combat" and why ~= "mounted" then
        dprint("Retry suppressed (non-transient state: " .. tostring(why) .. ").")
        return
    end

    -- Never retry if a pet is already out and rotation is off
    if HasPetOut() and not AutoPetDB.resummonIfPetOut then
        dprint("Retry suppressed (pet already out).")
        return
    end

    -- Prevent duplicate retries for the same reason
    if retryReason == why then
        dprint("Retry already scheduled for " .. why .. "; skipping.")
        return
    end
    retryReason = why

    retryHandle = C_Timer.NewTimer(delay or 2, function()
        retryHandle = nil
        retryReason = nil

        if not AutoPetDB.enabled then return end

        -- Re-check before firing
        if HasPetOut() and not AutoPetDB.resummonIfPetOut then
            dprint("Retry canceled at fire time (pet already out).")
            return
        end

        dprint("Retrying summon...", false)
        C_Timer.After(0.1, function() TrySummon("retry") end)
    end)
end


-- v1.0.4: this version never dismisses current pet; on dismount we only summon if none is out
function TrySummon(reason)
    dprint("TrySummon called (reason=" .. tostring(reason) .. ")", false)
    ApplyDefaults()
    local now = GetTime()
    local secs = IntervalSeconds()

    if (now - lastAttempt) < 1 then return end
    lastAttempt = now
    if not AutoPetDB.enabled then return end

    -- Forced reasons: login, slash, retry, dismount_needpet
    local isForced = (reason == "login" or reason == "login_force" or reason == "slash" or reason == "retry" or reason == "dismount_needpet")
    if not isForced then
        local nextAllowed = (AutoPetDB._lastSummonAt or 0) + secs
        if now < nextAllowed then
            dprint(("Too soon (%.0fs left)."):format(nextAllowed - now))
            return
        end
    end

    local currentGUID = C_PetJournal.GetSummonedPetGUID()
    if not AutoPetDB.resummonIfPetOut and currentGUID and reason ~= "slash" then
        dprint("Pet already out; skipping.")
        AutoPetDB._lastSummonAt = now
        return
    end

    local restricted, why = InRestrictedState()
    if restricted then
        dprint("Restricted (" .. why .. "); postponing.")

        -- Never schedule retries from raw login / world-load events
        if reason == "login" or reason == "PLAYER_ENTERING_WORLD" then
            dprint("No retry on login/world load.")
            return
        end

        -- login_force is allowed to schedule a single retry (combat/mounted only),
        -- because it's a one-shot attempt meant to restore a pet after /reload.
        ScheduleSingleRetry(2, why)
        return
    end

    -- v1.0.5: if this summon is triggered normally, not a dismount restore, we pick random
    -- (We store the GUID when a new pet is actually summoned)
    local numOwned = C_PetJournal.GetNumPets()
    if not numOwned or numOwned <= 0 then
        dprint("No pets available to summon.")
        return
    end

    local candidates = {}
    for i = 1, numOwned do
        local petID, speciesID, owned, customName, level, favorite = C_PetJournal.GetPetInfoByIndex(i)
        if owned and petID then
            if (not AutoPetDB.favoritesOnly) or favorite then
                if petID ~= currentGUID then
                    table.insert(candidates, petID)
                end
            end
        end
    end

    if #candidates == 0 then
        dprint("Only one summonable pet found or no valid alternate; skipping.")
        return
    end

    local newGUID = candidates[math.random(#candidates)]
    C_PetJournal.SummonPetByGUID(newGUID)
    AutoPetDB._lastSummonAt = now
    AutoPetDB.lastSummonedGUID = newGUID
    AutoPetDB.lastSummonTime = time()
    dprint("Summoning a new random pet.", true)
end

local function CancelTicker()
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
end

local function StartTicker()
    CancelTicker()
    if not AutoPetDB.enabled then return end
    local secs = IntervalSeconds()
    ticker = C_Timer.NewTicker(secs, function() TrySummon("ticker") end)
    dprint("Ticker started: every " .. secs .. "s")
end

local function TryRestorePet(source)
    if not AutoPetDB.enabled then return end
    if HasPetOut() then return end
    if InCombatLockdown and InCombatLockdown() then
        AutoPetDB._pendingPostCombatSummon = true
        dprint("Restore deferred (combat).")
        return
    end
    if IsMountedStrict() then return end
    if AutoPetDB.disableInInstances and IsInInstance and IsInInstance() then return end

    local last = AutoPetDB.lastSummonedGUID
    if last then
        dprint(("Restoring pet after %s: %s [%s]"):format(
            tostring(source),
            GetPetNiceName(last) or "?",
            tostring(last)
        ), false)

        C_PetJournal.SummonPetByGUID(last)
        C_Timer.After(0.2, function() CaptureSummonedPet("restore:" .. tostring(source)) end)
    end
end

function AutoPetSummoner_Refresh()
    ApplyDefaults()
    StartTicker()
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ApplyDefaults()

        C_Timer.After(3.0, function()
            if AutoPetDB.enabled and not HasPetOut() then
                TrySummon("login_force")
            end
        end)

        StartTicker()
    elseif event == "COMPANION_UPDATE" then
        -- Don't assume what the arg string is; log it and still capture by GUID
        local companionType = ...
        dprint("COMPANION_UPDATE arg=" .. tostring(companionType), false)
        C_Timer.After(0.1, function() CaptureSummonedPet("COMPANION_UPDATE:" .. tostring(companionType)) end)
    elseif event == "PET_JOURNAL_LIST_UPDATE" then
        -- Sometimes summons cause journal state refreshes; harmless + helps coverage
        C_Timer.After(0.1, function() CaptureSummonedPet("PET_JOURNAL_LIST_UPDATE") end)
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local mounted = IsMountedStrict()
        mprint(mounted and "Mounted: suspending attempts." or "Dismounted: attempts allowed.")
        -- On dismount: only summon if no pet is currently out (ignore interval so you're not pet-less)
        if not mounted and not HasPetOut() then
            C_Timer.After(0.5, function()
                -- Re-check at execution time (important!)
                if InCombatLockdown and InCombatLockdown() then
                    dprint("Dismount summon deferred (entered combat).")
                    AutoPetDB._pendingPostCombatSummon = true
                    return
                end

                if IsMountedStrict() then
                    dprint("Dismount summon canceled (still mounted/flying).")
                    return
                end

                if HasPetOut() then
                    dprint("Dismount summon canceled (pet already out).")
                    return
                end

                local last = AutoPetDB.lastSummonedGUID
                if last then
                    dprint(("Dismount: re-summoning last pet: %s [%s]")
                        :format(GetPetNiceName(last) or "?", tostring(last)), false)
                    C_PetJournal.SummonPetByGUID(last)
                    C_Timer.After(0.2, function() CaptureSummonedPet("dismount_resummon") end)
                else
                    TrySummon("dismount_needpet")
                end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AutoPetDB._pendingPostCombatSummon then
            AutoPetDB._pendingPostCombatSummon = false
            C_Timer.After(0.2, function() TryRestorePet("POST_COMBAT") end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AutoPetDB._pendingPostCombatSummon then
            AutoPetDB._pendingPostCombatSummon = false
            if AutoPetDB.enabled and not HasPetOut() and not IsMountedStrict() then
                dprint("Post-combat: restoring pet.")
                TrySummon("retry") -- or "login_force" style; either is fine
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- After teleports/loading screens, vanity pets are often dismissed.
        -- Wait a bit for the world + pet journal to stabilize, then restore.
        C_Timer.After(2.0, function()
            TryRestorePet("ENTERING_WORLD")
        end)
    elseif event == "COMPANION_UPDATE" then
        local companionType = ...
        if companionType == "CRITTER" then
            local guid = C_PetJournal.GetSummonedPetGUID()
            if guid then
                AutoPetDB.lastSummonedGUID = guid
                AutoPetDB.lastSummonTime = time()
                dprint("Captured new last pet from manual summon.")
            end
        end
    end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("COMPANION_UPDATE")
f:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")

-- Slash commands
SLASH_AUTOPET1 = "/autopet"
SlashCmdList.AUTOPET = function(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "" or cmd == "help" then
        print("|cff6cf0ffAuto Pet Summoner|r commands:")
        print("/autopet on|off")
        print("/autopet minutes <N>")
        print("/autopet favorites on|off")
        print("/autopet instances on|off")
        print("/autopet resummon on|off")
        print("/autopet debug on|off")
        print("/autopet mountdebug on|off")
        print("/autopet now")
        print("/autopet ui")
    elseif cmd == "on" then
        AutoPetDB.enabled = true; AutoPetSummoner_Refresh()
    elseif cmd == "off" then
        AutoPetDB.enabled = false; AutoPetSummoner_Refresh()
    elseif cmd == "minutes" then
        local n = tonumber(rest)
        if n and n > 0 then
            AutoPetDB.intervalMinutes = math.floor(n); AutoPetSummoner_Refresh()
        end
    elseif cmd == "favorites" or cmd == "fav" then
        AutoPetDB.favoritesOnly = rest:lower() == "on"
    elseif cmd == "instances" then
        AutoPetDB.disableInInstances = not (rest:lower() == "on")
    elseif cmd == "resummon" then
        AutoPetDB.resummonIfPetOut = rest:lower() == "on"
    elseif cmd == "debug" then
        AutoPetDB.debug = rest:lower() == "on"
        print("debug set to " .. rest)
    elseif cmd == "mountdebug" then
        AutoPetDB.mountdebug = rest:lower() == "on"
    elseif cmd == "now" then
        TrySummon("slash")
    elseif cmd == "ui" then
        if Settings and Settings.OpenToCategory and AutoPetSummoner_CategoryID then
            Settings.OpenToCategory(AutoPetSummoner_CategoryID)
        else
            InterfaceOptionsFrame_OpenToCategory("Auto Pet Summoner")
        end
    else
        print("Unknown command. Type /autopet help")
    end
end
