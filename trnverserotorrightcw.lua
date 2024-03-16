-- Rotor Microcontroller

local modem = peripheral.find("modem") or error("NO MODEM ATTACHED", 0)
local ship = peripheral.wrap("bottom")
modem.open(3223)

local bladeSignCW = {forward=-1,left=1,right=-1,back=1}

-- I can't believe this isn't inbuilt. god help me.
local vectorZero = vector.new(0,0,0)
local bladeTbl = {{forward=vector.new(0,0,1), socket="front", sign=bladeSignCW.forward},
{forward=vector.new(0,0,-1), socket="back", sign=bladeSignCW.back},
{forward=vector.new(-1,0,0), socket="left", sign=bladeSignCW.left},
{forward=vector.new(1,0,0), socket="right", sign=bladeSignCW.right}
}
local hubDirection = vector.new(1,0,0)

local running = true

local function clamp(x,min,max)
    if x < min then return min end
    if x > max then return max end
    return x
end

local function tblTovec(v)
	return vector.new(v.x,v.y,v.z)
end

-- ONLY FOR NORMALIZED QUATERNION ROTATIONS
local function inverseQuat(q)
	return {w=q.w, x=-q.x, y=-q.y, z=-q.z}
end

local function transformVector(q, v)
	local u = vector.new(q.x, q.y, q.z)
	return u * (u * 2):dot(v) + v*(q.w * q.w - u:dot(u)) + (u * 2 * q.w):cross(v)
end


function pidV(p,d)
    return{p=p,d=d,E=vectorZero,D=vectorZero,L=vectorZero,T=0,
		run=function(s,sp,pv,t)
			local E,D,A
			E = sp-pv
			D = (pv-s.L) / (t-s.T)
			s.E = E
			s.D = D
			s.L = pv
			s.T = t
			return E*s.p - D*s.d
        end,
        reset=function(s)
            s.E = 0
            s.D = 0
            s.I = 0
        end
	}
end

-- POSITIVE SIGN IS DOWNWARD FORCE
local function cyclicOutput(input, rotorQuat, bladeVector)
	local rotatedBladeVector = transformVector(rotorQuat, bladeVector)
    return input:dot(rotatedBladeVector)
end

-- POSITIVE SIGN IS DOWNWARD FORCE
local function diffCyclicOutput(input, rotorQuat, bladeVector, hubVector)
	local rotatedBladeVector = transformVector(rotorQuat, bladeVector)
	local diffComponent = input:dot(hubVector)
	local cyclicComponent = input - hubVector*diffComponent
	-- TODO: local diffCompensation = diffComponent
    return cyclicComponent:dot(rotatedBladeVector) + diffComponent/2
end

local function flapOutput(value, socket, sign)
	peripheral.call(socket, "setFlapAngle", value*sign)
end

local localForward = vector.new(0,0,1)
local vesselForward = vector.new(0,0,1)
local vesselQuat = nil
local controlVector = {roll=0, collect=0, pitch=0, yaw=0}
local lastControlTimestamp = 0
local function fComLoop()
	while true do
		-- print("loop ")
		local event, _, channel, _, msg, dist = os.pullEvent("modem_message")
		-- term.write("got smth ")
		if dist < 16.0 and type(msg) == "table" then
			-- term.write("got msg ")
			if os.epoch() - msg.time < 300 then
				-- term.write("got live msg ")
				vesselQuat = msg.rot
				vesselForward = transformVector(msg.rot, localForward)
				
				if msg.input then
					-- term.write("got control msg ")
					controlVector = msg.input
					lastControlTimestamp = os.epoch("utc")
				end 
			end
		else
			print(os.epoch("utc") - msg.time, dist, type(msg))
			print("wtf is this?")
		end
		-- print(" ")
	end
end

local sasPID=pidV(1,0.5)
local gpsPID=pidV(0.01,0.01)
local gpsHold=vectorZero
local function controlLoop()
	local lastRotorUp = nil
	local lastTimeStamp = os.clock()
	local localUp = vector.new(0,1,0)
	
	gpsHold = tblTovec(ship.getWorldspacePosition())
	gpsHold.y = 0
	
	while running do
		local rotorQuat = ship.getRotation(true)
		local controlUp = localUp
		local rotorUp = transformVector(rotorQuat,localUp)
		-- WHY IS THIS NOT A CC VECTOR TYPE
		local surfVel = tblTovec(ship.getVelocity())
		surfVel = surfVel - rotorUp*surfVel:dot(rotorUp)
		
		-- manual control
		if vesselQuat and os.epoch("utc") - lastControlTimestamp < 1000 then
			controlUp = controlUp + transformVector(vesselQuat, vector.new(controlVector.roll/5,0,controlVector.pitch/5 - controlVector.yaw/5))
		end
		
		-- pos hold
		if surfVel:length() < 3 and controlUp == localUp then
			controlUp = controlUp + gpsPID:run(gpsHold, tblTovec(ship.getWorldspacePosition()), os.clock())
		else
			gpsHold = tblTovec(ship.getWorldspacePosition())
			gpsHold.y = 0
			gpsPID:reset()
		end
		
		-- HELICOPTER WILL ROTATE *TOWARD* CONTROL UP
		local rotorControlVector = sasPID:run(controlUp, rotorUp, os.clock())
		-- eq does not correlate with tests???
		local pitchCollectiveLink = 2/math.max(rotorUp:dot(localUp), 0.1) - 1

		if vesselQuat then
			for _, blade in pairs(bladeTbl) do
				local outf = diffCyclicOutput(rotorControlVector, rotorQuat, blade.forward, transformVector(vesselQuat,hubDirection))
				flapOutput(clamp(outf*25+(controlVector.collect*3)*pitchCollectiveLink, -45, 45), blade.socket,blade.sign)
			end
		else
			for _, blade in pairs(bladeTbl) do
				local outf = cyclicOutput(rotorControlVector, rotorQuat, blade.forward)
				flapOutput(clamp(outf*25+(controlVector.collect*3)*pitchCollectiveLink, -45, 45), blade.socket,blade.sign)
			end
		end

		os.sleep(0)
	end
end

parallel.waitForAll(fComLoop,controlLoop)

    
