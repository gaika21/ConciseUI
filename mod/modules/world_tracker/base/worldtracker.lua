-- Copyright 2014-2019, Firaxis Games.
--	Hotloading note: The World Tracker button check now positions based on how many hooks are showing.
--	You'll need to save "LaunchBar" to see the tracker button appear.
include("InstanceManager");
include("TechAndCivicSupport");
include("SupportFunctions");
include("GameCapabilities");
include("ToolTipHelper"); -- CUI

g_TrackedItems = {}; -- Populated by WorldTrackerItems_* scripts;

include("WorldTrackerItem_", true);

-- Include self contained additional tabs
g_ExtraIconData = {};
include("CivicsTreeIconLoader_", true);
include("cui_helper"); -- CUI
include("cui_settings"); -- CUI

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "WorldTracker"; -- Must be unique (usually the same as the file name)
local CHAT_COLLAPSED_SIZE				:number = 99;
local MAX_BEFORE_TRUNC_TRACKER			:number = 180;
local MAX_BEFORE_TRUNC_CHECK			:number = 160;
local MAX_BEFORE_TRUNC_TITLE			:number = 225;
local LAUNCH_BAR_PADDING				:number = 50;
local STARTING_TRACKER_OPTIONS_OFFSET	:number = 75;
local WORLD_TRACKER_PANEL_WIDTH			:number = 300;


-- ===========================================================================
--	GLOBALS
-- ===========================================================================
g_TrackedInstances	= {};				-- Any instances created as a result of g_trackedItems

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_hideAll					:boolean = false;
local m_hideChat				:boolean = false;
local m_hideCivics				:boolean = false;
local m_hideResearch			:boolean = false;

local m_dropdownExpanded		:boolean = false;
local m_unreadChatMsgs			:number  = 0;		-- number of chat messages unseen due to the chat panel being hidden.

local m_researchInstance		:table	 = {};		-- Single instance wired up for the currently being researched tech
local m_civicsInstance			:table	 = {};		-- Single instance wired up for the currently being researched civic

-- CUI
local cui_gossipPanel = {};
local cui_gossipCount = 0;
local cui_gossipLogs  = {};

local cui_combatPanel = {};
local cui_combatCount = 0;
local cui_combatLogs  = {};

local cui_IsGossipTurnShown = false;
local cui_IsCombatTurnShown = false;

m_hideGossipLog = CuiSettings:GetBoolean(CuiSettings.HIDE_GOSSIP_LOG);
m_hideCombatLog = CuiSettings:GetBoolean(CuiSettings.HIDE_COMBAT_LOG);
local m_persistGossipLog = CuiSettings:GetBoolean(CuiSettings.GOSSIP_LOG_PERSIST);
local m_persistCombatLog = CuiSettings:GetBoolean(CuiSettings.COMBAT_LOG_PERSIST);
local cui_maxLog = 50;
local cui_LogPanelStatus:table = {};
cui_LogPanelStatus[1] = {main = 28,  log = 24};
cui_LogPanelStatus[2] = {main = 82,  log = 78};
cui_LogPanelStatus[3] = {main = 282, log = 278};
local cui_GossipState = CuiSettings:GetNumber(CuiSettings.GOSSIP_LOG_STATE);
local cui_CombatState = CuiSettings:GetNumber(CuiSettings.COMBAT_LOG_STATE);
--

local m_CachedModifiers			:table	 = {};

local m_currentResearchID		:number = -1;
local m_lastResearchCompletedID	:number = -1;
local m_currentCivicID			:number = -1;
local m_lastCivicCompletedID	:number = -1;
local m_isTrackerAlwaysCollapsed:boolean = false;	-- Once the launch bar extends past the width of the world tracker, we always show the collapsed version of the backing for the tracker element
local m_isDirty					:boolean = false;	-- Note: renamed from "refresh" which is a built in Forge mechanism; this is based on a gamecore event to check not frame update


-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================

-- ===========================================================================
--	The following are a accessors for Expansions/MODs so they can obtain status
--	of the common panels but don't have access to toggling them.
-- ===========================================================================
function IsChatHidden()			return m_hideChat;		end
function IsResearchHidden()		return m_hideResearch;	end
function IsCivicsHidden()		return m_hideCivics;	end

-- ===========================================================================
--	Checks all panels, static and dynamic as to whether or not they are hidden.
--	Returns true if they are.
-- ===========================================================================
function IsAllPanelsHidden()
	local isHide	:boolean = false;
	local uiChildren:table = Controls.PanelStack:GetChildren();
	for i,uiChild in ipairs(uiChildren) do
		if uiChild:IsVisible() then
			return false;
		end
	end
	return true;
end

-- ===========================================================================
function RealizeEmptyMessage()
	-- First a quick check if all native panels are hidden.
	if m_hideChat and m_hideCivics and m_hideResearch then
		local isAllPanelsHidden:boolean = IsAllPanelsHidden();	-- more expensive iteration
		Controls.EmptyPanel:SetHide( isAllPanelsHidden==false );
	else
		Controls.EmptyPanel:SetHide(true);
	end
end

-- ===========================================================================
function ToggleDropdown()
  if m_dropdownExpanded then
    m_dropdownExpanded = false;
    Controls.DropdownAnim:Reverse();
    Controls.DropdownAnim:Play();
    UI.PlaySound("Tech_Tray_Slide_Closed");
  else
    UI.PlaySound("Tech_Tray_Slide_Open");
    m_dropdownExpanded = true;
    Controls.DropdownAnim:SetToBeginning();
    Controls.DropdownAnim:Play();
  end
end

-- ===========================================================================
function ToggleAll(hideAll:boolean)

  -- Do nothing if value didn't change
  if m_hideAll == hideAll then return; end

  m_hideAll = hideAll;

  if(not hideAll) then
    Controls.PanelStack:SetHide(false);
    UI.PlaySound("Tech_Tray_Slide_Open");
  end

  Controls.ToggleAllButton:SetCheck(not m_hideAll);

	if ( not m_isTrackerAlwaysCollapsed) then
    Controls.TrackerHeading:SetHide(hideAll);
    Controls.TrackerHeadingCollapsed:SetHide(not hideAll);
  else
    Controls.TrackerHeading:SetHide(true);
    Controls.TrackerHeadingCollapsed:SetHide(false);
  end

  if( hideAll ) then
    UI.PlaySound("Tech_Tray_Slide_Closed");
    if( m_dropdownExpanded ) then
      Controls.DropdownAnim:SetToBeginning();
      m_dropdownExpanded = false;
    end
  end

  Controls.WorldTrackerAlpha:Reverse();
  Controls.WorldTrackerSlide:Reverse();
  CheckUnreadChatMessageCount();

  LuaEvents.WorldTracker_ToggleCivicPanel(m_hideCivics or m_hideAll);
  LuaEvents.WorldTracker_ToggleResearchPanel(m_hideResearch or m_hideAll);
end

-- ===========================================================================
function OnWorldTrackerAnimationFinished()
  if(m_hideAll) then
    Controls.PanelStack:SetHide(true);
  end
end

-- ===========================================================================
-- When the launch bar is resized, make sure to adjust the world tracker
-- button position/size to accommodate it
-- ===========================================================================
function OnLaunchBarResized( buttonStackSize: number)
	Controls.TrackerHeading:SetSizeX(buttonStackSize + LAUNCH_BAR_PADDING);
	Controls.TrackerHeadingCollapsed:SetSizeX(buttonStackSize + LAUNCH_BAR_PADDING);
	if( buttonStackSize > WORLD_TRACKER_PANEL_WIDTH - LAUNCH_BAR_PADDING) then
		m_isTrackerAlwaysCollapsed = true;
		Controls.TrackerHeading:SetHide(true);
		Controls.TrackerHeadingCollapsed:SetHide(false);
	else
		m_isTrackerAlwaysCollapsed = false;
		Controls.TrackerHeading:SetHide(m_hideAll);
		Controls.TrackerHeadingCollapsed:SetHide(not m_hideAll);
	end
	Controls.ToggleAllButton:SetOffsetX(buttonStackSize - 7);
end

-- ===========================================================================
function RealizeStack()
	Controls.PanelStack:CalculateSize();
	if(m_hideAll) then ToggleAll(true); end
end

-- ===========================================================================
function UpdateResearchPanel( isHideResearch:boolean )

  if not HasCapability("CAPABILITY_TECH_CHOOSER") then
    isHideResearch = true;
    Controls.ResearchCheck:SetHide(true);
  end

  if isHideResearch ~= nil then
    m_hideResearch = isHideResearch;
  end

  m_researchInstance.MainPanel:SetHide( m_hideResearch );
  Controls.ResearchCheck:SetCheck( not m_hideResearch );
  LuaEvents.WorldTracker_ToggleResearchPanel(m_hideResearch or m_hideAll);
  RealizeEmptyMessage();
  RealizeStack();

  -- Set the technology to show (or -1 if none)...
  local iTech			:number = m_currentResearchID;
  if m_currentResearchID == -1 then
    iTech = m_lastResearchCompletedID;
  end
  local ePlayer		:number = Game.GetLocalPlayer();
  local pPlayer		:table  = Players[ePlayer];
  local pPlayerTechs	:table	= pPlayer:GetTechs();
  local kTech			:table	= (iTech ~= -1) and GameInfo.Technologies[ iTech ] or nil;
  local kResearchData :table = GetResearchData( ePlayer, pPlayerTechs, kTech );
  if iTech ~= -1 then
    if m_currentResearchID == iTech then
      kResearchData.IsCurrent = true;
    elseif m_lastResearchCompletedID == iTech then
      kResearchData.IsLastCompleted = true;
    end
  end

  RealizeCurrentResearch( ePlayer, kResearchData, m_researchInstance);

  -- No tech started (or finished)
  if kResearchData == nil then
    m_researchInstance.TitleButton:SetHide( false );
    TruncateStringWithTooltip(m_researchInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, Locale.ToUpper(Locale.Lookup("LOC_WORLD_TRACKER_CHOOSE_RESEARCH")) );
  else
    -- CUI: add tooltip for research
    m_researchInstance.IconButton:SetToolTipString(Locale.Lookup(kResearchData.ToolTip));
  end
end

-- ===========================================================================
function UpdateCivicsPanel(hideCivics:boolean)

  local ePlayer:number = Game.GetLocalPlayer();
  if ePlayer == -1 then return; end	-- Autoplayer


  if not HasCapability("CAPABILITY_CIVICS_CHOOSER") then
    hideCivics = true;
    Controls.CivicsCheck:SetHide(true);
  end

  if hideCivics ~= nil then
    m_hideCivics = hideCivics;
  end

  m_civicsInstance.MainPanel:SetHide(m_hideCivics);
  Controls.CivicsCheck:SetCheck(not m_hideCivics);
  LuaEvents.WorldTracker_ToggleCivicPanel(m_hideCivics or m_hideAll);
  RealizeEmptyMessage();
  RealizeStack();

  -- Set the civic to show (or -1 if none)...
  local iCivic :number = m_currentCivicID;
  if iCivic == -1 then
    iCivic = m_lastCivicCompletedID;
  end
  local pPlayer		:table  = Players[ePlayer];
  local pPlayerCulture:table	= pPlayer:GetCulture();
  local kCivic		:table	= (iCivic ~= -1) and GameInfo.Civics[ iCivic ] or nil;
  local kCivicData	:table = GetCivicData( ePlayer, pPlayerCulture, kCivic );
  if iCivic ~= -1 then
    if m_currentCivicID == iCivic then
      kCivicData.IsCurrent = true;
    elseif m_lastCivicCompletedID == iCivic then
      kCivicData.IsLastCompleted = true;
    end
  end

  for _,iconData in pairs(g_ExtraIconData) do
    iconData:Reset();
  end
  RealizeCurrentCivic( ePlayer, kCivicData, m_civicsInstance, m_CachedModifiers );

  -- No civic started (or finished)
  if kCivicData == nil then
    m_civicsInstance.TitleButton:SetHide( false );
    TruncateStringWithTooltip(m_civicsInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, Locale.ToUpper(Locale.Lookup("LOC_WORLD_TRACKER_CHOOSE_CIVIC")) );
  else
    TruncateStringWithTooltip(m_civicsInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, m_civicsInstance.TitleButton:GetText() );
    -- CUI: add tooltip for civics
    m_civicsInstance.IconButton:SetToolTipString(Locale.Lookup(kCivicData.ToolTip));
  end
end

-- ===========================================================================
function UpdateChatPanel(hideChat:boolean)
  m_hideChat = hideChat;
  Controls.ChatPanel:SetHide(m_hideChat);
  Controls.ChatCheck:SetCheck(not m_hideChat);
  RealizeEmptyMessage();
  RealizeStack();

  CheckUnreadChatMessageCount();
end

-- ===========================================================================
function CheckUnreadChatMessageCount()
  -- Unhiding the chat panel resets the unread chat message count.
  if(not hideAll and not m_hideChat) then
    m_unreadChatMsgs = 0;
    UpdateUnreadChatMsgs();
    LuaEvents.WorldTracker_OnChatShown();
  end
end

-- ===========================================================================
function UpdateUnreadChatMsgs()
  if(GameConfiguration.IsPlayByCloud()) then
    Controls.ChatCheck:GetTextButton():SetText(Locale.Lookup("LOC_PLAY_BY_CLOUD_PANEL"));
  elseif(m_unreadChatMsgs > 0) then
    Controls.ChatCheck:GetTextButton():SetText(Locale.Lookup("LOC_HIDE_CHAT_PANEL_UNREAD_MESSAGES", m_unreadChatMsgs));
  else
    Controls.ChatCheck:GetTextButton():SetText(Locale.Lookup("LOC_HIDE_CHAT_PANEL"));
  end
end

-- ===========================================================================
--	Obtains full refresh and views most current research and civic IDs.
-- ===========================================================================
function Refresh()
  local localPlayer :number = Game.GetLocalPlayer();
  if localPlayer < 0 then
    ToggleAll(true);
    return;
  end

  local pPlayerTechs :table = Players[localPlayer]:GetTechs();
  m_currentResearchID = pPlayerTechs:GetResearchingTech();

  -- Only reset last completed tech once a new tech has been selected
  if m_currentResearchID >= 0 then
    m_lastResearchCompletedID = -1;
  end

  UpdateResearchPanel();


  local pPlayerCulture:table = Players[localPlayer]:GetCulture();
  m_currentCivicID = pPlayerCulture:GetProgressingCivic();

  -- Only reset last completed civic once a new civic has been selected
  if m_currentCivicID >= 0 then
    m_lastCivicCompletedID = -1;
  end

  UpdateCivicsPanel();

  -- Hide world tracker by default if there are no tracker options enabled
	if IsAllPanelsHidden() then
    ToggleAll(true);
  end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnLocalPlayerTurnBegin()
  local localPlayer = Game.GetLocalPlayer();
  if localPlayer ~= -1 then
    m_isDirty = true;
  end
  -- CUI
  cui_IsGossipTurnShown = false;
  cui_IsCombatTurnShown = false;
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCityInitialized( playerID:number, cityID:number )
  if playerID == Game.GetLocalPlayer() then
    m_isDirty = true;
  end
end

-- ===========================================================================
--	GAME EVENT
--	Buildings can change culture/science yield which can effect
--	"turns to complete" values
-- ===========================================================================
function OnBuildingChanged( plotX:number, plotY:number, buildingIndex:number, playerID:number, cityID:number, iPercentComplete:number )
  if playerID == Game.GetLocalPlayer() then
    m_isDirty = true;
  end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnDirtyCheck()
	if m_isDirty then
		Refresh();
		m_isDirty = false;
	end
end

-- ===========================================================================
--	GAME EVENT
--	A civic item has changed, this may not be the current civic item
--	but an item deeper in the tree that was just boosted by a player action.
-- ===========================================================================
function OnCivicChanged( ePlayer:number, eCivic:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		ResetOverflowArrow( m_civicsInstance );
		local pPlayerCulture:table = Players[localPlayer]:GetCulture();
		m_currentCivicID = pPlayerCulture:GetProgressingCivic();
		m_lastCivicCompletedID = -1;
		if eCivic == m_currentCivicID then
			UpdateCivicsPanel();
		end
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCivicCompleted( ePlayer:number, eCivic:number )
  local localPlayer = Game.GetLocalPlayer();
  if localPlayer ~= -1 and localPlayer == ePlayer then
    m_currentCivicID = -1;
    m_lastCivicCompletedID = eCivic;
    UpdateCivicsPanel();
  end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCultureYieldChanged( ePlayer:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
    UpdateCivicsPanel();
  end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnInterfaceModeChanged(eOldMode:number, eNewMode:number)
	if eNewMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		ContextPtr:SetHide(true);
	end
	if eOldMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		ContextPtr:SetHide(false);
	end
end

-- ===========================================================================
--	GAME EVENT
--	A research item has changed, this may not be the current researched item
--	but an item deeper in the tree that was just boosted by a player action.
-- ===========================================================================
function OnResearchChanged( ePlayer:number, eTech:number )
	if ShouldUpdateResearchPanel(ePlayer, eTech) then
		ResetOverflowArrow( m_researchInstance );
		UpdateResearchPanel();
	end
end

-- ===========================================================================
--	This function was separated so behavior can be modified in mods/expasions
-- ===========================================================================
function ShouldUpdateResearchPanel(ePlayer:number, eTech:number)
  local localPlayer = Game.GetLocalPlayer();

  if localPlayer ~= -1 and localPlayer == ePlayer then
    local pPlayerTechs :table = Players[localPlayer]:GetTechs();
    m_currentResearchID = pPlayerTechs:GetResearchingTech();

    -- Only reset last completed tech once a new tech has been selected
    if m_currentResearchID >= 0 then
      m_lastResearchCompletedID = -1;
    end

    if eTech == m_currentResearchID then
      return true;
    end
  end
	return false;
end

-- ===========================================================================
function OnResearchCompleted( ePlayer:number, eTech:number )
	if (ePlayer == Game.GetLocalPlayer()) then
		m_currentResearchID = -1;
		m_lastResearchCompletedID = eTech;
		UpdateResearchPanel();
	end
end

-- ===========================================================================
function OnResearchYieldChanged( ePlayer:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		UpdateResearchPanel();
	end
end


-- ===========================================================================
function OnMultiplayerChat( fromPlayer, toPlayer, text, eTargetType )
	-- If the chat panels are hidden, indicate there are unread messages waiting on the world tracker panel toggler.
	if(m_hideAll or m_hideChat) then
		m_unreadChatMsgs = m_unreadChatMsgs + 1;
		UpdateUnreadChatMsgs();
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnInit(isReload:boolean)
	LateInitialize();
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	else
		Refresh();	-- Standard refresh.
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnShutdown()
	Unsubscribe();

	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentResearchID",		m_currentResearchID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_lastResearchCompletedID",	m_lastResearchCompletedID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentCivicID",			m_currentCivicID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_lastCivicCompletedID",		m_lastCivicCompletedID);
end

-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
  if context == RELOAD_CACHE_ID then
    m_currentResearchID			= contextTable["m_currentResearchID"];
    m_lastResearchCompletedID	= contextTable["m_lastResearchCompletedID"];
    m_currentCivicID			= contextTable["m_currentCivicID"];
    m_lastCivicCompletedID		= contextTable["m_lastCivicCompletedID"];

    if m_currentResearchID == nil		then m_currentResearchID = -1; end
    if m_lastResearchCompletedID == nil then m_lastResearchCompletedID = -1; end
    if m_currentCivicID == nil			then m_currentCivicID = -1; end
    if m_lastCivicCompletedID == nil	then m_lastCivicCompletedID = -1; end

    -- Don't call refresh, use cached data from last hotload.
    UpdateResearchPanel();
    UpdateCivicsPanel();
  end
end

-- ===========================================================================
function OnTutorialGoalsShowing()
  RealizeStack();
end

-- ===========================================================================
function OnTutorialGoalsHiding()
  RealizeStack();
end

-- ===========================================================================
function Tutorial_ShowFullTracker()
  Controls.ToggleAllButton:SetHide(true);
  Controls.ToggleDropdownButton:SetHide(true);
  UpdateCivicsPanel(false);
  UpdateResearchPanel(false);
  ToggleAll(false);
end

-- ===========================================================================
function Tutorial_ShowTrackerOptions()
  Controls.ToggleAllButton:SetHide(false);
  Controls.ToggleDropdownButton:SetHide(false);
end

-- FF16 ======================================================================
function Test()
  local msg:string = "This is a text message.[NEWLINE]asdlfjlkadsjfl";
  LuaEvents.Custom_GossipMessage(msg, 10, ReportingStatusTypes.GOSSIP );
  LuaEvents.Custom_GossipMessage(msg, 10, ReportingStatusTypes.DEFAULT );


  ContextPtr:SetInputHandler(
    function( pInputStruct )
      local uiMsg = pInputStruct:GetMessageType();
      if uiMsg == KeyEvents.KeyUp then
        local key = pInputStruct:GetKey();
        if key == Keys.G then
          LuaEvents.Custom_GossipMessage(msg, 10, ReportingStatusTypes.GOSSIP );
          LuaEvents.Custom_GossipMessage(msg, 10, ReportingStatusTypes.DEFAULT );
          return true;
        end
      end
      return false;
    end,
  true);
end


-- ===========================================================================
--	CUI World Tracker Functions
-- ===========================================================================

-- CUI =======================================================================
function CuiUpdateLog(logString, displayTime, logType)

  if     (logType == ReportingStatusTypes.GOSSIP)  and (not cui_IsGossipTurnShown) then
    CuiAddNewLog(nil, logType);
    cui_IsGossipTurnShown = true;
  elseif (logType == ReportingStatusTypes.DEFAULT) and (not cui_IsCombatTurnShown) then
    CuiAddNewLog(nil, logType);
    cui_IsCombatTurnShown = true;
  end

  CuiAddNewLog(logString, logType);
end

-- CUI =======================================================================
function CuiAddNewLog(logString, logType)
  local logPanel, entries, counter = nil;
  if     logType == ReportingStatusTypes.GOSSIP then
    logPanel = cui_gossipPanel;
    entries  = cui_gossipLogs;
    if logString then cui_gossipCount = cui_gossipCount + 1; end
    counter  = cui_gossipCount;
  elseif logType == ReportingStatusTypes.DEFAULT then
    logPanel = cui_combatPanel;
    entries  = cui_combatLogs;
    if logString then cui_combatCount = cui_combatCount + 1; end
    counter  = cui_combatCount;
  else
    return;
  end

  local instance = {};
  ContextPtr:BuildInstanceForControl( "LogInstance", instance, logPanel.LogStack );

  if logString == nil then
    local turnLookup = Locale.Lookup("{LOC_TOP_PANEL_CURRENT_TURN:upper} ");
    logString = "[COLOR_FLOAT_GOLD]" .. turnLookup  .. Game.GetCurrentGameTurn() .. "[ENDCOLOR]";
  else
    logPanel.NewLogNumber:SetText("[ICON_NEW] " .. counter);
  end
  instance.String:SetText(logString);
  instance.LogRoot:SetSizeY(instance.String:GetSizeY() + 6);

  table.insert(entries, instance);

  -- Remove the earliest entry if the log limit has been reached
  if #entries > cui_maxLog then
    logPanel.LogStack:ReleaseChild(entries[1].LogRoot);
    table.remove(entries, 1);
  end

  -- Refresh log and reprocess size
  logPanel.LogStack:CalculateSize();
  logPanel.LogStack:ReprocessAnchoring();

end

-- CUI =======================================================================
function CuiClearLogs()
  if not(m_persistCombatLog) then
    CuiClearLogPanel(cui_gossipPanel, cui_gossipLogs);
  end
  cui_gossipCount = 0;
  cui_gossipPanel.NewLogNumber:SetText("");

  if not(m_persistGossipLog) then
    CuiClearLogPanel(cui_combatPanel, cui_combatLogs);
  end
  cui_combatCount = 0;
  cui_combatPanel.NewLogNumber:SetText("");
end

-- CUI =======================================================================
function CuiClearLogPanel(instance, entryInstance)
  for i = 1, table.count(entryInstance) do
    instance.LogStack:ReleaseChild( entryInstance[i].LogRoot);
  end
  entryInstance = {};
  instance.NewLogNumber:SetText("");
  instance.LogStack:CalculateSize();
  instance.LogStack:ReprocessAnchoring();
end

-- CUI =======================================================================
function CuiLogPanelResize(instance, state:number)
  local status:table = cui_LogPanelStatus[state];
  instance.MainPanel:SetSizeY(status.main);
  instance.LogPanel :SetSizeY(status.log);
  instance.LogStack :SetHide(state == 1);
  instance.ButtomDivider:SetHide(state == 1);
end

-- CUI =======================================================================
function CuiContractGossipLog()
  cui_GossipState = cui_GossipState - 1;
  if cui_GossipState == 0 then cui_GossipState = 3 end;
  CuiSettings:SetNumber(CuiSettings.GOSSIP_LOG_STATE, cui_GossipState);
  CuiLogPanelResize(cui_gossipPanel, cui_GossipState);
end

-- CUI =======================================================================
function CuiExpandGossipLog()
  cui_GossipState = cui_GossipState + 1;
  if cui_GossipState == 4 then cui_GossipState = 1 end;
  CuiSettings:SetNumber(CuiSettings.GOSSIP_LOG_STATE, cui_GossipState);
  CuiLogPanelResize(cui_gossipPanel, cui_GossipState);
end

-- CUI =======================================================================
function CuiContractCombatLog()
  cui_CombatState = cui_CombatState - 1;
  if cui_CombatState == 0 then cui_CombatState = 3 end;
  CuiSettings:SetNumber(CuiSettings.COMBAT_LOG_STATE, cui_CombatState);
  CuiLogPanelResize(cui_combatPanel, cui_CombatState);
end

-- CUI =======================================================================
function CuiExpandCombatLog()
  cui_CombatState = cui_CombatState + 1;
  if cui_CombatState == 4 then cui_CombatState = 1 end;
  CuiSettings:SetNumber(CuiSettings.COMBAT_LOG_STATE, cui_CombatState);
  CuiLogPanelResize(cui_combatPanel, cui_CombatState);
end

-- CUI =======================================================================
function CuiOnLogCheckClick()
  m_hideGossipLog = not Controls.GossipLogCheck:IsChecked();
  m_hideCombatLog = not Controls.CombatLogCheck:IsChecked();
  CuiSettings:SetBoolean(CuiSettings.HIDE_GOSSIP_LOG, m_hideGossipLog);
  CuiSettings:SetBoolean(CuiSettings.HIDE_COMBAT_LOG, m_hideCombatLog);
  cui_gossipPanel.MainPanel:SetHide(m_hideGossipLog);
  cui_combatPanel.MainPanel:SetHide(m_hideCombatLog);
  LuaEvents.CuiLogChange();
  RealizeEmptyMessage();
  RealizeStack();
end

-- CUI =======================================================================
function CuiOnPersistClick()
  m_persistGossipLog = Controls.GossipPersistCheck:IsChecked();
  m_persistCombatLog = Controls.GossipPersistCheck:IsChecked();
  CuiSettings:SetBoolean(CuiSettings.GOSSIP_LOG_PERSIST, m_persistGossipLog);
  CuiSettings:SetBoolean(CuiSettings.COMBAT_LOG_PERSIST, m_persistCombatLog);
end

-- CUI =======================================================================
function CuiOnReminderClick()
  local bTechRemind:boolean = Controls.TechReminderCheck:IsChecked();
  local bCivicsRemind:boolean = Controls.CivicsReminderCheck:IsChecked();
  CuiSettings:SetBoolean(CuiSettings.TECK_REMINDER, bTechRemind);
  CuiSettings:SetBoolean(CuiSettings.CIVICS_REMINDER, bCivicsRemind);
  Refresh();
end

-- CUI =======================================================================
function CuiInit()

  ContextPtr:BuildInstanceForControl( "GossipLogInstance", cui_gossipPanel,	Controls.PanelStack );
  ContextPtr:BuildInstanceForControl( "CombatLogInstance", cui_combatPanel,	Controls.PanelStack );

  cui_gossipPanel.MainPanel:SetHide(m_hideGossipLog);
  cui_combatPanel.MainPanel:SetHide(m_hideCombatLog);

  CuiRegCallback(cui_gossipPanel.TitleButton,
    CuiExpandGossipLog,
    CuiContractGossipLog
  );
  CuiRegCallback(cui_combatPanel.TitleButton,
    CuiExpandCombatLog,
    CuiContractCombatLog
  );

  CuiLogPanelResize(cui_combatPanel, cui_CombatState);
  CuiLogPanelResize(cui_gossipPanel, cui_GossipState);

  Controls.GossipLogCheck     :SetCheck(not CuiSettings:GetBoolean(CuiSettings.HIDE_GOSSIP_LOG));
  Controls.GossipLogCheck     :RegisterCheckHandler(CuiOnLogCheckClick);
  Controls.GossipPersistCheck :SetCheck(CuiSettings:GetBoolean(CuiSettings.GOSSIP_LOG_PERSIST));
  Controls.GossipPersistCheck :RegisterCheckHandler(CuiOnPersistClick);

  Controls.CombatLogCheck     :SetCheck(not CuiSettings:GetBoolean(CuiSettings.HIDE_COMBAT_LOG));
  Controls.CombatLogCheck     :RegisterCheckHandler(CuiOnLogCheckClick);
  Controls.CombatPersistCheck :SetCheck(CuiSettings:GetBoolean(CuiSettings.COMBAT_LOG_PERSIST));
  Controls.CombatPersistCheck :RegisterCheckHandler(CuiOnPersistClick);

  Controls.TechReminderCheck  :SetCheck(CuiSettings:GetBoolean(CuiSettings.TECK_REMINDER));
  Controls.TechReminderCheck  :RegisterCheckHandler(CuiOnReminderClick);
  Controls.CivicsReminderCheck:SetCheck(CuiSettings:GetBoolean(CuiSettings.CIVICS_REMINDER));
  Controls.CivicsReminderCheck:RegisterCheckHandler(CuiOnReminderClick);
end

-- ===========================================================================
-- Handling chat panel expansion
-- ===========================================================================
function OnChatPanel_OpenExpandedPanels()
	--[[ TODO: Embiggen the chat panel to fill size!  (Requires chat panel changes as well) ??TRON
	Controls.ChatPanel:SetHide(true);							-- Hide so it's not part of stack computation.
	RealizeStack();
	width, height				= UIManager:GetScreenSizeVal();
	local stackSize		:number	= Controls.PanelStack:GetSizeY();	-- Size of other stuff in the stack.
	local minimapSize	:number = 100;
	local chatSize		:number = math.max(199, height-(stackSize + minimapSize) );
	Controls.ChatPanel:SetHide(false);
	]]
	Controls.ChatPanel:SetSizeY(199);
	RealizeStack();
end

function OnChatPanel_CloseExpandedPanels()
	Controls.ChatPanel:SetSizeY( CHAT_COLLAPSED_SIZE );
	RealizeStack();
end

-- ===========================================================================
--	Add any UI from tracked items that are loaded.
--	Items are expected to be tables with the following fields:
--		Name			localization key for the title name of panel
--		InstanceType	the instance (in XML) to create for the control
--		SelectFunc		if instance has "IconButton" the callback when pressed
-- ===========================================================================
function AttachDynamicUI()
	for i,kData in ipairs(g_TrackedItems) do
		local uiInstance:table = {};
		ContextPtr:BuildInstanceForControl( kData.InstanceType, uiInstance, Controls.PanelStack );
		if uiInstance.IconButton then
			uiInstance.IconButton:RegisterCallback(Mouse.eLClick, function() kData.SelectFunc() end);
		end
		table.insert(g_TrackedInstances, uiInstance);

		if(uiInstance.TitleButton) then
			uiInstance.TitleButton:LocalizeAndSetText(kData.Name);
		end
	end
end

-- ===========================================================================
function OnForceHide()
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function OnForceShow()
	ContextPtr:SetHide(false);
end

-- ===========================================================================
function Subscribe()
	Events.CityInitialized.Add(OnCityInitialized);
	Events.BuildingChanged.Add(OnBuildingChanged);
	Events.CivicChanged.Add(OnCivicChanged);
	Events.CivicCompleted.Add(OnCivicCompleted);
	Events.CultureYieldChanged.Add(OnCultureYieldChanged);
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
	Events.LocalPlayerTurnBegin.Add(OnLocalPlayerTurnBegin);
	Events.MultiplayerChat.Add( OnMultiplayerChat );
	Events.ResearchChanged.Add(OnResearchChanged);
	Events.ResearchCompleted.Add(OnResearchCompleted);
	Events.ResearchYieldChanged.Add(OnResearchYieldChanged);
	Events.GameCoreEventPublishComplete.Add( OnDirtyCheck ); --This event is raised directly after a series of gamecore events.
	LuaEvents.LaunchBar_Resize.Add(OnLaunchBarResized);

	LuaEvents.CivicChooser_ForceHideWorldTracker.Add(	OnForceHide );
	LuaEvents.CivicChooser_RestoreWorldTracker.Add(		OnForceShow);
	LuaEvents.ResearchChooser_ForceHideWorldTracker.Add(OnForceHide);
	LuaEvents.ResearchChooser_RestoreWorldTracker.Add(	OnForceShow);
	LuaEvents.Tutorial_ForceHideWorldTracker.Add(		OnForceHide);
	LuaEvents.Tutorial_RestoreWorldTracker.Add(			Tutorial_ShowFullTracker);
	LuaEvents.Tutorial_EndTutorialRestrictions.Add(		Tutorial_ShowTrackerOptions);
	LuaEvents.TutorialGoals_Showing.Add(				OnTutorialGoalsShowing );
	LuaEvents.TutorialGoals_Hiding.Add(					OnTutorialGoalsHiding );
	LuaEvents.ChatPanel_OpenExpandedPanels.Add(			OnChatPanel_OpenExpandedPanels);
	LuaEvents.ChatPanel_CloseExpandedPanels.Add(		OnChatPanel_CloseExpandedPanels);
end

-- ===========================================================================
function Unsubscribe()
	Events.CityInitialized.Remove(OnCityInitialized);
	Events.BuildingChanged.Remove(OnBuildingChanged);
	Events.CivicChanged.Remove(OnCivicChanged);
	Events.CivicCompleted.Remove(OnCivicCompleted);
	Events.CultureYieldChanged.Remove(OnCultureYieldChanged);
	Events.InterfaceModeChanged.Remove( OnInterfaceModeChanged );
	Events.LocalPlayerTurnBegin.Remove(OnLocalPlayerTurnBegin);
	Events.MultiplayerChat.Remove( OnMultiplayerChat );
	Events.ResearchChanged.Remove(OnResearchChanged);
	Events.ResearchCompleted.Remove(OnResearchCompleted);
	Events.ResearchYieldChanged.Remove(OnResearchYieldChanged);
	Events.GameCoreEventPublishComplete.Remove( OnDirtyCheck ); --This event is raised directly after a series of gamecore events.
	LuaEvents.LaunchBar_Resize.Remove(OnLaunchBarResized);

	LuaEvents.CivicChooser_ForceHideWorldTracker.Remove(	OnForceHide );
	LuaEvents.CivicChooser_RestoreWorldTracker.Remove(		OnForceShow);
	LuaEvents.ResearchChooser_ForceHideWorldTracker.Remove(	OnForceHide);
	LuaEvents.ResearchChooser_RestoreWorldTracker.Remove(	OnForceShow);
	LuaEvents.Tutorial_ForceHideWorldTracker.Remove(		OnForceHide);
	LuaEvents.Tutorial_RestoreWorldTracker.Remove(			Tutorial_ShowFullTracker);
	LuaEvents.Tutorial_EndTutorialRestrictions.Remove(		Tutorial_ShowTrackerOptions);
	LuaEvents.TutorialGoals_Showing.Remove(					OnTutorialGoalsShowing );
	LuaEvents.TutorialGoals_Hiding.Remove(					OnTutorialGoalsHiding );
	LuaEvents.ChatPanel_OpenExpandedPanels.Remove(			OnChatPanel_OpenExpandedPanels);
	LuaEvents.ChatPanel_CloseExpandedPanels.Remove(			OnChatPanel_CloseExpandedPanels);
end

-- ===========================================================================
function LateInitialize()

	Subscribe();

	-- InitChatPanel
	if(UI.HasFeature("Chat")
		and (GameConfiguration.IsNetworkMultiplayer() or GameConfiguration.IsPlayByCloud()) ) then
		UpdateChatPanel(false);
	else
		UpdateChatPanel(true);
		Controls.ChatCheck:SetHide(true);
	end

	UpdateUnreadChatMsgs();
	AttachDynamicUI();
end

-- ===========================================================================
function Initialize()

	if not GameCapabilities.HasCapability("CAPABILITY_WORLD_TRACKER") then
		ContextPtr:SetHide(true);
		return;
	end

	m_CachedModifiers = TechAndCivicSupport_BuildCivicModifierCache();

	-- Create semi-dynamic instances; hack: change parent back to self for ordering:
	ContextPtr:BuildInstanceForControl( "ResearchInstance", m_researchInstance, Controls.PanelStack );
	ContextPtr:BuildInstanceForControl( "CivicInstance",	m_civicsInstance,	Controls.PanelStack );
	m_researchInstance.IconButton:RegisterCallback(	Mouse.eLClick,	function() LuaEvents.WorldTracker_OpenChooseResearch(); end);
	m_civicsInstance.IconButton:RegisterCallback(	Mouse.eLClick,	function() LuaEvents.WorldTracker_OpenChooseCivic(); end);

  CuiInit(); -- CUI

	Controls.ChatPanel:ChangeParent( Controls.PanelStack );
  Controls.TutorialGoals:ChangeParent( Controls.PanelStack );

	-- Handle any text overflows with truncation and tooltip
	local fullString :string = Controls.WorldTracker:GetText();
	Controls.DropdownScroll:SetOffsetY(Controls.WorldTrackerHeader:GetSizeY() + STARTING_TRACKER_OPTIONS_OFFSET);

	-- Hot-reload events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
  LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);

  -- CUI
  Events.StatusMessage.Add( CuiUpdateLog );
  Events.LocalPlayerTurnEnd.Add( CuiClearLogs);
  -- LuaEvents.Custom_GossipMessage.Add(CuiUpdateLog);
  -- Test();
  --

	Controls.ChatCheck:SetCheck(true);
	Controls.CivicsCheck:SetCheck(true);
	Controls.ResearchCheck:SetCheck(true);
	Controls.ToggleAllButton:SetCheck(true);

	Controls.ChatCheck:RegisterCheckHandler(						function() UpdateChatPanel(not m_hideChat); end);
	Controls.CivicsCheck:RegisterCheckHandler(						function() UpdateCivicsPanel(not m_hideCivics); end);
	Controls.ResearchCheck:RegisterCheckHandler(					function() UpdateResearchPanel(not m_hideResearch); end);
	Controls.ToggleAllButton:RegisterCheckHandler(					function() ToggleAll(not Controls.ToggleAllButton:IsChecked()) end);
	Controls.ToggleDropdownButton:RegisterCallback(	Mouse.eLClick, ToggleDropdown);
	Controls.WorldTrackerAlpha:RegisterEndCallback( OnWorldTrackerAnimationFinished );
end
Initialize();