local modem = peripheral.find("modem") or error("NO MODEM ATTACHED", 0)

local keybuffer = {w=0, a=0, s=0, d=0, q=0, e=0, leftShift=0, leftCtrl=0}

local function clamp(x,min,max)
    if x < min then return min end
    if x > max then return max end
    return x
end

local function keyInterrupt()
	while true do
		local eventData = {os.pullEvent()}
		if eventData[1] == "key" then
			keybuffer[keys.getName(eventData[2])] = 1
		elseif eventData[1] == "key_up" then
			keybuffer[keys.getName(eventData[2])] = 0
		else
			-- shd we requeue events?
		end
	end
end

local controlVector = {roll=0, collect=0, pitch=0, yaw=0}
local function commLoop()
	local lastTimestamp = os.epoch("utc")
	while true do
		local delta = (os.epoch("utc") - lastTimestamp)/1000
		commandRoll = (keybuffer.q - keybuffer.e)
		controlVector.roll = keybuffer.q - keybuffer.e
		commandCollect = keybuffer.leftShift - keybuffer.leftCtrl
		controlVector.collect = clamp(controlVector.collect + commandCollect*delta/3, -1, 1)
		controlVector.pitch = keybuffer.w - keybuffer.s
		controlVector.yaw = keybuffer.d - keybuffer.a
		term.clear()
		print("roll ", controlVector.roll)
		print("collect ", controlVector.collect)
		print("pitch ", controlVector.pitch)
		print("yaw ", controlVector.yaw)
		
		lastTimestamp = os.epoch("utc")
		modem.transmit(10318, 1, controlVector)
		os.sleep(0.1)
	end
end

parallel.waitForAll(keyInterrupt, commLoop)