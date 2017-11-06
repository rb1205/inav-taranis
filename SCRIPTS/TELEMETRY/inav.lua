
local flags, last_gps, home_gps, Vbatt, was, persistent

local masks={
Tmp1={
{'arm_ready','arm_block','armed'},
{'angle','horizon','passthru'},
{'headhold','althold','poshold'},
{'navrth','navwp','headfree'},
{'flaperon','autotune','failsafe'},
},
Tmp2={
{},
{},
{},
{'gpsfix','gpshome','homereset'},
}}

local headings={'N','NE','E','SE','S','SW','W','NW','N'}

-- Cell tensions. The Flight controller sends the average cell tension as 
-- in the A4 telemetry value. If you use more precise system to monitor
-- the tension (EG: FrSky FLVSS) overwrite the A4 value in the telemetry
-- menu with the minimum cell voltage.

local MAX_V=4.15
local WARN_V=3.5
local CRIT_V=3.4
local NOBAT_V=2
local MIN_V=3.4

local D_V=MAX_V-MIN_V

local function init_func()
	flags={}
	was={}
	persistent={}
	last_gps=nil
	home_gps=nil
	Vbatt=nil
end

local function calc_gps_hdistance(point,ref)
	--simplified distance calculation assuming small (~10km max) distances. Measures the straight line connecting the points.
	local lat = (point.lat + ref.lat) * 0.0087266462599716 --calculate mean latitude
	local dlon= 111300 * math.cos(lat) * (point.lon - ref.lon)
	local dlat = 111300 * (point.lat - ref.lat)
	return math.sqrt(dlon^2+dlat^2)
end

local function parse_data()
	local flags={telemetry=true}
	for field,mask in pairs(masks) do
		local value=getValue(field)
		local code=value
		if field=="Tmp1" and (not value or value==0) then flags.telemetry=false
		elseif value then
			for pos,posmask in ipairs(mask) do
				local p_code=code%10
				for i,bitname in ipairs(posmask) do
					flags[bitname]= bit32.band(p_code,bit32.lshift(1,i-1))~=0
				end
				code=math.floor(code/10)
			end
			if field=="Tmp2" then 
				flags.gpssats=value%100 
				flags.gpsqual=(value-flags.gpssats)/100 --satellite accuracy HDOP: 0 = worst, 9 = best
			end
		end
	end
	
	local vr=getValue("A4")
	if vr and vr>0 then 
		if persistent.Vbatt_tlast and Vbatt then --filter vbatt with a moving average
			local dt=getTime()-persistent.Vbatt_tlast
			Vbatt=(Vbatt*1000+vr*dt)/(1000+dt) -- 10 seconds timebase
		else
			Vbatt=vr
		end
		persistent.Vbatt_tlast=getTime()
	else
		Vbatt=nil
	end
	return flags
end

local function bg_func()
	flags=parse_data()

	if flags.telemetry then
		if not flags.armed then 
			persistent.auto=false 
		end

		if flags.gpsfix==false and was.gpsfix then 
			playFile("/SCRIPTS/SOUNDS/gpslost.wav")
		elseif flags.gpsfix and was.gpsfix==false then 
			playFile("/SCRIPTS/SOUNDS/gpsback.wav")
		end

		if not persistent.warmed and flags.arm_ready and flags.gpshome then
			playFile("/SCRIPTS/SOUNDS/ready.wav")
			persistent.warmed=true
		end

		local GPScoords=getValue("GPS")
		if flags.gpsfix and type(GPScoords)=="table" and GPScoords.lat and GPScoords.lon then
			last_gps=GPScoords
			if flags.armed==false then home_gps=GPScoords end
		end


		if flags.failsafe and not was.failsafe then
			playFile("/SCRIPTS/SOUNDS/fsalarm.wav")
		elseif was.failsafe and flags.failsafe==false then
			playFile("/SCRIPTS/SOUNDS/fsover.wav")
		end

		if flags.navrth or flags.navwp or (flags.althold and flags.poshold) then
			if not persistent.auto then 
				playFile("/SCRIPTS/SOUNDS/autop.wav")
				persistent.auto=true
			end
		else
			if persistent.auto then
				playFile("/SCRIPTS/SOUNDS/manual.wav") 
				persistent.auto=false
			end
		end 

		if flags.homereset and not was.homereset then
			playFile("/SCRIPTS/SOUNDS/homereset.wav")
		end

		if flags.armed and not was.armed then 
			playFile("/SCRIPTS/SOUNDS/armed.wav")
		elseif flags.armed==false and was.armed then 
			playFile("/SCRIPTS/SOUNDS/dearmed.wav") 
		end

		was=flags
	end		

	if Vbatt and Vbatt<WARN_V and Vbatt>NOBAT_V then --moving average (around 10 seconds)
		if Vbatt<CRIT_V and getTime()-(persistent.Vwarn_last or 0)>500 then --5 seconds for battcrit
			persistent.Vwarn_last=getTime()
			playFile("/SCRIPTS/SOUNDS/batcrit.wav")	
		elseif getTime()-(persistent.Vwarn_last or 0)>2000 then --20 seconds for lowbatt
			persistent.Vwarn_last=getTime()
			playFile("/SCRIPTS/SOUNDS/batlow.wav")
		end
	end
end

local function formatnum(num, decimals, unit)
	dec=10^(decimals or 2)
	unit=unit or ""
	return tostring(math.floor(num*dec)/dec)..unit
end

	

local function draw()   
	local drawText=lcd.drawText 
	local drawChannel=lcd.drawChannel
	local getLastPos=lcd.getLastPos
 
	--batt
	lcd.drawPixmap(1, 3, "/SCRIPTS/IMAGES/battery.bmp")
	local i = 38
	while (i > 0) do 
		lcd.drawLine(6, 12 + i, 26, 12 +i, SOLID, GREY_DEFAULT)
		i= i-2
	end
	if Vbatt then
		local battratio = (Vbatt-MIN_V)/D_V
		if battratio>1 then battratio=1 end
		local myPxHeight = math.floor(battratio * 37)  --draw level
		local myPxY = 50 - myPxHeight
		lcd.drawFilledRectangle(6, myPxY, 21, myPxHeight, FILL_WHITE)
		local textflags=0
		if Vbatt<WARN_V then textflags=INVERS + BLINK
		end
		drawText(6,56,formatnum(Vbatt,2,"V"),textflags)
		--drawChannel(23, 56, v_field,textflags)
	else
		drawText(1, 56, "No Data", INVERS + BLINK)
	end
   
	--rssi
	local rssi=getValue("RSSI")
	if rssi then
		if rssi > 38 then 
			rxpercent = ((math.log(rssi-28, 10)-1)/(math.log(72, 10)-1))*100
		else
			rxpercent=0
		end
		lcd.drawPixmap(164, 6, "/SCRIPTS/IMAGES/RSSI"..math.ceil(rxpercent*0.1)..".bmp")
		drawChannel(188, 56, "RSSI", GREY_DEFAULT) 
	else
		drawText(188, 56, "No Data", GREY_DEFAULT) 
	end

	--title
	local fmode
	local fmodef=DBLSIZE
	if not flags.telemetry then
		fmode=								"No Telemetry"
		fmodef=fmodef+BLINK+INVERS
	elseif not flags.armed then
		if flags.arm_ready then fmode=		"Ready"
		elseif flags.arm_block then 
			fmodef=fmodef+BLINK+INVERS
			fmode=							"Safety lock"		
		else	
			fmodef=fmodef+INVERS	
			fmode=							"Arm blocked"
		end
	elseif flags.failsafe then 
		fmodef=fmodef+BLINK+INVERS
		fmode=								"Failsafe"
	elseif flags.passthru then fmode=		"Passthrough"
	elseif flags.autotune then 
		fmodef=fmodef+BLINK+INVERS
		fmode=								"Auto Tuning"
	elseif flags.navrth then fmode=			"Return home"
	elseif flags.navwp then fmode=			"Waypoint"
	elseif flags.poshold then 
		if flags.althold then fmode=		"AltPos hold"
		else fmode=							"Position hold"
		end
	elseif flags.althold then fmode=		"Altitude hold"
	elseif flags.headfree then fmode=		"Headfree"
	elseif flags.angle then fmode=			"Angle"
	elseif flags.horizon then fmode=		"Horizon"
	elseif flags.flaperon then fmode=		"Flaperon"
	elseif flags.armed then fmode=			"Acro"
	end
	drawText(92-math.floor(#fmode*4.5),0,fmode,fmodef)
	
	--central data
	local hdg=getValue("Hdg")
	local hdg_s=hdg and headings[math.floor((hdg-22.4)/45)+2]
	drawText(36,22, "Fuel: ",SMLSIZE,0)
	drawChannel(getLastPos(), 18, "Fuel", MIDSIZE+LEFT)
	drawText(120, 22, "Hdg: ",SMLSIZE)
	drawText(getLastPos(), 18, hdg_s or "", MIDSIZE)
	drawText(36, 34, "Vspeed: ",SMLSIZE,0)
	drawChannel(getLastPos(), 30, "VSpd", MIDSIZE+LEFT)
	drawText(121, 34, "Alt: ",SMLSIZE,0)
	drawChannel(getLastPos(), 30, "Alt", MIDSIZE+LEFT)
	drawText(36, 46, "Timer: ",SMLSIZE)
	lcd.drawTimer(getLastPos(), 42, getValue("timer1"),MIDSIZE)
	drawText(124, 46, "Sats: ",SMLSIZE)
	drawText(getLastPos(), 42, flags.gpssats or "", MIDSIZE)

	--dist
	if last_gps and home_gps then
		local d=calc_gps_hdistance(last_gps,home_gps)
		if d<1000 then d=tostring(math.floor(d)).."m"
		else d=formatnum(d/1000,2,"km")
		end
		drawText(186-2*#d,3, d)
	end

	--lastcoord
	if last_gps then
		drawText(59,56, tostring(last_gps.lat).." "..tostring(last_gps.lon))
	end

	lcd.drawFilledRectangle(0, 55, 212, 10, GREY_DEFAULT)
end

local function run_func()
	--screen size 212x64
	lcd.clear()
	draw()   
end



return	{	run=run_func,	background=bg_func,	init=init_func		}
