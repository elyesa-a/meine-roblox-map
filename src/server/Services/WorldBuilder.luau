--!strict
-- WorldBuilder: schlanker Orchestrator.
--
-- Die komplette Map-Geometrie ist in den datenbasierten VirusLabBuilder
-- ausgelagert (10 Areale, 100 Gegner, Borders, Gates, Trainingsbereiche,
-- Egg-Catch-Stationen). WorldBuilder bleibt die stabile Schnittstelle fuer
-- Main.server.luau (build() + .PetEgg), damit das Bootstrap unveraendert
-- bleibt. UI / RemoteEvents werden NICHT angefasst.

local VirusLabBuilder = require(script.Parent:WaitForChild("VirusLabBuilder"))

local WorldBuilder = {}

WorldBuilder.PetEgg = nil :: BasePart?

function WorldBuilder.build()
	VirusLabBuilder.build()
	-- Pet-Egg-Referenz durchreichen, damit Main den ClickDetector verdrahtet.
	WorldBuilder.PetEgg = VirusLabBuilder.PetEgg
	print("[WorldBuilder] Virus-Labor-Welt erzeugt (delegiert an VirusLabBuilder).")
end

return WorldBuilder
