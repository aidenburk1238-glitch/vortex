-- Vortex Confuser (Xeno compatible)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

local CONFIG_FILE = "VortexConfuserConfig.json"

-- Pick the safest place to parent the GUI (Xeno supports gethui on most builds)
local function getGuiParent()
    local ok, result = pcall(function()
        if gethui then return gethui() end
    end)
    if ok and result then return result end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return LP:WaitForChild("PlayerGui")
end
local GuiParent = getGuiParent()

local COLORS = {
    bg          = Color3.fromRGB(8, 6, 12),
    bgDark      = Color3.fromRGB(3, 2, 6),
    frame       = Color3.fromRGB(14, 9, 22),
    stroke      = Color3.fromRGB(125, 55, 190),
    text        = Color3.fromRGB(255, 255, 255),
    textDim     = Color3.fromRGB(185, 145, 225),
    accent      = Color3.fromRGB(160, 70, 235),
    activeGreen = Color3.fromRGB(190, 105, 255),
    inactiveRed = Color3.fromRGB(110, 45, 155),
    buttonBg    = Color3.fromRGB(24, 13, 36),
    toggleOn    = Color3.fromRGB(190, 105, 255),
    toggleOff   = Color3.fromRGB(35, 25, 45)}

local State = {
    confuserOn = false,
    speed      = 50,
    lockGui    = false,
    activeOnSteal = false,
    background = "custom",
    guiPos     = {XScale = 0.5, XOffset = -115, YScale = 0.5, YOffset = -65}}

local toggleKey = Enum.KeyCode.X

local function saveConfig()
    local cfg = {
        toggleKey = toggleKey.Name,
        speed     = State.speed,
        lockGui   = State.lockGui,
        activeOnSteal = State.activeOnSteal,
        background = State.background,
        guiPos    = State.guiPos}
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(cfg))
        end
    end)
end

local function loadConfig()
    local hasFile = false
    pcall(function() hasFile = isfile and isfile(CONFIG_FILE) end)
    if not hasFile then return end
    local ok, cfg = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or not cfg then return end
    if cfg.toggleKey and Enum.KeyCode[cfg.toggleKey] then
        toggleKey = Enum.KeyCode[cfg.toggleKey]
    end
    if cfg.speed then State.speed = math.max(0, tonumber(cfg.speed) or 50) end
    if cfg.lockGui ~= nil then State.lockGui = cfg.lockGui end
    if cfg.activeOnSteal ~= nil then State.activeOnSteal = cfg.activeOnSteal end
    if cfg.background then State.background = tostring(cfg.background) end
    if cfg.guiPos and type(cfg.guiPos) == "table" then
        State.guiPos = cfg.guiPos
    end
end
loadConfig()

local Spin = {
    enabled = false,
    conn    = nil,
    angle   = 0}

local function startSpin()
    if Spin.conn then return end
    Spin.angle = 0

    Spin.conn = RunService.Heartbeat:Connect(function(dt)
        if not Spin.enabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.AutoRotate = false end)
        end

        local step = State.speed * dt * 60
        Spin.angle = (Spin.angle + step) % 360
        local yaw = math.rad(Spin.angle)

        local pos = root.Position
        root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
end

local function stopSpin()
    if Spin.conn then
        Spin.conn:Disconnect()
        Spin.conn = nil
    end
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.AutoRotate = true end)
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            pcall(function() root.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end)
        end
    end
end

local antiDieEnabled = false
local antiDieCharConns = {}
local antiDieCharAddedConn = nil
local antiDieHeartbeat = nil

local function clearCharEntry(char, restore)
    local entry = antiDieCharConns[char]
    if entry then
        if entry.healthConn then pcall(function() entry.healthConn:Disconnect() end) end
        if entry.diedConn then pcall(function() entry.diedConn:Disconnect() end) end
        if entry.cleanupConn then pcall(function() entry.cleanupConn:Disconnect() end) end
        antiDieCharConns[char] = nil
    end
    if restore and char and char.Parent then
        pcall(function()
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.BreakJointsOnDeath = true
                hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            end
        end)
    end
end

local function applyAntiDieToCharacter(char)
    if not char or not char.Parent then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    clearCharEntry(char, false)

    hum.BreakJointsOnDeath = false
    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

    local entry = { humanoid = hum }
    entry.healthConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
        if antiDieEnabled and antiDieCharConns[char] == entry and hum.Health <= 0 then
            hum.Health = hum.MaxHealth
        end
    end)
    entry.diedConn = hum.Died:Connect(function()
        task.defer(function()
            if antiDieEnabled and antiDieCharConns[char] == entry and hum and hum.Parent then
                hum.BreakJointsOnDeath = false
                hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                hum.Health = hum.MaxHealth
            end
        end)
    end)
    entry.cleanupConn = char.AncestryChanged:Connect(function()
        if not char.Parent then clearCharEntry(char, false) end
    end)
    antiDieCharConns[char] = entry
end

local function setAntiDieEnabled(enabled)
    enabled = enabled == true
    if enabled == antiDieEnabled then return end
    antiDieEnabled = enabled
    if enabled then
        if not antiDieCharAddedConn then
            antiDieCharAddedConn = LP.CharacterAdded:Connect(function(char)
                task.wait(0.2)
                if antiDieEnabled and char and char.Parent then
                    applyAntiDieToCharacter(char)
                end
            end)
        end
        local char = LP.Character
        if char and char.Parent and not antiDieCharConns[char] then
            applyAntiDieToCharacter(char)
        end
        if not antiDieHeartbeat then
            antiDieHeartbeat = RunService.Heartbeat:Connect(function()
                if not antiDieEnabled then return end
                local c = LP.Character
                local hum = c and c.Parent and c:FindFirstChildOfClass("Humanoid")
                if not hum then return end
                local entry = antiDieCharConns[c]
                if not entry or entry.humanoid ~= hum then applyAntiDieToCharacter(c) end
                if hum.BreakJointsOnDeath then hum.BreakJointsOnDeath = false end
                if hum:GetStateEnabled(Enum.HumanoidStateType.Dead) then
                    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                end
                if hum.Health <= 0 then hum.Health = hum.MaxHealth end
            end)
        end
    else
        if antiDieHeartbeat then antiDieHeartbeat:Disconnect(); antiDieHeartbeat = nil end
        for char in pairs(antiDieCharConns) do
            clearCharEntry(char, true)
        end
    end
end

local function setConfuser(on)
    Spin.enabled = on
    setAntiDieEnabled(on)
    if on then startSpin() else stopSpin() end
end

-- Remove old copies (including previous Vynx / Baki versions)
for _, name in pairs({"BakiBypass", "BakiwareConfuser", "BakiAntiDie", "VynxConfuser", "VortexConfuser"}) do
    pcall(function()
        local old = GuiParent:FindFirstChild(name)
        if old then old:Destroy() end
    end)
    pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            local o = pg:FindFirstChild(name)
            if o then o:Destroy() end
        end
    end)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VortexConfuser"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = GuiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 260, 0, 336)
mainFrame.Position = UDim2.new(State.guiPos.XScale, State.guiPos.XOffset, State.guiPos.YScale, State.guiPos.YOffset)
mainFrame.BackgroundColor3 = COLORS.bg
mainFrame.BackgroundTransparency = 1
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local borderStroke = Instance.new("UIStroke")
borderStroke.Thickness = 1.5
borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
borderStroke.Parent = mainFrame

local borderGradient = Instance.new("UIGradient")
borderGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 70, 235)),
    ColorSequenceKeypoint.new(0.3, Color3.fromRGB(110, 45, 170)),
    ColorSequenceKeypoint.new(0.7, Color3.fromRGB(190, 105, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 70, 235))})
borderGradient.Parent = borderStroke
TweenService:Create(borderGradient, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360}):Play()

local starContainer = Instance.new("Frame")
starContainer.Size = UDim2.new(1, 0, 1, 0)
starContainer.BackgroundTransparency = 1
starContainer.ClipsDescendants = true
starContainer.ZIndex = 1
starContainer.Parent = mainFrame

local function createStar()
    local star = Instance.new("Frame")
    star.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    star.BorderSizePixel = 0
    star.ZIndex = 1
    local size = math.random(1, 2)
    star.Size = UDim2.new(0, size, 0, size)
    Instance.new("UICorner", star).CornerRadius = UDim.new(1, 0)
    star.Position = UDim2.new(math.random(), 0, -0.1, 0)
    star.BackgroundTransparency = math.random(5, 8) / 10
    star.Parent = starContainer
    local tween = TweenService:Create(star, TweenInfo.new(math.random(4, 7), Enum.EasingStyle.Linear), {
        Position = UDim2.new(star.Position.X.Scale, 0, 1.1, 0)})
    tween:Play()
    tween.Completed:Connect(function() star:Destroy() end)
end

task.spawn(function()
    while mainFrame and mainFrame.Parent do
        createStar()
        task.wait(0.85)
    end
end)

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 56)
topBar.BackgroundColor3 = COLORS.bgDark
topBar.BackgroundTransparency = 1
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame
topBar.ZIndex = 2
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 10)

-- Text title (the old title image was a Vynx logo, so this replaces it)
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "VortexConfuserTitle"
titleLabel.Size = UDim2.new(0, 200, 0, 52)
titleLabel.Position = UDim2.new(0, 12, 0.5, -26)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "VORTEX CONFUSER"
titleLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
titleLabel.TextStrokeTransparency = 1
-- Change the font here. Other good options: Bangers, LuckiestGuy, Creepster, Oswald,
-- PermanentMarker, SciFi, Arcade, Sarpanch, Jura, FredokaOne, SpecialElite
-- Safe font: GothamBlack is built into every Roblox client (same family the rest of the GUI uses).
-- pcall + fallback so a missing font can never error out the script.
local okFont = pcall(function() titleLabel.Font = Enum.Font.GothamBlack end)
if not okFont then titleLabel.Font = Enum.Font.GothamBold end
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 5
titleLabel.Parent = topBar

-- OPTIONAL: custom title image (like the original script's logo).
-- Upload a "VORTEX CONFUSER" logo to Roblox, paste its asset ID here, and it replaces the text title.
local TITLE_IMAGE_ID = "" -- optional: your own uploaded logo ID (the built-in logo below is used first)
if TITLE_IMAGE_ID ~= "" then
    titleLabel.Visible = false
    local titleImage = Instance.new("ImageLabel")
    titleImage.Name = "VortexConfuserTitleImage"
    titleImage.Size = UDim2.new(0, 215, 0, 52)
    titleImage.Position = UDim2.new(0, 8, 0.5, -26)
    titleImage.BackgroundTransparency = 1
    titleImage.Image = "rbxassetid://" .. TITLE_IMAGE_ID
    titleImage.ScaleType = Enum.ScaleType.Fit
    titleImage.ZIndex = 5
    titleImage.Parent = topBar
end

local rightButtonContainer = Instance.new("Frame")
rightButtonContainer.Size = UDim2.new(0, 30, 0, 26)
rightButtonContainer.Position = UDim2.new(0.96, 0, 0.5, -13)
rightButtonContainer.AnchorPoint = Vector2.new(1, 0)
rightButtonContainer.BackgroundTransparency = 1
rightButtonContainer.Parent = topBar

local keybindBtn = Instance.new("TextButton")
keybindBtn.Name = "MinimizeButton"
keybindBtn.Size = UDim2.new(0, 28, 0, 26)
keybindBtn.Position = UDim2.new(1, 0, 0.5, -13)
keybindBtn.AnchorPoint = Vector2.new(1, 0)
keybindBtn.BackgroundTransparency = 1
keybindBtn.BorderSizePixel = 0
keybindBtn.Text = "-"
keybindBtn.TextColor3 = COLORS.text
keybindBtn.Font = Enum.Font.Gotham
keybindBtn.TextSize = 24
keybindBtn.ZIndex = 3
keybindBtn.Parent = rightButtonContainer

local isCollapsed = false
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -56)
body.Position = UDim2.new(0, 0, 0, 56)
body.BackgroundTransparency = 1
body.Parent = mainFrame
body.ZIndex = 2

keybindBtn.MouseButton1Click:Connect(function()
    isCollapsed = not isCollapsed
    body.Visible = not isCollapsed
    mainFrame.Size = isCollapsed and UDim2.new(0, 260, 0, 56) or UDim2.new(0, 260, 0, 336)
    keybindBtn.Text = isCollapsed and "+" or "-"
end)

local activateBtn = Instance.new("TextButton")
activateBtn.Size = UDim2.new(0.92, 0, 0, 40)
activateBtn.Position = UDim2.new(0.04, 0, 0, 8)
activateBtn.BackgroundColor3 = COLORS.buttonBg
activateBtn.BackgroundTransparency = 0.45
activateBtn.Text = "ACTIVATE"
activateBtn.TextColor3 = COLORS.text
activateBtn.Font = Enum.Font.GothamBold
activateBtn.TextSize = 10
activateBtn.ZIndex = 3
activateBtn.Parent = body
Instance.new("UICorner", activateBtn).CornerRadius = UDim.new(0, 6)
local activateStroke = Instance.new("UIStroke")
activateStroke.Color = COLORS.accent
activateStroke.Thickness = 1
activateStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
activateStroke.Parent = activateBtn

local radiusContainer = Instance.new("Frame")
radiusContainer.Name = "RadiusContainer"
radiusContainer.Size = UDim2.new(0.92, 0, 0, 30)
radiusContainer.Position = UDim2.new(0.04, 0, 0, 56)
radiusContainer.BackgroundColor3 = COLORS.bgDark
radiusContainer.BackgroundTransparency = 1
radiusContainer.BorderSizePixel = 0
radiusContainer.Parent = body
radiusContainer.ZIndex = 3
Instance.new("UICorner", radiusContainer).CornerRadius = UDim.new(0, 8)

local radiusStroke = Instance.new("UIStroke")
radiusStroke.Color = COLORS.accent
radiusStroke.Thickness = 1
radiusStroke.Transparency = 0
radiusStroke.Parent = radiusContainer

local radiusLabel = Instance.new("TextLabel")
radiusLabel.Name = "RadiusLabel"
radiusLabel.Size = UDim2.new(0, 56, 1, 0)
radiusLabel.Position = UDim2.new(0, 8, 0, 0)
radiusLabel.BackgroundTransparency = 1
radiusLabel.Text = "RADIUS"
radiusLabel.TextColor3 = COLORS.text
radiusLabel.Font = Enum.Font.GothamMedium
radiusLabel.TextSize = 10
radiusLabel.TextStrokeTransparency = 0.4
radiusLabel.TextXAlignment = Enum.TextXAlignment.Left
radiusLabel.ZIndex = 3
radiusLabel.Parent = radiusContainer

local speedBox = Instance.new("TextBox")
speedBox.Name = "RadiusValue"
speedBox.Size = UDim2.new(1, -76, 1, -8)
speedBox.Position = UDim2.new(0, 66, 0, 4)
speedBox.BackgroundColor3 = COLORS.frame
speedBox.BackgroundTransparency = 1
speedBox.BorderSizePixel = 0
speedBox.Text = tostring(State.speed)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
speedBox.TextStrokeTransparency = 1
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 12
speedBox.ClearTextOnFocus = false
speedBox.TextXAlignment = Enum.TextXAlignment.Center
speedBox.ZIndex = 3
speedBox.Parent = radiusContainer
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 6)

local stealRow = Instance.new("Frame")
stealRow.Name = "ActiveOnStealRow"
stealRow.Size = UDim2.new(0.92, 0, 0, 30)
stealRow.Position = UDim2.new(0.04, 0, 0, 94)
stealRow.BackgroundTransparency = 1
stealRow.ZIndex = 3
stealRow.Parent = body
Instance.new("UICorner", stealRow).CornerRadius = UDim.new(0, 8)
local stealRowStroke = Instance.new("UIStroke")
stealRowStroke.Color = COLORS.accent
stealRowStroke.Thickness = 1
stealRowStroke.Parent = stealRow

local stealLabel = Instance.new("TextLabel")
stealLabel.Size = UDim2.new(1, -70, 1, 0)
stealLabel.Position = UDim2.new(0, 10, 0, 0)
stealLabel.BackgroundTransparency = 1
stealLabel.Text = "ACTIVE ON STEAL"
stealLabel.TextColor3 = COLORS.text
stealLabel.TextStrokeTransparency = 0.4
stealLabel.Font = Enum.Font.GothamBold
stealLabel.TextSize = 10
stealLabel.TextXAlignment = Enum.TextXAlignment.Left
stealLabel.ZIndex = 3
stealLabel.Parent = stealRow

local stealToggle = Instance.new("TextButton")
stealToggle.Size = UDim2.new(0, 46, 0, 20)
stealToggle.Position = UDim2.new(1, -54, 0.5, -10)
stealToggle.BorderSizePixel = 0
stealToggle.Text = ""
stealToggle.AutoButtonColor = false
stealToggle.ZIndex = 4
stealToggle.Parent = stealRow
Instance.new("UICorner", stealToggle).CornerRadius = UDim.new(1, 0)
local stealKnob = Instance.new("Frame")
stealKnob.Size = UDim2.new(0, 16, 0, 16)
stealKnob.BackgroundColor3 = COLORS.text
stealKnob.BorderSizePixel = 0
stealKnob.ZIndex = 5
stealKnob.Parent = stealToggle
Instance.new("UICorner", stealKnob).CornerRadius = UDim.new(1, 0)

local function renderStealToggle()
    stealToggle.BackgroundColor3 = State.activeOnSteal and COLORS.toggleOn or COLORS.toggleOff
    stealKnob.Position = State.activeOnSteal and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
end
renderStealToggle()

local backgroundTitle = Instance.new("TextLabel")
backgroundTitle.Name = "BackgroundSelectorTitle"
backgroundTitle.Size = UDim2.new(0.92, 0, 0, 18)
backgroundTitle.Position = UDim2.new(0.04, 0, 0, 130)
backgroundTitle.BackgroundTransparency = 1
backgroundTitle.Text = "BACKGROUND"
backgroundTitle.TextColor3 = COLORS.text
backgroundTitle.Font = Enum.Font.GothamBold
backgroundTitle.TextSize = 10
backgroundTitle.TextStrokeTransparency = 0.4
backgroundTitle.TextXAlignment = Enum.TextXAlignment.Left
backgroundTitle.Parent = body
backgroundTitle.ZIndex = 3

-- CUSTOM BACKGROUND (embedded, no extra files needed) ---------------
-- The image is stored inside this script. On load it is written to your
-- executor's workspace as vortex_bg.jpg and shown with getcustomasset.
-- Optional fallback: paste a Roblox asset ID below.
local CUSTOM_BG_FILE = "vortex_bg.jpg"
local CUSTOM_BG_ID = ""

local EMBEDDED_BG = [[
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
]]

local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(data)
    data = data:gsub("%s", "")
    -- use the executor's built-in decoder when available (much faster)
    local ok, res = pcall(function()
        if crypt and crypt.base64decode then return crypt.base64decode(data) end
        if crypt and crypt.base64 and crypt.base64.decode then return crypt.base64.decode(data) end
        if base64_decode then return base64_decode(data) end
        if base64 and base64.decode then return base64.decode(data) end
    end)
    if ok and type(res) == "string" and #res > 0 then return res end
    -- pure Lua fallback
    local lookup = {}
    for i = 1, #B64CHARS do lookup[B64CHARS:sub(i, i)] = i - 1 end
    local out, buf, bits = {}, 0, 0
    for i = 1, #data do
        local v = lookup[data:sub(i, i)]
        if v then
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local byte = math.floor(buf / 2 ^ bits)
                buf = buf - byte * 2 ^ bits
                out[#out + 1] = string.char(byte)
            end
        end
    end
    return table.concat(out)
end

local function getCustomBackground()
    local ok, res = pcall(function()
        if getcustomasset and writefile then
            if not (isfile and isfile(CUSTOM_BG_FILE)) then
                writefile(CUSTOM_BG_FILE, b64decode(EMBEDDED_BG))
            end
            return getcustomasset(CUSTOM_BG_FILE)
        end
    end)
    if ok and res then return res end
    if CUSTOM_BG_ID ~= "" then return "rbxassetid://" .. CUSTOM_BG_ID end
    return nil
end
local customBackground = getCustomBackground()

-- HU TAO BACKGROUND (embedded)
local PURPLE_FILE = "vortex_hutao.jpg"
local EMBEDDED_PURPLE = [[
/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYn
KSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo
KCgoKCgoKCj/wAARCAFQAQQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF
BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVW
V1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi
4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAEC
AxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm
Z2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq
8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD17T7j7RBl+JUOyRfRhVqsfU1lsbr+0LZS6EYuIx/EOzD3FaVrcRXUCywOHRu47fWqT7nR
JdUTUUZpCRgk8Ad6ZItFIDkZHI9RXPeIPE8OnztZ2Mf2zUQPmjVsJDnvI3b6dTSbSGot6I3bm4htYHnuZUihQZZ3OAPxrk9Q8WzT
nZodspT/AJ+roFUP+6n3j9TgVhTm4vJhPqtx9qmHKrjbHH/ur/U5NSZLH5eB6mspTfQ3jRW7Kd9bC9O/Wbqa/dSW/fHCL9EGAKz7
fSI2vjcvGkcOzasSDH5/WruoSASxRL90HzHHqOgH4n+VSGZhdrEdoXyi5+oIFQa2SLSrhQFAAHYUEAUobIGKacA0iiGdxHhs8Kwz
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
wKfnHFAXHcUUzNFAz//Z
]]
local function getPurpleBackground()
    local ok, res = pcall(function()
        if getcustomasset and writefile then
            if not (isfile and isfile(PURPLE_FILE)) then
                writefile(PURPLE_FILE, b64decode(EMBEDDED_PURPLE))
            end
            return getcustomasset(PURPLE_FILE)
        end
    end)
    if ok and res then return res end
    return nil
end
local purpleBackground = getPurpleBackground()
local MEME_FILE = "vortex_meme.jpg"
local EMBEDDED_MEME = [[
/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwMDAgQDAwMEBAQFBgoGBgUFBgwICQcKDgwPDg4MDQ0PERYTDxAVEQ0NExoTFRcY
GRkZDxIbHRsYHRYYGRj/2wBDAQQEBAYFBgsGBgsYEA0QGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgY
GBgYGBgYGBj/wAARCAETANgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF
BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVW
V1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi
4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAEC
AxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm
Z2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq
8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD7C/4Uh8Fv+iQ+A/8Awn7T/wCN0f8ACkPgt/0SHwH/AOE/af8Axuu8ooA+Pvit4y+Bvwr/
AGgtD+Gmpfs4+DLlNXa3EOpJo9kqjzX2H5THn5TUGlfEb9nXUv2h/FHwsPwA8FxSaHDdyfbzotmUmNupZgB5fGcGua/4KFaY2j6/
8OPiLDFuksrtoGKjn5GWVf5V8ovrWraFer8bmEjf8JNdarZhBwQWjCk5/wC2h/KgD7s/Z21z4IftAQ67cWf7O/gvR7fSnSIyy6LZ
yCRmycDEfHAr3P8A4Uh8Fv8AokPgP/wn7T/43X5/eC4fij4J/wCCbsniT4bC/t7jWNekk1G5sFJnS1jXarLjkAnOSO1bfhv4u6j4
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
]]
local function getMemeBackground()
    local ok, res = pcall(function()
        if getcustomasset and writefile then
            if not (isfile and isfile(MEME_FILE)) then
                writefile(MEME_FILE, b64decode(EMBEDDED_MEME))
            end
            return getcustomasset(MEME_FILE)
        end
    end)
    if ok and res then return res end
    return nil
end
local memeBackground = getMemeBackground()
local function isCustomBg(id) return id == "custom" or id == "purple" or id == "meme" end

-- EMBEDDED TITLE LOGO ("VORTEX CONFUSER", red) ------------------------
local TITLE_FILE = "vortex_title_v2.png"
local EMBEDDED_TITLE = [[
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
]]

pcall(function()
    if not (getcustomasset and writefile) then return end
    if not (isfile and isfile(TITLE_FILE)) then
        writefile(TITLE_FILE, b64decode(EMBEDDED_TITLE))
    end
    local asset = getcustomasset(TITLE_FILE)
    if not asset then return end
    local logo = Instance.new("ImageLabel")
    logo.Name = "VortexConfuserLogo"
    logo.Size = UDim2.new(0, 215, 0, 52)
    logo.Position = UDim2.new(0, 8, 0.5, -26)
    logo.BackgroundTransparency = 1
    logo.Image = asset
    logo.ScaleType = Enum.ScaleType.Fit
    logo.ZIndex = 5
    logo.Parent = topBar
    titleLabel.Visible = false
end)
-----------------------------------------------------------------------
-----------------------------------------------------------------------

local backgroundIds = {
    "112180017939463",
    "106344835483006",
    "134260766475623",
    "124053948669794"}
-- option list: your custom image first (if it loaded), then the originals
local backgroundOptions = {}
if customBackground then table.insert(backgroundOptions, "custom") end
if purpleBackground then table.insert(backgroundOptions, "purple") end
if memeBackground then table.insert(backgroundOptions, "meme") end
for _, id in ipairs(backgroundIds) do table.insert(backgroundOptions, id) end

local selectedBackgroundId = backgroundOptions[1]
for _, id in ipairs(backgroundOptions) do
    if id == State.background then selectedBackgroundId = id end
end
local function imageFor(id)
    if id == "custom" then return customBackground end
    if id == "purple" then return purpleBackground end
    if id == "meme" then return memeBackground end
    return "rbxassetid://" .. id
end

local backgroundPreview = Instance.new("ImageLabel")
backgroundPreview.Name = "BackgroundPreview"
backgroundPreview.Size = UDim2.new(0, 72, 0, 48)
backgroundPreview.Position = UDim2.new(0.04, 0, 0, 150)
backgroundPreview.BackgroundTransparency = 1
backgroundPreview.BorderSizePixel = 0
backgroundPreview.Image = imageFor(selectedBackgroundId)
backgroundPreview.ScaleType = Enum.ScaleType.Crop
backgroundPreview.Parent = body
backgroundPreview.ZIndex = 3
Instance.new("UICorner", backgroundPreview).CornerRadius = UDim.new(0, 7)

local previewStroke = Instance.new("UIStroke")
previewStroke.Color = COLORS.stroke
previewStroke.Thickness = 1
previewStroke.Parent = backgroundPreview

local selectorButtons = {}
local backgroundImage
local bgOverlay
for i, assetId in ipairs(backgroundOptions) do
    local button = Instance.new("ImageButton")
    button.Name = "BackgroundOption" .. i
    button.Size = UDim2.new(0, 22, 0, 22)
    button.Position = UDim2.new(0, 88 + (i - 1) * 24, 0, 163)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.Image = imageFor(assetId)
    button.ScaleType = Enum.ScaleType.Crop
    button.AutoButtonColor = true
    button.Parent = body
    button.ZIndex = 4
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)

    local optionStroke = Instance.new("UIStroke")
    optionStroke.Color = assetId == selectedBackgroundId and COLORS.accent or COLORS.stroke
    optionStroke.Thickness = assetId == selectedBackgroundId and 2 or 1
    optionStroke.Parent = button

    button.MouseButton1Click:Connect(function()
        selectedBackgroundId = assetId
        backgroundPreview.Image = imageFor(assetId)
        backgroundImage.Image = imageFor(assetId)
        bgOverlay.BackgroundTransparency = isCustomBg(assetId) and 0.5 or 1
        State.background = assetId
        saveConfig()
        for _, entry in ipairs(selectorButtons) do
            entry.stroke.Color = entry.id == selectedBackgroundId and COLORS.accent or COLORS.stroke
            entry.stroke.Thickness = entry.id == selectedBackgroundId and 2 or 1
        end
    end)
    table.insert(selectorButtons, {button = button, stroke = optionStroke, id = assetId})
end

backgroundImage = Instance.new("ImageLabel")
backgroundImage.Name = "PanelBackgroundImage"
backgroundImage.Size = UDim2.new(1, 0, 1, 0)
backgroundImage.Position = UDim2.new(0, 0, 0, 0)
backgroundImage.BackgroundTransparency = 1
backgroundImage.Image = imageFor(selectedBackgroundId)
backgroundImage.ImageTransparency = 0
backgroundImage.ScaleType = Enum.ScaleType.Crop
backgroundImage.ZIndex = 0
backgroundImage.Parent = mainFrame
backgroundImage.Active = false
Instance.new("UICorner", backgroundImage).CornerRadius = UDim.new(0, 10)

-- dark overlay so the white text stays readable on a bright image
bgOverlay = Instance.new("Frame")
bgOverlay.Name = "BackgroundOverlay"
bgOverlay.Size = UDim2.new(1, 0, 1, 0)
bgOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bgOverlay.BackgroundTransparency = isCustomBg(selectedBackgroundId) and 0.5 or 1
bgOverlay.BorderSizePixel = 0
bgOverlay.ZIndex = 0
bgOverlay.Active = false
bgOverlay.Parent = mainFrame
Instance.new("UICorner", bgOverlay).CornerRadius = UDim.new(0, 10)

local function updateUI()
    if State.confuserOn then
        activateBtn.Text = "ON"
        activateBtn.TextColor3 = COLORS.activeGreen
    else
        activateBtn.Text = "ACTIVATE"
        activateBtn.TextColor3 = COLORS.text
    end
    local n = tonumber(speedBox.Text) or State.speed
    n = math.max(0, n)
    State.speed = n
end

speedBox.FocusLost:Connect(function()
    local n = tonumber(speedBox.Text)
    if not n then n = State.speed end
    n = math.max(0, n)
    State.speed = n
    speedBox.Text = tostring(n)
    saveConfig()
end)

local function toggleConfuser()
    State.confuserOn = not State.confuserOn
    setConfuser(State.confuserOn)
    updateUI()
    saveConfig()
end

activateBtn.MouseButton1Click:Connect(toggleConfuser)

local stealActive = false

local function isCarryingBrainrot()
    local char = LP.Character
    return LP:GetAttribute("Stealing") == true
        or (char ~= nil and char:GetAttribute("Stealing") == true)
end

local function endSteal()
    if not stealActive then return end
    stealActive = false
    State.confuserOn = false
    setConfuser(false)
    updateUI()
end

stealToggle.MouseButton1Click:Connect(function()
    State.activeOnSteal = not State.activeOnSteal
    renderStealToggle()
    if not State.activeOnSteal then endSteal() end
    saveConfig()
end)

task.spawn(function()
    while screenGui and screenGui.Parent do
        task.wait(0.15)
        if State.activeOnSteal then
            local carrying = isCarryingBrainrot()
            if carrying and not stealActive and not State.confuserOn then
                stealActive = true
                State.confuserOn = true
                setConfuser(true)
                updateUI()
            elseif not carrying and stealActive then
                endSteal()
            end
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == toggleKey and (input.UserInputType == Enum.UserInputType.Keyboard
        or input.UserInputType == Enum.UserInputType.Gamepad1
        or input.UserInputType == Enum.UserInputType.Gamepad2) then
        toggleConfuser()
    end
end)

local isDragging = false
local dragInput, mousePos, framePos

mainFrame.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not State.lockGui then
        isDragging = true
        mousePos = input.Position
        framePos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                isDragging = false
                local pos = mainFrame.Position
                State.guiPos = {XScale = pos.X.Scale, XOffset = pos.X.Offset, YScale = pos.Y.Scale, YOffset = pos.Y.Offset}
                saveConfig()
            end
        end)
    end
end)

mainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and isDragging then
        local delta = input.Position - mousePos
        mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
    end
end)

updateUI()
print("[VORTEX CONFUSER] Loaded")
