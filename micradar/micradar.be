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

import string
import mqtt
import json

class micradar: Driver
	static _head = bytes("5359")
	static _tail = bytes("5443")

	var _topic
	var _uart
	var _stats

	var route
	var dp

	def _cksum(b)
		var cksum = 0
		var i = 0
		while i < size(b)
			cksum += b[i]
			i += 1
		end
		return cksum
	end

	def _send(control, command, data)
		var msg = bytes()
		msg += self._head
		msg.add(control, 1)
		msg.add(command, 1)
		msg.add(size(data), -2)
		msg += data
		msg.add(self._cksum(msg), 1)
		msg += self._tail

		self._uart.write(msg)
		self._uart.flush()

		log(f"MIC: write {msg}", 4)

		self._stats["TxBytes"] += size(msg)
		self._stats["TxMsgs"] += 1
	end

	var _rxstate
	var _rxcksum
	var _rxdata
	var _rxlen
	var _rxoff

	def _parse(byte)
		var state = self._rxstate

		#print(format("parse %s %02x", state, byte))

		if state == "idle"
			if byte != self._head[0]
				return "idle"
			end

			self._rxcksum = 0
			self._rxstate = "header"
		elif state == "header"
			if byte != self._head[1]
				self._stats["RxErrs"] += 1
				return "idle"
			end

			self._rxdata = {
				"control": 0,
				"command": 0,
				"data": nil,
			}
			self._rxstate = "control"
		elif state == "control"
			self._rxdata["control"] = byte;
			self._rxstate = "command"
		elif state == "command"
			self._rxdata["command"] = byte;
			self._rxstate = "len_hi"
		elif state == "len_hi"
			self._rxlen = byte << 8;
			self._rxstate = "len_lo"
		elif state == "len_lo"
			self._rxlen |= byte;

			self._rxdata["data"] = bytes(self._rxlen)
			self._rxoff = 0
			self._rxstate = "data"
		elif state == "data"
			self._rxdata["data"].add(byte, 1)
			self._rxoff += 1
			if self._rxoff >= self._rxlen
				self._rxstate = "cksum"
			end
		elif state == "cksum"
			if byte != self._rxcksum & 0xff
				self._stats["RxErrs"] += 1
				return "idle"
			end
			self._rxstate = "tail0"
		elif state == "tail0"
			if byte != self._tail[0]
				self._stats["RxErrs"] += 1
				return "idle"
			end

			self._rxstate = "tail1"
		elif state == "tail1"
			if byte != self._tail[1]
				self._stats["RxErrs"] += 1
				return "idle"
			end

			self._stats["RxMsgs"] += 1
			self._rxstate = "idle"

			var d = self._rxdata

			# this is easier than a nested map
			var key = format("%02x/%02x", 
			    d["control"], d["command"])
			self.dp.insert(key, d["data"])

			var route = self.route.find(key)
			if type(route) == 'nil'
				var k = format("%02x", d["control"])
				route = self.route.find(k)
				if type(route) == 'nil'
					route = true
				end
			end

			if type(route) == 'function'
				route(d["data"], d["control"], d["command"])
			elif type(route) == 'bool' && route
				var topic = format("tele/%s/MIC/%s",
				    self._topic, key)
				mqtt.publish(topic, d["data"].tohex())
			end

			return;
		end

		self._rxcksum += byte
	end

	var _txq

	def send(control, command, data)
		if type(data) == 'nil'
			data = 0x0f
		end
		if type(data) == 'int'
			var d = bytes()
			d.add(data, 1)
			data = d
		end

		var msg = {
			"control": control,
			"command": command,
			"data": data,
		}

		# enqueue
		self._txq.push(msg)
	end

	def every_50ms()
		if self._txq.size() > 0
			# dequeue
			var msg = self._txq.item(0)
			self._txq.remove(0)

			self._send(msg["control"], msg["command"], msg["data"])
		end

		if self._uart.available() == 0
			return;
		end

		var msg = self._uart.read()
		self._stats["RxBytes"] += size(msg)
		log(f"MIC: read {msg}", 4)

		var i = 0
		while i < size(msg)
			self._parse(msg[i])
			i += 1
		end
	end

	def init(tx, rx)
		self.dp = { }
		self.route = { }

		self._txq = list()
		self._topic = tasmota.cmd("Status", true)["Status"]["Topic"]
		self._rxstate = "idle"

		self._stats = {
			"TxBytes": 0,
			"TxMsgs": 0,

			"RxBytes": 0,
			"RxMsgs": 0,
			"RxErrs": 0,
		}
		if !tx
			tx = gpio.pin(gpio.TXD)
		end
		if !rx
			rx = gpio.pin(gpio.RXD)
		end

		self._uart = serial(rx, tx, 115200, serial.SERIAL_8N1)
	end
end
