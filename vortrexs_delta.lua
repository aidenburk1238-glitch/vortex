-- Vortex Confuser (Delta/Xeno safe build)
local __ok, __err = xpcall(function()
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

local EMBEDDED_BG = [[]]

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
        if EMBEDDED_BG ~= "" and getcustomasset and writefile then
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
local EMBEDDED_PURPLE = [[]]
local function getPurpleBackground()
    local ok, res = pcall(function()
        if EMBEDDED_PURPLE ~= "" and getcustomasset and writefile then
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
local function isCustomBg(id) return id == "custom" or id == "purple" end

-- EMBEDDED TITLE LOGO ("VORTEX CONFUSER", red) ------------------------
local TITLE_FILE = "vortex_title_v2.png"
local EMBEDDED_TITLE = [[]]

pcall(function()
    if EMBEDDED_TITLE == "" or not (getcustomasset and writefile) then return end
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
for _, id in ipairs(backgroundIds) do table.insert(backgroundOptions, id) end

local selectedBackgroundId = backgroundOptions[1]
for _, id in ipairs(backgroundOptions) do
    if id == State.background then selectedBackgroundId = id end
end
local function imageFor(id)
    if id == "custom" then return customBackground end
    if id == "purple" then return purpleBackground end
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
    button.Size = UDim2.new(0, 26, 0, 26)
    button.Position = UDim2.new(0, 88 + (i - 1) * 28, 0, 161)
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

end, function(e) return tostring(e) end)
if not __ok then
    warn('[VORTEX] ' .. tostring(__err))
    pcall(function()
        game:GetService('StarterGui'):SetCore('SendNotification', {Title='Vortex error', Text=tostring(__err):sub(1,200), Duration=15})
    end)
end
