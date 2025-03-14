class MICS4514
	static addr = 0x75
	static r_sensor = 0x04
	static r_power_mode = 0x0a

	var gases
	var wire
	var power_mode
	var cal_ox
	var cal_red
	var data

	def read_bytes(offs, len)
		return self.wire.read_bytes(self.addr, offs, len)
	end
	def read(offs)
		return self.wire.read(self.addr, offs, 1)
	end
	def write(offs, v)
		return self.wire.write(self.addr, offs, v, 1)
	end

	def yawn()
		print("I2C: MICS4514 should be awake now")
		var b = self.read_bytes(self.r_sensor, 6)

		var v_ox = b.get(0, -2)
		var v_red = b.get(2, -2)
		var v_power = b.get(4, -2)

		self.cal_ox = 1.0 * (v_power - v_ox)
		self.cal_red = 1.0 * (v_power - v_red)
		self.power_mode = 1
	end
  
	def init()
		self.gases = [
			'CarbonMonoxide', 'NitrogenDioxide',
			'Methane', 'Ethanol', 'Hydrogen', 'Ammonia'
		]
		import string

		self.wire = tasmota.wire_scan(self.addr)
		if !self.wire return end

		self.power_mode = self.read(self.r_power_mode)
		if self.power_mode == 0x00
			print("I2C: MICS4514 is asleep, waking it up")
			self.write(self.r_power_mode, 1)
			tasmota.set_timer(3 * 60 * 1000, /-> self.yawn())
		else
			print("I2C: MICS4514 is already awake")
			self.yawn()
		end
	end

	#- trigger a read every second -#
	def every_second()
		if !self.power_mode return nil end
		var b = self.read_bytes(self.r_sensor, 6)
		if !b
			self.data = nil
			return nil
		end

		var v_ox = b.get(0, -2)
		var v_red = b.get(2, -2)
		var v_power = b.get(4, -2)

		var ox = (v_power - v_ox) / self.cal_ox
		var red = (v_power - v_red) / self.cal_red

		import math

		self.data = { 'raw': {
			'v_ox':v_ox, 'v_red':v_red, 'v_power':v_power,
			'ox':ox, 'red':red
		} }
		var v = 0.0

		if red > 3.4
			v = nil
		elif red < 0.1
			v = 1000.0
		else
			v = 4.2 / math.pow(red, 1.2)
		end
		self.data.insert('CarbonMonoxide', v)

		if ox < 0.3
			v = nil
		else
			v = 0.164 / math.pow(ox, 0.975)
		end
		self.data.insert('NitrogenDioxide', v)

		if red > 0.9 || red < 0.5
			v = nil
		else
			v = 630 / math.pow(red, 4.4)
		end
		self.data.insert('Methane', v)

		if red > 1 || red < 0.02
			v = nil
		else
			v = 1.52 / math.pow(red, 1.55)
		end
		self.data.insert('Ethanol', v)

		if red > 0.9 || red < 0.02
			v = nil
		else
			v = 0.85 / math.pow(red, 1.75)
		end
		self.data.insert('Hydrogen', v)

		if red > 0.98 || red < 0.2532
			v = nil
		else
			v = 0.9 / math.pow(red, 4.6)
		end
		self.data.insert('Ammonia', v)

		#print(self.data)
	end

	#- display sensor value in the web UI -#
	def web_sensor()
		if !self.data return nil end
		import string
		var msg = ''
		for g: self.gases.iter()
			var v = self.data[g]
			var f = type(v) != 'nil' ?
			    "{s}MICS4514 %s{m}%.2f ppm{e}" : "{s}MICS4514 %s{m}Unknown{e}"
			msg = msg .. string.format(f, g, v)
		end
		tasmota.web_send_decimal(msg)
	end

	#- add sensor value to teleperiod -#
	def json_append()
		if !self.data return nil end
		import json
		tasmota.response_append(',"MICS4514":')
		tasmota.response_append(json.dump(self.data))
	end
end

drv = MICS4514()
tasmota.add_driver(drv)
