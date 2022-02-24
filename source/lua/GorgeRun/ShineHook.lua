
if Shine then
    if Server then
        local PreGamePlugin = Shine.Plugins["pregame"]
        if PreGamePlugin then
            Shared.Message("[CNGR] Pregame Hooked")
            function PreGamePlugin:CheckGameStart( Gamerules )
                -- local State = Gamerules:GetGameState()
                -- if State > kGameState.PreGame then return end
            
                -- -- Do not allow starting too soon.
                -- local StartDelay = self.Config.StartDelayInSeconds
                -- if StartDelay > 0 and Shared.GetTime() < StartDelay then
                --     return false
                -- end
            
                -- self.UpdateFuncs[ PreGamePlugin.Modes.TIME ]( self, Gamerules )
            
                -- return false
            end
            
        end
    end
end