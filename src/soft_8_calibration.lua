local ledNumber = 4
local leds = Ledbar.new(ledNumber)
local unpack = table.unpack
local curr_state = "PREPARE_FLIGHT"
local function changeColor(color)
    for i=0, ledNumber - 1, 1 do
        leds:set(i, unpack(color))
    end
end 
local colors = {
    ["black"] = {0, 0, 0},  -- черный/отключение светодиодов
    ["red"] = {1, 0, 0}, -- красный
    ["green"] = {0, 1, 0}, -- зеленый
    ["blue"] = {0, 0, 1}, -- синий
    ["yellow"] = {1, 1, 0}, -- желтый
    ["purple"] = {1, 0, 1}, -- фиолетовый
    ["cyan"] = {0, 1, 1}, -- cине-зелёный
    ["white"] = {1, 1, 1} -- белый
}

local uartNum = 4
local baudRate = 115200
local dataBits = 8
local stopBits = 1
local parity = Uart.PARITY_NONE
local uart = Uart.new(uartNum, baudRate, parity, stopBits)

HIGHT = 1.05
RADIUS = 1.0
LENGTH = 2.5
CIRCLE_BIAS = 0.1
GLOBAL_CENTER_X = 0.0
GLOBAL_CENTER_Y = RADIUS + LENGTH
CURENT_FROM = "ERROR"
CALIBRATION_REG_KOEFF = 1.75

ANGLE_BEGIN_FIRST = math.pi/2.0 + math.acos(RADIUS/LENGTH)
ANGLE_END_FIRST = math.pi*2.0 + math.pi/2.0 - math.acos(RADIUS/LENGTH)
CENTER_X_FIRST = 0.0
CENTER_Y_FIRST = -LENGTH
CURENT_FIRST = math.pi*1.5

ANGLE_BEGIN_SECOND = math.pi + math.pi/2.0 - math.acos(RADIUS/LENGTH)
ANGLE_END_SECOND = -math.pi/2.0 + math.acos(RADIUS/LENGTH)
CENTER_X_SECOND = 0.0
CENTER_Y_SECOND = LENGTH
CURENT_SECOND = ANGLE_BEGIN_SECOND
if (CIRCLE_BIAS > 0.0) then
    CURENT_SECOND = ANGLE_BEGIN_SECOND
else
    CURENT_SECOND = ANGLE_END_SECOND
end

local function from_global_to_local(global_x, global_y)
    global_x = global_x + GLOBAL_CENTER_X
    global_y = global_y + GLOBAL_CENTER_Y
    return global_x, global_y
end

local function circle_first()
  if (CURENT_FIRST < ANGLE_BEGIN_FIRST) then 
    curr_state = "CALIBRATION"
    CURENT_FIRST = ANGLE_END_FIRST
    CURENT_FROM = "FIRST"
    local_x = 0.0
    local_y = 0.0
  elseif (CURENT_FIRST > ANGLE_END_FIRST) then
    curr_state = "CALIBRATION"
    CURENT_FIRST = ANGLE_BEGIN_FIRST
    CURENT_FROM = "FIRST"
    local_x = 0.0
    local_y = 0.0
  else
    curr_state = "CIRCLE_FIRST"
    CURENT_FIRST = CURENT_FIRST + CIRCLE_BIAS
    local_x = math.cos(CURENT_FIRST)*RADIUS + CENTER_X_FIRST
    local_y = math.sin(CURENT_FIRST)*RADIUS + CENTER_Y_FIRST
  end
  return local_x, local_y
end

local function circle_second()
  local_x = 0.0
  local_y = -3.5
  if (CURENT_SECOND > ANGLE_BEGIN_SECOND) then 
    curr_state = "CALIBRATION"
    CURENT_SECOND = ANGLE_END_SECOND
    CURENT_FROM = "SECOND"
    local_x = 0.0
    local_y = 0.0
  elseif (CURENT_SECOND < ANGLE_END_SECOND) then
    curr_state = "CALIBRATION"
    CURENT_SECOND = ANGLE_BEGIN_SECOND
    CURENT_FROM = "SECOND"
    local_x = 0.0
    local_y = 0.0
  else
    curr_state = "CIRCLE_SECOND"
    CURENT_SECOND = CURENT_SECOND - CIRCLE_BIAS
    local_x = math.cos(CURENT_SECOND)*RADIUS + CENTER_X_SECOND
    local_y = math.sin(CURENT_SECOND)*RADIUS + CENTER_Y_SECOND
  end
  return local_x, local_y
end

local function getc()
	while uart:bytesToRead() == 0 do
	end
	return uart:read(1)
end

local function ord(chr, signed)
	local specifier = "B"
	if signed then specifier = "b" end
	return string.unpack(specifier, chr)
end

local function getData() -- функция приёма пакета данных
    result = ""
	while true do -- ждём приёма начала пакета
		if (ord(getc()) == 0xBB) then break end
	end
	while true do -- ждём конца пакета
		local valAdd = ord(getc())
		if (valAdd == 0xFF) then break end
		result = string.format("%s%c", result, valAdd)
	end
    return result
end

action = {
    ["PREPARE_FLIGHT"] = function(x)
        changeColor(colors["white"])
        Timer.callLater(2, function () ap.push(Ev.MCE_PREFLIGHT) end)
        Timer.callLater(4, function () changeColor(colors["yellow"]) end)
        Timer.callLater(6, function () 
            ap.push(Ev.MCE_TAKEOFF)
            -- CIRCLE_FIRST
            curr_state = "CIRCLE_FIRST"
        end)
        changeColor(colors["black"])
    end,
    ["CIRCLE_FIRST"] = function (x)
        changeColor(colors["purple"])
        local_x, local_y = circle_first()
        local_x, local_y = from_global_to_local(local_x, local_y)
        ap.goToLocalPoint(local_x, local_y, HIGHT)
    end,
    ["CIRCLE_SECOND"] = function (x)
        changeColor(colors["cyan"])
        local_x, local_y = circle_second()
        local_x, local_y = from_global_to_local(local_x, local_y)
        ap.goToLocalPoint(local_x, local_y, HIGHT)
    end,
    ["CALIBRATION"] = function (x)
        changeColor(colors["yellow"])
        curr_state = "CALIBRATION"
        -- CALIBRATION BEGIN

        uart:read(uart:bytesToRead())
        uart:write('c', 1)
        boofStr = getData()
        split = string.find(boofStr," ")
        bias_x = tonumber(boofStr:sub(1, split))
        bias_y = tonumber(boofStr:sub(split, boofStr:len()))
        
        if (bias_x > -1.0) then
            GLOBAL_CENTER_X = GLOBAL_CENTER_X + (bias_y-0.5)*CALIBRATION_REG_KOEFF -- *= HIGHT
            GLOBAL_CENTER_Y = GLOBAL_CENTER_Y + (bias_x-0.5)*CALIBRATION_REG_KOEFF -- *= HIGHT
        end
        
        -- CALIBRATION END
        if (CURENT_FROM == "FIRST") then
            curr_state = "CIRCLE_SECOND"
        elseif (CURENT_FROM == "SECOND") then
            curr_state = "CIRCLE_FIRST"
        else 
            curr_state = "PIONEER_LANDING"
        end
        local_x, local_y = from_global_to_local(0.0, 0.0)
        ap.goToLocalPoint(local_x, local_y, HIGHT)

        changeColor(colors["cyan"])
    end,
    ["PIONEER_LANDING"] = function (x) 
        changeColor(colors["yellow"])
        Timer.callLater(7, function ()
            ap.push(Ev.MCE_LANDING)
            changeColor(colors["white"])
        end)
    end
}

-- функция обработки событий, автоматически вызывается автопилотом
function callback(event)
    if (event == Ev.ALTITUDE_REACHED) then
        action[curr_state]()
    end
    if (event == Ev.SHOCK) then
        changeColor(colors["red"])
    end
    if ((event == Ev.POINT_DECELERATION and curr_state ~= "CALIBRATION") or 
        (event == Ev.POINT_REACHED and curr_state == "CALIBRATION")) then
        action[curr_state]()
    end
    if (event == Ev.COPTER_LANDED) then
        changeColor(colors["black"])
    end

end

changeColor(colors["green"])
Timer.callLater(2, function () action[curr_state]() end)











