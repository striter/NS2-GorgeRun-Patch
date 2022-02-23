-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIPlayerResource.lua
--
-- Created by: Andreas Urwalek (a_urwa@sbox.tugraz.at)
--
-- Displays team and personal resources. Everytime resources are being added, the numbers pulsate
-- x times, where x is the amount of resource towers.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

class 'GUIPlayerResource'

GUIPlayerResource.kPersonalResourceIcon = { Width = 0, Height = 0, X = 0, Y = 0 }
GUIPlayerResource.kPersonalResourceIcon.Width = 32
GUIPlayerResource.kPersonalResourceIcon.Height = 64

GUIPlayerResource.kPersonalResourceIconSize = Vector(GUIPlayerResource.kPersonalResourceIcon.Width, GUIPlayerResource.kPersonalResourceIcon.Height, 0)
GUIPlayerResource.kPersonalResourceIconSizeBig = Vector(GUIPlayerResource.kPersonalResourceIcon.Width, GUIPlayerResource.kPersonalResourceIcon.Height, 0) * 1.1

GUIPlayerResource.kPersonalIconPos = Vector(30,-4,0)
GUIPlayerResource.kPersonalTextPos = Vector(100,4,0)
GUIPlayerResource.kPresDescriptionPos = Vector(110,4,0)
GUIPlayerResource.kResGainedTextPos = Vector(90,-6,0)

GUIPlayerResource.kTeam1TextPos = Vector(20, 360, 0)
GUIPlayerResource.kTeam2TextPos = Vector(20, 540, 0)

GUIPlayerResource.kIconTextXOffset = -20

GUIPlayerResource.kFontSizePersonal = 30
GUIPlayerResource.kFontSizePersonalBig = 30

GUIPlayerResource.kPulseTime = 0.5

GUIPlayerResource.kFontSizePresDescription = 18
GUIPlayerResource.kFontSizeResGained = 25
GUIPlayerResource.kFontSizeTeam = 18
GUIPlayerResource.kTextFontName = Fonts.kAgencyFB_Small
GUIPlayerResource.kTresTextFontName = Fonts.kAgencyFB_Small
GUIPlayerResource.kResGainedFontName = Fonts.kAgencyFB_Small

local kBackgroundTextures = { alien = PrecacheAsset("ui/alien_HUD_presbg.dds"), marine = PrecacheAsset("ui/marine_HUD_presbg.dds") }

local kPresIcons = { alien = PrecacheAsset("ui/alien_HUD_presicon.dds"), marine = PrecacheAsset("ui/marine_HUD_presicon.dds") }

GUIPlayerResource.kBackgroundSize = Vector(280, 58, 0)
GUIPlayerResource.kBackgroundPos = Vector(-320, -100, 0)

function CreatePlayerResourceDisplay(scriptHandle, hudLayer, frame, style, teamNum)

    local playerResource = GUIPlayerResource()
    playerResource.script = scriptHandle
    playerResource.hudLayer = hudLayer
    playerResource.frame = frame
    playerResource:Initialize(style, teamNum)
    
    return playerResource
    
end

function GUIPlayerResource:Initialize(style, teamNumber)

    self.style = style
    self.teamNumber = teamNumber
    self.scale = 1
    
    self.lastPersonalResources = 0
    
    -- Background.
    self.background = self.script:CreateAnimatedGraphicItem()
    self.background:SetAnchor(GUIItem.Right, GUIItem.Bottom)
    self.background:SetTexture(kBackgroundTextures[style.textureSet])
    self.background:AddAsChildTo(self.frame)
    
    -- Personal display.
    self.personalIcon = self.script:CreateAnimatedGraphicItem()
    self.personalIcon:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.personalIcon:SetTexture(kPresIcons[style.textureSet])
    ---------------------------------------------------------------------------------------
    -- self.background:AddChild(self.personalIcon)
    ---------------------------------------------------------------------------------------
    
    self.personalText = self.script:CreateAnimatedTextItem()
    self.personalText:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.personalText:SetTextAlignmentX(GUIItem.Align_Max)
    self.personalText:SetTextAlignmentY(GUIItem.Align_Center)
    self.personalText:SetColor(style.textColor)
    self.personalText:SetFontIsBold(true)
    self.personalText:SetFontName(GUIPlayerResource.kTextFontName)
    self.background:AddChild(self.personalText)
    
    self.pResDescription = self.script:CreateAnimatedTextItem()
    self.pResDescription:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.pResDescription:SetTextAlignmentX(GUIItem.Align_Min)
    self.pResDescription:SetTextAlignmentY(GUIItem.Align_Center)
    -----------------------------------------------------------------------
    --  self.pResDescription:SetColor(style.textColor)
    self.pResDescription:SetColor(Color(255/255, 20/255, 20/255, 1))
    -------------------------------------------------------------------------
    self.pResDescription:SetFontIsBold(true)
    self.pResDescription:SetFontName(GUIPlayerResource.kTextFontName)
    ----------------------------------------------
    --   self.pResDescription:SetText(Locale.ResolveString("RESOURCES"))
    self.pResDescription:SetText(": GORGE RUN TIMER")
    -----------------------------------------------------
    self.background:AddChild(self.pResDescription)
    
    self.ResGainedText = self.script:CreateAnimatedTextItem()
    self.ResGainedText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.ResGainedText:SetScale(GetScaledVector())
    self.ResGainedText:SetTextAlignmentX(GUIItem.Align_Max)
    self.ResGainedText:SetTextAlignmentY(GUIItem.Align_Max)
    self.ResGainedText:SetColor(style.textColor)
    self.ResGainedText:SetFontIsBold(false)
    self.ResGainedText:SetBlendTechnique(GUIItem.Add)
    self.ResGainedText:SetFontName(GUIPlayerResource.kResGainedFontName)
    self.ResGainedText:SetText("+")
    self.background:AddChild(self.ResGainedText)
    
end

function GUIPlayerResource:Reset(scale)

    self.scale = scale

    self.background:SetUniformScale(self.scale)
    self.background:SetPosition(GUIPlayerResource.kBackgroundPos)
    self.background:SetSize(GUIPlayerResource.kBackgroundSize)
    
    self.personalIcon:SetUniformScale(self.scale)
    self.personalIcon:SetSize(Vector(GUIPlayerResource.kPersonalResourceIcon.Width, GUIPlayerResource.kPersonalResourceIcon.Height, 0))
    self.personalIcon:SetPosition(GUIPlayerResource.kPersonalIconPos)
    
    self.personalText:SetScale(Vector(1,1,1) * self.scale * 1.2)
    self.personalText:SetFontSize(GUIPlayerResource.kFontSizePersonal)
    self.personalText:SetPosition(GUIPlayerResource.kPersonalTextPos)
    self.personalText:SetFontName(GUIPlayerResource.kTextFontName)
    GUIMakeFontScale(self.personalText)
   
    self.pResDescription:SetScale(Vector(1,1,1) * self.scale * 1.2)
    self.pResDescription:SetFontSize(GUIPlayerResource.kFontSizePresDescription)
    self.pResDescription:SetPosition(GUIPlayerResource.kPresDescriptionPos)
    self.pResDescription:SetFontName(GUIPlayerResource.kTextFontName)
    GUIMakeFontScale(self.pResDescription)
    
    self.ResGainedText:SetUniformScale(self.scale)
    self.ResGainedText:SetPosition(GUIPlayerResource.kResGainedTextPos)
    self.ResGainedText:SetFontName(GUIPlayerResource.kResGainedFontName)
    GUIMakeFontScale(self.ResGainedText)

end

function GUIPlayerResource:Update(_, parameters)

    PROFILE("GUIPlayerResource:Update")
    
    local tRes, pRes, numRTs = parameters[1], parameters[2], parameters[3]
    
    self.personalText:SetText(ToString(math.floor(pRes * 10) / 10))
    if pRes > self.lastPersonalResources then

        self.ResGainedText:DestroyAnimations()
        self.ResGainedText:SetColor(self.style.textColor)
        self.ResGainedText:FadeOut(2)
        
        self.lastPersonalResources = pRes
        self.pulseLeft = 1
        
        self.personalText:SetFontSize(GUIPlayerResource.kFontSizePersonalBig)
        self.personalText:SetFontSize(GUIPlayerResource.kFontSizePersonal, GUIPlayerResource.kPulseTime, "RES_PULSATE")
        self.personalText:SetColor(Color(1,1,1,1))
        self.personalText:SetColor(self.style.textColor, GUIPlayerResource.kPulseTime)
        
        self.personalIcon:DestroyAnimations()
        self.personalIcon:SetSize(GUIPlayerResource.kPersonalResourceIconSizeBig)
        self.personalIcon:SetSize(GUIPlayerResource.kPersonalResourceIconSize, GUIPlayerResource.kPulseTime,  nil, AnimateQuadratic)
        
    end

end

function GUIPlayerResource:OnAnimationCompleted(animatedItem, animationName, itemHandle)

    if animationName == "RES_PULSATE" then
    
        if self.pulseLeft > 0 then
        
            self.personalText:SetFontSize(GUIPlayerResource.kFontSizePersonalBig)
            self.personalText:SetFontSize(GUIPlayerResource.kFontSizePersonal, GUIPlayerResource.kPulseTime, "RES_PULSATE", AnimateQuadratic)
            self.personalText:SetColor(Color(1, 1, 1, 1))
            self.personalText:SetColor(self.style.textColor, GUIPlayerResource.kPulseTime)
            
            self.personalIcon:DestroyAnimations()
            self.personalIcon:SetSize(GUIPlayerResource.kPersonalResourceIconSizeBig)
            self.personalIcon:SetSize(GUIPlayerResource.kPersonalResourceIconSize, GUIPlayerResource.kPulseTime,  nil, AnimateQuadratic)
            
            self.pulseLeft = self.pulseLeft - 1
            
        end
        
    end
    
end

function GUIPlayerResource:Destroy()
end