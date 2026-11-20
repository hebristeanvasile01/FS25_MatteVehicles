-- Matte Vehicles: lowers smoothness and removes clear coat on all vehicle shapes at runtime.

MatteVehicles = {}

MatteVehicles.SMOOTHNESS_FACTOR = 0.25   -- 1.0 = original gloss, 0.0 = fully matte
MatteVehicles.CHECK_INTERVAL = 1000      -- ms between sweeps for newly loaded vehicles
MatteVehicles.SKIP_NAMES = {
    "glass", "window", "windshield", "light", "lamp", "lens", "mirror",
    "display", "screen", "chrome", "beacon", "led"
}

MatteVehicles.timer = 0

local function skipNode(node)
    local name = string.lower(getName(node) or "")
    for _, part in ipairs(MatteVehicles.SKIP_NAMES) do
        if string.find(name, part, 1, true) ~= nil then
            return true
        end
    end
    return false
end

function MatteVehicles.applyToNode(node)
    if skipNode(node) then
        return
    end

    if getHasClassId(node, ClassIds.SHAPE) and getHasShaderParameter(node, "smoothnessScale") then
        local x, y, z, w = getShaderParameter(node, "smoothnessScale")
        setShaderParameter(node, "smoothnessScale", x * MatteVehicles.SMOOTHNESS_FACTOR, y, z, w, false)

        if getHasShaderParameter(node, "clearCoatIntensity") then
            setShaderParameter(node, "clearCoatIntensity", 0, 0, 0, 0, false)
        end
    end

    for i = 0, getNumOfChildren(node) - 1 do
        MatteVehicles.applyToNode(getChildAt(node, i))
    end
end

function MatteVehicles.applyToVehicle(vehicle)
    if vehicle.components == nil then
        return false
    end

    for _, component in ipairs(vehicle.components) do
        if component.node ~= nil and entityExists(component.node) then
            MatteVehicles.applyToNode(component.node)
        end
    end

    return true
end

function MatteVehicles:update(dt)
    if g_currentMission == nil then
        return
    end

    self.timer = self.timer + dt
    if self.timer < MatteVehicles.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    local vehicles = nil
    if g_currentMission.vehicleSystem ~= nil then
        vehicles = g_currentMission.vehicleSystem.vehicles
    end
    if vehicles == nil then
        vehicles = g_currentMission.vehicles
    end
    if vehicles == nil then
        return
    end

    for _, vehicle in pairs(vehicles) do
        if vehicle.matteApplied == nil and vehicle.isDeleted ~= true then
            if MatteVehicles.applyToVehicle(vehicle) then
                vehicle.matteApplied = true
            end
        end
    end
end

addModEventListener(MatteVehicles)
