--!strict
-- HighlightOcclusion.client.lua
-- Forces all Highlight instances to use Occluded depth mode so they don't render through walls

local Workspace = game:GetService("Workspace")

local function ForceOccluded(instance: Instance)
	if instance:IsA("Highlight") then
		instance.DepthMode = Enum.HighlightDepthMode.Occluded
	end
end

-- Apply to all existing Highlights
for _, descendant in ipairs(Workspace:GetDescendants()) do
	ForceOccluded(descendant)
end

-- Apply to any new Highlights added at runtime
Workspace.DescendantAdded:Connect(ForceOccluded)

print("[HighlightOcclusion] Initialized")
