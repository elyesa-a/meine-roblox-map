--!strict
-- EggCatchService: verbindet die 30 Area-Egg-Catch-Stationen
-- (Workspace.EggStations) mit dem bestehenden Pet-Egg-System.
--
-- Jede Station hat einen ClickDetector "OpenEgg". Klick -> PetService.openEgg.
-- So haben die Stationen ECHTE Funktion (oeffnen das vorhandene Pet-Egg).
-- Die pro Area/Seltenheit angezeigten Kosten (EggCatchConfig) sind Anzeige-
-- /Datenwerte -- die tatsaechliche DNA-Abbuchung steuert weiterhin
-- PetService (globaler EggCost). Bestehende Pet-Logik bleibt unangetastet.

local Workspace = game:GetService("Workspace")

local EggCatchService = {}

local PetService

function EggCatchService.start(deps)
	PetService = deps.PetService

	local folder = Workspace:FindFirstChild("EggStations")
	if not folder then
		return
	end

	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("ClickDetector") and desc.Name == "OpenEgg" then
			desc.MouseClick:Connect(function(player)
				PetService.openEgg(player)
			end)
		end
	end
end

return EggCatchService
