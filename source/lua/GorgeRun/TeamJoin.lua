-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\TeamJoin.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Trigger.lua")

class 'TeamJoin' (Trigger)

TeamJoin.kMapName = "team_join"

local networkVars =
{
    teamNumber = string.format("integer (-1 to %d)", kSpectatorIndex),
    teamIsFull = "boolean",
    playerCount = "integer (0 to " .. kMaxPlayers - 1 .. ")"
}

function TeamJoin:OnCreate()

    Trigger.OnCreate(self)
    
    self.teamIsFull = false
    self.playerCount = 0
    
    if Server then
        self:SetUpdates(true, kDefaultUpdateRate)
    end
    
end

function TeamJoin:OnInitialized()

    Trigger.OnInitialized(self)
    
    -- self:SetPropagate(Actor.Propagate_Never)
    self:SetPropagate(Entity.Propagate_Always)
    
    self:SetIsVisible(false)
    
    self:SetTriggerCollisionEnabled(true)
    
end

if Server then

    function TeamJoin:OnUpdate()
    
        local team1PlayerCount = GetGamerules():GetTeam(kTeam1Index):GetNumPlayers()
        local team2PlayerCount = GetGamerules():GetTeam(kTeam2Index):GetNumPlayers()
        if self.teamNumber == kTeam1Index then
        
            self.teamIsFull = team1PlayerCount > team2PlayerCount
            self.playerCount = team1PlayerCount
            
        elseif self.teamNumber == kTeam2Index then
        
            self.teamIsFull = team2PlayerCount > team1PlayerCount
            self.playerCount = team2PlayerCount
            
        end
        
    end
    
    function JoinRandomTeam(player)

        -- Join team with less players or random.
        local team1Players = GetGamerules():GetTeam(kTeam1Index):GetNumPlayers()
        local team2Players = GetGamerules():GetTeam(kTeam2Index):GetNumPlayers()
        
        -- Join team with least.
        if team1Players < team2Players then
            Server.ClientCommand(player, "jointeamone")
        elseif team2Players < team1Players then
            Server.ClientCommand(player, "jointeamtwo")
        else
        
            -- Join random otherwise.
            if math.random() < 0.5 then
                Server.ClientCommand(player, "jointeamone")
            else
                Server.ClientCommand(player, "jointeamtwo")
            end
            
        end
        
    end
    
    function ForceEvenTeams_GetPlayerSkill( player )
        if player:isa("Commander") then
            return player:GetCommanderTeamSkill()
        end
        return player:GetPlayerTeamSkill()
    end

    function ForceEvenTeams_GetNumPlayersOnTeam( teamIdx )
        return  GetGamerules():GetTeam(teamIdx):GetNumPlayers()
    end

    function ForceEvenTeams_GetPlayers()

        local playerEnts = GetEntities("Player")
        local players = {}

        for _,player in ipairs( playerEnts ) do
            if not player:GetIsSpectator() then -- don't try to balance ragdolls or spectators
                players[#players+1] = player
            end
        end

        return players
    end

    function ForceEvenTeams_AssignPlayer( player, team )
        player:SetCameraDistance(0)
        GetGamerules():JoinTeam(player, team, true)
    end
    
    function ForceEvenTeams()
    
        local kTeamSign = { [1] = 1, [2] = -1 }
                
        local players = ForceEvenTeams_GetPlayers()
        table.sort( players, function( a, b )
                return ForceEvenTeams_GetPlayerSkill(b) < ForceEvenTeams_GetPlayerSkill(a)
                end )
        
        local teamCount = { ForceEvenTeams_GetNumPlayersOnTeam(kTeam1Index), ForceEvenTeams_GetNumPlayersOnTeam(kTeam2Index) }
        local maxTeamSize = math.ceil( #players / 2 )
        local skillDifference = 0
        
        local playersToAssign = {}
        
        local playerTeamNumber
        local playerTeamSign
        
        for round = 1, 3 do

            for _, player in ipairs(players) do

                playerTeamNumber = player:GetTeamNumber()
                playerTeamSign = kTeamSign[playerTeamNumber or 0]
                
                local shouldProcess = false 
                if playerTeamSign and player:isa("Commander") then
                    shouldProcess = round == 1
                elseif playerTeamSign then
                    shouldProcess = round == 2
                else
                    shouldProcess = round == 3
                end
                
                if shouldProcess then

                    if not playerTeamSign or not player:isa("Commander") then -- if not on a team or not a commander, player can be swapped later on
                        if not playerTeamSign then -- if not on a team yet, pick a team
                            if teamCount[1] == maxTeamSize then
                                playerTeamNumber = 2
                            elseif teamCount[2] == maxTeamSize then
                                playerTeamNumber = 1
                            elseif skillDifference > 0 then
                                playerTeamNumber = 2
                            elseif skillDifference < 0 then
                                playerTeamNumber = 1
                            else
                                playerTeamNumber = math.random(1,2)
                            end
                            
                            -- new player is being added to a team, accumulate the difference
                            teamCount[ playerTeamNumber ] = teamCount[ playerTeamNumber ] + 1
                        end
                        
                        playersToAssign[ #playersToAssign + 1 ] = 
                        { 
                            player = player; 
                            teamDestination = playerTeamNumber;
                            hadPreference = playerTeamSign;
                        };
                        
                    end
                    
                    -- accumulate the skill difference
                    skillDifference = skillDifference + kTeamSign[playerTeamNumber] * ForceEvenTeams_GetPlayerSkill(player)
                end

            end

        end
        
        -- Balance out teams if uneven by swapping the least skilled player (results in smallest delta)
        local otherTeamNumber

        for playerTeamNumber = 1, 2 do

            otherTeamNumber = playerTeamNumber == 2 and 1 or 2

            if teamCount[playerTeamNumber] > maxTeamSize then

                for i = #playersToAssign, 1, -1 do

                    if playersToAssign[i].teamDestination == playerTeamNumber then
                        teamCount[ playerTeamNumber ] = teamCount[ playerTeamNumber ] - 1                        
                        teamCount[ otherTeamNumber ] = teamCount[ otherTeamNumber ] + 1
                        playersToAssign[i].teamDestination = otherTeamNumber
                        skillDifference = skillDifference + 2 * kTeamSign[otherTeamNumber] * ForceEvenTeams_GetPlayerSkill(playersToAssign[i].player)
                    end
                    
                    if teamCount[playerTeamNumber] == maxTeamSize then
                        break
                    end

                end

            end

        end
        
        -- We break the optimization into two rounds, one where we optimize only the ambivalent players
        -- and one where we optimize everyone. This makes it more likely that we'll get into a local optima
        -- before we get to players that have already picked a team.
        -- To optimize, we greedily find the swap among all pairs of players that minimizes the skill difference
        
        local bestSwapI, bestSwapJ, bestSwapDelta
        local playerToAssignI,teamI        
        local playerToAssignJ,teamJ
        local delta
        
        for round = 0, 1 do

            for swaps = 0, 20 do -- 20 swaps per round should be plenty

                bestSwapI = -1
                bestSwapJ = -1
                bestSwapDelta = skillDifference

                for i = 1, #playersToAssign do

                    playerToAssignI = playersToAssign[i]
                    teamI = playerToAssignI.teamDestination

                    -- In round 1 do everyone, in round 0 only the ambivalent players.
                    if round == 1 or not playerToAssignI.hasPreference then

                        for j = i + 1, #playersToAssign do

                            playerToAssignJ = playersToAssign[j]

                            local teamJ = playerToAssignJ.teamDestination

                            if teamI ~= teamJ and (round == 1 or not playerToAssignJ.hasPreference ) then
                                delta = 
                                    kTeamSign[teamI] * ForceEvenTeams_GetPlayerSkill(playerToAssignI.player) + 
                                    kTeamSign[teamJ] * ForceEvenTeams_GetPlayerSkill(playerToAssignJ.player)

                                if math.abs(skillDifference - 2 * delta) < math.abs(bestSwapDelta) then
                                    bestSwapI = i
                                    bestSwapJ = j
                                    bestSwapDelta = skillDifference - 2 * delta
                                    --RawPrint( "Good", ForceEvenTeams_GetPlayerSkill(playerToAssignI.player) , ForceEvenTeams_GetPlayerSkill(playerToAssignJ.player), delta, skillDifference - delta, bestSwapDelta )
                                else
                                    --RawPrint( "Bad", ForceEvenTeams_GetPlayerSkill(playerToAssignI.player) , ForceEvenTeams_GetPlayerSkill(playerToAssignJ.player), delta, skillDifference - delta, bestSwapDelta )
                                end

                            end

                        end

                    end

                end

                if bestSwapI ~= -1 then
                    playersToAssign[bestSwapI].teamDestination, playersToAssign[bestSwapJ].teamDestination 
                        = playersToAssign[bestSwapJ].teamDestination, playersToAssign[bestSwapI].teamDestination
                    --RawPrint( "Swapping", bestSwapI, bestSwapJ, skillDifference, bestSwapDelta )
                    skillDifference = bestSwapDelta
                else
                    break
                end

            end

        end

        local playerToAssign
        for i = 1, #playersToAssign do
            playerToAssign = playersToAssign[i]
            ForceEvenTeams_AssignPlayer( playerToAssign.player, playerToAssign.teamDestination )
        end

    end
    
    
    function TeamJoin:OnTriggerEntered(enterEnt, triggerEnt)

        if enterEnt:isa("Player") then
        
            if self.teamNumber == kTeamReadyRoom then
                Server.ClientCommand(enterEnt, "spectate")
            elseif self.teamNumber == kTeam1Index then
-------------------------------------------------------------------------------------
-- Server.ClientCommand(enterEnt, "jointeamone")
---
-- If the gorge touches a marine join 'entity' the end of run has been reached triggering this code
                -- Convert the seconds to min:sec time representation
                local TotalTime = math.floor(enterEnt:GetResources())
                local Minutes = math.floor(TotalTime / 60)
                local Seconds = TotalTime - Minutes * 60
                Server.SendNetworkMessage("Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, string.format("%s 完成了挑战. 耗时: %d:%02d",enterEnt:GetName(), Minutes, Seconds), true))
                local mapname = Shared.GetMapName()
                local grfilename = string.format("config://%s.grstatsV3", mapname)
                local grstatsline = {}
                local oldgrstatsline = {}
                local grstats = io.open( grfilename, "r" )
                if not grstats then --no file so load defaults and loadup up oldgr... in case an update is needed
                    for i= 1,30,3
                        do
                            grstatsline[i] = "3540"
                            oldgrstatsline[i] = "3540"
                            grstatsline[i+1] = "TinCan"
                            oldgrstatsline[i+1] = "TinCan"
                            grstatsline[i+2] = "x_xxxxx"
                            oldgrstatsline[i+2] = "x_xxxxx"
                        end
                else
                    local i = 1
                    for line in grstats:lines() do
                        grstatsline[i] = line
                        oldgrstatsline[i] = line
                        i = i + 1
                    end
                grstats:close()
                end

                exitConditionVariable = true
                if tonumber(enterEnt:GetResources()) <= tonumber(grstatsline[28]) then
                    local grc = 25 -- Setup counter
                    local playerexistsflag = false
   	                local exitConditionVariable = false
                    local existingtopspot = false
                    -- Check if player exists already
                    for i=3,30,3
                    do
                    if tonumber(grstatsline[i]) == tonumber(enterEnt:GetSteamId()) then -- playerid then
                        if tonumber(enterEnt:GetResources()) <= tonumber(grstatsline[i-2]) then
                                grc =  i - 2
                                if grc == 1 then
                                    existingtopspot = true
                                end
                                playerexistsflag = true
                                Server.SendNetworkMessage(enterEnt, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, "你进行了一个记录的超越!"), true)
                        else
                                Server.SendNetworkMessage(enterEnt, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, "之前的你更棒一点,再试试吧!"), true)
                                exitConditionVariable = true
                        end
                    end
                end
                while not exitConditionVariable do
                    if playerexistsflag == false then
                        -- Move records down three at a time
                        grstatsline[grc+3] = oldgrstatsline[grc]
                        grstatsline[grc+4] = oldgrstatsline[grc+1]
                        grstatsline[grc+5] = oldgrstatsline[grc+2]
                     end
                    if existingtopspot == true then
                            grstatsline[grc] = enterEnt:GetResources()
                            grstatsline[grc+1] = enterEnt:GetName()
                            grstatsline[grc+2] = enterEnt:GetSteamId()
                            exitConditionVariable = true -- Done, no need to upate further
                    else
                            if tonumber(enterEnt:GetResources()) >= tonumber(oldgrstatsline[grc-3]) then
                                grstatsline[grc] = enterEnt:GetResources()
                                grstatsline[grc+1] = enterEnt:GetName()
                                grstatsline[grc+2] = enterEnt:GetSteamId()
                                exitConditionVariable = true -- Done, no need to upate further
                            end
                    end



                    grc = grc - 3
                    playerexistsflag = false
                    if grc == 1 and exitConditionVariable == false then
                        -- Top score so move down one more time and insert here
                        grstatsline[grc+3] = oldgrstatsline[grc]
                        grstatsline[grc+4] = oldgrstatsline[grc+1]
                        grstatsline[grc+5] = oldgrstatsline[grc+2]
                        grstatsline[grc] = enterEnt:GetResources()
                        grstatsline[grc+1] = enterEnt:GetName()
                        grstatsline[grc+2] = enterEnt:GetSteamId()
                        exitConditionVariable = true -- Done
                    end
                end
                
                local GRMessage = string.format("服务器排名(%s):",Shared.GetMapName())
        
                local rank = 0
                for i=1,30,3
                do
                    rank=rank+1
                    if grstatsline[i] == nil then -- Just in case
                        grstatsline[i] = "10101010"
                        grstatsline[i+1] = "10101010"
                        grstatsline[i+2] = "10101010"
                    end

                    local grtime = grstatsline[i]
                    local grname = grstatsline[i+1]
                    local minutes = math.floor(grtime/60)
                    local seconds = grtime - minutes*60
                    GRMessage = GRMessage .. string.format("\n#%d <%s>:%d:%02d",  rank, grname, minutes, seconds)
                end
        
                Server.SendNetworkMessage(enterEnt, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, GRMessage), true)
            end
            
            local ccheck4grfile = io.open(grfilename,"w")
            for i = 1,30 do
                if grstatsline[i] == nil then -- Just in case?
                    grstatsline[i] = "10101010"
                end
                ccheck4grfile:write(grstatsline[i],"\n")
            end
            ccheck4grfile:close()
            -- all done so send player to readyroom
            Server.ClientCommand(enterEnt, "readyroom")
            elseif self.teamNumber == kTeam2Index then
                Server.ClientCommand(enterEnt, "jointeamtwo")
            elseif self.teamNumber == kRandomTeamType then
                JoinRandomTeam(enterEnt)
            end
            
        end
        
    end
    
    
    local function OnCommandTestForceEvenTeams(client,seed,team1,team2,team1hasCom,team2hasCom,totalPlayers)
        
        if not Shared.GetDevMode() then return end
        
        seed = tonumber(seed) or 0
        team1, team2, totalPlayers = tonumber(team1) or 3, tonumber(team2) or 2, tonumber(totalPlayers) or 16
        team1hasCom = not team1hasCom or tonumber(team1hasCom) ~= 0 and true or false
        team2hasCom = not team2hasCom or tonumber(team2hasCom) ~= 0 and true or false
        Shared.Message( string.format( 
                "TestForceEvenTeams( seed (%d), team1Size (%d), team2Size (%d), team1hasCom (%d), team2hasCom (%d), totalPlayers (%d)) returned : ",
                seed,team1,team2,team1hasCom and 1 or 0,team2hasCom and 1 or 0,totalPlayers
            ) )
        
        -- Build fake player list
        local fakePlayerList = {}
        
        math.randomseed( seed )
        local hasCom = { team1hasCom or true, team2hasCom or false }
        local joinedSize = { math.max( team1hasCom and 1 or 0, team1 ), math.max( team2hasCom and 1 or 0, team2 ) }
        local total = math.max( team1 + team2, totalPlayers )
        local function FakePlayer( i,team, skill, iscomm )
            return 
            {
                idx = i;
                originalTeam = team;
                team = team;
                skill = skill;
                iscomm = iscomm;
                GetTeamNumber = function( self ) return self.team; end;
                GetPlayerSkill = function( self ) return self.skill; end;
                GetClient = function( self ) return true end;
                isa = function( self, type ) return self.iscomm; end;
            }
        end
        for team=1,2 do
            for i=1,joinedSize[team] do
                local playerId = #fakePlayerList + 1
                fakePlayerList[playerId] = FakePlayer( playerId, team, math.random(500), i==1 and hasCom[team] );
            end
        end
        for i=#fakePlayerList+1,total do
            fakePlayerList[i] = FakePlayer( i,0, math.random(500), false);
        end
        
        -- Hook functions to use fake data
        local oldForceEvenTeams_GetNumPlayersOnTeam, oldForceEvenTeams_AssignPlayer, oldForceEvenTeams_GetPlayers = ForceEvenTeams_GetNumPlayersOnTeam, ForceEvenTeams_AssignPlayer, ForceEvenTeams_GetPlayers        
        ForceEvenTeams_GetNumPlayersOnTeam = function( teamIdx )
            local sum = 0
            for i,player in ipairs(fakePlayerList) do
                if player.team == teamIdx then
                    sum = sum + 1
                end
            end
            return sum
        end
        ForceEvenTeams_AssignPlayer = function( player, team )
            player.team = team;
        end
        ForceEvenTeams_GetPlayers = function()
            return fakePlayerList
        end
        
        -- Run algorithm
        ForceEvenTeams()
        
        -- Restore hooked functions
        ForceEvenTeams_GetNumPlayersOnTeam, ForceEvenTeams_AssignPlayer, ForceEvenTeams_GetPlayers = oldForceEvenTeams_GetNumPlayersOnTeam, oldForceEvenTeams_AssignPlayer, oldForceEvenTeams_GetPlayers
        
        -- Print output
        table.sort( fakePlayerList, function( a, b )
                return b.team > a.team or b.team == a.team and b:GetPlayerSkill() < a:GetPlayerSkill() 
                end )
        
        local teamCount = { 0, 0 }
        local skillCount = { 0, 0 }
        for id,player in ipairs( fakePlayerList ) do
            Shared.Message( string.format( "%s %d, Skill %d was on Team %d now on %d", player.iscomm and "COMM" or "PLAYER", player.idx, player.skill, player.originalTeam, player.team ) )
            teamCount[player.team] = teamCount[player.team] + 1
            skillCount[player.team] = skillCount[player.team] + player.skill
        end
       Shared.Message( string.format( "%d (%d skill) v. %d (%d skill)", teamCount[1], skillCount[1], teamCount[2], skillCount[2] ) )
       
    end
    Event.Hook("Console_testforceeventeams",  OnCommandTestForceEvenTeams)

end

Shared.LinkClassToMap("TeamJoin", TeamJoin.kMapName, networkVars)