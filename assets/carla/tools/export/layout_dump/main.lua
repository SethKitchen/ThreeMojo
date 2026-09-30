-- Write every static mesh component of the loaded level: its mesh, its
-- materials, its world transform and, for an instanced component, each
-- instance's matrix in the component's frame. Units are Unreal's:
-- centimeters, degrees, left-handed, z up.
--
-- A dump starts when REQUEST exists, in the game's binary folder (UE4SS's
-- working directory). Its first line is the output path. The mod deletes
-- REQUEST, writes the layout, and then writes the output path with
-- ".done" added. It also writes each component's name to the output path
-- with ".progress" added before it reads it, so a crash names the
-- component it was reading.
--
-- `dump_layout.py` installs this as a UE4SS Lua mod and drives it.

local REQUEST = "layout_dump_request.txt"
local CLASSES = {
    "StaticMeshComponent",
    "InstancedStaticMeshComponent",
    "HierarchicalInstancedStaticMeshComponent",
    "FoliageInstancedStaticMeshComponent",
    "SplineMeshComponent",
}

local function name_of(object)
    if object == nil or not object:IsValid() then
        return nil
    end
    return object:GetFullName()
end

local function num(x)
    return string.format("%.4f", x)
end

local function vec(v)
    return "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]"
end

local function quote(s)
    if s == nil then
        return "null"
    end
    return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function plane(p)
    return num(p.X) .. "," .. num(p.Y) .. "," .. num(p.Z) .. "," .. num(p.W)
end

local PROGRESS = nil
local function step(tag)
    PROGRESS:write("  ", tag, "\n")
    PROGRESS:flush()
end

local function write_component(out, component, class)
    step("mesh")
    local mesh = name_of(component.StaticMesh)
    if mesh == nil then
        return 0
    end
    step("owner")
    local owner = component:GetOwner()
    step("transform")
    local location = component:K2_GetComponentLocation()
    local rotation = component:K2_GetComponentRotation()
    local scale = component:K2_GetComponentScale()
    step("materials")
    local materials = {}
    local count = component:GetNumMaterials()
    for i = 0, count - 1 do
        materials[#materials + 1] = quote(name_of(component:GetMaterial(i)))
    end
    out:write('{"class":', quote(class),
        ',"owner":', quote(name_of(owner)),
        ',"component":', quote(component:GetFName():ToString()),
        ',"mesh":', quote(mesh),
        ',"visible":', tostring(component:IsVisible()),
        ',"location":', vec(location),
        ',"rotation":[', num(rotation.Pitch), ',', num(rotation.Yaw), ',', num(rotation.Roll), ']',
        ',"scale":', vec(scale),
        ',"materials":[', table.concat(materials, ","), ']')
    if class == "SplineMeshComponent" then
        local p = component.SplineParams
        out:write(',"spline":{"start":', vec(p.StartPos),
            ',"start_tangent":', vec(p.StartTangent),
            ',"end":', vec(p.EndPos),
            ',"end_tangent":', vec(p.EndTangent),
            ',"start_roll":', num(p.StartRoll),
            ',"end_roll":', num(p.EndRoll),
            ',"start_scale":[', num(p.StartScale.X), ',', num(p.StartScale.Y), ']',
            ',"end_scale":[', num(p.EndScale.X), ',', num(p.EndScale.Y), ']',
            ',"forward_axis":', tostring(component.ForwardAxis),
            '}')
    end
    local instances = 0
    if class ~= "StaticMeshComponent" and class ~= "SplineMeshComponent" then
        step("instances")
        out:write(',"instances":[')
        local first = true
        component.PerInstanceSMData:ForEach(function(_, element)
            local m = element:get().Transform
            if not first then
                out:write(",")
            end
            first = false
            out:write("[", plane(m.XPlane), ",", plane(m.YPlane), ",", plane(m.ZPlane), ",", plane(m.WPlane), "]")
            instances = instances + 1
            if instances % 1000 == 0 then
                step(tostring(instances))
            end
        end)
        out:write("]")
    end
    out:write("}\n")
    return math.max(instances, 1)
end

local function dump(path)
    local out = io.open(path, "w")
    local progress = io.open(path .. ".progress", "w")
    PROGRESS = progress
    local seen = {}
    local components, placed = 0, 0
    for _, class in ipairs(CLASSES) do
        local found = FindAllOf(class)
        if found ~= nil then
            for _, component in ipairs(found) do
                local address = component:GetAddress()
                if not seen[address] and component:IsValid() then
                    seen[address] = true
                    progress:write(class, " ", tostring(name_of(component)), "\n")
                    progress:flush()
                    local ok, result = pcall(write_component, out, component, component:GetClass():GetFName():ToString())
                    if ok then
                        placed = placed + result
                        components = components + 1
                        out:flush()
                    else
                        print("[LayoutDump] skipped " .. tostring(name_of(component)) .. ": " .. tostring(result) .. "\n")
                    end
                end
            end
        end
    end
    out:close()
    progress:close()
    local done = io.open(path .. ".done", "w")
    done:write(components, " components, ", placed, " placements\n")
    done:close()
    print("[LayoutDump] " .. path .. ": " .. components .. " components, " .. placed .. " placements\n")
end

LoopAsync(3000, function()
    local request = io.open(REQUEST, "r")
    if request == nil then
        return false
    end
    local path = request:read("*l")
    request:close()
    os.remove(REQUEST)
    ExecuteInGameThread(function()
        collectgarbage("stop")
        local ok, err = pcall(dump, path)
        collectgarbage("restart")
        collectgarbage("collect")
        if not ok then
            print("[LayoutDump] failed: " .. tostring(err) .. "\n")
            local done = io.open(path .. ".done", "w")
            done:write("failed: ", tostring(err), "\n")
            done:close()
        end
    end)
    return false
end)

print("[LayoutDump] waiting for " .. REQUEST .. "\n")
