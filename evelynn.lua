if myHero.charName ~= "Evelynn" then return end
require("DamageLib")
local _atan = math.atan2
local _min = math.min
local _abs = math.abs
local _sqrt = math.sqrt
local _floor = math.floor
local _max = math.max
local _pow = math.pow
local _huge = math.huge
local _pi = math.pi
local _insert = table.insert
local _contains = table.contains
local _sort = table.sort
local _pairs = pairs
local _find = string.find
local _sub = string.sub
local _len = string.len

local LocalDrawLine = Draw.Line;
local LocalDrawColor = Draw.Color;
local LocalDrawCircle = Draw.Circle;
local LocalDrawCircleMinimap = Draw.CircleMinimap;
local LocalDrawText = Draw.Text;
local LocalControlIsKeyDown = Control.IsKeyDown;
local LocalControlMouseEvent = Control.mouse_event;
local LocalControlSetCursorPos = Control.SetCursorPos;
local LocalControlCastSpell = Control.CastSpell;
local LocalControlKeyUp = Control.KeyUp;
local LocalControlKeyDown = Control.KeyDown;
local LocalControlMove = Control.Move;
local LocalGetTickCount = GetTickCount;
local LocalGamecursorPos = Game.cursorPos;
local LocalGameCanUseSpell = Game.CanUseSpell;
local LocalGameLatency = Game.Latency;
local LocalGameTimer = Game.Timer;
local LocalGameHeroCount = Game.HeroCount;
local LocalGameHero = Game.Hero;
local LocalGameMinionCount = Game.MinionCount;
local LocalGameMinion = Game.Minion;
local LocalGameTurretCount = Game.TurretCount;
local LocalGameTurret = Game.Turret;
local LocalGameWardCount = Game.WardCount;
local LocalGameWard = Game.Ward;
local LocalGameObjectCount = Game.ObjectCount;
local LocalGameObject = Game.Object;
local LocalGameMissileCount = Game.MissileCount;
local LocalGameMissile = Game.Missile;
local LocalGameParticleCount = Game.ParticleCount;
local LocalGameParticle = Game.Particle;
local LocalGameIsChatOpen = Game.IsChatOpen;
local LocalGameIsOnTop = Game.IsOnTop;
function GetGameObjects()
    --EnemyHeroes = {}
    print(Game.ObjectCount())
    for i = 1, Game.ObjectCount() do
        local GameObject = Game.Object(i)
        if GameObject.isEnemy then
            if GameObject.charName:match("Cait") then
                if EnemyTraps[GameObject.name] == nil then
                    print(GameObject.isEnemy)
                    print(GameObject.type)
                    print(GameObject.name)
                    print(GameObject.pos)
                    print(EnemyTraps[GameObject.name])
                    Draw.Circle(GameObject.pos, GameObject.boundingRadius, 10, Draw.Color(255, 255, 255, 255))
                    Draw.Text(GameObject.name, 17, GameObject.pos2D.x - 45, GameObject.pos2D.y + 10, Draw.Color(0xFF32CD32))
                    EnemyTraps[GameObject.name] = GameObject.name
                end
            end
        end
    end
    if Game.ObjectCount() == 0 then
        EnemyTraps = {}
    end
--return EnemyHeroes
end

local units = {}

for i = 1, Game.HeroCount() do
    local unit = Game.Hero(i)
    units[i] = {unit = unit, spell = nil}
end

function GetMode()
    if _G.SDK then
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            return "Combo"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            return "Harass"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            return "Clear"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_FLEE] then
            return "Flee"
        end
    else
        return GOS.GetMode()
    end
end

function IsReady(spell)
    return Game.CanUseSpell(spell) == 0
end

function ValidTarget(target, range)
    range = range and range or math.huge
    return target ~= nil and target.valid and target.visible and not target.dead and target.distance <= range
end

function GetDistance(p1, p2)
    return _sqrt(_pow((p2.x - p1.x), 2) + _pow((p2.y - p1.y), 2) + _pow((p2.z - p1.z), 2))
end

function GetDistance2D(p1, p2)
    return _sqrt(_pow((p2.x - p1.x), 2) + _pow((p2.y - p1.y), 2))
end

local _OnWaypoint = {}
function OnWaypoint(unit)
    if _OnWaypoint[unit.networkID] == nil then _OnWaypoint[unit.networkID] = {pos = unit.posTo, speed = unit.ms, time = LocalGameTimer()} end
    if _OnWaypoint[unit.networkID].pos ~= unit.posTo then
        _OnWaypoint[unit.networkID] = {startPos = unit.pos, pos = unit.posTo, speed = unit.ms, time = LocalGameTimer()}
        DelayAction(function()
            local time = (LocalGameTimer() - _OnWaypoint[unit.networkID].time)
            local speed = GetDistance2D(_OnWaypoint[unit.networkID].startPos, unit.pos) / (LocalGameTimer() - _OnWaypoint[unit.networkID].time)
            if speed > 1250 and time > 0 and unit.posTo == _OnWaypoint[unit.networkID].pos and GetDistance(unit.pos, _OnWaypoint[unit.networkID].pos) > 200 then
                _OnWaypoint[unit.networkID].speed = GetDistance2D(_OnWaypoint[unit.networkID].startPos, unit.pos) / (LocalGameTimer() - _OnWaypoint[unit.networkID].time)
            end
        end, 0.05)
    end
    return _OnWaypoint[unit.networkID]
end

function VectorPointProjectionOnLineSegment(v1, v2, v)
    local cx, cy, ax, ay, bx, by = v.x, (v.z or v.y), v1.x, (v1.z or v1.y), v2.x, (v2.z or v2.y)
    local rL = ((cx - ax) * (bx - ax) + (cy - ay) * (by - ay)) / ((bx - ax) ^ 2 + (by - ay) ^ 2)
    local pointLine = {x = ax + rL * (bx - ax), y = ay + rL * (by - ay)}
    local rS = rL < 0 and 0 or (rL > 1 and 1 or rL)
    local isOnSegment = rS == rL
    local pointSegment = isOnSegment and pointLine or {x = ax + rS * (bx - ax), y = ay + rS * (by - ay)}
    return pointSegment, pointLine, isOnSegment
end

function GetMinionCollision(StartPos, EndPos, Width, Target)
    local Count = 0
    for i = 1, LocalGameMinionCount() do
        local m = LocalGameMinion(i)
        if m and not m.isAlly then
            local w = Width + m.boundingRadius
            local pointSegment, pointLine, isOnSegment = VectorPointProjectionOnLineSegment(StartPos, EndPos, m.pos)
            if isOnSegment and GetDistanceSqr(pointSegment, m.pos) < w ^ 2 and GetDistanceSqr(StartPos, EndPos) > GetDistanceSqr(StartPos, m.pos) then
                Count = Count + 1
            end
        end
    end
    return Count
end

function GetDistanceSqr(Pos1, Pos2)
    local Pos2 = Pos2 or myHero.pos
    local dx = Pos1.x - Pos2.x
    local dz = (Pos1.z or Pos1.y) - (Pos2.z or Pos2.y)
    return dx ^ 2 + dz ^ 2
end

function GetEnemyHeroes()
    EnemyHeroes = {}
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy then
            table.insert(EnemyHeroes, Hero)
        end
    end
    return EnemyHeroes
end

function IsUnderTurret(unit)
    for i = 1, Game.TurretCount() do
        local turret = Game.Turret(i);
        if turret and turret.isEnemy and turret.valid and turret.health > 0 then
            if GetDistance(unit, turret.pos) <= 850 then
                return true
            end
        end
    end
    return false
end
Evelynn = class()

function OnLoad()
    if GetChampName(GetMyChamp()) == "Evelynn" then
		Evelynn:Assasin()
	end
end

function Evelynn:Assasin()

    SetLuaCombo(true)
    SetLuaLaneClear(true)

    self.JungleMoster = minionManager(MINION_JUNGLE, 2000, myHero, MINION_SORT_HEALTH_ASC)
    self.Predc = VPrediction(true)
  
    self:EveMenus()
  
    self.Q = Spell(_Q, 800)
    self.Q2 = Spell(_Q, 550)
    self.W = Spell(_W, 1100)
    self.E = Spell(_E, 350)
    self.R = Spell(_R, 500)

    self.Wstack = 0
    self.SpawW = 0
    self.MakedW = false
  
    self.Q:SetSkillShot(0.54, math.huge, 200, false)
    self.Q2:SetTargetted()
    self.W:SetTargetted()
    self.E:SetTargetted()
    self.R:SetSkillShot(0.25, math.huge, 150 ,false)
  
    Callback.Add("Tick", function() self:OnTick() end) 
    Callback.Add("Draw", function(...) self:OnDraw(...) end)
    Callback.Add("DrawMenu", function(...) self:OnDrawMenu(...) end)
    Callback.Add("UpdateBuff", function(...) self:OnUpdateBuff(...) end)
    Callback.Add("RemoveBuff", function(...) self:OnRemoveBuff(...) end)
    Callback.Add("ProcessSpell", function(...) self:OnProcessSpell(...) end)
  
  end 

  --SDK {{Toir+}}
function Evelynn:MenuBool(stringKey, bool)
	return ReadIniBoolean(self.menu, stringKey, bool)
end

function Evelynn:MenuSliderInt(stringKey, valueDefault)
	return ReadIniInteger(self.menu, stringKey, valueDefault)
end

function Evelynn:MenuKeyBinding(stringKey, valueDefault)
	return ReadIniInteger(self.menu, stringKey, valueDefault)
end

function Evelynn:MenuComboBox(stringKey, valueDefault)
	return ReadIniInteger(self.menu, stringKey, valueDefault)
end

function Evelynn:EveMenus()
    self.menu = "Evelynn Jungle"
    --Combo [[ Evelynn ]]
	self.CQ = self:MenuBool("Combo Q", true)
	self.CW = self:MenuBool("Combo W", true)
    self.CE = self:MenuBool("Combo E", true)
    self.ModeQ = self:MenuComboBox("Mode [Q]", 0)
    
    --Jungle
    self.JQ = self:MenuBool("Jungle Q", true)
    self.JE = self:MenuBool("Jungle E", true)
    self.JMana = self:MenuSliderInt("Mana Jungle %", 45)

    --Add R
    self.CR = self:MenuBool("Combo R", true)
    self.UseRLogic = self:MenuBool("Use Logic R", true)
    self.UseRmy = self:MenuSliderInt("HP Minimum %", 45)
    self.UseRange = self:MenuSliderInt("Range Enemys", 2)

    --KillSteal [[ Evelynn ]]
    self.KQ = self:MenuBool("KillSteal > Q", true)
    self.KE = self:MenuBool("KillSteal > E", true)
    self.KR = self:MenuBool("KillSteal > R", true)

    --Draws [[ Evelynn ]]
    self.DQWER = self:MenuBool("Draw On/Off", true)
    self.DQ = self:MenuBool("Draw Q", true)
    self.DE = self:MenuBool("Draw E", true)
    self.DR = self:MenuBool("Draw R", true)

    --Misc [[ Evelynn ]]
    --self.LogicR = self:MenuBool("Use Logic R?", true)]]

    --KeyStone [[ Evelynn ]]
	self.Combo = self:MenuKeyBinding("Combo", 32)
    self.LaneClear = self:MenuKeyBinding("Lane Clear", 86)
end

function Evelynn:OnDrawMenu()
	if Menu_Begin(self.menu) then
		if Menu_Begin("Combo") then
            self.CQ = Menu_Bool("Combo Q", self.CQ, self.menu)
            self.ModeQ = Menu_ComboBox("Mode [Q]", self.ModeQ, "Always\0Only with the brand\0\0", self.menu)
			self.CW = Menu_Bool("Combo W", self.CW, self.menu)
            self.CE = Menu_Bool("Combo E", self.CE, self.menu)
			Menu_End()
        end
        if Menu_Begin("Jungle") then
			self.JQ = Menu_Bool("Jungle Q", self.JQ, self.menu)
			self.JE = Menu_Bool("Jungle E", self.JE, self.menu)
            self.JMana = Menu_SliderInt("Mana %", self.JMana, 0, 100, self.menu)
			Menu_End()
        end
        if Menu_Begin("Draws") then
            self.DQWER = Menu_Bool("Draw On/Off", self.DQWER, self.menu)
            self.DQ = Menu_Bool("Draw Q", self.DQ, self.menu)
            self.DE = Menu_Bool("Draw E", self.DE, self.menu)
			self.DR = Menu_Bool("Draw R", self.DR, self.menu)
			Menu_End()
        end
        if Menu_Begin("Configuration [R]") then
            self.CR = Menu_Bool("Combo R", self.CR, self.menu)
			Menu_End()
        end
        if Menu_Begin("Logic [R]") then
            self.UseRLogic = Menu_Bool("Logic R", self.UseRLogic, self.menu)
            self.UseRmy = Menu_SliderInt("My HP Minimum %", self.UseRmy, 0, 100, self.menu)
            self.UseRange = Menu_SliderInt("Range Enemys %", self.UseRange, 0, 5, self.menu)
			Menu_End()
        end
        if Menu_Begin("KillSteal") then
            self.KQ = Menu_Bool("KillSteal > Q", self.KQ, self.menu)
            self.KE = Menu_Bool("KillSteal > E", self.KE, self.menu)
            self.KR = Menu_Bool("KillSteal > R", self.KR, self.menu)
			Menu_End()
        end
		if Menu_Begin("KeyStone") then
			self.Combo = Menu_KeyBinding("Combo", self.Combo, self.menu)
            self.LaneClear = Menu_KeyBinding("Lane Clear", self.LaneClear, self.menu)
			Menu_End()
		end
		Menu_End()
	end
end

function Evelynn:OnProcessSpell(unit,spell)
    if unit.IsMe and spell.Name == "EvelynnW" then
      if self.SpawW > 0 then
        self.SpawW = self.SpawW - 1
    end
   end
end

function Evelynn:OnUpdateBuff(source, unit, buff, stacks)
    if unit.IsEnemy and buff.Name == "EvelynnW" then
        self.MakedW = true
        self.Wstack = buff.Count
    end
end

function Evelynn:OnRemoveBuff(unit, buff)
    if unit.IsEnemy and buff.Name == "EvelynnW" then
        self.MakedW = false
        self.Wstack = buff.Count
    end
end

function Evelynn:OnDraw()
    if self.DQWER then

    if self.DQ and self.Q:IsReady() then
        DrawCircleGame(myHero.x, myHero.y, myHero.z,self.Q.range, Lua_ARGB(255,255,0,0))
      end

      if self.DE and self.E:IsReady() then
        DrawCircleGame(myHero.x, myHero.y, myHero.z, self.E.range, Lua_ARGB(255,0,0,255))
      end

      if self.DR and self.R:IsReady() then
        DrawCircleGame(myHero.x, myHero.y, myHero.z, self.R.range, Lua_ARGB(255,0,0,255))
    end
   end 
end 

function Evelynn:FishEnemy()
    local UseQ = GetTargetSelector(800)
    Enemy = GetAIHero(UseQ)
    if CanCast(_Q) and self.KQ and UseQ ~= 0 and GetDistance(Enemy) < self.Q.range and GetDamage("Q", Enemy) > Enemy.HP then
        local CQPosition, HitChance, Position = self.Predc:GetLineCastPosition(Enemy, self.Q.delay, self.Q.width, self.Q.range, self.Q.speed, myHero, false)
        local Sun = CountObjectCollision(0, Enemy.Addr, myHero.x, myHero.z, CQPosition.x, CQPosition.z, self.Q.width, self.Q.range, 10)
		if Sun == 0 and HitChance >= 2 then
			CastSpellToPos(CQPosition.x, CQPosition.z, _Q)
        end
    end 
    local UseR = GetTargetSelector(500)
    EnemyR = GetAIHero(UseR)
    if CanCast(_R) and self.KR and UseR ~= 0 and GetDistance(EnemyR) < self.R.range and GetDamage("R", EnemyR) > EnemyR.HP then
        local CRPosition, HitChance, Position = self.Predc:GetLineCastPosition(Enemy, self.R.delay, self.R.width, self.R.range, self.R.speed, myHero, false)
		if HitChance >= 2 then
            CastSpellToPos(CRPosition.x, CRPosition.z, _R)
        end 
    end 
    local UseE = GetTargetSelector(350)
    Enemy = GetAIHero(UseE)
    if CanCast(_E) and self.KE and UseE ~= 0 and GetDistance(Enemy) < self.E.range and GetDamage("E", Enemy) > Enemy.HP then
       CastSpellTarget(Enemy.Addr, _E)
    end 
end 

function Evelynn:QPaixon()
    local UseQ = GetTargetSelector(800)
    Enemy = GetAIHero(UseQ)
    if self.ModeQ == 0 then
    if CanCast(_Q) and self.CQ and self.Wstack and UseQ ~= 0 and GetDistance(Enemy) < self.Q.range then
        local CQPosition, HitChance, Position = self.Predc:GetLineCastPosition(Enemy, self.Q.delay, self.Q.width, self.Q.range, self.Q.speed, myHero, false)
        local Sun = CountObjectCollision(0, Enemy.Addr, myHero.x, myHero.z, CQPosition.x, CQPosition.z, self.Q.width, self.Q.range, 10)
		if Sun == 0 and HitChance >= 2 then
			CastSpellToPos(CQPosition.x, CQPosition.z, _Q)
        end
    end 
end
    
    local UseQ2 = GetTargetSelector(550)
    Enemy = GetAIHero(UseQ2)
    if CanCast(_Q) and self.CQ and UseQ2 ~= 0 and GetDistance(Enemy) < self.Q2.range then
            CastSpellTarget(Enemy.Addr, _Q)
    end 
end 
   

function Evelynn:WIsMaKed()
    local UseW = GetTargetSelector(1100)
    Enemy = GetAIHero(UseW)
    if CanCast(_W) and self.CW and UseW ~= 0 then
        CastSpellTarget(Enemy.Addr, _W)
    end
end 

function Evelynn:Epos()
    local UseE = GetTargetSelector(350)
    Enemy = GetAIHero(UseE)
    if CanCast(_E) and self.CE and UseE ~= 0 then
        CastSpellTarget(Enemy.Addr, _E)
    end
end 

function Evelynn:Jungo()
    if CanCast(_Q) and self.JQ and GetPercentMP(myHero.Addr) >= self.JMana and (GetType(GetTargetOrb()) == 3) then
		if (GetObjName(GetTargetOrb()) ~= "PlantSatchel" and GetObjName(GetTargetOrb()) ~= "PlantHealth" and GetObjName(GetTargetOrb()) ~= "PlantVision") then
			target = GetUnit(GetTargetOrb())
	    	local targetPos, HitChance, Position = self.Predc:GetLineCastPosition(target, self.Q.delay, self.Q.width, self.Q.range, self.Q.speed, myHero, false)
			CastSpellToPos(targetPos.x, targetPos.z, _Q)
		end
    end
    if CanCast(_E) and self.JE and GetPercentMP(myHero.Addr) >= self.JMana and (GetType(GetTargetOrb()) == 3) then
		if (GetObjName(GetTargetOrb()) ~= "PlantSatchel" and GetObjName(GetTargetOrb()) ~= "PlantHealth" and GetObjName(GetTargetOrb()) ~= "PlantVision") then
			target = GetUnit(GetTargetOrb())
			CastSpellTarget(target.Addr, _E)
		end
	end
end

function Evelynn:RIsEnemy()
    local UseR = GetTargetSelector(self.R.range)
    Enemy = GetAIHero(UseR)
    if CanCast(_R) and UseR ~= 0 and IsValidTarget(Enemy, self.R.range) and Enemy.HP*100/Enemy.MaxHP < 25 then 
        local CrPosition, HitChance, Position = self.Predc:GetLineCastPosition(Enemy, self.R.delay, self.R.width, self.R.range, self.R.speed, myHero, false)
        if HitChance >= 2 then
        CastSpellToPos(CrPosition.x, CrPosition.z, _R)
        end
    end
end 

function Evelynn:LogicRIsEnemy()
    local UseR = GetTargetSelector(self.R.range)
    Enemy = GetAIHero(UseR)
    if CanCast(R) and UseR ~= 0 and self.CR and IsValidTarget(Enemy, self.R.range) and CountEnemyChampAroundObject(Enemy, self.R.range) <= self.UseRange and GetPercentHP(myHero.Addr) < self.UseRmy then 
        local CrPosition, HitChance, Position = self.Predc:GetLineCastPosition(Enemy, self.R.delay, self.R.width, self.R.range, self.R.speed, myHero, false)
        if HitChance >= 2 then
        CastSpellToPos(CrPosition.x, CrPosition.z, _R)
        end
    end 
end 


function Evelynn:OnTick()
    if IsDead(myHero.Addr) or IsTyping() or IsDodging() then return end

    self:FishEnemy()
    self:LogicRIsEnemy()

    if GetSpellLevel(GetMyChamp(), _W) >= 1 then
        self.W.range = 1100 * GetSpellLevel(GetMyChamp(), _W) + 100
    end

    if GetKeyPress(self.LaneClear) > 0 then	
        self:Jungo()
    end

	if GetKeyPress(self.Combo) > 0 then	
		self:QPaixon()
        self:WIsMaKed()
        self:Epos()
        self:RIsEnemy()
    end
end 
