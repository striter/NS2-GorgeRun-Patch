-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\NS2Gamerules.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http:\\www.unknownworlds.com =====================

Script.Load("lua/Gamerules.lua")
Script.Load("lua/dkjson.lua")
Script.Load("lua/bots/BotTeamController.lua")
Script.Load("lua/PlayerRanking.lua")

if Client then
    Script.Load("lua/NS2ConsoleCommands_Client.lua")
else
    Script.Load("lua/NS2ConsoleCommands_Server.lua")
end

class 'NS2Gamerules' (Gamerules)

NS2Gamerules.kMapName = "ns2_gamerules"

kGameEndAutoConcedeCheckInterval = 0.75
kDrawGameWindow = 0.75

local kRookieModeDelay = 20
local kPregameLength = 3
local kTimeToReadyRoom = 8
local kPauseToSocializeBeforeMapcycle = 30
local kGameStartMessageInterval = 10

local kMaxWorldSoundDistance = 30

-- How often to send the "No commander" message to players in seconds.
local kSendNoCommanderMessageRate = 50

-- Find team start with team 0 or for specified team. Remove it from the list so other teams don't start there. Return nil if there are none.
function NS2Gamerules:ChooseTechPoint(techPoints, teamNumber)

    local validTechPoints = { }
    local totalTechPointWeight = 0
    
    -- Build list of valid starts (marked as "neutral" or for this team in map)
    for _, currentTechPoint in ipairs(techPoints) do
    
        -- Always include tech points with team 0 and never include team 3 into random selection process
        local teamNum = currentTechPoint:GetTeamNumberAllowed()
        if (teamNum == 0 or teamNum == teamNumber) and teamNum ~= 3 then
        
            table.insert(validTechPoints, currentTechPoint)
            totalTechPointWeight = totalTechPointWeight + currentTechPoint:GetChooseWeight()
            
        end
        
    end
    
    local chosenTechPointWeight = self.techPointRandomizer:random(0, totalTechPointWeight)
    local chosenTechPoint
    local currentWeight = 0
    for _, currentTechPoint in ipairs(validTechPoints) do
    
        currentWeight = currentWeight + currentTechPoint:GetChooseWeight()
        if chosenTechPointWeight - currentWeight <= 0 then
        
            chosenTechPoint = currentTechPoint
            break
            
        end
        
    end
    
    -- Remove it from the list so it isn't chosen by other team
    if chosenTechPoint ~= nil then
        table.removevalue(techPoints, chosenTechPoint)
    else
        assert(false, "ChooseTechPoint couldn't find a tech point for team " .. teamNumber)
    end
    
    return chosenTechPoint
    
end

------------
-- Server --
------------
if Server then

    Script.Load("lua/PlayingTeam.lua")
    Script.Load("lua/ReadyRoomTeam.lua")
    Script.Load("lua/SpectatingTeam.lua")
    Script.Load("lua/GameViz.lua")
    Script.Load("lua/ObstacleMixin.lua")

    NS2Gamerules.kMarineStartSound = PrecacheAsset("sound/NS2.fev/marine/voiceovers/game_start")
    NS2Gamerules.kAlienStartSound = PrecacheAsset("sound/NS2.fev/alien/voiceovers/game_start")
    NS2Gamerules.kCountdownSound = PrecacheAsset("sound/NS2.fev/common/countdown")

    function NS2Gamerules:BuildTeam(teamType)

        if teamType == kAlienTeamType then
            return AlienTeam()
        end
        
        return MarineTeam()
        
    end
    
    function NS2Gamerules:ResetPlayerScores()
    
        for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do      --FIXME This is setting enter times to invalid ranges (because round data is reset..thus, not releative to game-start)
            if player.ResetScores and player.client then
                player:ResetScores()
                self.playerRanking:SetEntranceTime( player, player:GetTeamNumber() )
            end
        end

    end

    function NS2Gamerules:SetGameState(state)
    
        if state ~= self.gameState then
        
            self.gameState = state
            self.gameInfo:SetState(state)
            self.timeGameStateChanged = Shared.GetTime()
            self.timeSinceGameStateChanged = 0
            
            if self.gameState == kGameState.Started then
                
                PostGameViz("Game started")
                self:ResetPlayerScores()
                self.gameStartTime = Shared.GetTime()
                
                self.gameInfo:SetStartTime(self.gameStartTime)
                
                SendTeamMessage(self.team1, kTeamMessageTypes.GameStarted)
                SendTeamMessage(self.team2, kTeamMessageTypes.GameStarted)
                
            end
            
            -- On end game, check for map switch conditions
            if state == kGameState.Team1Won or state == kGameState.Team2Won then
            
                if MapCycle_TestCycleMap() then
                    self.timeToCycleMap = Shared.GetTime() + kPauseToSocializeBeforeMapcycle
                else
                    self.timeToCycleMap = nil
                end
                
            end
            
        end
        
    end

    function NS2Gamerules:GetGameTimeChanged()
        return self.timeSinceGameStateChanged
    end

    function NS2Gamerules:GetGameState()
        return self.gameState
    end

    function NS2Gamerules:OnCreate()

        -- Calls SetGamerules()
        Gamerules.OnCreate(self)
        
        self.playerRanking = PlayerRanking()
        
        self.techPointRandomizer = Randomizer()
        self.techPointRandomizer:randomseed(Shared.GetSystemTime())

        self.botTeamController = BotTeamController()
        
        -- Create team objects
        self.team1 = self:BuildTeam(kTeam1Type)
        self.team1:Initialize(kTeam1Name, kTeam1Index)
        
        self.team2 = self:BuildTeam(kTeam2Type)
        self.team2:Initialize(kTeam2Name, kTeam2Index)
        
        self.worldTeam = ReadyRoomTeam()
        self.worldTeam:Initialize("World", kTeamReadyRoom)
        
        self.spectatorTeam = SpectatingTeam()
        self.spectatorTeam:Initialize("Spectator", kSpectatorIndex)
        
        self.gameInfo = Server.CreateEntity(GameInfo.kMapName)
        
        self:SetGameState(kGameState.NotStarted)
        
        self.allTech = false
        self.orderSelf = false
        self.autobuild = false
        self.teamsReady = false
        self.tournamentMode = false

        if self.gameInfo:GetIsDedicated() then
            --Set rookie mode based on the config values
            self:SetRookieMode(Server.GetConfigSetting("rookie_only"))
            if self.gameInfo:GetRookieMode() then
                self:SetMaxBots(Server.GetConfigSetting("rookie_only_bots"), true)
            else
                self:SetMaxBots(Server.GetConfigSetting("filler_bots"), false)
            end
        end

        self:SetIsVisible(false)
        self:SetPropagate(Entity.Propagate_Never)
        
        -- Track how much pres clients have when they switch a team or disconnect
        self.clientpres = {}
        
        self.justCreated = true

        self:SetUpdateRate(kRealTimeUpdateRate)
        
    end

    function NS2Gamerules:OnDestroy()

        self.team1:Uninitialize()
        self.team1 = nil
        self.team2:Uninitialize()
        self.team2 = nil
        self.worldTeam:Uninitialize()
        self.worldTeam = nil
        self.spectatorTeam:Uninitialize()
        self.spectatorTeam = nil

        Gamerules.OnDestroy(self)

    end
    
    function NS2Gamerules:GetFriendlyFire()
        return false
    end

    -- All damage is routed through here.
    function NS2Gamerules:CanEntityDoDamageTo(attacker, target)
        return CanEntityDoDamageTo(attacker, target, Shared.GetCheatsEnabled(), Shared.GetDevMode(), self:GetFriendlyFire())
    end

    function NS2Gamerules:OnCommanderLogout(commandStructure, oldCommander)
        if self.gameInfo:GetRookieMode() and self:GetGameState() > kGameState.NotStarted and
                self:GetGameState() < kGameState.Team1Won then
            self.botTeamController:UpdateBotsForTeam(commandStructure:GetTeamNumber())
        end
    end

    function NS2Gamerules:OnCommanderLogin(commandStructure, newCommander)
        local teamInfo = GetTeamInfoEntity(commandStructure:GetTeamNumber())

        if teamInfo:GetLastCommIsBot() then
            for i = 1, #gServerBots do
                local bot = gServerBots[i]
                if bot and bot:GetPlayer():GetTeamNumber() == commandStructure:GetTeamNumber() then
                    bot:Disconnect()
                    break
                end
            end
        end

        if not self.gameInfo:GetRookieMode() and not Shared.GetCheatsEnabled() and
           Server.IsDedicated() and not self.botTraining and newCommander:GetIsRookie() then
            
            Server.SendNetworkMessage(nil, "CommanderLoginError", {}, true)
        end

        return not commandStructure:GetTeam():GetHasCommander()
    end

    function NS2Gamerules:OnClientConnect(client)
        local player = Gamerules.OnClientConnect(self, client) -- creates player entity

        -- Move spectators into the spectator team
        if client:GetIsSpectator() then
            self:JoinTeam(player, kSpectatorIndex, true)
        end

        return player
    end

    function NS2Gamerules:OnClientDisconnect(client)

        local player = client:GetControllingPlayer()
        
        if player then
        
            -- When a player disconnects remove them from their team
            local teamNumber = player:GetTeamNumber()

            --Log player for the round report
            if teamNumber == kTeam1Index or teamNumber == kTeam2Index then
                self.playerRanking:SetExitTime( player, teamNumber )
            end
            self.playerRanking:LogPlayer(player)
            
            local team = self:GetTeam(teamNumber)
            if team then
                team:RemovePlayer(player)
            end
            
            player:RemoveSpectators(nil)
            
            local clientUserId = client:GetUserId()
            if not self.clientpres[clientUserId] then self.clientpres[clientUserId] = {} end
            self.clientpres[clientUserId][teamNumber] = player:GetResources()

            self.botTeamController:UpdateBots()
        end
        
        Gamerules.OnClientDisconnect(self, client)  --??? TD-TODO review for potential "auto" pause, and revising rules, etc.
        
    end
    
    function NS2Gamerules:OnEntityCreate(entity)

        self:OnEntityChange(nil, entity:GetId())

        if entity.GetTeamNumber then
        
            local team = self:GetTeam(entity:GetTeamNumber())
            
            if team then
            
                if entity:isa("Player") then
            
                    team:AddPlayer(entity)

                end
                
            end
            
        end
        
    end

    function NS2Gamerules:OnEntityDestroy(entity)
        
        self:OnEntityChange(entity:GetId(), nil)

        if entity.GetTeamNumber then
        
            local team = self:GetTeam(entity:GetTeamNumber())
            if team then
            
                if entity:isa("Player") then
                    team:RemovePlayer(entity)
                end
                
            end
            
        end
       
    end

    -- Update player and entity lists
    function NS2Gamerules:OnEntityChange(oldId, newId)

        PROFILE("NS2Gamerules:OnEntityChange")
        
        if self.worldTeam then
            self.worldTeam:OnEntityChange(oldId, newId)
        end
        
        if self.team1 then
            self.team1:OnEntityChange(oldId, newId)
        end
        
        if self.team2 then
            self.team2:OnEntityChange(oldId, newId)
        end
        
        if self.spectatorTeam then
            self.spectatorTeam:OnEntityChange(oldId, newId)
        end
        
        -- Keep server map entities up to date
        local index = table.find(Server.mapLoadLiveEntityValues, oldId)
        if index then
        
            table.removevalue(Server.mapLoadLiveEntityValues, oldId)
            if newId then
                table.insert(Server.mapLoadLiveEntityValues, newId)
            end
            
        end
        
        local notifyEntities = Shared.GetEntitiesWithTag("EntityChange")
        
        -- Tell notifyEntities this entity has changed ids or has been deleted (changed to nil).
        for _, ent in ientitylist(notifyEntities) do
        
            if ent:GetId() ~= oldId and ent.OnEntityChange then
                ent:OnEntityChange(oldId, newId)
            end
            
        end
        
    end

    -- Called whenever an entity is killed. Killer could be the same as targetEntity. Called before entity is destroyed.
    function NS2Gamerules:OnEntityKilled(targetEntity, attacker, doer, point, direction)
        
        -- skip all this if it's part of the concede sequence killing stuff.
        if GetConcedeSequenceActive() then
            return
        end
        PostGameViz(string.format("%s killed %s", SafeClassName(doer), SafeClassName(targetEntity)), targetEntity)
        self.team1:OnEntityKilled(targetEntity, attacker, doer, point, direction)
        self.team2:OnEntityKilled(targetEntity, attacker, doer, point, direction)
        self.worldTeam:OnEntityKilled(targetEntity, attacker, doer, point, direction)
        self.spectatorTeam:OnEntityKilled(targetEntity, attacker, doer, point, direction)

    end

    -- logs out any players currently as the commander
    function NS2Gamerules:LogoutCommanders()

        for _, entity in ientitylist(Shared.GetEntitiesWithClassname("CommandStructure")) do
            entity:Logout()
        end
        
    end
     
    function NS2Gamerules:DestroyUnusedPowerNodes()
    
        local powerConsumers = GetEntitiesWithMixin("PowerConsumer")
        local roomsNeedingPower = {}
        for i=1, #powerConsumers do
            if powerConsumers[i] then
                roomsNeedingPower[powerConsumers[i]:GetLocationId()] = true
            end
        end
        local powerNodes = EntityListToTable(Shared.GetEntitiesWithClassname("PowerPoint"))
        for i=1, #powerNodes do
            if powerNodes[i] then
                if not powerNodes[i]:GetIsSocketed() then
                    powerNodes[i]:SocketPowerNode()
                end
                if not powerNodes[i]:GetIsBuilt() then
                    powerNodes[i]:SetConstructionComplete()
                end
                if not roomsNeedingPower[powerNodes[i]:GetLocationId()] then
                    -- power is permanently destroyed in all other rooms
                    powerNodes[i]:SetInternalPowerState(PowerPoint.kPowerState.destroyed)
                    powerNodes[i]:SetLightMode(kLightMode.NoPower)
                    
                    -- Fake kill it
                    powerNodes[i].health = 0
                    powerNodes[i].armor = 0
                    powerNodes[i].alive = false
                    powerNodes[i]:OnKill()
                end
            end
        end
    end
    
    --[[
     * Starts a new game by resetting the map and all of the players. Keep everyone on current teams (readyroom, playing teams, etc.) but 
     * respawn playing players.
     ]]
    function NS2Gamerules:ResetGame()
        
        StatsUI_ResetStats()

        StatsUI_ResetStats()

        self:SetGameState(kGameState.NotStarted)

        TournamentModeOnReset()
    
        -- save commanders for later re-login
        local team1CommanderClient = self.team1:GetCommander() and self.team1:GetCommander():GetClient()
        local team2CommanderClient = self.team2:GetCommander() and self.team2:GetCommander():GetClient()
        
        -- Cleanup any peeps currently in the commander seat by logging them out
        -- have to do this before we start destroying stuff.
        self:LogoutCommanders()
        
        -- Destroy any map entities that are still around
        DestroyLiveMapEntities()
        
        -- Reset all players, delete other not map entities that were created during 
        -- the game (hives, command structures, initial resource towers, etc)
        -- We need to convert the EntityList to a table since we are destroying entities
        -- within the EntityList here.
        for _, entity in ientitylist(Shared.GetEntitiesWithClassname("Entity")) do
        
            -- Don't reset/delete NS2Gamerules or TeamInfo or ThunderdomeRules.
            -- NOTE!!!
            -- MapBlips are destroyed by their owner which has the MapBlipMixin.
            -- There is a problem with how this reset code works currently. A map entity such as a Hive creates
            -- it's MapBlip when it is first created. Before the entity:isa("MapBlip") condition was added, all MapBlips
            -- would be destroyed on map reset including those owned by map entities. The map entity Hive would still reference
            -- it's original MapBlip and this would cause problems as that MapBlip was long destroyed. The right solution
            -- is to destroy ALL entities when a game ends and then recreate the map entities fresh from the map data
            -- at the start of the next game, including the NS2Gamerules. This is how a map transition would have to work anyway.
            -- Do not destroy any entity that has a parent. The entity will be destroyed when the parent is destroyed or
            -- when the owner manually destroyes the entity.
            local shieldTypes = { "GameInfo", "MapBlip", "NS2Gamerules", "PlayerInfoEntity", "ThunderdomeRules" }
            local allowDestruction = true
            for i = 1, #shieldTypes do
                allowDestruction = allowDestruction and not entity:isa(shieldTypes[i])
            end
            
            if allowDestruction and entity:GetParent() == nil then
                
                -- Reset all map entities and all player's that have a valid Client (not ragdolled players for example).
                local resetEntity = entity:isa("TeamInfo") or entity:GetIsMapEntity() or (entity:isa("Player") and entity:GetClient() ~= nil)
                if resetEntity then
                
                    if entity.Reset then
                        entity:Reset()
                    end
                    
                else
                    DestroyEntity(entity)
                end
                
            end       
            
        end
        
        -- Clear out obstacles from the navmesh before we start repopualating the scene
        RemoveAllObstacles()
        
        -- Build list of tech points
        local techPoints = EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))
        if #techPoints < 2 then
            Print("Warning -- Found only %d %s entities.", table.maxn(techPoints), TechPoint.kMapName)
        end
        
        local resourcePoints = Shared.GetEntitiesWithClassname("ResourcePoint")
        if resourcePoints:GetSize() < 2 then
            Print("Warning -- Found only %d %s entities.", resourcePoints:GetSize(), ResourcePoint.kPointMapName)
        end
        
        -- add obstacles for resource points back in
        for _, resourcePoint in ientitylist(resourcePoints) do
            resourcePoint:AddToMesh()        
        end
        
        local team1TechPoint, team2TechPoint
        
        if Server.teamSpawnOverride and #Server.teamSpawnOverride > 0 then
           
            for t = 1, #techPoints do

                local techPointName = string.lower(techPoints[t]:GetLocationName())
                local selectedSpawn = Server.teamSpawnOverride[1]
                if techPointName == selectedSpawn.marineSpawn then
                    team1TechPoint = techPoints[t]
                elseif techPointName == selectedSpawn.alienSpawn then
                    team2TechPoint = techPoints[t]
                end
                
            end
            
            if not team1TechPoint or not team2TechPoint then
                Shared.Message("Invalid spawns, defaulting to normal spawns")
                if Server.spawnSelectionOverrides then
        
                    local selectedSpawn = self.techPointRandomizer:random(1, #Server.spawnSelectionOverrides)
                    selectedSpawn = Server.spawnSelectionOverrides[selectedSpawn]
                    
                    for t = 1, #techPoints do
                    
                        local techPointName = string.lower(techPoints[t]:GetLocationName())
                        if techPointName == selectedSpawn.marineSpawn then
                            team1TechPoint = techPoints[t]
                        elseif techPointName == selectedSpawn.alienSpawn then
                            team2TechPoint = techPoints[t]
                        end
                        
                    end
                        
                else
                    
                    -- Reset teams (keep players on them)
                    team1TechPoint = self:ChooseTechPoint(techPoints, kTeam1Index)
                    team2TechPoint = self:ChooseTechPoint(techPoints, kTeam2Index)

                end
            
            end
            
        elseif Server.spawnSelectionOverrides then
        
            local selectedSpawn = self.techPointRandomizer:random(1, #Server.spawnSelectionOverrides)
            selectedSpawn = Server.spawnSelectionOverrides[selectedSpawn]
            
            for t = 1, #techPoints do
            
                local techPointName = string.lower(techPoints[t]:GetLocationName())
                if techPointName == selectedSpawn.marineSpawn then
                    team1TechPoint = techPoints[t]
                elseif techPointName == selectedSpawn.alienSpawn then
                    team2TechPoint = techPoints[t]
                end
                
            end
            
        else
        
            -- Reset teams (keep players on them)
            team1TechPoint = self:ChooseTechPoint(techPoints, kTeam1Index)
            team2TechPoint = self:ChooseTechPoint(techPoints, kTeam2Index)

        end
        
        self.team1:ResetPreservePlayers(team1TechPoint)
        self.team2:ResetPreservePlayers(team2TechPoint)
        
        assert(self.team1:GetInitialTechPoint() ~= nil)
        assert(self.team2:GetInitialTechPoint() ~= nil)
        
        -- Save data for end game stats later.
        self.startingLocationNameTeam1 = team1TechPoint:GetLocationName()
        self.startingLocationNameTeam2 = team2TechPoint:GetLocationName()
        self.startingLocationsPathDistance = GetPathDistance(team1TechPoint:GetOrigin(), team2TechPoint:GetOrigin())
        self.initialHiveTechId = nil
        
        self.worldTeam:ResetPreservePlayers(nil)
        self.spectatorTeam:ResetPreservePlayers(nil)    
        
        -- Replace players with their starting classes with default loadouts at spawn locations
        self.team1:ReplaceRespawnAllPlayers()
        self.team2:ReplaceRespawnAllPlayers()
        
		self.clientpres = {}

        -- Create team specific entities
        local commandStructure1 = self.team1:ResetTeam()
        local commandStructure2 = self.team2:ResetTeam()
        
        -- login the commanders again
        local function LoginCommander(commandStructure, client)
            local player = client and client:GetControllingPlayer()
            
            if commandStructure and player and commandStructure:GetIsBuilt() then
                
				-- make up for not manually moving to CS and using it
                commandStructure.occupied = not client:GetIsVirtual()
                
                player:SetOrigin(commandStructure:GetDefaultEntryOrigin())
                
                commandStructure:LoginPlayer( player, true )
            else
                if player then
                    Log("%s| Failed to Login commander[%s - %s(%s)] on ResetGame", self:GetClassName(), player:GetClassName(), player:GetId(),
                        client:GetIsVirtual() and "BOT" or "HUMAN"
                    )
                end
            end
        end
        
        LoginCommander(commandStructure1, team1CommanderClient)
        LoginCommander(commandStructure2, team2CommanderClient)
        
        -- Create living map entities fresh
        CreateLiveMapEntities()
        
        self.forceGameStart = false
        self.preventGameEnd = nil

        -- Reset banned players for new game
        if not self.bannedPlayers then
            self.bannedPlayers = unique_set()
        end
        self.bannedPlayers:Clear()
        
        -- Send scoreboard and tech node update, ignoring other scoreboard updates (clearscores resets everything)
        for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
            Server.SendCommand(player, "onresetgame")
            player.sendTechTreeBase = true
        end
        
        self.team1:OnResetComplete()
        self.team2:OnResetComplete()

        StatsUI_InitializeTeamStatsAndTechPoints(self)
    end
    
    function NS2Gamerules:GetTeam1()
        return self.team1
    end
    
    function NS2Gamerules:GetTeam2()
        return self.team2
    end
    
    function NS2Gamerules:GetWorldTeam()
        return self.worldTeam
    end
    
    function NS2Gamerules:GetSpectatorTeam()
        return self.spectatorTeam
    end
    
    function NS2Gamerules:GetTeams()
        return { self.team1, self.team2, self.worldTeam, self.spectatorTeam }
    end
    
    --[[
     * Should be called when the Hive type is chosen.
    ]]
    function NS2Gamerules:SetHiveTechIdChosen(hive, techId)
    
        if self.initialHiveTechId == nil then
            self.initialHiveTechId = techId
        end
        
    end

    -- Batch together string with pings of every player to update scoreboard. This is a separate
    -- command to keep network utilization down.
    function NS2Gamerules:UpdatePings()
    
        local now = Shared.GetTime()
        
        -- Check if the individual player's should be sent their own ping.
        if self.timeToSendIndividualPings == nil or now >= self.timeToSendIndividualPings then
        
            for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
                Server.SendNetworkMessage(player, "Ping", BuildPingMessage(player:GetClientIndex(), player:GetPing()), false)
            end
            
            self.timeToSendIndividualPings =  now + kUpdatePingsIndividual
            
        end
        
        -- Check if all player's pings should be sent to everybody.
        if self.timeToSendAllPings == nil or  now >= self.timeToSendAllPings then
        
            for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
                Server.SendNetworkMessage("Ping", BuildPingMessage(player:GetClientIndex(), player:GetPing()), false)
            end
            
            self.timeToSendAllPings =  now + kUpdatePingsAll
            
        end
        
    end
    
    -- Sends player health to all spectators
    function NS2Gamerules:UpdateHealth()
    
        if self.timeToSendHealth == nil or Shared.GetTime() > self.timeToSendHealth then
        
            local spectators = Shared.GetEntitiesWithClassname("Spectator")
            if spectators:GetSize() > 0 then
            
                -- Send spectator all health
                for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
                
                    for _, spectator in ientitylist(spectators) do
                    
                        if not spectator:GetIsFirstPerson() then
                            Server.SendNetworkMessage(spectator, "Health", BuildHealthMessage(player), false)
                        end
                        
                    end
                    
                end
            
            end
            self.timeToSendHealth = Shared.GetTime() + 0.25
            
        end
        
    end
    
    -- Send Tech Point info to all spectators
    function NS2Gamerules:UpdateTechPoints()
    
        if self.timeToSendTechPoints == nil or Shared.GetTime() > self.timeToSendTechPoints then
        
            local spectators = Shared.GetEntitiesWithClassname("Spectator")
            if spectators:GetSize() > 0 then
                
                local powerNodes = Shared.GetEntitiesWithClassname("PowerPoint")
                local eggs = Shared.GetEntitiesWithClassname("Egg")
                
                for _, techpoint in ientitylist(Shared.GetEntitiesWithClassname("TechPoint")) do
                
                    local message = BuildTechPointsMessage(techpoint, powerNodes, eggs)
                    for _, spectator in ientitylist(spectators) do
                    
                        if not spectator:GetIsFirstPerson() then
                            Server.SendNetworkMessage(spectator, "TechPoints", message, false)
                        end
                        
                    end
                    
                end
            
            end
            
            self.timeToSendTechPoints = Shared.GetTime() + 0.5
            
        end
        
    end
        
    function NS2Gamerules:VotingConcedeVoteAllowed()
        local gameRules = GetGamerules()
        return gameRules:GetGameStarted() and Shared.GetTime() - gameRules:GetGameStartTime() > kMinTimeBeforeConcede
    end
    
    -- Commander ejection functionality
    function NS2Gamerules:CastVoteByPlayer(voteTechId, player)
    
        if voteTechId == kTechId.VoteConcedeRound then
        
            if self:VotingConcedeVoteAllowed() then
            
                local team = player:GetTeam()
                if team.VoteToGiveUp then
                    team:VoteToGiveUp(player)
                end
                
            end
        
        elseif voteTechId == kTechId.VoteDownCommander1 or voteTechId == kTechId.VoteDownCommander2 or voteTechId == kTechId.VoteDownCommander3 then

            -- Get the 1st, 2nd or 3rd commander by entity order (does this on client as well)    
            local playerIndex = (voteTechId - kTechId.VoteDownCommander1 + 1)        
            local commanders = GetEntitiesForTeam("Commander", player:GetTeamNumber())
            
            if playerIndex <= table.icount(commanders) then
            
                local targetCommander = commanders[playerIndex]
                local team = player:GetTeam()
                
                if player and team.VoteToEjectCommander then    --TD-TODO Review and verify this isn't open for abuse (ejecting the second people join, etc)
                    team:VoteToEjectCommander(player, targetCommander)
                end
                
            end
            
        end
        
    end

    function NS2Gamerules:OnMapPostLoad()

        Gamerules.OnMapPostLoad(self)
        
        -- Now allow script actors to hook post load
        local allScriptActors = Shared.GetEntitiesWithClassname("ScriptActor")
        for _, scriptActor in ientitylist(allScriptActors) do
            scriptActor:OnMapPostLoad()
        end
        
    end

    local function MovePlayerToReadyRoom(player)
        if not player:GetIsSpectator() then
            GetGamerules():JoinTeam(player, kTeamReadyRoom)
        end
    end

    function NS2Gamerules:UpdateToReadyRoom(force)

        local state = self:GetGameState()
        if(state == kGameState.Team1Won or state == kGameState.Team2Won or state == kGameState.Draw) and not GetConcedeSequenceActive() then
            if force or self.timeSinceGameStateChanged >= kTimeToReadyRoom then
                -- Force the commanders to logout before we spawn people
                -- in the ready room
                self:LogoutCommanders()

                -- Set all players to ready room team
                Server.ForAllPlayers(MovePlayerToReadyRoom)

                -- Spawn them there and reset teams
                self:ResetGame()

            end
            
        end
        
    end
    
    function NS2Gamerules:UpdateMapCycle()
    
        if Shared.GetThunderdomeEnabled() then
        --We never change maps automatically (cycled) in TD, only via map-votes. This may change in the future
            return
        end

        if self.timeToCycleMap ~= nil and Shared.GetTime() >= self.timeToCycleMap then

            MapCycle_CycleMap()
            self.timeToCycleMap = nil

        end
        
    end
    
    -- Network variable type time has a maximum value it can contain, so reload the map if
    -- the age exceeds the limit and no game is going on.
    NS2Gamerules.kMaxServerAgeBeforeMapChange = 36000
    function NS2Gamerules:ServerAgeCheck()
    
        if Shared.GetThunderdomeEnabled() then
            return
        end

        if self.gameState ~= kGameState.Started and Shared.GetTime() > self.kMaxServerAgeBeforeMapChange then
            MapCycle_ChangeMap(Shared.GetMapName())
        end
        
    end

    function NS2Gamerules:UpdateAutoTeamBalance(dt)
    
        local wasDisabled = false
        
        -- Check if auto-team balance should be enabled or disabled. 
        -- Disable automatically if cheats are on so you can play against more bots
        --local autoTeamBalance = not Shared.GetCheatsEnabled() and Server.GetConfigSetting("auto_team_balance")
        local autoTeamBalance = false -- disable for now
        if autoTeamBalance and autoTeamBalance.enabled then
        
            local enabledOnUnbalanceAmount = autoTeamBalance.enabled_on_unbalance_amount or 2
            -- Prevent the unbalance amount from being 0 or less.
            enabledOnUnbalanceAmount = enabledOnUnbalanceAmount > 0 and enabledOnUnbalanceAmount or 2
            local enabledAfterSeconds = autoTeamBalance.enabled_after_seconds or 10
            
            local team1Players = self.team1:GetNumPlayers()
            local team2Players = self.team2:GetNumPlayers()
            
            local unbalancedAmount = math.abs(team1Players - team2Players)
            if unbalancedAmount >= enabledOnUnbalanceAmount then
            
                if not self.autoTeamBalanceEnabled then
                
                    self.teamsUnbalancedTime = self.teamsUnbalancedTime or 0
                    self.teamsUnbalancedTime = self.teamsUnbalancedTime + dt
                    
                    if self.teamsUnbalancedTime >= enabledAfterSeconds then
                    
                        self.autoTeamBalanceEnabled = true
                        if team1Players > team2Players then
                            self.team1:SetAutoTeamBalanceEnabled(true, unbalancedAmount)
                        else
                            self.team2:SetAutoTeamBalanceEnabled(true, unbalancedAmount)
                        end
                        
                        SendTeamMessage(self.team1, kTeamMessageTypes.TeamsUnbalanced)
                        SendTeamMessage(self.team2, kTeamMessageTypes.TeamsUnbalanced)
                        Print("Auto-team balance enabled")
                        
                    end
                    
                end
                
            -- The autobalance system itself has turned itself off.
            elseif self.autoTeamBalanceEnabled then
                wasDisabled = true
            end
            
        -- The autobalance system was turned off by the admin.
        elseif self.autoTeamBalanceEnabled then
            wasDisabled = true
        end
        
        if wasDisabled then
        
            self.team1:SetAutoTeamBalanceEnabled(false)
            self.team2:SetAutoTeamBalanceEnabled(false)
            self.teamsUnbalancedTime = 0
            self.autoTeamBalanceEnabled = false
            SendTeamMessage(self.team1, kTeamMessageTypes.TeamsBalanced)
            SendTeamMessage(self.team2, kTeamMessageTypes.TeamsBalanced)
            Print("Auto-team balance disabled")

        end
        
    end
    
    function NS2Gamerules:CheckForNoCommander(onTeam, commanderType)

        self.noCommanderStartTime = self.noCommanderStartTime or { }
        
        if not self:GetGameStarted() then
            self.noCommanderStartTime[commanderType] = nil
        else
        
            local commanderExists = Shared.GetEntitiesWithClassname(commanderType):GetSize() ~= 0
            
            if commanderExists then
                self.noCommanderStartTime[commanderType] = nil
            elseif not self.noCommanderStartTime[commanderType] then
                self.noCommanderStartTime[commanderType] = Shared.GetTime()
            elseif Shared.GetTime() - self.noCommanderStartTime[commanderType] >= kSendNoCommanderMessageRate then
            
                self.noCommanderStartTime[commanderType] = nil
                SendTeamMessage(onTeam, kTeamMessageTypes.NoCommander)
                
            end
            
        end
        
    end

    function NS2Gamerules:KillEnemiesNearCommandStructureInPreGame(timePassed)
    
        if self:GetGameState() < kGameState.Countdown then
        
            local commandStations = Shared.GetEntitiesWithClassname("CommandStructure")
            for _, ent in ientitylist(commandStations) do

                local location = GetLocationForPoint(ent:GetOrigin())
            
                local enemyPlayers = GetEntitiesForTeam("Player", GetEnemyTeamNumber(ent:GetTeamNumber()))
                for e = 1, #enemyPlayers do
                
                    local enemy = enemyPlayers[e]
                    local enemyLocation = GetLocationForPoint(enemy:GetOrigin())
                    if enemyLocation and location:GetName() == enemyLocation:GetName() then
                        local health = enemy:GetMaxHealth() * 0.2 * timePassed
                        local armor = enemy:GetMaxArmor() * 0.2 * timePassed
                        local damage = health + armor
                        enemy:TakeDamage(damage, nil, nil, nil, nil, armor, health, kDamageType.Normal)

                        if not enemy.lastReturnToBaseSend or enemy.lastReturnToBaseSend + 5 < Shared.GetTime() then
                            Server.SendNetworkMessage(enemy, "TeamMessage", { type = kTeamMessageTypes.ReturnToBase, data =  0 }, true)
                            enemy.lastReturnToBaseSend = Shared.GetTime()
                        end
                    end
                    
                end
                
            end
            
        end
        
    end
    
    local function RemoveTag(tagName)
        local tags = { }
        Server.GetTags(tags)

        for t = 1, #tags do

            if string.find(tags[t], tagName) then
                Server.RemoveTag(tags[t])
            end

        end

    end

    local function UpdateTag(tagName, value)

        RemoveTag(tagName)
        Server.AddTag(string.format("%s%s", tagName, value))

    end

    function NS2Gamerules:GetReservedSlots()
        return Server.GetReservedSlotLimit()
    end

    function NS2Gamerules:SetRookieMode(state)
        self.gameInfo:SetRookieMode(state)

        if state then
            Server.AddTag("rookie_only")
        else
            RemoveTag("rookie_only")
        end
    end

    function NS2Gamerules:UpdatePlayerSkill()   --TODO-HIVE / Review, revise (e.g. offsets, comms, etc)
        
        local kTime = Shared.GetTime()
        if not self.nextTimeUpdatePlayerSkill or kTime > self.nextTimeUpdatePlayerSkill then

            self.nextTimeUpdatePlayerSkill = kTime + 10

            local averageSkill = self.playerRanking:GetAveragePlayerSkill()

            Server.SetAvgPlayerSkill(averageSkill)

            -- used by some 3rd party services.
            Server.SetKeyValue("AverageSkill", tostring(averageSkill))

            self.gameInfo:SetAveragePlayerSkill(averageSkill)
        end

    end

    function NS2Gamerules:UpdateNumPlayersForScoreboard()
        
        local kTime = Shared.GetTime()
        if not self.nextTimeUpdateNumPlayersForScoreboard or self.nextTimeUpdateNumPlayersForScoreboard < kTime then

            local numClientsTotal = Server.GetNumClientsTotal and Server.GetNumClientsTotal() or 0

            self.gameInfo:SetNumBots( #gServerBots )
            self.gameInfo:SetNumPlayers( Server.GetNumPlayingPlayers() )
            self.gameInfo:SetNumClientsTotal( numClientsTotal )
                
            self.nextTimeUpdateNumPlayersForScoreboard = kTime + 0.25
        end

    end

    function NS2Gamerules:GetNumPlayersConnecting()
        local rrCount = self.worldTeam:GetNumPlayers()
        local t1Count = self.team1:GetNumPlayers()
        local t2Count = self.team2:GetNumPlayers()
        local spCount = self.spectatorTeam:GetNumPlayers()
        local numClientsTotal = Server.GetNumClientsTotal and Server.GetNumClientsTotal() or 0
        local playersCount = rrCount + t1Count + t2Count + spCount
        local actualPlayers = playersCount - #gServerBots
        return math.max(0, numClientsTotal - actualPlayers)
    end

    function NS2Gamerules:OnUpdate(timePassed)
    
        PROFILE("NS2Gamerules:OnUpdate")
        
        if Server then
            
            if self.justCreated then
                if not self.gameStarted then
                    self:ResetGame()
                end
                self.justCreated = false
            end
            
            if self:GetMapLoaded() then
            
                self:CheckGameStart()
                self:CheckGameEnd()

                self:UpdateWarmUp()
                
                self:UpdatePregame(timePassed)
                self:UpdateToReadyRoom()
                self:UpdateMapCycle()
                self:ServerAgeCheck()
                self:UpdateAutoTeamBalance(timePassed)
                
                self.timeSinceGameStateChanged = self.timeSinceGameStateChanged + timePassed
                
                self.worldTeam:Update(timePassed)
                self.team1:Update(timePassed)
                self.team2:Update(timePassed)
                self.spectatorTeam:Update(timePassed)
                
                self:UpdatePings()
                self:UpdateHealth()
                self:UpdateTechPoints()

                self:CheckForNoCommander(self.team1, "MarineCommander")
                self:CheckForNoCommander(self.team2, "AlienCommander")
                self:KillEnemiesNearCommandStructureInPreGame(timePassed)
                
                self:UpdatePlayerSkill()
                self:UpdateNumPlayersForScoreboard()
                
                if Shared.GetThunderdomeEnabled() then
                    GetThunderdomeRules():CheckForAutoConcede(self)
                end

            end
            
        end
        
    end
    
    -- Global in case mods want to do something different with concede sequences. :)
    function NS2Gamerules:CheckForConcedeSequence(autoConcededTeam)
        
        local concedingTeam
        if autoConcededTeam then -- this team was forced to auto-concede
            concedingTeam = autoConcededTeam
        else -- no team auto-conceded... check for good old fashioned regular concede
            local marineTeam = self:GetTeam(kTeam1Index)
            local alienTeam = self:GetTeam(kTeam2Index)
            
            if marineTeam:GetHasConceded() then
                concedingTeam = marineTeam
            elseif alienTeam:GetHasConceded() then
                concedingTeam = alienTeam
            end
        end
        
        if not concedingTeam then -- nobody conceded, don't do concede sequence.
            return
        end
        
        -- it is determined that one team did concede, or was forced to auto-concede, so we'll
        -- do the concede sequence involving this team.
        DoConcedeSequence(concedingTeam:GetTeamNumber())
        
    end
    
    --[[
     * Ends the current game (optional boolean parameter specifies if it is due to an auto-concede
    ]]
    function NS2Gamerules:EndGame(winningTeam, autoConceded)


        -- Send stats to players
        local roundStats = StatsUI_FormatRoundStats()
        Server.ForAllPlayers(StatsUI_SendPlayerStats)

        -- Don't send the round data if there's no player data
        if #roundStats[1] > 0 or #roundStats[2] > 0 then

            for _, teamStats in ipairs(roundStats) do
                for _, entry in ipairs(teamStats) do
                    Server.SendNetworkMessage("PlayerStats", entry, true)
                end
            end

            StatsUI_SendTeamStats()

            StatsUI_SendGlobalCommanderStats()

        end

        StatsUI_SaveRoundStats(winningTeam)
    
        if self:GetGameState() == kGameState.Started then
            
            local winningTeamType = winningTeam and winningTeam.GetTeamType and winningTeam:GetTeamType() or kNeutralTeamType
            
            if winningTeamType == kMarineTeamType then

                self:SetGameState(kGameState.Team1Won)
                Log("- Marine Team Victory")
                PostGameViz("Marines Win!")

            elseif winningTeamType == kAlienTeamType then

                self:SetGameState(kGameState.Team2Won)
                Log("- Alien Team Victory")
                PostGameViz("Aliens Win!")

            else
                self:SetGameState(kGameState.Draw)
                Log("- Round Draw")
                PostGameViz("Draw Game!")
            end


            if Shared.GetThunderdomeEnabled() then
                GetThunderdomeRules():EndRound()
            end

            Server.SendNetworkMessage( "GameEnd", { win = winningTeamType }, true)
            
            self.team1:ClearRespawnQueue()
            self.team2:ClearRespawnQueue()

            -- Clear out Draw Game window handling
            self.team1Lost = nil
            self.team2Lost = nil
            self.timeDrawWindowEnds = nil
            
            -- Automatically end any performance logging when the round has ended.
            Shared.ConsoleCommand("p_endlog")

            self:LogoutCommanders() --XXX Still required?
            
            --McG: worth mentioning that winningTeam will be nil on Draws, rounds are not reported for Draws
            self.playerRanking:EndGame(winningTeam)

            --remove commander bots that where added via the comm bot vote
            if self.removeCommanderBots then
                self.botTeamController:RemoveCommanderBots()
            end
            
            if winningTeam then
                self.playerRanking:EndGame(winningTeam)
            end

            TournamentModeOnGameEnd()
            
            -- Check if the game ended due to either team conceding.  If so, do the concede
            -- sequence.
            if autoConceded then
                if winningTeam == self:GetTeam(kTeam1Index) then
                    self:CheckForConcedeSequence(self:GetTeam(kTeam2Index))
                else
                    self:CheckForConcedeSequence(self:GetTeam(kTeam1Index))
                end
            else
                self:CheckForConcedeSequence()
            end

        end
        
    end
    
    function NS2Gamerules:OnTournamentModeEnabled()
        self.tournamentMode = true
    end
    
    function NS2Gamerules:OnTournamentModeDisabled()
        self.tournamentMode = false
    end
    
    function NS2Gamerules:DrawGame()

        self:EndGame()
        
    end

    function NS2Gamerules:GetTeam(teamNum)

        local team
        if(teamNum == kTeamReadyRoom) then
            team = self.worldTeam
        elseif(teamNum == kTeam1Index) then
            team = self.team1
        elseif(teamNum == kTeam2Index) then
            team = self.team2
        elseif(teamNum == kSpectatorIndex) then
            team = self.spectatorTeam
        end
        return team
        
    end

    function NS2Gamerules:GetRandomTeamNumber()

        -- Return lesser of two teams, or random one if they are the same
        local team1Players = self.team1:GetNumPlayers()
        local team2Players = self.team2:GetNumPlayers()
        
        if team1Players < team2Players then
            return self.team1:GetTeamNumber()
        elseif team2Players < team1Players then
            return self.team2:GetTeamNumber()
        end
        
        return ConditionalValue(math.random() < .5, kTeam1Index, kTeam2Index)
        
    end

    --list of users that played the tutorial
    local playedTutorial = {}

    -- No enforced balanced teams on join as the auto team balance system balances teams.
    function NS2Gamerules:GetCanJoinTeamNumber(player, teamNumber)
----------------------------------------------------
--[[
        local team1Players = self.team1:GetNumPlayers()
        local team2Players = self.team2:GetNumPlayers()

        local team1Number = self.team1:GetTeamNumber()
        local team2Number = self.team2:GetTeamNumber()

        -- Every check below is disabled with cheats enabled
        if Shared.GetCheatsEnabled() then
            return true
        end

        local forceEvenTeams = Server.GetConfigSetting("force_even_teams_on_join")
        if forceEvenTeams then
            
            if (team1Players > team2Players) and (teamNumber == team1Number) then
                Server.SendNetworkMessage(player, "JoinError", BuildJoinErrorMessage(0), true)
                return false
            elseif (team2Players > team1Players) and (teamNumber == team2Number) then
                Server.SendNetworkMessage(player, "JoinError", BuildJoinErrorMessage(0), true)
                return false
            end

        end

        -- Scenario: Veteran tries to join a team at rookie only server
        if teamNumber ~= kSpectatorIndex then --allow to spectate
            local isRookieOnly = Server.IsDedicated() and not self.botTraining and self.gameInfo:GetRookieMode()

            if isRookieOnly and player:GetSkillTier() > kRookieMaxSkillTier then
                Server.SendNetworkMessage(player, "JoinError", BuildJoinErrorMessage(2), true)
                return false
            end
        end
]]--
---------------------------------------------------        
        return true
        
    end

    local function OnReceivedTutorialPlayed(client)
        playedTutorial[client:GetUserId()] = true
    end
    Server.HookNetworkMessage("PlayedTutorial", OnReceivedTutorialPlayed)

    function NS2Gamerules:GetCanSpawnImmediately()
        return not self:GetGameStarted() or Shared.GetCheatsEnabled()
    end

    function NS2Gamerules:SetMaxBots(newMax, com)
        self.botTeamController:SetMaxBots(newMax, com)
        self.botTeamController:UpdateBots()
    end

    function NS2Gamerules:UpdateBots()
        self.botTeamController:UpdateBots()
    end

    function NS2Gamerules:SetBotTraining(training)
        self.botTraining = training
    end
    
    --[[
     * Returns two return codes: success and the player on the new team. This player could be a new
     * player (the default respawn type for that team) or it will be the original player if the team 
     * wasn't changed (false, original player returned). Pass force = true to make player change team 
     * no matter what and to respawn immediately.
     ]]
    function NS2Gamerules:JoinTeam(player, newTeamNumber, force)
        
        local client = Server.GetOwner(player)
        if not client then return end
        
        -- reset players camera distance, so for example if a player is respawning from an infantry portal, they won't
        -- be stuck in 3rd person view.
        player:SetCameraDistance(0)
        
        if newTeamNumber ~= kSpectatorIndex and not self:GetCanJoinPlayingTeam(player) then
            return false
        end

        if not force and not self:GetCanJoinTeamNumber(player, newTeamNumber) then
            return false
        end
        
        local success = false
        local newPlayer

        local oldPlayerWasSpectating = client and client:GetSpectatingPlayer()
        local oldPlayerWasCommander = client and player:isa("Commander")
        local oldTeamNumber = player:GetTeamNumber()

-----------------------------------------------------------------
        if newTeamNumber == 1 or newTeamNumber == 3 then --Im still debating if spectate (3) should work
            newTeamNumber = 2
        end
-----------------------------------------------------------------
        
        -- Join new team
        if oldTeamNumber ~= newTeamNumber or force then
            
            if not Shared.GetCheatsEnabled() and self:GetGameStarted() and newTeamNumber ~= kTeamReadyRoom then
                player.spawnBlockTime = Shared.GetTime() + kSuicideDelay
            end
        
            local team = self:GetTeam(newTeamNumber)
            local oldTeam = self:GetTeam(oldTeamNumber)
            
            -- Remove the player from the old queue if they happen to be in one
            if oldTeam then
                oldTeam:RemovePlayerFromRespawnQueue(player)
            end
            
            -- Spawn immediately if going to ready room, game hasn't started, cheats on, or game started recently
            if newTeamNumber == kTeamReadyRoom or self:GetCanSpawnImmediately() or force then
            
                success, newPlayer = team:ReplaceRespawnPlayer(player, nil, nil)
                
                local teamTechPoint = team.GetInitialTechPoint and team:GetInitialTechPoint()
                if teamTechPoint then
                    newPlayer:OnInitialSpawn(teamTechPoint:GetOrigin())
                end
                
            else
            
                -- Destroy the existing player and create a spectator in their place.
                newPlayer = player:Replace(team:GetSpectatorMapName(), newTeamNumber)
                
                -- Queue up the spectator for respawn.
                team:PutPlayerInRespawnQueue(newPlayer)
                
                success = true
                
            end
            
            local clientUserId = client:GetUserId()
            --Save old pres 
            if oldTeam == self.team1 or oldTeam == self.team2 then
                if not self.clientpres[clientUserId] then self.clientpres[clientUserId] = {} end
-----------------------------------------------------
                -- self.clientpres[clientUserId][oldTeamNumber] = player:GetResources()
                self.clientpres[clientUserId][oldTeamNumber] = 0 
-----------------------------------------------------
            end
            
            -- Update frozen state of player based on the game state and player team.
            if team == self.team1 or team == self.team2 then
            
                local devMode = Shared.GetDevMode()
                local inCountdown = self:GetGameState() == kGameState.Countdown
                if not devMode and inCountdown then
                    newPlayer.frozen = true
                end
                
                local pres = self.clientpres[clientUserId] and self.clientpres[clientUserId][newTeamNumber]
                newPlayer:SetResources( pres or ConditionalValue(team == self.team1, kMarineInitialIndivRes, kAlienInitialIndivRes) )
            
            else
            
                -- Ready room or spectator players should never be frozen
                newPlayer.frozen = false
                
            end
            
            
            newPlayer:TriggerEffects("join_team")
            
            if success then
                
                local newPlayerClient = Server.GetOwner(newPlayer)
                if oldPlayerWasSpectating then
                    newPlayerClient:SetSpectatingPlayer(nil)
                end
                
                if newPlayer.OnJoinTeam then
                    newPlayer:OnJoinTeam()
                end
                
                if newTeamNumber == kTeam1Index or newTeamNumber == kTeam2Index then
                    self.playerRanking:SetEntranceTime( newPlayer, newTeamNumber )
                elseif oldTeamNumber == kTeam1Index or oldTeamNumber == kTeam2Index then
                    self.playerRanking:SetExitTime( newPlayer, oldTeamNumber )
                    if oldPlayerWasCommander then
                        self.playerRanking:SetCommanderExitTime( player, oldTeamNumber )
                    end
                end

                if newTeamNumber == kSpectatorIndex then
                    newPlayer:SetSpectatorMode(kSpectatorMode.Overhead)
                    newPlayer:SetIsSpectator(true)
                else
                    --remove player from spectator list
                    if newPlayer:GetIsSpectator() then
                        newPlayer:SetIsSpectator(false)
                    end
                end
                
                Server.SendNetworkMessage(newPlayerClient, "SetClientTeamNumber", { teamNumber = newPlayer:GetTeamNumber() }, true)

                self.botTeamController:UpdateBots()
            end

            return success, newPlayer
            
        end
        
        -- Return old player
        return success, player
        
    end
    
    -- For test framework only. Prevents game from ending on its own also.
    function NS2Gamerules:SetGameStarted()

        self:SetGameState(kGameState.Started)
        self.preventGameEnd = true
        
    end

    function NS2Gamerules:SetPreventGameEnd(state)
        self.preventGameEnd = state
    end
    
    function NS2Gamerules:SetTeamsReady(ready)
    
        self.teamsReady = ready
        
        -- unstart the game without tracking statistics
        if self.tournamentMode and not ready and self:GetGameStarted() then
            self:ResetGame()
        end
        
    end
    
    function NS2Gamerules:SetPaused()    
    end
    
    function NS2Gamerules:DisablePause()
    end

    function NS2Gamerules:GetWarmUpPlayerLimit()    --(McG)TODO Move values to local globals
        return 12
    end

    function NS2Gamerules:UpdateWarmUp()
        local gameState = self:GetGameState()
        if gameState < kGameState.PreGame then
            local team1players, _, team1bots = self.team1:GetNumPlayers()
            local team2players, _, team2bots = self.team2:GetNumPlayers()
            local numPlayers = team1players - team1bots + team2players - team2bots
            if gameState == kGameState.NotStarted and numPlayers < self:GetWarmUpPlayerLimit() then
                self.team1:SpawnWarmUpStructures()
                self.team2:SpawnWarmUpStructures()

                self:SetGameState(kGameState.WarmUp)
                if GetSeason() == Seasons.kFall then
                    self:DestroyUnusedPowerNodes()
                end
            elseif gameState == kGameState.WarmUp and numPlayers >= self:GetWarmUpPlayerLimit() then
                self:SetGameState(kGameState.NotStarted)
            end
        end
    end

    NS2Gamerules.kStartGameVoteDelay = 300
    function NS2Gamerules:CheckGameStart()
    
        if self:GetGameState() <= kGameState.PreGame then
        
            -- Start pre-game when both teams have commanders or when once side does if cheats are enabled
            local team1Commander = self.team1:GetCommander()
            local team2Commander = self.team2:GetCommander()

            local team1NumPlayer = self.team1:GetNumPlayers()
            local team2NumPlayer = self.team2:GetNumPlayers()

            --firstPregameJoin is used to trigger the vote to start the game with bots
            if team1NumPlayer + team2NumPlayer > 0 then
                if self.firstPregameJoin == nil then
                    self.firstPregameJoin = Shared.GetTime()
                end
            else
                self.firstPregameJoin = nil
            end

            if ((team1Commander and team2Commander) or Shared.GetCheatsEnabled()) and (not self.tournamentMode or self.teamsReady) then
            
                if self:GetGameState() < kGameState.PreGame then
                    self:SetGameState(kGameState.PreGame)
                end
                
            else
            
                if self:GetGameState() == kGameState.PreGame then
                    self:SetGameState(kGameState.NotStarted)
                end
                
                if (not team1Commander or not team2Commander) then
                --Remind teams they need a Commander, but only in non TD-Mode as it handles that automatically
                    
                    if not self.nextGameStartMessageTime or Shared.GetTime() > self.nextGameStartMessageTime then

                        --Inform players in TD round we're still waiting on connecting clients; otherwise, remind players they need a Commander.
                        local messageType = Shared.GetThunderdomeEnabled() and kTeamMessageTypes.TD_RoundWaitingPlayers or kTeamMessageTypes.GameStartCommanders

                        SendTeamMessage(self.team1, messageType)
                        SendTeamMessage(self.team2, messageType)

                        self.nextGameStartMessageTime = Shared.GetTime() + kGameStartMessageInterval
                    end

                    local gamestate = self:GetGameState()

                    if not Shared.GetThunderdomeEnabled() then
                    --Don't display when TD-mode enabled, as round will immediately start once all clients joined and assigned automtically
                        local displayWarmupMsg = 
                            gamestate == kGameState.WarmUp and 
                            self.nextGameStartMessageTime and 
                            self.nextGameStartMessageTime ~= self.lastWarmUpMessageTime and 
                            Shared.GetTime() > self.nextGameStartMessageTime - kGameStartMessageInterval / 2
                        
                        if displayWarmupMsg then
                            SendTeamMessage(self.team1, kTeamMessageTypes.WarmUpActive, self:GetWarmUpPlayerLimit())
                            -- SendTeamMessage(self.team2, kTeamMessageTypes.WarmUpActive, self:GetWarmUpPlayerLimit())
                            self.lastWarmUpMessageTime = self.nextGameStartMessageTime
                        end
                    end
                    
                    --check if it's time to start the add commander bots vote
                    local autoVoteAddCommBots = Server.GetConfigSetting("auto_vote_add_commander_bots")
                    if autoVoteAddCommBots and gamestate < kGameState.PreGame and self.firstPregameJoin
                            and self.firstPregameJoin + self.kStartGameVoteDelay < Shared.GetTime() then

                        local votename = "VoteAddCommanderBots"
                        if GetStartVoteAllowed(votename) == kVoteCannotStartReason.VoteAllowedToStart then
                            self.firstPregameJoin = false
                            StartVote(votename, nil, {})
                        end
                    end
                end
                
            end
            
        end
        
    end
    
    local function CheckAutoConcede(self)

        PROFILE("NS2Gamerules:CheckAutoConcede")
                
        -- This is an optional end condition based on the teams being unbalanced.
        local endGameOnUnbalancedAmount = Server.GetConfigSetting("end_round_on_team_unbalance")
        if endGameOnUnbalancedAmount and endGameOnUnbalancedAmount > 0 then

            local gameLength = Shared.GetTime() - self:GetGameStartTime()
            -- Don't start checking for auto-concede until the game has started for some time.
            local checkAutoConcedeAfterTime = Server.GetConfigSetting("end_round_on_team_unbalance_check_after_time") or 300
            if gameLength > checkAutoConcedeAfterTime then

                local team1Players = self.team1:GetNumPlayers()
                local team2Players = self.team2:GetNumPlayers()
                local totalCount = team1Players + team2Players
                -- Don't consider unbalanced game end until enough people are playing.

                if totalCount > 6 then
                
                    local team1ShouldLose = false
                    local team2ShouldLose = false
                    
                    if (1 - (team1Players / team2Players)) >= endGameOnUnbalancedAmount then

                        team1ShouldLose = true
                    elseif (1 - (team2Players / team1Players)) >= endGameOnUnbalancedAmount then

                        team2ShouldLose = true
                    end
                    
                    if team1ShouldLose or team2ShouldLose then
                    
                        -- Send a warning before ending the game.
                        local warningTime = Server.GetConfigSetting("end_round_on_team_unbalance_after_warning_time") or 30
                        if self.sentAutoConcedeWarningAtTime and Shared.GetTime() - self.sentAutoConcedeWarningAtTime >= warningTime then
                            return team1ShouldLose, team2ShouldLose
                        elseif not self.sentAutoConcedeWarningAtTime then
                        
                            Shared.Message((team1ShouldLose and "Marine" or "Alien") .. " team auto-concede in " .. warningTime .. " seconds")
                            Server.SendNetworkMessage("AutoConcedeWarning", { time = warningTime, team1Conceding = team1ShouldLose }, true)
                            self.sentAutoConcedeWarningAtTime = Shared.GetTime()
                            
                        end
                        
                    else
                        self.sentAutoConcedeWarningAtTime = nil
                    end
                    
                end
                
            else
                self.sentAutoConcedeWarningAtTime = nil
            end
            
        end
        
        return false, false
        
    end
    
    function NS2Gamerules:CheckGameEnd()

        PROFILE("NS2Gamerules:CheckGameEnd")
        
        if self:GetGameStarted() and self.timeGameEnded == nil and not Shared.GetCheatsEnabled() and not self.preventGameEnd then

            local time = Shared.GetTime()
            if not self.timeDrawWindowEnds or time < self.timeDrawWindowEnds then

                local team1Lost = self.team1Lost or self.team1:GetHasTeamLost()
                local team2Lost = self.team2Lost or self.team2:GetHasTeamLost()

                if team1Lost or team2Lost then
            
                    -- After a team has entered a loss condition, they can not recover
                    self.team1Lost = team1Lost
                    self.team2Lost = team2Lost

                    -- Continue checking for a draw for kDrawGameWindow seconds
                    if not self.timeDrawWindowEnds then
                        self.timeDrawWindowEnds = time + kDrawGameWindow
                    end
                    
                else
                    -- Check for auto-concede if neither team lost.
                    if not self.timeNextAutoConcedeCheck or self.timeNextAutoConcedeCheck < time then
                        
                        team1Lost, team2Lost = CheckAutoConcede(self)
                        if team2Lost then
                            self:EndGame( self.team1 , true )
                        elseif team1Lost then
                            self:EndGame( self.team2 , true )
                        end
                        
                        self.timeNextAutoConcedeCheck = time + kGameEndAutoConcedeCheckInterval
                    end
                    
                end

            else

                if self.team2Lost and self.team1Lost then
                    
                    -- It's a draw
                    self:DrawGame()
                    
                elseif self.team2Lost then

                    -- Still no draw after kDrawGameWindow, count the win
                    self:EndGame( self.team1 )

                elseif self.team1Lost then

                    -- Still no draw after kDrawGameWindow, count the win
                    self:EndGame( self.team2 )
                    
                end

            end

        end

    end

    function NS2Gamerules:GetCountingDown()
        return self:GetGameState() == kGameState.Countdown
    end
    
    local function StartCountdown(self)
    
        self:ResetGame()
        
        self:SetGameState(kGameState.Countdown)
        self.countdownTime = kCountDownLength
        
        self.lastCountdownPlayed = nil
        
    end

    function NS2Gamerules:GetPregameLength()
    
        local preGameTime = kPregameLength
        if Shared.GetCheatsEnabled() then
            preGameTime = 0
        end

        if self.gameInfo:GetRookieMode() and #gServerBots >= 2 then
            preGameTime = kRookieModeDelay
        end
        
        return preGameTime
        
    end
    
    function NS2Gamerules:UpdatePregame(timePassed)

        if self:GetGameState() == kGameState.PreGame then

            local preGameTime = self:GetPregameLength()
            
            if self.timeSinceGameStateChanged > preGameTime then

                StartCountdown(self)
                if Shared.GetCheatsEnabled() then
                    self.countdownTime = 1
                end
                
            end
            
        elseif self:GetGameState() == kGameState.Countdown then
        
            self.countdownTime = self.countdownTime - timePassed
            
            -- Play count down sounds for last few seconds of count-down
            local countDownSeconds = math.ceil(self.countdownTime)
            if self.lastCountdownPlayed ~= countDownSeconds and (countDownSeconds < 4) then
            
                self.worldTeam:PlayPrivateTeamSound(NS2Gamerules.kCountdownSound)
                self.team1:PlayPrivateTeamSound(NS2Gamerules.kCountdownSound)
                self.team2:PlayPrivateTeamSound(NS2Gamerules.kCountdownSound)
                self.spectatorTeam:PlayPrivateTeamSound(NS2Gamerules.kCountdownSound)
                
                self.lastCountdownPlayed = countDownSeconds
                
            end
            
            if self.countdownTime <= 0 then
            
                self.team1:PlayPrivateTeamSound(ConditionalValue(self.team1:GetTeamType() == kAlienTeamType, NS2Gamerules.kAlienStartSound, NS2Gamerules.kMarineStartSound))
                self.team2:PlayPrivateTeamSound(ConditionalValue(self.team2:GetTeamType() == kAlienTeamType, NS2Gamerules.kAlienStartSound, NS2Gamerules.kMarineStartSound))
                
                self.playerRanking:StartGame()
                self:SetGameState(kGameState.Started)

                --Reset all scores right when the round starts, required in order for skill weighted time to be accurate
                self:ResetPlayerScores()
                
                if Shared.GetThunderdomeEnabled() then
                    GetThunderdomeRules():StartRound()
                end
            end
            
        end
        
    end

    function NS2Gamerules:GetAllTech()
        return self:GetGameState() == kGameState.WarmUp or self.allTech
    end

    function NS2Gamerules:SetAllTech(state)

        if state ~= self.allTech then
        
            self.allTech = state
            
            self.team1:GetTechTree():SetTechChanged()
            self.team2:GetTechTree():SetTechChanged()
            
        end
        
    end

    function NS2Gamerules:GetAutobuild()
        return self.autobuild
    end

    function NS2Gamerules:SetAutobuild(state)
        self.autobuild = state
    end

    function NS2Gamerules:SetOrderSelf(state)
        self.orderSelf = state
    end

    function NS2Gamerules:GetOrderSelf()
        return self.orderSelf
    end

    function NS2Gamerules:GetIsPlayerFollowingTeamNumber(player, teamNumber)

        local following = false
        
        if player:isa("Spectator") then
        
            local playerId = player:GetFollowingPlayerId()
            
            if playerId ~= Entity.invalidId then
            
                local followedPlayer = Shared.GetEntity(playerId)
                
                if followedPlayer and followedPlayer:GetTeamNumber() == teamNumber then
                
                    following = true
                    
                end
                
            end

        end
        
        return following

    end

    -- Function for allowing teams to hear each other's voice chat
    function NS2Gamerules:GetCanPlayerHearPlayer(listenerPlayer, speakerPlayer, channelType)

        local canHear = false
        
        if Server.GetConfigSetting("alltalk") or Server.GetConfigSetting("pregamealltalk") and not self:GetGameStarted() then
            return true
        end
        
        -- Check if the listerner has the speaker muted.
        if listenerPlayer:GetClientMuted(speakerPlayer:GetClientIndex()) then
            return false
        end
        
        -- If both players have the same team number, they can hear each other
        if(listenerPlayer:GetTeamNumber() == speakerPlayer:GetTeamNumber()) then
            if channelType == nil or channelType == VoiceChannel.Global then
                canHear = true
            else 
                canHear = listenerPlayer:GetDistance(speakerPlayer) < kMaxWorldSoundDistance
            end
        end
            
        -- Or if cheats AND dev mode is on, they can hear each other
        if(Shared.GetCheatsEnabled() and Shared.GetDevMode()) then
            canHear = true
        end
        
        -- NOTE: SCRIPT ERROR CAUSED IN THIS FUNCTION WHEN FP SPEC WAS ADDED.
        -- This functionality never really worked anyway.
        -- If we're spectating a player, we can hear their team (but not in tournamentmode, once that's in)
        --if self:GetIsPlayerFollowingTeamNumber(listenerPlayer, speakerPlayer:GetTeamNumber()) then
        --    canHear = true
        --end
        
        return canHear
        
    end

    function NS2Gamerules:RespawnPlayer(player)

        local team = player:GetTeam()
        team:RespawnPlayer(player, nil, nil)
        
    end

    -- Add SteamId of player to list of players that can't command again until next game
    function NS2Gamerules:BanPlayerFromCommand(playerId)
        self.bannedPlayers:Insert(playerId)
    end

    function NS2Gamerules:GetPlayerBannedFromCommand(playerId)
        return self.bannedPlayers:Contains(playerId)
    end

----------------    
-- End Server --
----------------

end

function NS2Gamerules:GetGameStartTime()
    return ConditionalValue(self:GetGameStarted(), self.gameStartTime, 0)
end

function NS2Gamerules:GetGameStarted()
    return self.gameState == kGameState.Started
end

function NS2Gamerules:GetWarmUpActive()
    return self.gameState == kGameState.WarmUp
end

Shared.LinkClassToMap("NS2Gamerules", NS2Gamerules.kMapName, { })

