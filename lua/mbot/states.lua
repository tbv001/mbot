--[[----------------------------------------
    Bot States
----------------------------------------]]--

MBot.DefaultBotStates = {
    -- Pathfinding
    goalPos = nil,
    pathSegment = 2,

    -- Stuck management
    lastPos = nil,
    nextStuckCheck = 0,
    stuckTime = 0,
    stuckStrafeDir = 0,
    stuckStrafeTime = 0,
    stuckBackTime = 0,

    -- Target
    curTarget = nil,
    propTarget = nil,
    forgetTargetTime = 0,
    targetVisibleTime = 0,
    targetVisiblePos = nil,

    -- Look at
    lookAtPos = nil,
    lookAtTime = 0,

    -- Combat
    attack1Delay = 0,
    attack2CD = 0,
    forceAttack1Time = 0,
    broodExposed = false,
    changeWepDelay = 0, -- For Brood bots

    -- Movement
    jumpTime = 0,
    crouchTime = 0,

    -- Movement (Ladder)
    onLadder = false,
    prevOnLadder = false,
    timeOnLadder = 0,

    -- Movement (Melee)
    meleeCircleDir = 0,
    meleeCircleTime = 0,
    meleeFlankRushTime = 0,

    -- Game mode
    whatRole = 1, -- ROLE_HUMAN (1), ROLE_BROOD (2), ROLE_SWARM (3)
    curMission = 0, -- MISSION_NONE (0), MISSION_SLEEP (1), MISSION_EAT (2), MISSION_CLEAN (3), MISSION_BATHROOM (4), MISSION_KILL (5)
    prevMission = 0,
    missionPos = nil,
    upgradeCheckTime = 0,
    maxedOutUpgrades = false,

    -- Weapon info
    inventory = {},
    curWeapon = nil,
    curWeaponClass = "",
    isMelee = false,
    nextWeaponCheck = 0,
    closestWep = nil,
    closestWepDist = math.huge,

    -- Movement info
    isCrouching = false,
    isOnGround = false,

    -- Other bot info
    botPos = nil,

    -- Set by coroutines
    pendingTarget = nil,
    pendingProp = nil,

    -- Other timing stuff
    randomSpotTime = 0,
    lookForWeaponsTime = 0
}