--Flight Control Computer

local modem = peripheral.find("modem") or error("NO MODEM ATTACHED", 0)
local ship = peripheral.wrap("back")
modem.open(10318)

-- CLOCKWISE IS POSITIVE
local yawTbl={resistor="left",reverse="right",direction=1}

local function clamp(x,min,max)
    if x < min then return min end
    if x > max then return max end
    return x
end

local function transformVector(q, v)
	local u = vector.new(q.x, q.y, q.z)
	return u * (u * 2):dot(v) + v*(q.w * q.w - u:dot(u)) + (u * 2 * q.w):cross(v)
end

local function tblTovec(v)
	return vector.new(v.x,v.y,v.z)
end

-- ANGLE FROM A TOWARDS B, CLOCKWISE IS POSITIVE
-- NORMALIZED VECTORS ONLY
local function signedAngleDiffUnitVec(a, b, up)
	return math.atan2(b:cross(a):dot(up), a:dot(b))
end

local hdgHold = nil
local controlVector = nil
function inputLoop()
	while true do
		local event, _, channel, _, msg, dist = os.pullEvent("modem_message")
		if dist < 100 and type(msg) == "table" then		
			modem.transmit(3223, 1, {time=os.epoch("utc"), rot=ship.getRotation(true), input=msg})
			controlVector = msg
		end
	end
end

local function transformLoop()
	while true do
		modem.transmit(14313, 1, {time=os.epoch("utc"), rot=ship.getRotation(true), input=nil})
		os.sleep(0.05)
	end 
end

-- TODO: Fuel loop

parallel.waitForAll(transformLoop, inputLoop)
