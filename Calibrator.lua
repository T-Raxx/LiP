-- LiP Firerate Calibrator — STANDALONE + HUD interactivo (Drawing API, 0 instancias = AC-safe).
-- Corré esto SOLO (sin el cheat), jugá legit sosteniendo M1 con cada arma. OBSERVADOR puro del op17
-- (FirearmBullets) del juego: mide el delta REAL entre disparos por arma → el firerate (min robusto ≤ rate
-- real por cuantización de frame → firar a ese intervalo NUNCA excede = seguro vs "rps"/"nc" de v50).
-- Guarda a "LiP_firerates.json" (workspace del executor), AUTOSAVE debounced + botón Save.
--
-- HUD: lista live de armas con firerate/samples. Botones: Save / Reset arma actual / Reset all / Hide.
-- Click en una fila de arma = reset SOLO esa arma (re-medir). Arrastrá la barra de título para mover.
-- Toggle HUD: tecla INSERT. Parar todo: getgenv().__LIP_CAL_STOP().
-- Tamaño del menú: subí `S` (DPI/escala) abajo.

local RS          = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local GuiService  = game:GetService("GuiService")

local SHOOT = 17
local FILE  = "LiP_firerates.json"
local NOISE_LO, NOISE_HI = 0.03, 3

local getncm  = getnamecallmethod
local hookmm  = hookmetamethod
local newcc   = newcclosure or function(f) return f end
local canFile = (type(writefile) == "function") and (type(readfile) == "function")

-- reload-safe: si ya hay una instancia, limpiala. El hook viejo (hookmetamethod no se desinstala) queda
-- INERTE porque su TOKEN capturado ≠ el nuevo → pasa sin grabar. Sin doble-grabado ni clobber de resets.
if getgenv().__LIP_CAL_STOP then pcall(getgenv().__LIP_CAL_STOP) end
local TOKEN = {}
getgenv().__LIP_CAL_TOKEN = TOKEN

local RE = RS:WaitForChild("Events"):WaitForChild("RemoteEvent")
local LP = game:GetService("Players").LocalPlayer

-- ── DB ────────────────────────────────────────────────────────────────────
local db = {}
if canFile and isfile and isfile(FILE) then
    pcall(function() db = HttpService:JSONDecode(readfile(FILE)) end)
end
db = db or {}
local raw, last = {}, {}
for name, e in pairs(db) do
    if type(e) == "table" and type(e._deltas) == "table" then raw[name] = e._deltas end
end

local function robustMin(sorted)
    for i = 1, #sorted do
        if i < #sorted and sorted[i + 1] <= sorted[i] * 1.10 then return sorted[i] end
    end
    return sorted[1]
end
local function recompute(name)
    local ds = raw[name]; if not ds or #ds < 2 then return end
    local s = table.clone(ds); table.sort(s)
    local function pct(p) return s[math.max(1, math.floor(p * #s))] end
    db[name] = { firerate = robustMin(s), min = s[1], p10 = pct(0.10), p25 = pct(0.25),
                 median = pct(0.50), max = s[#s], samples = #s, _deltas = ds }
end
local saveQueued = false
local function save(force)
    if not canFile then return end
    if force then pcall(function() writefile(FILE, HttpService:JSONEncode(db)) end); return end
    if saveQueued then return end
    saveQueued = true
    task.delay(0.5, function() saveQueued = false
        pcall(function() writefile(FILE, HttpService:JSONEncode(db)) end) end)
end
local function resetWeapon(name) raw[name] = nil; db[name] = nil; last[name] = nil; save(true) end
local function resetAll() for k in pairs(db) do db[k] = nil end; raw = {}; last = {}; save(true) end

-- ── observer hook (passthrough) ─────────────────────────────────────────────
local orig
local ok = pcall(function()
    orig = hookmm(game, "__namecall", newcc(function(self, ...)
        if getgenv().__LIP_CAL_TOKEN == TOKEN and self == RE and getncm() == "FireServer" then
            local a1, a2 = ...
            if a1 == SHOOT and typeof(a2) == "Instance" then
                local name = a2.Name
                local now  = os.clock()
                local lt   = last[name]; last[name] = now
                if lt then
                    local dt = now - lt
                    if dt > NOISE_LO and dt < NOISE_HI then
                        local ds = raw[name]; if not ds then ds = {}; raw[name] = ds end
                        ds[#ds + 1] = dt
                        if #ds > 800 then table.remove(ds, 1) end
                        recompute(name); save()
                    end
                end
            end
        end
        return orig(self, ...)
    end))
end)
if not ok then warn("[Calibrator] no pude hookear (executor sin hookmetamethod?)."); return end

-- ══ HUD (Drawing API) ════════════════════════════════════════════════════════
local S = 1.6                                        -- DPI / escala del menú (subí para MÁS grande)
local FS_TITLE = math.floor(16 * S)
local FS_STAT  = math.floor(13 * S)
local FS_ROW   = math.floor(13 * S)
local FS_BTN   = math.floor(13 * S)
local FS_HINT  = math.floor(11 * S)
local ROW_H    = math.floor(17 * S)
local HEAD_H   = math.floor(38 * S)
local BAR_H    = math.floor(24 * S)
local BTN_H    = math.floor(22 * S)
local PAD      = math.floor(9 * S)
local ROWS_MAX = 18

-- ox,oy en espacio ABSOLUTO de pantalla (mismo que Drawing). El mouse se convierte a este espacio
-- sumándole el GuiInset (GetMouseLocation es viewport = bajo el topbar).
local hud = { visible = true, ox = 50, oy = 150, w = math.floor(320 * S), dragging = false, dragOff = nil }
local INSET = GuiService:GetGuiInset()

local COL = {
    bg   = Color3.fromRGB(18, 18, 24),  bar = Color3.fromRGB(32, 26, 54),
    acc  = Color3.fromRGB(140, 105, 255), txt = Color3.fromRGB(236, 236, 246),
    dim  = Color3.fromRGB(150, 150, 168), btn = Color3.fromRGB(48, 48, 64),
    good = Color3.fromRGB(120, 220, 150), warn = Color3.fromRGB(240, 180, 90),
}
local draws = {}
local function mk(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    draws[#draws + 1] = d
    return d
end
local function P(x, y) return Vector2.new(hud.ox + x, hud.oy + y) end     -- Drawing space (absoluto)

local bg     = mk("Square", { Filled = true, Color = COL.bg,  Transparency = 0.93, ZIndex = 90 })
local barBg  = mk("Square", { Filled = true, Color = COL.bar, Transparency = 1,    ZIndex = 91 })
local accent = mk("Square", { Filled = true, Color = COL.acc, Transparency = 1,    ZIndex = 92 })
local title  = mk("Text",   { Text = "LiP Firerate Calibrator", Size = FS_TITLE, Color = COL.txt, ZIndex = 93 })
local status = mk("Text",   { Text = "", Size = FS_STAT, Color = COL.dim, ZIndex = 93 })
local hint   = mk("Text",   { Text = "click fila = reset arma  ·  INSERT oculta", Size = FS_HINT, Color = COL.dim, ZIndex = 93 })

local rowPool = {}
for i = 1, ROWS_MAX do rowPool[i] = mk("Text", { Text = "", Size = FS_ROW, Color = COL.txt, ZIndex = 93, Visible = false }) end

local buttons = {}
local function addButton(label, onClick)
    buttons[#buttons + 1] = {
        bgD  = mk("Square", { Filled = true, Color = COL.btn, Transparency = 1, ZIndex = 92, Visible = false }),
        txtD = mk("Text",   { Text = label, Size = FS_BTN, Color = COL.txt, Center = true, ZIndex = 93, Visible = false }),
        onClick = onClick, rect = { 0, 0, 0, 0 },
    }
end
addButton("Save",       function() save(true) end)
addButton("Reset arma", function()
    local t = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
    if t then resetWeapon(t.Name) end
end)
addButton("Reset all",  function() resetAll() end)
addButton("Hide",       function() hud.visible = false end)

local rowRects = {}
local function sortedNames()
    local t = {}; for name in pairs(db) do t[#t + 1] = name end; table.sort(t); return t
end
local function layout()
    local names = sortedNames()
    local nrow  = math.min(#names, ROWS_MAX)
    local rowY0 = HEAD_H
    local btnY  = rowY0 + math.max(nrow, 1) * ROW_H + PAD
    local totalH = btnY + BTN_H + PAD + FS_HINT + PAD

    bg.Size   = Vector2.new(hud.w, totalH);   bg.Position   = P(0, 0)
    barBg.Size = Vector2.new(hud.w, BAR_H);   barBg.Position = P(0, 0)
    accent.Size = Vector2.new(hud.w, math.max(2, math.floor(2*S))); accent.Position = P(0, BAR_H)
    title.Position  = P(PAD, math.floor(4*S))
    local eq = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
    status.Text = string.format("armas: %d   ·   equipada: %s", #names, eq and eq.Name or "—")
    status.Position = P(PAD, BAR_H + math.floor(4*S))

    rowRects = {}
    for i = 1, ROWS_MAX do
        local d, name = rowPool[i], names[i]
        if name and i <= nrow then
            local e  = db[name]
            local fr = e.firerate or 0
            d.Text = string.format("%-13s %.4fs  %5.1f/s   n=%d", name:sub(1, 13), fr, fr > 0 and 1/fr or 0, e.samples or 0)
            d.Color = (e.samples or 0) >= 8 and COL.good or COL.warn
            d.Position = P(PAD + math.floor(2*S), rowY0 + (i - 1) * ROW_H)
            d.Visible = hud.visible
            rowRects[#rowRects + 1] = { name = name, x = 0, y = rowY0 + (i - 1) * ROW_H, w = hud.w, h = ROW_H }
        else
            d.Visible = false
        end
    end

    local n = #buttons
    local gap = math.floor(6 * S)
    local bw  = (hud.w - 2 * PAD - (n - 1) * gap) / n
    for i, b in ipairs(buttons) do
        local x = PAD + (i - 1) * (bw + gap)
        b.rect = { x, btnY, bw, BTN_H }
        b.bgD.Size = Vector2.new(bw, BTN_H); b.bgD.Position = P(x, btnY); b.bgD.Visible = hud.visible
        b.txtD.Position = P(x + bw / 2, btnY + math.floor(4*S)); b.txtD.Visible = hud.visible
    end
    hint.Position = P(PAD, btnY + BTN_H + PAD)

    bg.Visible = hud.visible; barBg.Visible = hud.visible; accent.Visible = hud.visible
    title.Visible = hud.visible; status.Visible = hud.visible; hint.Visible = hud.visible
end
local renderConn = RunService.RenderStepped:Connect(function() pcall(layout) end)

-- ── input (mouse en espacio absoluto = GetMouseLocation + inset) ─────────────
local function mouse() return UIS:GetMouseLocation() + INSET end
local function inRect(m, x, y, w, h)
    return m.X >= hud.ox + x and m.X <= hud.ox + x + w and m.Y >= hud.oy + y and m.Y <= hud.oy + y + h
end

local conns = {}
conns[#conns + 1] = UIS.InputBegan:Connect(function(inp)
    if inp.KeyCode == Enum.KeyCode.Insert then hud.visible = not hud.visible; return end
    if inp.UserInputType ~= Enum.UserInputType.MouseButton1 or not hud.visible then return end
    local m = mouse()
    if inRect(m, 0, 0, hud.w, BAR_H) then                       -- barra título → drag
        hud.dragging = true; hud.dragOff = Vector2.new(m.X - hud.ox, m.Y - hud.oy); return
    end
    for _, b in ipairs(buttons) do
        local r = b.rect
        if inRect(m, r[1], r[2], r[3], r[4]) then pcall(b.onClick); return end
    end
    for _, rr in ipairs(rowRects) do
        if inRect(m, rr.x, rr.y, rr.w, rr.h) then resetWeapon(rr.name); return end
    end
end)
conns[#conns + 1] = UIS.InputChanged:Connect(function(inp)
    if hud.dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local m = mouse(); hud.ox = m.X - hud.dragOff.X; hud.oy = m.Y - hud.dragOff.Y
    end
end)
conns[#conns + 1] = UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then hud.dragging = false end
end)

-- ── control global ──────────────────────────────────────────────────────────
getgenv().__LIP_CAL = true
getgenv().__LIP_CAL_DB = db
getgenv().__LIP_CAL_STOP = function()
    save(true)
    pcall(function() renderConn:Disconnect() end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(draws) do pcall(function() d:Remove() end) end
    getgenv().__LIP_CAL = nil
    getgenv().__LIP_CAL_TOKEN = nil
    warn("[Calibrator] detenido. Data en " .. FILE)
end

print(string.format("[Calibrator] HUD activo (INSERT oculta, escala S=%.1f). Sostené M1 con cada arma. Archivo: %s%s",
    S, FILE, canFile and "" or "  (⚠ executor SIN writefile → solo memoria)"))
