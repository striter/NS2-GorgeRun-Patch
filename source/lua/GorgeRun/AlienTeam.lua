function AlienTeam:Initialize(teamName, teamNumber)

    PlayingTeam.Initialize(self, teamName, teamNumber)

    ---------------------------------------------------------------------------------------------------------
        -- self.respawnEntity = Skulk.kMapName
    self.respawnEntity = Gorge.kMapName
    self.entranceTime = Shared.GetTime()   
    ---------------------------------------------------------------------------------------------


    -- List stores all the structures owned by builder player types such as the Gorge.
    -- This list stores them based on the player platform ID in order to maintain structure
    -- counts even if a player leaves and rejoins a server.
    self.clientOwnedStructures = { }
    self.clientStructuresOwner = { }
    self.lastAutoHealIndex = 1

    self.updateAlienArmorInTicks = nil

    self.timeLastWave = 0
    self.bioMassLevel = 0
    self.bioMassAlertLevel = 0
    self.maxBioMassLevel = 0
    self.bioMassFraction = 0

end
