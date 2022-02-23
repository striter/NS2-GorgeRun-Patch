function Gamerules:OnClientConnect(client)

    local mapName = self:GetPlayerConnectMapName(client)
    local player = CreateEntity(mapName, nil, kTeamReadyRoom)
    
    local steamid = tonumber(client:GetUserId())
    Shared.Message(string.format('Client Authed. Steam ID: %s', steamid))
    
    if player ~= nil then
----------------------------------------------------------------------------
        local GRMessage1 = "Gorge Run Mod is active. "
        local GRMessage2 = "Type GRSTATS in console to see the top scores. "
        Print(GRMessage1)
        Print(GRMessage2)
        Server.SendNetworkMessage(client, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, GRMessage1), true)
        Server.SendNetworkMessage(client, "Chat", BuildChatMessage(false, "", -1, -1, kNeutralTeamType, GRMessage2), true)
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
