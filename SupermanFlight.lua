--[[
	SISTEMA DE VOO "SUPERMAN"  •  LocalScript
	Local: StarterPlayer > StarterCharacterScripts   |   Rig: R15

	F / Y ............. liga/desliga voo (no chão = decolagem com agachamento)
	WASD / analógico .. voa pra onde a câmera aponta
	Espaço / A ........ subir
	Ctrl ou Q / L2 .... descer (perto do chão = pouso)
	Shift / R2 ........ boost supersônico
	(Mobile ganha botões na tela automaticamente)
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local CAS          = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local root      = character:WaitForChild("HumanoidRootPart")
local animator  = humanoid:WaitForChild("Animator")
local camera    = workspace.CurrentCamera

if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
	warn("[Voo] Esse sistema precisa de rig R15.")
	return
end

local Controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

--==================== CONFIG ====================--
local CONFIG = {
	CruiseSpeed       = 70,
	BoostSpeed        = 230,
	VerticalSpeed     = 45,
	Acceleration      = 4,
	BoostAcceleration = 2.2,   -- menor = boost "pega" mais devagar (sensação de peso)
	TurnSpeed         = 6,
	BankFactor        = 0.35,
	MaxBank           = math.rad(55),
	PoseSpeed         = 8,
	BaseFOV           = camera.FieldOfView,
	CruiseFOV         = 82,
	BoostFOV          = 105,
	TakeoffImpulse    = 65,
	CrouchTime        = 0.22,
	HardLandingSpeed  = 65,
	HeroLandingTime   = 0.8,
}

--==================== UTILS ====================--
local rad = math.rad
local function ang(x, y, z) return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0)) end
local function alpha(speed, dt) return 1 - math.exp(-speed * dt) end
local function damp(a, b, speed, dt) return a + (b - a) * alpha(speed, dt) end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }
local function groundBelow(dist)
	return workspace:Raycast(root.Position, Vector3.new(0, -dist, 0), rayParams)
end

--==================== JUNTAS ====================--
local function motor(partName, motorName)
	return character:WaitForChild(partName):WaitForChild(motorName)
end

local joints = {
	Root      = motor("LowerTorso", "Root"),
	Waist     = motor("UpperTorso", "Waist"),
	Neck      = motor("Head", "Neck"),
	RShoulder = motor("RightUpperArm", "RightShoulder"),
	LShoulder = motor("LeftUpperArm", "LeftShoulder"),
	RElbow    = motor("RightLowerArm", "RightElbow"),
	LElbow    = motor("LeftLowerArm", "LeftElbow"),
	RWrist    = motor("RightHand", "RightWrist"),
	LWrist    = motor("LeftHand", "LeftWrist"),
	RHip      = motor("RightUpperLeg", "RightHip"),
	LHip      = motor("LeftUpperLeg", "LeftHip"),
	RKnee     = motor("RightLowerLeg", "RightKnee"),
	LKnee     = motor("LeftLowerLeg", "LeftKnee"),
	RAnkle    = motor("RightFoot", "RightAnkle"),
	LAnkle    = motor("LeftFoot", "LeftAnkle"),
}

-- "Overlapping action": extremidades atrasam mais que o tronco
local LAG = {
	Root = 1.4, Waist = 1.2, Neck = 1.0,
	RShoulder = 0.9, LShoulder = 0.9, RElbow = 0.7, LElbow = 0.7, RWrist = 0.55, LWrist = 0.55,
	RHip = 0.9, LHip = 0.9, RKnee = 0.7, LKnee = 0.7, RAnkle = 0.5, LAnkle = 0.5,
}

local baseC0, current = {}, {}
for name, m in joints do
	baseC0[name] = m.C0
	current[name] = CFrame.identity
end

--==================== POSES ====================--
-- {rotX, rotY, rotZ, posX, posY, posZ} em graus/studs
-- Ombro/Quadril: +X = pra frente | Joelho: -X = dobra | Tornozelo: -X = ponta do pé
local POSE_DEFS = {
	Hover = {
		Waist = {4,0,0}, Neck = {-6,0,0},
		RShoulder = {8,0,12}, LShoulder = {8,0,-12},
		RElbow = {18,0,0}, LElbow = {18,0,0},
		RWrist = {0,0,5}, LWrist = {0,0,-5},
		RHip = {10,0,3}, LHip = {-4,0,-3},
		RKnee = {-28,0,0}, LKnee = {-12,0,0},
		RAnkle = {-25,0,0}, LAnkle = {-20,0,0},
	},
	Cruise = { -- pose clássica: punho direito na frente
		Waist = {10,0,0}, Neck = {55,0,0},
		RShoulder = {172,0,4}, LShoulder = {-10,0,-8},
		LElbow = {25,0,0},
		RHip = {-6,0,2}, LHip = {-2,0,-2},
		RKnee = {-4,0,0}, LKnee = {-22,0,0},
		RAnkle = {-45,0,0}, LAnkle = {-40,0,0},
	},
	Boost = { -- dois braços à frente, corpo em flecha
		Waist = {14,0,0}, Neck = {62,0,0},
		RShoulder = {176,0,-6}, LShoulder = {176,0,6},
		RHip = {-8,0,1}, LHip = {-8,0,-1},
		RAnkle = {-55,0,0}, LAnkle = {-55,0,0},
	},
	Ascend = {
		Waist = {-4,0,0}, Neck = {20,0,0},
		RShoulder = {165,0,6}, LShoulder = {20,0,-15},
		LElbow = {30,0,0},
		RHip = {-4,0,2}, LHip = {6,0,-2},
		RKnee = {-8,0,0}, LKnee = {-30,0,0},
		RAnkle = {-50,0,0}, LAnkle = {-40,0,0},
	},
	Descend = {
		Waist = {8,0,0}, Neck = {-20,0,0},
		RShoulder = {30,0,45}, LShoulder = {30,0,-45},
		RElbow = {25,0,0}, LElbow = {25,0,0},
		RHip = {25,0,6}, LHip = {12,0,-6},
		RKnee = {-45,0,0}, LKnee = {-30,0,0},
		RAnkle = {-10,0,0}, LAnkle = {-10,0,0},
	},
	Brake = { -- freada: corpo joga pra trás, braços abrem
		Waist = {-12,0,0}, Neck = {-10,0,0},
		RShoulder = {70,0,55}, LShoulder = {70,0,-55},
		RElbow = {35,0,0}, LElbow = {35,0,0},
		RHip = {55,0,8}, LHip = {40,0,-8},
		RKnee = {-60,0,0}, LKnee = {-45,0,0},
		RAnkle = {10,0,0}, LAnkle = {10,0,0},
	},
	Crouch = { -- antecipação da decolagem
		Root = {0,0,0, 0,-1.1,0}, Waist = {-28,0,0}, Neck = {30,0,0},
		RShoulder = {-40,0,18}, LShoulder = {-40,0,-18},
		RElbow = {25,0,0}, LElbow = {25,0,0},
		RHip = {75,0,5}, LHip = {75,0,-5},
		RKnee = {-105,0,0}, LKnee = {-105,0,0},
		RAnkle = {35,0,0}, LAnkle = {35,0,0},
	},
	Launch = {
		Waist = {6,0,0}, Neck = {35,0,0},
		RShoulder = {178,0,0}, LShoulder = {-25,0,-20},
		LElbow = {20,0,0},
		RHip = {-6,0,2}, LHip = {4,0,-2},
		RKnee = {-5,0,0}, LKnee = {-25,0,0},
		RAnkle = {-55,0,0}, LAnkle = {-50,0,0},
	},
	SoftLanding = {
		Root = {0,0,0, 0,-0.5,0}, Waist = {-10,0,0}, Neck = {5,0,0},
		RShoulder = {20,0,25}, LShoulder = {20,0,-25},
		RElbow = {20,0,0}, LElbow = {20,0,0},
		RHip = {40,0,4}, LHip = {40,0,-4},
		RKnee = {-60,0,0}, LKnee = {-60,0,0},
		RAnkle = {20,0,0}, LAnkle = {20,0,0},
	},
	HeroLanding = { -- punho no chão, joelho dobrado
		Root = {0,0,0, 0,-1.5,0}, Waist = {-35,8,0}, Neck = {30,0,0},
		RShoulder = {45,0,8}, RElbow = {10,0,0},
		LShoulder = {-40,0,-50}, LElbow = {25,0,0},
		RHip = {100,0,12}, RKnee = {-105,0,0}, RAnkle = {15,0,0},
		LHip = {15,0,-8}, LKnee = {-120,0,0}, LAnkle = {-30,0,0},
	},
}

local POSES = {}
for poseName, def in POSE_DEFS do
	local pose = {}
	for name in joints do
		local d = def[name]
		pose[name] = d and (CFrame.new(d[4] or 0, d[5] or 0, d[6] or 0) * ang(d[1], d[2], d[3])) or CFrame.identity
	end
	POSES[poseName] = pose
end

--==================== FÍSICA ====================--
local att = Instance.new("Attachment")
att.Name = "FlightAttachment"
att.Parent = root

local lv = Instance.new("LinearVelocity")
lv.Attachment0 = att
lv.RelativeTo = Enum.ActuatorRelativeTo.World
lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
lv.MaxForce = 1e9
lv.Enabled = false
lv.Parent = root

local ao = Instance.new("AlignOrientation")
ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
ao.Attachment0 = att
ao.MaxTorque = 1e9
ao.Responsiveness = 25
ao.Enabled = false
ao.Parent = root

--==================== EFEITOS ====================--
local function makeTrail(part, offA, offB, lifetime, startTransp, color)
	local a0 = Instance.new("Attachment"); a0.Position = offA; a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = offB; a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = lifetime
	tr.MinLength = 0.05
	tr.FaceCamera = true
	tr.LightEmission = 1
	tr.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, startTransp), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	tr.Enabled = false
	tr.Parent = part
	return tr
end

local trailColor = Color3.fromRGB(120, 180, 255)
local limbTrails = {}
for _, partName in { "RightHand", "LeftHand", "RightFoot", "LeftFoot" } do
	local p = character:WaitForChild(partName)
	table.insert(limbTrails, makeTrail(p, Vector3.new(-0.12, 0, 0), Vector3.new(0.12, 0, 0), 0.35, 0.35, trailColor))
end
local bodyTrail = makeTrail(character:WaitForChild("UpperTorso"), Vector3.new(-0.9, 0, 0), Vector3.new(0.9, 0, 0), 0.5, 0.7, trailColor)

local wind = Instance.new("ParticleEmitter")
wind.Texture = "rbxasset://textures/particles/sparkles_main.dds"
wind.LightEmission = 1
wind.Lifetime = NumberRange.new(0.15, 0.3)
wind.Speed = NumberRange.new(0)
wind.Size = NumberSequence.new(0.15, 0)
wind.Transparency = NumberSequence.new(0.4, 1)
wind.Rate = 0
wind.Parent = root

local function fxPart(size, color, material)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local shakeAmp, boostShake = 0, 0
local function shake(a) shakeAmp = math.max(shakeAmp, a) end

local function surfaceColor(hit)
	if hit.Instance:IsA("Terrain") then
		local ok, c = pcall(function() return workspace.Terrain:GetMaterialColor(hit.Material) end)
		return ok and c or Color3.fromRGB(120, 110, 100)
	end
	return hit.Instance.Color
end

local function groundRing(pos, size, color, life, material)
	local ring = fxPart(Vector3.new(0.15, 1, 1), color, material)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, size, size), Transparency = 1 }):Play()
	Debris:AddItem(ring, life + 0.1)
end

local function sonicBoom(pos, dir, scale)
	scale = scale or 1
	local unit = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
	local cf
	if math.abs(unit.Y) > 0.99 then
		cf = CFrame.new(pos) * CFrame.Angles(0, 0, rad(90))
	else
		cf = CFrame.lookAt(pos, pos + unit) * CFrame.Angles(0, rad(90), 0) -- eixo X do cilindro = direção do voo
	end
	local ring = fxPart(Vector3.new(0.3, 4, 4), Color3.fromRGB(200, 230, 255), Enum.Material.ForceField)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = cf
	ring.Transparency = 0.1
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, 45 * scale, 45 * scale), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.7)

	local sphere = fxPart(Vector3.one * 3, Color3.new(1, 1, 1), Enum.Material.ForceField)
	sphere.Shape = Enum.PartType.Ball
	sphere.CFrame = CFrame.new(pos)
	sphere.Transparency = 0.3
	sphere.Parent = workspace
	TweenService:Create(sphere, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 25 * scale, Transparency = 1 }):Play()
	Debris:AddItem(sphere, 0.5)

	shake(1.2 * scale)
end

local function impactFX(hit, impact)
	local pos = hit.Position
	local color = surfaceColor(hit)
	groundRing(pos, 30, color, 0.8)
	groundRing(pos, 16, Color3.new(1, 1, 1), 0.35, Enum.Material.ForceField)

	-- cratera (borda de pedras inclinadas pra fora)
	local n = 12
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local rock = fxPart(Vector3.new(math.random(18, 30) / 10, math.random(6, 12) / 10, math.random(14, 22) / 10), color, Enum.Material.Slate)
		rock.CastShadow = true
		rock.CFrame = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.1, -4) * CFrame.Angles(rad(math.random(25, 45)), 0, 0)
		rock.Parent = workspace
		task.delay(2.5, function()
			TweenService:Create(rock, TweenInfo.new(1), { Transparency = 1, Size = rock.Size * 0.5 }):Play()
		end)
		Debris:AddItem(rock, 3.6)
	end

	-- detritos voando
	for _ = 1, math.clamp(math.floor(impact / 10), 6, 18) do
		local s = math.random(3, 8) / 10
		local p = fxPart(Vector3.one * s, color, Enum.Material.Slate)
		p.Anchored = false
		p.CanCollide = true
		p.CFrame = CFrame.new(pos + Vector3.new(math.random(-20, 20) / 10, 0.5, math.random(-20, 20) / 10))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = workspace
		p.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(25, 50), math.random(-30, 30))
		p.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		Debris:AddItem(p, 2.5)
	end
end

--==================== ESTADO ====================--
local state = "Grounded" -- Grounded | Takeoff | Flying | Landing | Recover
local token = 0
local t = 0
local input = { up = false, down = false, boost = false }

local velocity = Vector3.zero
local yaw, pitch, bank, leanF = 0, 0, 0, 0
local speedF, boostF, vertInput, brakeGoal = 0, 0, 0, 0
local wasBoosting, boomReady = false, true
local overridePose, overrideTarget = nil, 0
local masterW = 0
local w = { cruise = 0, boost = 0, asc = 0, desc = 0, brake = 0, override = 0 }

local function startPhysics(initVel)
	velocity = initVel
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	lv.VectorVelocity = velocity
	ao.CFrame = CFrame.Angles(0, yaw, 0)
	lv.Enabled = true
	ao.Enabled = true
end

local function stopPhysics()
	lv.Enabled = false
	ao.Enabled = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	input.up, input.down, input.boost = false, false, false
	wasBoosting = false
end

local function restoreJoints()
	for name, m in joints do
		m.C0 = baseC0[name]
		current[name] = CFrame.identity
	end
end

local function beginFlight()
	token += 1
	local my = token
	local _, y = root.CFrame:ToEulerAnglesYXZ()
	yaw, pitch, bank, leanF = y, 0, 0, 0
	boomReady = true

	if humanoid.FloorMaterial ~= Enum.Material.Air then
		state = "Takeoff"
		overridePose = "Crouch"
		task.delay(CONFIG.CrouchTime, function()
			if token ~= my or state ~= "Takeoff" then return end
			local hit = groundBelow(8)
			if hit then
				local c = surfaceColor(hit)
				groundRing(hit.Position, 14, c, 0.5)
				groundRing(hit.Position, 8, Color3.new(1, 1, 1), 0.3, Enum.Material.ForceField)
			end
			overridePose = "Launch"
			w.override = 1
			overrideTarget = 1
			state = "Flying"
			startPhysics(Vector3.yAxis * CONFIG.TakeoffImpulse)
			shake(0.6)
			task.delay(0.35, function()
				if token == my then overrideTarget = 0 end
			end)
		end)
	else
		overrideTarget = 0
		state = "Flying"
		startPhysics(root.AssemblyLinearVelocity)
	end
end

local function endFlightAir()
	token += 1
	stopPhysics()
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	root.AssemblyLinearVelocity = velocity
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	state = "Recover"
end

local function land(hit, impact)
	token += 1
	local my = token
	local hard = impact >= CONFIG.HardLandingSpeed
	stopPhysics()

	local groundY = hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2
	root.CFrame = CFrame.new(root.Position.X, groundY, root.Position.Z) * CFrame.Angles(0, yaw, 0)
	root.AssemblyLinearVelocity = Vector3.zero

	state = "Landing"
	overridePose = hard and "HeroLanding" or "SoftLanding"
	w.override = 1

	if hard then
		root.Anchored = true
		impactFX(hit, impact)
		shake(2.2)
	else
		groundRing(hit.Position, 9, surfaceColor(hit), 0.4)
		shake(0.3)
	end

	task.delay(hard and CONFIG.HeroLandingTime or 0.25, function()
		if token ~= my then return end
		root.Anchored = false
		state = "Recover"
	end)
end

--==================== VOO ====================--
local function flightStep(dt)
	local camCF = camera.CFrame
	local mv = Controls:GetMoveVector()
	local dir = camCF.LookVector * -mv.Z + camCF.RightVector * mv.X
	local dirMag = math.min(dir.Magnitude, 1)
	local hasDir = dirMag > 0.05
	vertInput = (input.up and 1 or 0) - (input.down and 1 or 0)
	local boosting = input.boost and hasDir

	if boosting and not wasBoosting then
		sonicBoom(root.Position, dir, 0.45)
	end
	wasBoosting = boosting

	-- velocidade
	local targetVel = Vector3.zero
	if hasDir then
		targetVel = dir.Unit * dirMag * (boosting and CONFIG.BoostSpeed or CONFIG.CruiseSpeed)
	end
	targetVel += Vector3.yAxis * vertInput * CONFIG.VerticalSpeed
	velocity = velocity:Lerp(targetVel, alpha(boosting and CONFIG.BoostAcceleration or CONFIG.Acceleration, dt))

	local idle = (not hasDir) and vertInput == 0
	local bob = idle and Vector3.yAxis * math.sin(t * 2.2) * 1.4 or Vector3.zero
	lv.VectorVelocity = velocity + bob

	local speed = velocity.Magnitude
	speedF = math.clamp(speed / CONFIG.CruiseSpeed, 0, 1)
	boostF = math.clamp((speed - CONFIG.CruiseSpeed) / (CONFIG.BoostSpeed - CONFIG.CruiseSpeed), 0, 1)

	-- direção (yaw) + inclinação nas curvas (bank)
	local horiz = Vector3.new(velocity.X, 0, velocity.Z)
	local flat
	if horiz.Magnitude > 6 then
		flat = horiz.Unit
	else
		local cl = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		flat = cl.Magnitude > 0.01 and cl.Unit or root.CFrame.LookVector
	end
	local targetYaw = math.atan2(-flat.X, -flat.Z)
	local dYaw = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
	local step = dYaw * alpha(CONFIG.TurnSpeed, dt)
	yaw += step
	local yawRate = step / math.max(dt, 1e-3)
	bank = damp(bank, math.clamp(-yawRate * CONFIG.BankFactor, -CONFIG.MaxBank, CONFIG.MaxBank) * speedF, 5, dt)

	-- corpo deita conforme a velocidade; segue subida/mergulho
	leanF = damp(leanF, hasDir and speedF or 0, 4, dt)
	local climb = speed > 1 and math.asin(math.clamp(velocity.Y / speed, -1, 1)) or 0
	local braking = (not hasDir) and speed > CONFIG.CruiseSpeed * 0.35
	brakeGoal = braking and math.clamp(speed / CONFIG.CruiseSpeed, 0, 1) or 0
	local targetPitch = (-math.pi / 2 + climb) * leanF + rad(28) * w.brake
	pitch = damp(pitch, targetPitch, 6, dt)

	ao.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, bank, 0)

	-- sonic boom ao romper a "barreira"
	if boostF < 0.3 then
		boomReady = true
	elseif boomReady and boostF > 0.85 then
		boomReady = false
		sonicBoom(root.Position, velocity, 1)
	end

	-- pouso automático
	local descending = velocity.Y < -6 and -velocity.Y > horiz.Magnitude * 0.3
	if descending then
		local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.5 + (-velocity.Y) * dt * 2
		local hit = groundBelow(reach)
		if hit then land(hit, speed) end
	end
end

--==================== CAMADAS PROCEDURAIS ====================--
local function proceduralLayers()
	local L = {}
	local hoverK = (1 - w.cruise) * (1 - w.override)
	local flyK = w.cruise * (1 - w.override)
	local bankDeg = math.deg(bank)
	local jit = w.boost

	-- respiração / flutuação
	L.Root = ang(math.sin(t * 0.9) * 2 * hoverK, 0, math.sin(t * 0.7) * 2 * hoverK)
	L.Waist = ang(math.sin(t * 1.6) * 2.5 * hoverK, bankDeg * 0.25 * flyK, 0)

	-- cabeça acompanha a câmera no hover
	local camLocal = root.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	local headYaw = math.clamp(math.deg(math.atan2(-camLocal.X, -camLocal.Z)), -55, 55)
	local headPitch = math.clamp(math.deg(math.asin(math.clamp(camLocal.Y, -1, 1))), -35, 35)
	L.Neck = ang(headPitch * 0.5 * hoverK, headYaw * 0.6 * hoverK - bankDeg * 0.2 * flyK, 0)

	-- braços: balanço no hover, entram na curva, tremem com o vento no boost
	L.RShoulder = ang(math.sin(t * 31) * 1.2 * jit, 0,
		math.sin(t * 1.3) * 4 * hoverK - bankDeg * 0.3 * flyK + math.cos(t * 27) * 1.2 * jit)
	L.LShoulder = ang(math.sin(t * 29 + 1) * 1.2 * jit, 0,
		-math.sin(t * 1.3 + 0.6) * 4 * hoverK - bankDeg * 0.3 * flyK + math.cos(t * 25) * 1.2 * jit)

	-- pernas: deriva no hover, "flutter" no voo, contrabalanço nas curvas
	local flutter = math.sin(t * 9) * 3 * flyK * (1 - jit * 0.6)
	L.RHip = ang(math.sin(t * 1.1) * 5 * hoverK + flutter, 0, bankDeg * 0.2 * flyK)
	L.LHip = ang(math.sin(t * 1.1 + 1.7) * 5 * hoverK - flutter, 0, bankDeg * 0.2 * flyK)
	L.RAnkle = ang(math.sin(t * 1.1 + 0.5) * 6 * hoverK, 0, 0)
	L.LAnkle = ang(math.sin(t * 1.1 + 2.2) * 6 * hoverK, 0, 0)
	return L
end

local function applyPose(dt)
	local layers = proceduralLayers()
	for name, m in joints do
		local cf = POSES.Hover[name]
		cf = cf:Lerp(POSES.Ascend[name], w.asc)
		cf = cf:Lerp(POSES.Descend[name], w.desc)
		cf = cf:Lerp(POSES.Cruise[name], w.cruise)
		cf = cf:Lerp(POSES.Boost[name], w.boost)
		cf = cf:Lerp(POSES.Brake[name], w.brake)
		if overridePose then
			cf = cf:Lerp(POSES[overridePose][name], w.override)
		end
		local layer = layers[name]
		if layer then cf = cf * layer end
		cf = CFrame.identity:Lerp(cf, masterW)

		current[name] = current[name]:Lerp(cf, alpha(CONFIG.PoseSpeed * 2 * LAG[name], dt))
		m.C0 = baseC0[name] * current[name]
	end
end

--==================== LOOP PRINCIPAL ====================--
local targetFOV = CONFIG.BaseFOV

local function update(dt)
	t += dt
	if state == "Flying" then flightStep(dt) end

	local tgt = { cruise = 0, boost = 0, asc = 0, desc = 0, brake = 0 }
	local overrideGoal, masterGoal = 0, 1
	targetFOV = CONFIG.BaseFOV
	boostShake = 0

	if state == "Flying" then
		tgt.cruise = leanF
		tgt.boost = boostF
		tgt.asc = vertInput > 0 and (1 - leanF) or 0
		tgt.desc = vertInput < 0 and (1 - leanF) or 0
		tgt.brake = brakeGoal
		overrideGoal = overrideTarget
		targetFOV = CONFIG.BaseFOV + (CONFIG.CruiseFOV - CONFIG.BaseFOV) * speedF + (CONFIG.BoostFOV - CONFIG.CruiseFOV) * boostF
		boostShake = boostF * 0.25
	elseif state == "Takeoff" or state == "Landing" then
		overrideGoal = 1
	else
		masterGoal = 0
	end

	for k, v in tgt do w[k] = damp(w[k], v, CONFIG.PoseSpeed, dt) end
	w.override = damp(w.override, overrideGoal, 10, dt)
	masterW = damp(masterW, masterGoal, 12, dt)

	-- efeitos
	local flying = state == "Flying"
	for _, tr in limbTrails do tr.Enabled = flying and speedF > 0.55 end
	bodyTrail.Enabled = flying and boostF > 0.4
	wind.Rate = flying and (boostF * 140 + speedF * 15) or 0

	-- silencia as animações padrão enquanto o voo controla o corpo
	if state == "Flying" or state == "Takeoff" or state == "Landing" then
		for _, track in animator:GetPlayingAnimationTracks() do track:Stop(0.15) end
	end

	if state == "Grounded" then return end
	if state == "Recover" and masterW < 0.02 then
		restoreJoints()
		overridePose = nil
		state = "Grounded"
		return
	end
	applyPose(dt)
end

RunService:BindToRenderStep("SupermanFlight", Enum.RenderPriority.Character.Value + 1, update)

RunService:BindToRenderStep("SupermanFlightCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local amp = shakeAmp + boostShake
	if amp > 0.001 then
		local c = os.clock() * 18
		camera.CFrame *= CFrame.Angles(
			rad(math.noise(c, 0.3) * amp * 2),
			rad(math.noise(0.7, c) * amp * 2),
			rad(math.noise(c, c) * amp))
	end
	shakeAmp = damp(shakeAmp, 0, 5, dt)
	camera.FieldOfView = damp(camera.FieldOfView, targetFOV, 6, dt)
end)

--==================== INPUT ====================--
local Sink, Pass = Enum.ContextActionResult.Sink, Enum.ContextActionResult.Pass

local function onToggle(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then return Pass end
	if state == "Flying" then
		endFlightAir()
	elseif state == "Grounded" or state == "Recover" then
		beginFlight()
	end
	return Sink
end

local function hold(flag)
	return function(_, inputState)
		if state ~= "Flying" and state ~= "Takeoff" then
			input[flag] = false
			return Pass
		end
		input[flag] = inputState == Enum.UserInputState.Begin
		return Sink
	end
end

CAS:BindAction("SF_Toggle", onToggle, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
CAS:BindActionAtPriority("SF_Up", hold("up"), true, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
CAS:BindActionAtPriority("SF_Down", hold("down"), true, 3000, Enum.KeyCode.LeftControl, Enum.KeyCode.Q, Enum.KeyCode.ButtonL2)
CAS:BindActionAtPriority("SF_Boost", hold("boost"), true, 3000, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
CAS:SetTitle("SF_Toggle", "Voar")
CAS:SetTitle("SF_Up", "Subir")
CAS:SetTitle("SF_Down", "Descer")
CAS:SetTitle("SF_Boost", "Boost")

--==================== LIMPEZA ====================--
local cleaned = false
local function cleanup()
	if cleaned then return end
	cleaned = true
	token += 1
	for _, a in { "SF_Toggle", "SF_Up", "SF_Down", "SF_Boost" } do CAS:UnbindAction(a) end
	RunService:UnbindFromRenderStep("SupermanFlight")
	RunService:UnbindFromRenderStep("SupermanFlightCam")
	camera.FieldOfView = CONFIG.BaseFOV
	pcall(stopPhysics)
end
humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)
