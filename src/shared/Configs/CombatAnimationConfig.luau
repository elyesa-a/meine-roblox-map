--!strict
-- Combat punch animation settings.
--
-- Replace the fallback ids with your own uploaded punch animations when ready.
-- The system supports one loop animation OR separate right/left hit animations.

local CombatAnimationConfig = {}

CombatAnimationConfig.RigType = "Auto" -- "Auto", "R15", or "R6"

-- Preferred custom ids. Leave empty until you upload real punch animations.
CombatAnimationConfig.RightPunchAnimationId = ""
CombatAnimationConfig.LeftPunchAnimationId = ""
CombatAnimationConfig.PunchLoopAnimationId = ""

-- Roblox default tool-slash fallbacks. These are not perfect boxing punches,
-- but they are real AnimationTracks and visibly move the arms.
CombatAnimationConfig.EnableRobloxDefaultFallback = true
CombatAnimationConfig.R15PunchLoopAnimationId = "rbxassetid://522635514"
CombatAnimationConfig.R6PunchLoopAnimationId = "rbxassetid://129967390"

CombatAnimationConfig.Priority = Enum.AnimationPriority.Action
CombatAnimationConfig.LoopSpeed = 1.15
CombatAnimationConfig.HitSpeed = 1.25
CombatAnimationConfig.FadeIn = 0.08
CombatAnimationConfig.FadeOut = 0.12
CombatAnimationConfig.Debug = true

return CombatAnimationConfig
