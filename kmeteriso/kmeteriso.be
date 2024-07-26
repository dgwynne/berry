class KMeterISO
	static addr = 0x66

	var wire
	var ready
	var temp
	var itemp

	def read(offs, len)
		return self.wire.read_bytes(self.addr, offs, len)
	end
  
	def init()
		import string

		var wire = tasmota.wire_scan(self.addr)
		if !wire return end

		var v = wire.read(self.addr, 0xff, 1)
		if v != self.addr return end

		v = wire.read(self.addr, 0x20, 1)
		if v != 0
			print("I2c: KMeterISO error %u", v)
		end
		v = wire.read(self.addr, 0xfe, 1)

		var msg = string.format("KMeterISO, fw %u", v)
		print("I2C: " + msg + ", bus " + str(wire.bus))

		self.wire = wire
	end

	#- trigger a read every second -#
	def every_second()
		if !self.wire return nil end
		self.temp = self.read(0x00, 4).geti(0, 4) / 100.0
		self.itemp = self.read(0x10, 4).geti(0, 4) / 100.0
	end

	#- display sensor value in the web UI -#
	def web_sensor()
		if !self.wire return nil end
		import string
		var msg = string.format(
		    "{s}KMeterISO{m}%.2f degC{e}" ..
		    "{s}KMeterISO Internal{m}%.2f degC{e}",
		    self.temp, self.itemp)
		tasmota.web_send_decimal(msg)
	end

	#- add sensor value to teleperiod -#
	def json_append()
		if !self.wire return nil end
		import string
		var msg = string.format(
		    ",\"KMeterISO\":{\"Temperature\":%.2f}" ..
		    ",\"KMeterISO-internal\":{\"Temperature\":%.2f}",
		    self.temp, self.itemp)
		tasmota.response_append(msg)
	end
end

drv = KMeterISO()
tasmota.add_driver(drv)
