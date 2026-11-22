-- Matte Vehicles: lowers smoothness and removes clear coat on all vehicle shapes at runtime.
-- On / Off switch lives in the game settings (General settings page), saved in modSettings.

MatteVehicles = {}

MatteVehicles.modName = g_currentModName
MatteVehicles.SMOOTHNESS_FACTOR = 0.25   -- 1.0 = original gloss, 0.0 = fully matte
MatteVehicles.CHECK_INTERVAL = 1000      -- ms between sweeps for newly loaded vehicles
-- always left untouched
MatteVehicles.SKIP_NAMES = {
    "glass", "window", "windshield", "light", "lamp", "lens",
    "display", "screen", "beacon", "led"
}
-- left untouched unless the "chrome parts" option is on
MatteVehicles.CHROME_NAMES = { "mirror", "chrome" }

MatteVehicles.enabled = true
MatteVehicles.matteChrome = false
MatteVehicles.timer = 0

-- ------------------------------------------------------------------ settings file

function MatteVehicles.getSettingsPath()
    return getUserProfileAppPath() .. "modSettings/FS25_MatteVehicles.xml"
end

function MatteVehicles.loadSettings()
    local path = MatteVehicles.getSettingsPath()
    if fileExists(path) then
        local xml = loadXMLFile("MatteVehiclesSettings", path)
        if xml ~= nil and xml ~= 0 then
            local value = getXMLBool(xml, "matteVehicles#enabled")
            if value ~= nil then MatteVehicles.enabled = value end
            local chrome = getXMLBool(xml, "matteVehicles#matteChrome")
            if chrome ~= nil then MatteVehicles.matteChrome = chrome end
            delete(xml)
        end
    end
end

function MatteVehicles.saveSettings()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    local xml = createXMLFile("MatteVehiclesSettings", MatteVehicles.getSettingsPath(), "matteVehicles")
    if xml ~= nil and xml ~= 0 then
        setXMLBool(xml, "matteVehicles#enabled", MatteVehicles.enabled)
        setXMLBool(xml, "matteVehicles#matteChrome", MatteVehicles.matteChrome)
        saveXMLFile(xml)
        delete(xml)
    end
end

-- ------------------------------------------------------------------ paint

local function nameHasAny(name, list)
    for _, part in ipairs(list) do
        if string.find(name, part, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function skipNode(node)
    local name = string.lower(getName(node) or "")
    if nameHasAny(name, MatteVehicles.SKIP_NAMES) then
        return true
    end
    if nameHasAny(name, MatteVehicles.CHROME_NAMES) then
        return not MatteVehicles.matteChrome
    end
    return false
end

-- saved originals go into `saved` so the paint can be restored when the option is turned off
function MatteVehicles.applyToNode(node, saved)
    if skipNode(node) then
        return
    end

    if getHasClassId(node, ClassIds.SHAPE) and getHasShaderParameter(node, "smoothnessScale") then
        local x, y, z, w = getShaderParameter(node, "smoothnessScale")
        local entry = { node = node, smooth = { x, y, z, w } }
        setShaderParameter(node, "smoothnessScale", x * MatteVehicles.SMOOTHNESS_FACTOR, y, z, w, false)

        if getHasShaderParameter(node, "clearCoatIntensity") then
            local cx, cy, cz, cw = getShaderParameter(node, "clearCoatIntensity")
            entry.clear = { cx, cy, cz, cw }
            setShaderParameter(node, "clearCoatIntensity", 0, 0, 0, 0, false)
        end
        table.insert(saved, entry)
    end

    for i = 0, getNumOfChildren(node) - 1 do
        MatteVehicles.applyToNode(getChildAt(node, i), saved)
    end
end

function MatteVehicles.applyToVehicle(vehicle)
    if vehicle.components == nil then
        return false
    end

    local saved = {}
    for _, component in ipairs(vehicle.components) do
        if component.node ~= nil and entityExists(component.node) then
            MatteVehicles.applyToNode(component.node, saved)
        end
    end
    vehicle.matteSaved = saved

    return true
end

function MatteVehicles.restoreVehicle(vehicle)
    if vehicle.matteSaved ~= nil then
        for _, entry in ipairs(vehicle.matteSaved) do
            if entityExists(entry.node) then
                local s = entry.smooth
                setShaderParameter(entry.node, "smoothnessScale", s[1], s[2], s[3], s[4], false)
                if entry.clear ~= nil then
                    local c = entry.clear
                    setShaderParameter(entry.node, "clearCoatIntensity", c[1], c[2], c[3], c[4], false)
                end
            end
        end
    end
    vehicle.matteSaved = nil
    vehicle.matteApplied = nil
end

function MatteVehicles.getVehicles()
    local mission = g_currentMission
    if mission == nil then
        return nil
    end
    if mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles ~= nil then
        return mission.vehicleSystem.vehicles
    end
    return mission.vehicles
end

function MatteVehicles.setEnabled(state)
    state = state == true
    if MatteVehicles.enabled == state then
        return
    end
    MatteVehicles.enabled = state
    MatteVehicles.saveSettings()

    if not state then
        local vehicles = MatteVehicles.getVehicles()
        if vehicles ~= nil then
            for _, vehicle in pairs(vehicles) do
                if vehicle.matteApplied then
                    MatteVehicles.restoreVehicle(vehicle)
                end
            end
        end
    else
        MatteVehicles.timer = MatteVehicles.CHECK_INTERVAL  -- sweep on the next update
    end
end

function MatteVehicles.setMatteChrome(state)
    state = state == true
    if MatteVehicles.matteChrome == state then
        return
    end
    MatteVehicles.matteChrome = state
    MatteVehicles.saveSettings()

    -- restore everything and sweep again with the new rule
    local vehicles = MatteVehicles.getVehicles()
    if vehicles ~= nil then
        for _, vehicle in pairs(vehicles) do
            if vehicle.matteApplied then
                MatteVehicles.restoreVehicle(vehicle)
            end
        end
    end
    MatteVehicles.timer = MatteVehicles.CHECK_INTERVAL
end

function MatteVehicles:update(dt)
    if g_currentMission == nil or not MatteVehicles.enabled then
        return
    end

    self.timer = self.timer + dt
    if self.timer < MatteVehicles.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    local vehicles = MatteVehicles.getVehicles()
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

-- ------------------------------------------------------------------ settings menu entry

local function findTitleAndOption(box)
    local option, title
    for _, element in ipairs(box.elements) do
        if element.setIsChecked ~= nil then
            option = element
        elseif element.setText ~= nil and title == nil then
            title = element
        end
    end
    return option, title
end

-- layoutName / templateNames: the in-game menu and the main-menu settings use different frames
function MatteVehicles.addSettingsEntry(frame, layoutName, templateNames)
    local layout = frame[layoutName]
    if frame.matteVehiclesBox ~= nil or layout == nil then
        return
    end

    -- any existing on/off row of the page is used as template
    local template = nil
    for _, name in ipairs(templateNames) do
        if frame[name] ~= nil then
            template = frame[name]
            break
        end
    end
    if template == nil then
        for _, element in ipairs(layout.elements) do
            local option = findTitleAndOption(element)
            if option ~= nil then
                template = element
                break
            end
        end
    end
    if template == nil then
        Logging.warning("[MatteVehicles] no settings template found in %s, menu entry skipped", layoutName)
        return
    end

    -- own category: clone an existing section header (text-only element without an option)
    local headerTemplate = nil
    for _, element in ipairs(layout.elements) do
        if element.name == "sectionHeader" then
            headerTemplate = element
            break
        end
    end
    if headerTemplate == nil then
        for _, element in ipairs(layout.elements) do
            if findTitleAndOption(element) == nil and (element.setText ~= nil or #(element.elements or {}) > 0) then
                headerTemplate = element
                break
            end
        end
    end
    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header.id = nil
        header.name = "sectionHeader"
        header:setVisible(true)
        local function setHeaderText(element)
            if element.setText ~= nil then
                element:setText(g_i18n:getText("matte_category", MatteVehicles.modName))
                return true
            end
            for _, child in ipairs(element.elements or {}) do
                if setHeaderText(child) then return true end
            end
            return false
        end
        setHeaderText(header)
        frame.matteVehiclesHeader = header
        Logging.info("[MatteVehicles] category header added (%s)", tostring(headerTemplate.name))
    else
        Logging.warning("[MatteVehicles] no section header template found in %s", layoutName)
    end

    local function buildRow(titleKey, tipKey, onChange)
        local box = template:clone(layout)
        box.id = nil
        box:setVisible(true)

        local option, title = findTitleAndOption(box)
        if option == nil then
            box:delete()
            Logging.warning("[MatteVehicles] template without on/off option, menu entry skipped")
            return nil
        end

        option.id = nil
        option.target = MatteVehicles
        option.onClickCallback = function(_, state)
            onChange(state == BinaryOptionElement.STATE_RIGHT)
        end
        if title ~= nil then
            title:setText(g_i18n:getText(titleKey, MatteVehicles.modName))
        end
        local tipText = g_i18n:getText(tipKey, MatteVehicles.modName)
        local function setTips(element)
            for _, child in ipairs(element.elements or {}) do
                local name = string.lower(child.name or "")
                if child ~= option.leftButtonElement and child ~= option.rightButtonElement then
                    local profile = string.lower(tostring(child.profile or ""))
                    if child.setText ~= nil and (string.find(name, "tool", 1, true) ~= nil or string.find(profile, "tooltip", 1, true) ~= nil) then
                        child:setText(tipText)
                    end
                    setTips(child)
                end
            end
        end
        setTips(box)
        local function setTipFields(element)
            if element.toolTipText ~= nil then
                element.toolTipText = tipText
            end
            for _, child in ipairs(element.elements or {}) do
                setTipFields(child)
            end
        end
        setTipFields(box)
        option.toolTipText = tipText
        option:setTexts({ g_i18n:getText("matte_glossy", MatteVehicles.modName), g_i18n:getText("matte_matte", MatteVehicles.modName) })
        return box, option
    end

    local box, option = buildRow("matte_title", "matte_tooltip", function(state) MatteVehicles.setEnabled(state) end)
    if option == nil then
        return
    end
    frame.matteVehiclesBox = box
    frame.matteVehiclesOption = option

    local chromeBox, chromeOption = buildRow("matte_chrome_title", "matte_chrome_tooltip", function(state) MatteVehicles.setMatteChrome(state) end)
    if chromeOption ~= nil then
        frame.matteChromeBox = chromeBox
        frame.matteChromeOption = chromeOption
    end
    layout:invalidateLayout()
    Logging.info("[MatteVehicles] settings entry added to %s", layoutName)
end

function MatteVehicles.onFrameOpen(frame, layoutName, templateNames)
    MatteVehicles.addSettingsEntry(frame, layoutName, templateNames)
    if frame.matteVehiclesOption ~= nil then
        frame.matteVehiclesOption:setIsChecked(MatteVehicles.enabled, true)
        if frame.matteChromeOption ~= nil then
            frame.matteChromeOption:setIsChecked(MatteVehicles.matteChrome, true)
        end
        if frame.updateAlternatingElements ~= nil then
            frame:updateAlternatingElements(frame[layoutName])
        end
    end
end

local function hookFrame(frameClass, layoutName, templateNames)
    if frameClass == nil then
        return
    end
    frameClass.onFrameOpen = Utils.appendedFunction(frameClass.onFrameOpen, function(frame)
        local ok, err = pcall(MatteVehicles.onFrameOpen, frame, layoutName, templateNames)
        if not ok then
            Logging.warning("[MatteVehicles] settings entry error: %s", tostring(err))
        end
    end)
end

-- in-game menu: Settings > General
hookFrame(InGameMenuSettingsFrame, "generalSettingsLayout", { "checkUseMilesBox", "checkIsTrainTabbableBox", "checkShowFieldInfoBox" })
-- main menu: Settings > General
hookFrame(SettingsGeneralFrame, "boxLayout", { "invertYLookElementBox", "isGamepadEnabledElementBox" })

MatteVehicles.loadSettings()
addModEventListener(MatteVehicles)
