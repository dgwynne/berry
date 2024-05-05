#-
 - Copyright (c) 2024 David Gwynne <david@gwynne.id.au>
 -
 - Permission to use, copy, modify, and distribute this software for any
 - purpose with or without fee is hereby granted, provided that the above
 - copyright notice and this permission notice appear in all copies.
 -
 - THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 - WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 - MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 - ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 - WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 - ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 - OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 -#

import json

class r60asm1: micradar
	static _bool = {
		0x00: "false",
		0x01: "true",
	}
	static _on_off = {
		0x00: "off",
		0x01: "on",
	}
	static _body_movement = {
		0x00: "none",
		0x01: "still",
		0x02: "active",
	}
	static _breathing_information = {
		0x01: "normal",
		0x02: "high",
		0x03: "low",
		0x04: "none",
	}
	static _sleep_state = {
		0x00: "deep sleep",
		0x01: "light sleep",
		0x02: "awake",
		0x03: "none",
	}
	static _sleep_rating = {
		0x00: "none",
		0x01: "high",
		0x02: "medium",
		0x03: "poor",
	}

	def publish(topic, payload)
		mqtt.publish(format('tele/%s/R60ASM1/%s', self._topic, topic), payload)
	end

	def publish_uint(topic, u)
		self.publish(topic, format("%u", u))
	end

	def publish_str(topic, data)
		self.publish(topic, data.asstring())
	end

	def map_data(m, k)
		var v = m.find(k)
		if type(v) == 'nil'
			v = format("0x%02x", k)
		end
		return v
	end

	def publish_map(topic, m, k)
		self.publish(topic, self.map_data(m, k))
	end

	def publish_human_activity(score)
		var a = { "Score": score }

		var state = self._body_movement.find(score)
		if type(state) != 'nil'
			a.insert('State', state)
		end

		self.publish("HumanActivity", json.dump(a))
	end

	def getpos(data, offset)
		var word = data.get(offset, -2)
		var pos = word & 0x7fff
		if word & 0x8000
			pos = 0 - pos
		end
		return pos
	end

	def publish_human_position(data)
		if size(data) != 6
			return;
		end
		var p = {
			"x": self.getpos(data, 0),
			"y": self.getpos(data, 2),
			"z": self.getpos(data, 4),
		}
		self.publish("HumanPosition", json.dump(p))
	end

	def publish_sleep_status_report(data)
		var p = {
			"Existing": data[0] ? true : false,
			"SleepingState": self.map_data(self._sleep_state, data[1]),
			"AverageBreathingRate": data[2],
			"AverageHeartbeatRate": data[3],
			"TurnoverTimes": data[4],
			"LargeScaleBodyMovements": data[5],
			"SmallScaleBodyMovements": data[6],
			"ApneaTimes": data[7],
			"_raw": data.asstring(),
		}
		self.publish("SleepStatusReport", json.dump(p))
	end

	static _report_queries = {
		"07/07": [ 0x07, 0x87 ],

		"80/00": [ 0x80, 0x80 ], # human presense switch

		"80/01": [ 0x80, 0x81 ], # HumanPresence
		"80/02": [ 0x80, 0x82 ], # HumanActivity
		"80/03": [ 0x80, 0x83 ], # HumanMovement
		"80/04": [ 0x80, 0x84 ], # HumanDistance

		"81/00": [ 0x81, 0x80 ], # breathing monitoring
		"84/00": [ 0x84, 0x80 ], # sleep monitoring
		"84/01": [ 0x84, 0x81 ], # in bed
		"84/02": [ 0x84, 0x82 ], # sleep state
		"84/12": [ 0x84, 0x92 ], # Unoccupied timing status report
		"84/13": [ 0x84, 0x93 ], # Abnormal struggling state switch setting
		"84/14": [ 0x84, 0x94 ], # Unoccupied timing status report switch setting
		"84/15": [ 0x84, 0x95 ], # Timing duration setting in unoccupied situations
		"84/16": [ 0x84, 0x96 ], # Enter stop-sleeping state timing setting
		"85/00": [ 0x85, 0x80 ], # heart rate monitoring
	}

	def reroute(target, data)
		self.dp.insert(target, data) # cheeky

		var route = self.route.find(target)
print('reroute', target, data)
		route(data)
	end

	static sensors = [
		"07/07",
		"80/00",
		"80/01",
		"80/02",
		"80/03",
		"80/04",
		"81/00",
		"84/00",
		"84/01",
		"84/02",
		"85/00",
	]

	def after_teleperiod()
		print("hi")
		for s: self.sensors
			var data = self.dp.find(s)
			if type(data) != 'nil'
				var route = self.route.find(s)
print('after', s, data)
				route(data)
			end
		end

		for s: self._report_queries.keys()
			var data = self.dp.find(s)
			if type(data) == 'nil'
				var q = self._report_queries[s]
				self.send(q[0], q[1], 0x0f)
			end
		end
	end

	static _cmnds = {
		"reset": [ 0x01, 0x02, 0x0f ],
	}

	def cmnd_micsend(payload)
		var q = self._cmnds.find(payload)
		if type(q) == 'nil'
			return false
		end

		self.send(q[0], q[1], q[2])

		return true
	end

	def init(tx, rx)
		super(self).init(tx, rx) 

		# HeartBeat
		self.route.insert("01/01", false)

		#self.route.insert("02/a1", / data -> self.publish_str("ProductModel", data))
		#self.route.insert("02/a2", / data -> self.publish_str("ProductID", data))
		#self.route.insert("02/a3", / data -> self.publish_str("HardwareModel", data))
		#self.route.insert("02/a4", / data -> self.publish_str("FirmwareVersion", data))

		self.route.insert("07/07", / data ->
		    self.publish_map("InRange", self._bool, data[0]))

		self.route.insert("80/00",
		    / data -> self.publish_map("Switch", self._on_off, data[0]))
		self.route.insert("80/01", / data ->
		    self.publish_map("HumanPresence", self._bool, data[0]))
		self.route.insert("80/02", / data -> self.publish_human_activity(data[0]))
		self.route.insert("80/03", / data ->
		    self.publish_uint("HumanMovement", data[0]))
		self.route.insert("80/04", / data ->
		    self.publish_uint("HumanDistance", data.get(0, -2)))
		self.route.insert("80/05", / data -> self.publish_human_position(data))

		self.route.insert("81/00",
		    / data -> self.publish_map("BreathingMonitor", self._on_off, data[0]))
		self.route.insert("81/01",
		    / data -> self.publish_map("BreathingInfo", self._breathing_information, data[0]))
		self.route.insert("81/02",
		    / data -> self.publish_uint("BreathingRate", data[0]))

		self.route.insert("84/00",
		    / data -> self.publish_map("SleepMonitor", self._on_off, data[0]))
		self.route.insert("84/01",
		    / data -> self.publish_map("InBed", self._bool, data[0]))
		self.route.insert("84/02",
		    / data -> self.publish_map("SleepState", self._sleep_state, data[0]))
		self.route.insert("84/03", / data ->
		    self.publish_uint("AwakeTime", data.get(0, -2)))
		self.route.insert("84/04", / data ->
		    self.publish_uint("LightSleepTime", data.get(0, -2)))
		self.route.insert("84/05", / data ->
		    self.publish_uint("DeepSleepTime", data.get(0, -2)))
		self.route.insert("80/0c", / data -> self.publish_sleep_status_report(data))
		self.route.insert("84/06",
		    / data -> self.publish_uint("SleepQualityScore", data[0]))
		self.route.insert("84/10",
		    / data -> self.publish_map("SleepQualityRating", self._sleep_rating, data[0]))

		self.route.insert("85/00",
		    / data -> self.publish_map("HeartMonitor", self._on_off, data[0]))
		self.route.insert("85/02",
		    / data -> self.publish_uint("HeartRate", data[0]))

		for s: self._report_queries.keys()
			var q = self._report_queries[s]
			var key = format("%02x/%02x", q[0], q[1])

			self.route.insert(key, / data -> self.reroute(s, data))
		end

		tasmota.add_cmd('MicSend', def (cmd, idx, payload, payload_json)
			self.cmnd_micsend(payload) ? tasmota.resp_cmnd_done() : tasmota.resp_cmnd_error()
		end)
 	end
end
