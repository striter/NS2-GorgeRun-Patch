local function NotifyPlayer(player, message)
    Server.SendNetworkMessage(player, "ServerAdminPrint", { message = message }, true)
end


local function showgrstats(client)
    local player = client and client:GetControllingPlayer() or nil

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
    if player then
        if client ~= nil then
            local rank = 0
            local grbannerprint1 = "+--------------------------------------------------------------------------------------------------------"
            local grbannerprint2 = "|                      GorgeRun top scores for this map"
            local grbannerprint0 = "|"
            local mapname = Shared.GetMapName()
            NotifyPlayer(player, grbannerprint1)
            NotifyPlayer(player, grbannerprint2)
            NotifyPlayer(player, grbannerprint1)
            for i=1,30,3
            do
                rank = rank + 1
                if grstatsline[i] == nil then -- Just in case
                    grstatsline[i] = "10101010"
                    grstatsline[i+1] = "10101010"
                    grstatsline[i+2] = "10101010"
                end


                local grtime = grstatsline[i]
                local grname = grstatsline[i+1]
                local minutes = math.floor(grtime/60)
                local seconds = grtime - minutes*60
                NotifyPlayer(player, grbannerprint0)
                local GRMessage1 = string.format("|       #%d - %s completed the course with a total time of: %d:%02d", rank, grname, minutes, seconds)
                NotifyPlayer(player, GRMessage1)
            end
            NotifyPlayer(player, grbannerprint0)
            NotifyPlayer(player, grbannerprint1)
        end
    end
end


Event.Hook("Console_grstats", showgrstats)
