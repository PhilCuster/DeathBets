-- Referencing: https://www.wowace.com/projects/ace3/pages/getting-started and https://wow.gamepedia.com/WelcomeHome_-_Your_first_Ace3_Addon
DeathBets = LibStub("AceAddon-3.0"):NewAddon("DeathBets", "AceConsole-3.0", "AceEvent-3.0")

function DeathBets:OnInitialize()
    -- Called when the addon is loaded
end

function DeathBets:OnEnable()
    -- Called when the addon is enabled
    self:Print("Use /deathbets to start!")
    self.groupType = nil
    self.guesses = {}
    self.processing = false
    self.guidNames = {}
    self.deathLogs = {}
end

function DeathBets:OnDisable()
    -- Called when the addon is disabled
end

function DeathBets:ResetValues()
    self.groupType = nil
    self.guesses = {}
    self.processing = false
    self.guidNames = {}
    self.deathLogs = {}
end

-- [[ -----------------------------------------------------------
-- Register the main chat command
-------------------------------------------------------------- ]]
DeathBets:RegisterChatCommand("deathbets", "SlashProcessor")

function DeathBets:SlashProcessor(input)
    if not input or input == "" then
        self:StartGuessing()
    else
        self:Print("Command not recognized...")
    end
end

-- [[ -----------------------------------------------------------
-- Begin guessing process
-------------------------------------------------------------- ]]
function DeathBets:StartGuessing()
    if self.processing then
        self:Print("Guessing already in progress!")
        return
    end
    DeathBets:ResetValues()
    self.processing = true
    -- Make sure the situation is right.
    local instanceStatus = DeathBets:CheckInstanceStatus()
    if not instanceStatus then
        self:Print("Can only use in a dungeon or raid!")
        return
    end
    local isOutOfCombat = self:CheckOutOfCombat()
    if not isOutOfCombat then
        self:Print("Full party/raid must be out of combat!")
        return
    end

    -- Listen for leaving instance. TODO: The below event was removed.
    -- DeathBets:RegisterEvent("WORLD_MAP_UPDATE", "CheckIfLeftInstance")

    -- Prompt for guesses.
    SendChatMessage("Taking guesses for deaths during the next boss!  Please reply with a number to place your guess!  Guesses close on pull.", DeathBets:GetTargetChat())
    DeathBets:RegisterEvent("CHAT_MSG_" .. DeathBets:GetTargetChat(), "RecordGuess")

    -- Detect when pull happens.
    DeathBets:RegisterEvent("ENCOUNTER_START", "EncounterStart")
end

-- TODO: Probably need to redo, Blizzard changed the map API...
function DeathBets:CheckIfLeftInstance(event, ...)
    SetMapToCurrentZone()
    local posX, posY = GetPlayerMapPosition("player")
    if posX == 0 and posY == 0 then
        self:Print("You left the instance, ending guessing game...")
        DeathBets:ResetValues()
    end
end

-- [[ -----------------------------------------------------------
-- Handle messages and if they are a guess, record it
-------------------------------------------------------------- ]]
function DeathBets:RecordGuess(event, ...)
    local msg, playerName = ...
    if msg:match("%d+") then
        inputNumber = tonumber(msg)
        if inputNumber >= 0 and inputNumber <= 200 then
            if self.guesses[playerName] == nil then
                self.guesses[playerName] = inputNumber
                self:Print("Recorded guess " .. inputNumber .. " for " .. playerName)
            else
                self:Print(playerName .. " already guessed!")
            end
        end
    end
end

function DeathBets:EncounterStart(event, ...)
    local encounterID, encounterName, difficultyID, groupSize = ...

    local count = 0
    for _ in pairs(self.guesses) do count = count + 1 end
    SendChatMessage("Fight started against " .. encounterName .. ". " .. count .. " players guessed, good luck!" , DeathBets:GetTargetChat())
    DeathBets:UnregisterEvent("CHAT_MSG_" .. DeathBets:GetTargetChat())
    -- TODO: Listen for deaths.
    DeathBets:CatalogGroup()
    DeathBets:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLogHandler")
    DeathBets:RegisterEvent("ENCOUNTER_END", "HandleEncounterEnd")
end

-- [[ -----------------------------------------------------------
-- Save group members so we know who to watch for.
-------------------------------------------------------------- ]]
function DeathBets:CatalogGroup()
    local groupType,groupSize,inGroup="party"
	if IsInRaid() then
		groupType = "raid"
		groupSize = GetNumGroupMembers()
		inGroup = true
	elseif IsInGroup() then
		groupSize = GetNumSubgroupMembers()
		inGroup = true
	else
		groupSize = 0
	end

	local i = 0
	local unit = "player"
	
	while i <= groupSize do
	
		-- put the player into the combat log tracker
		if UnitExists(unit) then
			
			local id = UnitGUID(unit)
			local name = UnitName(unit)
			
			if not self.deathLogs[id] then
				self.guidNames[id] = name
				self.deathLogs[id] = 0
			end
		end
	
		i = i + 1
		unit = groupType..i
	
	end
end

-- [[ -----------------------------------------------------------
--  Handle combat log events.
-------------------------------------------------------------- ]]
function DeathBets:CombatLogHandler(event, ...)
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = ...
    -- Stop if this is a combat log event we don't care about
    if not dstGUID then return end	  
    if not self.deathLogs[dstGUID] then return end
    
    if eventType == "UNIT_DIED" and not UnitIsFeignDeath(self:GetNameByGUID(dstGUID)) then -- we need special case for Spirit of Redemption as well buffid: 20711
        self:HandleDeathEvent(dstGUID)
        --[[
    elseif eventType == "SPELL_AURA_APPLIED" or
            eventType == "SPELL_AURA_REMOVED" or
            eventType == "SPELL_AURA_APPLIED_DOSE" or
            eventType == "SPELL_AURA_REMOVED_DOSE"
    then
        self:HandleBuffEvent(event, timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcFlags2, dstGUID, dstName, dstFlags, dstFlags2, ...)
    else
        self:HandleHealthEvent(event, timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcFlags2, dstGUID, dstName, dstFlags, dstFlags2, ...)
        --]]
    end
end

-- [[ -----------------------------------------------------------
--  Handle deaths.
-------------------------------------------------------------- ]]
function DeathBets:HandleDeathEvent(dstGUID)

	deathsSoFar = self.deathLogs[dstGUID]

	-- Make the entry
    self.deathLogs[dstGUID] = deathsSoFar + 1
    
    self:Print(self:GetNameByGUID(dstGUID) .. " died! " .. self:TotalDeaths() .. " deaths so far...")
end

function DeathBets:TotalDeaths()
    local total = 0
    for k, v in pairs(self.deathLogs) do
        total = total + v
    end
    return total
end

-- [[ -----------------------------------------------------------
--  Handle end of encounter.
-------------------------------------------------------------- ]]
function DeathBets:HandleEncounterEnd(event, ...)
    local encounterID, encounterName, difficultyID, groupSize, success = ...

    -- Stop listening for deaths.
    DeathBets:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    local totalDeaths = self:TotalDeaths()
    local winOrLose = ""
    if success then
        winOrLose = "Congrats! "
    else
        winOrLose = "Better luck next time. "
    end

    SendChatMessage("Fight ended against " .. encounterName .. ". " .. winOrLose .. totalDeaths .. " deaths occured! " .. DeathBets:DetermineWinner(totalDeaths)  , DeathBets:GetTargetChat())

    self.processing = false
    DeathBets:ResetValues()
end

-- [[ -----------------------------------------------------------
--  Return a string reporting who the winner is.
-------------------------------------------------------------- ]]
function DeathBets:DetermineWinner(answer)
    local winners = {}
    local closest = {}
    local result = ""
    local closest = 100000
    -- If anyone guessed exactly right, they win.
    for player, guess in pairs(self.guesses) do
        if guess == answer then
            winners[#winners+1] = player
        else
            local accuracy = math.abs(guess - answer)
            if accuracy < closest then
                closest = {}
                table.insert(closest, player)
            elseif accuracy == closest then
                table.insert(closest, player)
            end
        end
    end
    if #winners > 0 then
        result = "Winners: "
        for _, winner in ipairs(winners) do:
            result = result .. winner .. ", "
        end
        result = result:sub(1, -3)
        return result
    else
        result = "Closest guess: "
        for _, player in ipairs(closest) do:
            result = result .. player .. ", "
        end
        result = result:sub(1, -3)
        return result
    end
end

-- [[ -----------------------------------------------------------
-- Return true if player and every raid/party member 
-- is not in combat
-------------------------------------------------------------- ]]
function DeathBets:CheckOutOfCombat()
    if UnitAffectingCombat("player") then
        return false
    end

    if IsInRaid() then
        for i=1,40 do
            if UnitAffectingCombat("raid" .. i) then
                return false
            end
        end
    elseif IsInGroup() then
        for i=1,5 do
            if UnitAffectingCombat("party" .. i) then
                return false
            end
        end
    end
    return true
end

-- [[ -----------------------------------------------------------
-- Return true if player is in a dungeon or raid instance
-------------------------------------------------------------- ]]
function DeathBets:CheckInstanceStatus()
    inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

-- [[ -----------------------------------------------------------
-- Return the appropriate chat for comms.
-------------------------------------------------------------- ]]
function DeathBets:GetTargetChat()
    -- This is for testing only!
    if not IsInGroup() then
        return "SAY"
    end

    return (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT") or (UnitInRaid("player") and "RAID") or "PARTY"
end

--[[ ---------------------------------------------------------------------------
	 Get name from GUID
----------------------------------------------------------------------------- ]]
function DeathBets:GetNameByGUID(guid)
	return self.guidNames[guid]
end
