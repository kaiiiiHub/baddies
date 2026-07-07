local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "MacroScript | Baddies",
    LoadingTitle = "Script For Baddies",
    LoadingSubtitle = "by KaiiiHub",
    ConfigurationSaving = {Enabled = false}
})

local FOVEnabled = false
local HitboxEnabled = false
local FastPunch = false
local PunchAura = false

local fovValue = 70
local HitboxSize = 5
local PunchSpeed = 0.05
local AuraDistance = 10


local Tab = Window:CreateTab("Main")

Tab:CreateSlider({
    Name = "FOV",
    Range = {70, 120},
    Increment = 1,
    CurrentValue = 70,
    Callback = function(Value)
        fovValue = Value
    end
})

Tab:CreateToggle({
    Name = "Enable FOV",
    CurrentValue = false,
    Callback = function(Value)
        FOVEnabled = Value
        if Value then ShowMakuLoading() end
    end
})

task.spawn(function()
    while true do
        if FOVEnabled then
            workspace.CurrentCamera.FieldOfView = fovValue
        end
        task.wait()
    end
end)

Tab:CreateSlider({
    Name = "Hitbox Size",
    Range = {5, 30},
    Increment = 1,
    CurrentValue = 5,
    Callback = function(Value)
        HitboxSize = Value
    end
})

Tab:CreateToggle({
    Name = "Hitbox Expander",
    CurrentValue = false,
    Callback = function(Value)
        HitboxEnabled = Value
        if Value then ShowMakuLoading() end
    end
})

task.spawn(function()
    while true do
        if HitboxEnabled then
            for _,v in pairs(game.Players:GetPlayers()) do
                if v ~= game.Players.LocalPlayer 
                and v.Character 
                and v.Character:FindFirstChild("HumanoidRootPart") then

                    local hrp = v.Character.HumanoidRootPart
                    hrp.Size = Vector3.new(HitboxSize, HitboxSize, HitboxSize)
                    hrp.Transparency = 0.5
                    hrp.Material = Enum.Material.Neon
                    hrp.CanCollide = false
                end
            end
        end
        task.wait(0.5)
    end
end)

Tab:CreateToggle({
    Name = "Fast Punch",
    CurrentValue = false,
    Callback = function(Value)
        FastPunch = Value
        if Value then ShowMakuLoading() end
    end
})

Tab:CreateSlider({
    Name = "Punch Speed",
    Range = {1, 10},
    Increment = 1,
    CurrentValue = 20,
    Callback = function(Value)
        PunchSpeed = 1 / Value
    end
})

Tab:CreateToggle({
    Name = "Punch Aura",
    CurrentValue = false,
    Callback = function(Value)
        PunchAura = Value
    end
})

Tab:CreateSlider({
    Name = "Aura Distance",
    Range = {5, 25},
    Increment = 1,
    CurrentValue = 10,
    Callback = function(Value)
        AuraDistance = Value
    end
})

task.spawn(function()
    while true do
        if FastPunch then
            local player = game.Players.LocalPlayer
            local char = player.Character

            if char then
                local tool = char:FindFirstChildOfClass("Tool")
                local root = char:FindFirstChild("HumanoidRootPart")

                if tool then
                    if PunchAura and root then
                        for _,v in pairs(game.Players:GetPlayers()) do
                            if v ~= player and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                                local enemyRoot = v.Character.HumanoidRootPart
                                local dist = (enemyRoot.Position - root.Position).Magnitude

                                if dist <= AuraDistance then
                                    tool:Activate()
                                end
                            end
                        end
                    else
                        tool:Activate()
                    end
                end
            end
        end
        task.wait(PunchSpeed)
    end
end)
