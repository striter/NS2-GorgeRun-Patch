Script.Load("lua/StaticTargetMixin.lua")

if Server then

------------------------------------------
-- Katzenfleisch's code for SentryGuns to target clogs
-------------------------------------------
    local oldClogOnInitialized = Clog.OnInitialized
    function Clog:OnInitialized()
        oldClogOnInitialized(self)
        InitMixin(self, StaticTargetMixin)
    end

--------------------------------------------
-- Katzenfleisch's code for Killing a clog if nothing is around
---------------------------------------------
 -- Callback
   -- @return true if it should be called again, false otherwise
   local kCallbackTick = 2
   local kNoGorgeRange = 30
   local function KillClogIfNoGorgeAround(self)
      local gorge_around = #GetEntitiesWithinRange("Gorge", self:GetOrigin(), kNoGorgeRange)

      if gorge_around == 0 then
         self:Kill()
         return false
      end
      return self:GetIsAlive()
   end

   local clogOnInitialized = Clog.OnInitialized
   function Clog:OnInitialized()
      if clogOnInitialized then -- Just a safety check
         clogOnInitialized(self)
      end
      -- Check once a second, should be fully enough
      Entity.AddTimedCallback(self, KillClogIfNoGorgeAround, kCallbackTick)
   end
end
