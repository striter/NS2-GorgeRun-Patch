function Gamerules:OnClientConnect(client)

    local mapName = self:GetPlayerConnectMapName(client)
    local player = CreateEntity(mapName, nil, kTeamReadyRoom)
    
    local steamid = tonumber(client:GetUserId())
    Shared.Message(string.format('Client Authed. Steam ID: %s', steamid))
    
    if player ~= nil then
----------------------------------------------------------------------------
        local GRMessage = "现在运行的是: <Gorger> 赛跑模式. "
        GRMessage = GRMessage .. string.format("\n服务器排名(%s):",Shared.GetMapName())
        
        local mapname = Shared.GetMapName()
        local grfilename = string.format("config://%s.grstatsV3", mapname)
        local grstatsline = {}
        local grstats = io.open( grfilename, "r" )
        if not grstats then --
            for i=1,30,3
                do
                    grstatsline[i] = "3540"
                    grstatsline[i+1] = "TinCan"
                    grstatsline[i+2] = "111111111111"
                end
    
        else
            local i = 1
            for line in grstats:lines() do
                grstatsline[i] = line
                i = i + 1
            end
            grstats:close()
        end

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

        Server.SendNetworkMessage(client, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, GRMessage), true)

        
-----------------------------------------------------------------------------
        -- Tell engine that player is controlling this entity
        player:SetControllerClient(client)
        
        player:OnClientConnect(client)
        
        self:RespawnPlayer(player)
        
    else
        Print("Gamerules:OnClientConnect(): Couldn't create player entity of type \"%s\"", mapName)
    end
    
    Server.SendNetworkMessage(client, "SetClientIndex", { clientIndex = client:GetId() }, true)
    
    Server.SendNetworkMessage(client, "ServerHidden", { hidden = Server.GetServerHidden() }, true)
    
    local playerInfo = CreateEntity(PlayerInfoEntity.kMapName)
    player:SetPlayerInfo(playerInfo)
    
    return player
    
end
