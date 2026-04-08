import string
import persist
import mqtt

class FlowerCooler
  var sensor_top_name, sensor_bottom_name, sensor_mid_name
  var cool_on, cool_off, hum_on, hum_off, too_cold_trip, too_cold_reset
  var cal_top_temp, cal_mid_temp, cal_bottom_temp, cal_humidity
  var min_comp_on_ms, min_comp_off_ms, fan_postrun_ms, door_recover_ms, door_open_comp_off_delay_ms, watchdog_timeout_ms, mix_cycle_period_ms, mix_cycle_run_ms
  var startup_comp_lockout_ms, high_temp_alarm_on, high_temp_alarm_off, high_temp_alarm_delay_ms, door_alarm_delay_ms, max_comp_runtime_ms, humidifier_post_cool_lockout_ms, sensor_stuck_timeout_ms
  var startup_sensor_grace_ms

  var compressor_on, fan_on, humidifier_on, alarm_on, alarm_reason, door_open
  var too_cold_latched, fail_safe, high_temp_alarm_latched, door_alarm_latched, runtime_alarm_latched
  var startup_waiting_for_sensors
  var boot_ms
  var last_comp_on_ms, last_comp_off_ms, last_door_change_ms, last_mix_ms, door_open_since_ms, high_temp_since_ms, last_humidifier_lockout_ms

  var t_top, t_mid, t_bottom, rh
  var raw_t_top, raw_t_mid, raw_t_bottom, raw_rh
  var last_top_ms, last_mid_ms, last_bottom_ms, last_hum_ms
  var prev_top_ms, prev_mid_ms, prev_bottom_ms, prev_hum_ms
  var prev_t_top, prev_t_mid, prev_t_bottom, prev_rh
  var err_top, err_mid, err_bottom, err_hum
  var err_top_stuck, err_mid_stuck, err_bottom_stuck, err_hum_stuck
  var top_seen, mid_seen, bottom_seen, hum_seen

  var sim_enabled, sim_top, sim_mid, sim_bottom, sim_hum, sim_door_open
  var mqtt_status_enabled, mqtt_status_topic, mqtt_status_interval_ms, last_mqtt_status_ms

  def init()
    self.sensor_top_name = "DS18B20-1"
    self.sensor_bottom_name = "DS18B20-2"
    self.sensor_mid_name = "SHT3X"

    self.cool_on = 5.0
    self.cool_off = 4.0
    self.hum_on = 82.0
    self.hum_off = 87.0
    self.too_cold_trip = 1.5
    self.too_cold_reset = 2.5

    self.cal_top_temp = 0.0
    self.cal_mid_temp = 0.0
    self.cal_bottom_temp = 0.0
    self.cal_humidity = 0.0

    self.min_comp_on_ms = 180000
    self.min_comp_off_ms = 300000
    self.fan_postrun_ms = 120000
    self.door_recover_ms = 30000
    self.door_open_comp_off_delay_ms = 30000
    self.watchdog_timeout_ms = 180000
    self.mix_cycle_period_ms = 900000
    self.mix_cycle_run_ms = 120000

    self.startup_comp_lockout_ms = 300000
    self.high_temp_alarm_on = 8.0
    self.high_temp_alarm_off = 6.5
    self.high_temp_alarm_delay_ms = 900000
    self.door_alarm_delay_ms = 120000
    self.max_comp_runtime_ms = 3600000
    self.humidifier_post_cool_lockout_ms = 120000
    self.sensor_stuck_timeout_ms = 1800000
    self.startup_sensor_grace_ms = 60000

    self.compressor_on = false
    self.fan_on = false
    self.humidifier_on = false
    self.alarm_on = false
    self.alarm_reason = ""
    self.door_open = false

    self.too_cold_latched = false
    self.fail_safe = false
    self.high_temp_alarm_latched = false
    self.door_alarm_latched = false
    self.runtime_alarm_latched = false
    self.startup_waiting_for_sensors = true

    self.boot_ms = tasmota.millis()
    self.last_comp_on_ms = 0
    self.last_comp_off_ms = self.boot_ms
    self.last_door_change_ms = 0
    self.last_mix_ms = 0
    self.door_open_since_ms = 0
    self.high_temp_since_ms = 0
    self.last_humidifier_lockout_ms = 0

    self.t_top = nil
    self.t_mid = nil
    self.t_bottom = nil
    self.rh = nil
    self.raw_t_top = nil
    self.raw_t_mid = nil
    self.raw_t_bottom = nil
    self.raw_rh = nil

    self.last_top_ms = 0
    self.last_mid_ms = 0
    self.last_bottom_ms = 0
    self.last_hum_ms = 0
    self.prev_top_ms = 0
    self.prev_mid_ms = 0
    self.prev_bottom_ms = 0
    self.prev_hum_ms = 0
    self.prev_t_top = nil
    self.prev_t_mid = nil
    self.prev_t_bottom = nil
    self.prev_rh = nil

    self.err_top = false
    self.err_mid = false
    self.err_bottom = false
    self.err_hum = false
    self.err_top_stuck = false
    self.err_mid_stuck = false
    self.err_bottom_stuck = false
    self.err_hum_stuck = false

    self.top_seen = false
    self.mid_seen = false
    self.bottom_seen = false
    self.hum_seen = false

    self.sim_enabled = false
    self.sim_top = 5.0
    self.sim_mid = 4.5
    self.sim_bottom = 4.0
    self.sim_hum = 85.0
    self.sim_door_open = false

    self.mqtt_status_enabled = true
    self.mqtt_status_topic = "tele/flowercooler/status"
    self.mqtt_status_interval_ms = 60000
    self.last_mqtt_status_ms = 0

    self.load_persisted_config()

    tasmota.add_driver(self)

    self.force_outputs_off_hard()

    tasmota.add_rule(self.sensor_mid_name .. "#Temperature", def(value, trigger, msg) self.cb_mid_temp(value, trigger, msg) end)
    tasmota.add_rule(self.sensor_mid_name .. "#Humidity", def(value, trigger, msg) self.cb_mid_hum(value, trigger, msg) end)
    tasmota.add_rule(self.sensor_top_name .. "#Temperature", def(value, trigger, msg) self.cb_top_temp(value, trigger, msg) end)
    tasmota.add_rule(self.sensor_bottom_name .. "#Temperature", def(value, trigger, msg) self.cb_bottom_temp(value, trigger, msg) end)
    tasmota.add_rule("Switch1#State=1", def(value, trigger, msg) self.cb_door_open() end)
    tasmota.add_rule("Switch1#State=0", def(value, trigger, msg) self.cb_door_close() end)
  end

  def persist_get_num(key, default_val)
    var v = persist.find(key, nil)
    if v == nil return default_val end
    try return real(v)
    except .. as e return default_val
    end
  end

  def load_persisted_config()
    self.cool_on = self.persist_get_num("fc.cool_on", self.cool_on)
    self.cool_off = self.persist_get_num("fc.cool_off", self.cool_off)
    self.hum_on = self.persist_get_num("fc.hum_on", self.hum_on)
    self.hum_off = self.persist_get_num("fc.hum_off", self.hum_off)
    self.too_cold_trip = self.persist_get_num("fc.too_cold_trip", self.too_cold_trip)
    self.too_cold_reset = self.persist_get_num("fc.too_cold_reset", self.too_cold_reset)
    self.cal_top_temp = self.persist_get_num("fc.cal_top_temp", self.cal_top_temp)
    self.cal_mid_temp = self.persist_get_num("fc.cal_mid_temp", self.cal_mid_temp)
    self.cal_bottom_temp = self.persist_get_num("fc.cal_bottom_temp", self.cal_bottom_temp)
    self.cal_humidity = self.persist_get_num("fc.cal_humidity", self.cal_humidity)

    self.min_comp_on_ms = int(self.persist_get_num("fc.min_comp_on_ms", self.min_comp_on_ms))
    self.min_comp_off_ms = int(self.persist_get_num("fc.min_comp_off_ms", self.min_comp_off_ms))
    self.fan_postrun_ms = int(self.persist_get_num("fc.fan_postrun_ms", self.fan_postrun_ms))
    self.door_recover_ms = int(self.persist_get_num("fc.door_recover_ms", self.door_recover_ms))
    self.door_open_comp_off_delay_ms = int(self.persist_get_num("fc.door_open_comp_off_delay_ms", self.door_open_comp_off_delay_ms))
    self.watchdog_timeout_ms = int(self.persist_get_num("fc.watchdog_timeout_ms", self.watchdog_timeout_ms))
    self.mix_cycle_period_ms = int(self.persist_get_num("fc.mix_cycle_period_ms", self.mix_cycle_period_ms))
    self.mix_cycle_run_ms = int(self.persist_get_num("fc.mix_cycle_run_ms", self.mix_cycle_run_ms))

    self.startup_comp_lockout_ms = int(self.persist_get_num("fc.startup_comp_lockout_ms", self.startup_comp_lockout_ms))
    self.high_temp_alarm_on = self.persist_get_num("fc.high_temp_alarm_on", self.high_temp_alarm_on)
    self.high_temp_alarm_off = self.persist_get_num("fc.high_temp_alarm_off", self.high_temp_alarm_off)
    self.high_temp_alarm_delay_ms = int(self.persist_get_num("fc.high_temp_alarm_delay_ms", self.high_temp_alarm_delay_ms))
    self.door_alarm_delay_ms = int(self.persist_get_num("fc.door_alarm_delay_ms", self.door_alarm_delay_ms))
    self.max_comp_runtime_ms = int(self.persist_get_num("fc.max_comp_runtime_ms", self.max_comp_runtime_ms))
    self.humidifier_post_cool_lockout_ms = int(self.persist_get_num("fc.humidifier_post_cool_lockout_ms", self.humidifier_post_cool_lockout_ms))
    self.sensor_stuck_timeout_ms = int(self.persist_get_num("fc.sensor_stuck_timeout_ms", self.sensor_stuck_timeout_ms))
    self.startup_sensor_grace_ms = int(self.persist_get_num("fc.startup_sensor_grace_ms", self.startup_sensor_grace_ms))

    self.mqtt_status_interval_ms = int(self.persist_get_num("fc.mqtt_status_interval_ms", self.mqtt_status_interval_ms))
    self.mqtt_status_enabled = self.persist_get_num("fc.mqtt_status_enabled", self.mqtt_status_enabled ? 1 : 0) != 0
  end

  def save_persisted_config()
    persist.setmember("fc.cool_on", self.cool_on)
    persist.setmember("fc.cool_off", self.cool_off)
    persist.setmember("fc.hum_on", self.hum_on)
    persist.setmember("fc.hum_off", self.hum_off)
    persist.setmember("fc.too_cold_trip", self.too_cold_trip)
    persist.setmember("fc.too_cold_reset", self.too_cold_reset)
    persist.setmember("fc.cal_top_temp", self.cal_top_temp)
    persist.setmember("fc.cal_mid_temp", self.cal_mid_temp)
    persist.setmember("fc.cal_bottom_temp", self.cal_bottom_temp)
    persist.setmember("fc.cal_humidity", self.cal_humidity)

    persist.setmember("fc.min_comp_on_ms", self.min_comp_on_ms)
    persist.setmember("fc.min_comp_off_ms", self.min_comp_off_ms)
    persist.setmember("fc.fan_postrun_ms", self.fan_postrun_ms)
    persist.setmember("fc.door_recover_ms", self.door_recover_ms)
    persist.setmember("fc.door_open_comp_off_delay_ms", self.door_open_comp_off_delay_ms)
    persist.setmember("fc.watchdog_timeout_ms", self.watchdog_timeout_ms)
    persist.setmember("fc.mix_cycle_period_ms", self.mix_cycle_period_ms)
    persist.setmember("fc.mix_cycle_run_ms", self.mix_cycle_run_ms)

    persist.setmember("fc.startup_comp_lockout_ms", self.startup_comp_lockout_ms)
    persist.setmember("fc.high_temp_alarm_on", self.high_temp_alarm_on)
    persist.setmember("fc.high_temp_alarm_off", self.high_temp_alarm_off)
    persist.setmember("fc.high_temp_alarm_delay_ms", self.high_temp_alarm_delay_ms)
    persist.setmember("fc.door_alarm_delay_ms", self.door_alarm_delay_ms)
    persist.setmember("fc.max_comp_runtime_ms", self.max_comp_runtime_ms)
    persist.setmember("fc.humidifier_post_cool_lockout_ms", self.humidifier_post_cool_lockout_ms)
    persist.setmember("fc.sensor_stuck_timeout_ms", self.sensor_stuck_timeout_ms)
    persist.setmember("fc.startup_sensor_grace_ms", self.startup_sensor_grace_ms)

    persist.setmember("fc.mqtt_status_interval_ms", self.mqtt_status_interval_ms)
    persist.setmember("fc.mqtt_status_enabled", self.mqtt_status_enabled ? 1 : 0)
    persist.save()
  end

  def millis() return tasmota.millis() end
  def log(msg) print("[flowercooler] " .. msg) end

  def clamp(v, minv, maxv)
    if v < minv return minv end
    if v > maxv return maxv end
    return v
  end

  def to_num(v)
    if v == nil return nil end
    try return real(v)
    except .. as e return nil
    end
  end

  def normalize_spaces(line)
    line = string.replace(str(line), "\t", " ")
    while string.find(line, "  ") >= 0
      line = string.replace(line, "  ", " ")
    end
    return line
  end

  def almost_same(a, b, eps)
    if a == nil || b == nil return false end
    var d = a - b
    if d < 0 d = -d end
    return d <= eps
  end

  def boolstr(v)
    if v return "true" end
    return "false"
  end

  def num_or_null(v)
    if v == nil return "null" end
    return str(v)
  end

  def ms_remaining(target_ms)
    var rem = target_ms - self.millis()
    if rem < 0 return 0 end
    return rem
  end

  def sec_from_ms(msv)
    return int((msv + 999) / 1000)
  end

  def startup_sensor_ready()
    return self.mid_seen && self.hum_seen
  end

  def startup_sensor_grace_active()
    return self.millis() < (self.boot_ms + self.startup_sensor_grace_ms)
  end

  def startup_comp_lockout_active()
    if self.compressor_on return false end
    return self.millis() < (self.last_comp_off_ms + self.startup_comp_lockout_ms)
  end

  def compressor_power_on_protection_active()
    if self.compressor_on return false end
    return self.millis() < (self.last_comp_off_ms + self.min_comp_off_ms)
  end

  def compressor_power_off_protection_active()
    if !self.compressor_on return false end
    return self.millis() < (self.last_comp_on_ms + self.min_comp_on_ms)
  end

  def door_open_comp_off_delay_active()
    if !self.door_open return false end
    if !self.compressor_on return false end
    if self.door_open_since_ms == 0 return false end
    return self.millis() < (self.door_open_since_ms + self.door_open_comp_off_delay_ms)
  end

  def humidifier_lockout_active()
    return self.millis() < (self.last_humidifier_lockout_ms + self.humidifier_post_cool_lockout_ms)
  end

  def compressor_wait_to_on_ms()
    if self.compressor_on || self.t_mid == nil || self.t_mid < self.cool_on return 0 end
    var rem1 = 0
    var rem2 = 0
    if self.compressor_power_on_protection_active()
      rem1 = self.ms_remaining(self.last_comp_off_ms + self.min_comp_off_ms)
    end
    if self.startup_comp_lockout_active()
      rem2 = self.ms_remaining(self.last_comp_off_ms + self.startup_comp_lockout_ms)
    end
    if rem2 > rem1 return rem2 end
    return rem1
  end

  def compressor_wait_to_off_ms()
    if !self.compressor_on || self.t_mid == nil || self.t_mid > self.cool_off || !self.compressor_power_off_protection_active() return 0 end
    return self.ms_remaining(self.last_comp_on_ms + self.min_comp_on_ms)
  end

  def compressor_wait_to_off_by_door_ms()
    if !self.door_open_comp_off_delay_active() return 0 end
    return self.ms_remaining(self.door_open_since_ms + self.door_open_comp_off_delay_ms)
  end

  def force_outputs_off_hard()
    tasmota.cmd("Power1 0")
    tasmota.cmd("Power2 0")
    tasmota.cmd("Power3 0")
    tasmota.cmd("Power4 0")
    self.compressor_on = false
    self.fan_on = false
    self.humidifier_on = false
    self.alarm_on = false
    self.alarm_reason = ""
    self.log("startup outputs forced OFF")
  end

  def force_all_outputs_off()
    if !self.sim_enabled
      self.force_outputs_off_hard()
    else
      self.compressor_on = false
      self.fan_on = false
      self.humidifier_on = false
      self.alarm_on = false
      self.alarm_reason = ""
    end
    self.log("all outputs forced OFF")
  end

  def set_alarm(state)
    if state != self.alarm_on
      self.relay(4, state)
      self.alarm_on = state
    end
  end

  def build_alarm_reason()
    var r = ""
    if self.too_cold_latched
      r = r == "" ? "too_cold" : r .. ",too_cold"
    end
    if self.fail_safe
      r = r == "" ? "fail_safe" : r .. ",fail_safe"
    end
    if self.high_temp_alarm_latched
      r = r == "" ? "high_temp" : r .. ",high_temp"
    end
    if self.door_alarm_latched
      r = r == "" ? "door" : r .. ",door"
    end
    if self.runtime_alarm_latched
      r = r == "" ? "max_runtime" : r .. ",max_runtime"
    end
    return r
  end

  def refresh_alarm_output()
    var on = self.too_cold_latched || self.fail_safe || self.high_temp_alarm_latched || self.door_alarm_latched || self.runtime_alarm_latched
    self.set_alarm(on)
    self.alarm_reason = on ? self.build_alarm_reason() : ""
  end

  def relay(power_idx, state)
    if self.sim_enabled
      self.log("SIM output: Power" .. str(power_idx) .. " -> " .. (state ? "ON" : "OFF"))
      return
    end
    if state
      tasmota.cmd("Power" .. str(power_idx) .. " 1")
    else
      tasmota.cmd("Power" .. str(power_idx) .. " 0")
    end
  end

  def start_fan()
    if !self.fan_on
      self.relay(2, true)
      self.fan_on = true
    end
  end

  def stop_fan()
    if self.fan_on
      self.relay(2, false)
      self.fan_on = false
    end
  end

  def start_compressor()
    if !self.compressor_on
      self.relay(1, true)
      self.compressor_on = true
      self.last_comp_on_ms = self.millis()
      self.start_fan()
      self.log("compressor ON")
    end
  end

  def stop_compressor()
    if self.compressor_on
      self.relay(1, false)
      self.compressor_on = false
      self.last_comp_off_ms = self.millis()
      self.last_humidifier_lockout_ms = self.last_comp_off_ms
      self.start_fan()
      tasmota.set_timer(self.fan_postrun_ms, def() self.postrun_fan_stop() end)
      self.log("compressor OFF")
    end
  end

  def bypass_start_compressor()
    if self.too_cold_latched
      self.log("bypass denied: too cold protection is latched")
      return
    end
    if self.fail_safe
      self.log("bypass denied: fail-safe is active")
      return
    end
    if self.door_open
      self.log("bypass denied: door is open")
      return
    end
    if self.startup_waiting_for_sensors
      self.log("bypass denied: waiting for startup sensor data")
      return
    end
    self.stop_humidifier()
    self.start_compressor()
    self.log("compressor BYPASS START executed")
  end

  def start_humidifier()
    if !self.humidifier_on
      self.relay(3, true)
      self.humidifier_on = true
      self.log("humidifier ON")
    end
  end

  def stop_humidifier()
    if self.humidifier_on
      self.relay(3, false)
      self.humidifier_on = false
      self.log("humidifier OFF")
    end
  end

  def postrun_fan_stop()
    if !self.compressor_on && !self.door_open && !self.fail_safe
      self.stop_fan()
    end
  end

  def value_ok_temp(v)
    if v == nil return false end
    return v > -20 && v < 50
  end

  def value_ok_hum(v)
    if v == nil return false end
    return v >= 0 && v <= 100
  end

  def apply_cal_temp_top(v)
    if v == nil return nil end
    return v + self.cal_top_temp
  end

  def apply_cal_temp_mid(v)
    if v == nil return nil end
    return v + self.cal_mid_temp
  end

  def apply_cal_temp_bottom(v)
    if v == nil return nil end
    return v + self.cal_bottom_temp
  end

  def apply_cal_hum(v)
    if v == nil return nil end
    return self.clamp(v + self.cal_humidity, 0, 100)
  end

  def refresh_from_sim()
    var prev_door = self.door_open
    self.prev_t_top = self.t_top
    self.prev_t_mid = self.t_mid
    self.prev_t_bottom = self.t_bottom
    self.prev_rh = self.rh
    self.prev_top_ms = self.last_top_ms
    self.prev_mid_ms = self.last_mid_ms
    self.prev_bottom_ms = self.last_bottom_ms
    self.prev_hum_ms = self.last_hum_ms

    self.raw_t_top = self.sim_top
    self.raw_t_mid = self.sim_mid
    self.raw_t_bottom = self.sim_bottom
    self.raw_rh = self.sim_hum

    self.t_top = self.apply_cal_temp_top(self.raw_t_top)
    self.t_mid = self.apply_cal_temp_mid(self.raw_t_mid)
    self.t_bottom = self.apply_cal_temp_bottom(self.raw_t_bottom)
    self.rh = self.apply_cal_hum(self.raw_rh)

    self.top_seen = true
    self.mid_seen = true
    self.bottom_seen = true
    self.hum_seen = true
    self.startup_waiting_for_sensors = false

    self.door_open = self.sim_door_open
    if self.door_open && !prev_door
      self.door_open_since_ms = self.millis()
      self.last_door_change_ms = self.door_open_since_ms
    end
    if !self.door_open
      self.door_open_since_ms = 0
    end

    var now = self.millis()
    self.last_top_ms = now
    self.last_mid_ms = now
    self.last_bottom_ms = now
    self.last_hum_ms = now
  end

  def cb_top_temp(value, trigger, msg)
    if self.sim_enabled return end
    var v = self.to_num(value)
    if v == nil return end
    self.prev_t_top = self.t_top
    self.prev_top_ms = self.last_top_ms
    self.raw_t_top = v
    self.t_top = self.apply_cal_temp_top(v)
    self.last_top_ms = self.millis()
    self.top_seen = true
    self.evaluate()
  end

  def cb_mid_temp(value, trigger, msg)
    if self.sim_enabled return end
    var v = self.to_num(value)
    if v == nil return end
    self.prev_t_mid = self.t_mid
    self.prev_mid_ms = self.last_mid_ms
    self.raw_t_mid = v
    self.t_mid = self.apply_cal_temp_mid(v)
    self.last_mid_ms = self.millis()
    self.mid_seen = true
    self.evaluate()
  end

  def cb_bottom_temp(value, trigger, msg)
    if self.sim_enabled return end
    var v = self.to_num(value)
    if v == nil return end
    self.prev_t_bottom = self.t_bottom
    self.prev_bottom_ms = self.last_bottom_ms
    self.raw_t_bottom = v
    self.t_bottom = self.apply_cal_temp_bottom(v)
    self.last_bottom_ms = self.millis()
    self.bottom_seen = true
    self.evaluate()
  end

  def cb_mid_hum(value, trigger, msg)
    if self.sim_enabled return end
    var v = self.to_num(value)
    if v == nil return end
    self.prev_rh = self.rh
    self.prev_hum_ms = self.last_hum_ms
    self.raw_rh = v
    self.rh = self.apply_cal_hum(v)
    self.last_hum_ms = self.millis()
    self.hum_seen = true
    self.evaluate()
  end

  def cb_door_open()
    if self.sim_enabled return end
    self.door_open = true
    self.door_open_since_ms = self.millis()
    self.last_door_change_ms = self.door_open_since_ms
    self.stop_humidifier()
    self.log("door OPEN")
    self.evaluate()
  end

  def cb_door_close()
    if self.sim_enabled return end
    self.door_open = false
    self.door_open_since_ms = 0
    self.door_alarm_latched = false
    self.last_door_change_ms = self.millis()
    self.stop_humidifier()
    self.stop_fan()
    self.refresh_alarm_output()
    self.log("door CLOSED")
    tasmota.set_timer(self.door_recover_ms, def() self.evaluate() end)
  end

  def update_sensor_health()
    var now = self.millis()

    self.err_top = false
    self.err_mid = false
    self.err_bottom = false
    self.err_hum = false

    if self.top_seen
      self.err_top = (!self.value_ok_temp(self.t_top)) || ((now - self.last_top_ms) > self.watchdog_timeout_ms)
    end
    if self.mid_seen
      self.err_mid = (!self.value_ok_temp(self.t_mid)) || ((now - self.last_mid_ms) > self.watchdog_timeout_ms)
    end
    if self.bottom_seen
      self.err_bottom = (!self.value_ok_temp(self.t_bottom)) || ((now - self.last_bottom_ms) > self.watchdog_timeout_ms)
    end
    if self.hum_seen
      self.err_hum = (!self.value_ok_hum(self.rh)) || ((now - self.last_hum_ms) > self.watchdog_timeout_ms)
    end
  end

  def update_secondary_alarms()
    var now = self.millis()

    if self.mid_seen && !self.err_mid && self.t_mid >= self.high_temp_alarm_on
      if self.high_temp_since_ms == 0
        self.high_temp_since_ms = now
      end
      if (now - self.high_temp_since_ms) >= self.high_temp_alarm_delay_ms
        self.high_temp_alarm_latched = true
      end
    else
      self.high_temp_since_ms = 0
      if self.mid_seen && !self.err_mid && self.t_mid <= self.high_temp_alarm_off
        self.high_temp_alarm_latched = false
      end
    end

    if self.door_open && self.door_open_since_ms > 0 && ((now - self.door_open_since_ms) >= self.door_alarm_delay_ms)
      self.door_alarm_latched = true
    end
    if !self.door_open
      self.door_alarm_latched = false
    end

    if self.compressor_on && ((now - self.last_comp_on_ms) >= self.max_comp_runtime_ms)
      self.runtime_alarm_latched = true
    end
    if !self.compressor_on
      self.runtime_alarm_latched = false
    end

    self.refresh_alarm_output()
  end

  def main_temp_missing()
    return !self.mid_seen || self.err_mid
  end

  def too_cold_trip_hit()
    if self.top_seen && !self.err_top && self.t_top <= self.too_cold_trip return true end
    if self.mid_seen && !self.err_mid && self.t_mid <= self.too_cold_trip return true end
    if self.bottom_seen && !self.err_bottom && self.t_bottom <= self.too_cold_trip return true end
    return false
  end

  def too_cold_can_reset()
    if !self.mid_seen || self.err_mid return false end
    if self.t_mid < self.too_cold_reset return false end
    if self.top_seen && (!self.err_top && self.t_top < self.too_cold_reset) return false end
    if self.bottom_seen && (!self.err_bottom && self.t_bottom < self.too_cold_reset) return false end
    return true
  end

  def compressor_can_start()
    if self.compressor_on return false end
    if self.startup_comp_lockout_active() return false end
    return !self.compressor_power_on_protection_active()
  end

  def compressor_can_stop()
    if !self.compressor_on return false end
    return !self.compressor_power_off_protection_active()
  end

  def temp_spread_high()
    if !self.top_seen || !self.bottom_seen return false end
    if self.err_top || self.err_bottom return false end
    return (self.t_top - self.t_bottom) > 1.0
  end

  def enter_fail_safe(reason)
    self.fail_safe = true
    self.stop_compressor()
    self.stop_humidifier()
    self.start_fan()
    self.refresh_alarm_output()
    self.log("FAIL-SAFE: " .. reason)
  end

  def clear_fail_safe_if_possible()
    if self.fail_safe
      if !self.main_temp_missing() && !self.door_open && !self.too_cold_latched
        self.fail_safe = false
        self.refresh_alarm_output()
        self.log("FAIL-SAFE cleared")
      end
    end
  end

  def evaluate()
    if self.sim_enabled
      self.refresh_from_sim()
    end

    self.update_sensor_health()
    self.update_secondary_alarms()

    if self.startup_waiting_for_sensors
      if self.startup_sensor_ready()
        self.startup_waiting_for_sensors = false
        self.log("startup sensor wait completed")
      elif self.startup_sensor_grace_active()
        return
      else
        self.enter_fail_safe("startup sensor grace expired without required data")
        return
      end
    end

    if self.main_temp_missing()
      self.enter_fail_safe("main SHT30 temperature missing/invalid")
      return
    end

    if self.too_cold_trip_hit()
      self.too_cold_latched = true
      self.stop_compressor()
      self.refresh_alarm_output()
      self.log("too cold protection latched")
    end

    if self.too_cold_latched
      if self.too_cold_can_reset()
        self.too_cold_latched = false
        self.refresh_alarm_output()
        self.log("too cold protection reset")
      else
        self.stop_compressor()
        return
      end
    end

    if self.door_open
      self.stop_humidifier()
      if self.compressor_on && !self.door_open_comp_off_delay_active()
        self.stop_compressor()
      end
      return
    end

    if (self.millis() - self.last_door_change_ms) < self.door_recover_ms
      return
    end

    self.clear_fail_safe_if_possible()
    if self.fail_safe return end

    if self.t_mid >= self.cool_on
      if self.compressor_can_start()
        self.stop_humidifier()
        self.start_compressor()
      end
    elif self.t_mid <= self.cool_off
      if self.compressor_can_stop()
        self.stop_compressor()
      end
    end

    if !self.err_hum
      if self.rh < self.hum_on
        if !self.compressor_on && !self.humidifier_lockout_active()
          self.start_humidifier()
        end
      elif self.rh > self.hum_off
        self.stop_humidifier()
      end
    else
      self.stop_humidifier()
    end

    if self.compressor_on
      self.start_fan()
    else
      if self.temp_spread_high()
        self.start_fan()
        tasmota.set_timer(120000, def() self.postrun_fan_stop() end)
      else
        if (self.millis() - self.last_mix_ms) > self.mix_cycle_period_ms
          self.last_mix_ms = self.millis()
          self.start_fan()
          tasmota.set_timer(self.mix_cycle_run_ms, def() self.postrun_fan_stop() end)
        end
      end
    end
  end

  def set_sim_enabled(v)
    if v
      self.force_all_outputs_off()
      self.sim_enabled = true
      self.startup_waiting_for_sensors = false
      self.log("simulation mode enabled")
    else
      self.sim_enabled = false
      self.log("simulation mode disabled")
    end
  end

  def set_sim_door(v)
    if v == "open"
      self.sim_door_open = true
      return true
    end
    if v == "closed"
      self.sim_door_open = false
      return true
    end
    return false
  end

  def build_status_json()
    var s = "{"
    s += "\"t_top\":" .. self.num_or_null(self.t_top) .. ","
    s += "\"t_mid\":" .. self.num_or_null(self.t_mid) .. ","
    s += "\"t_bottom\":" .. self.num_or_null(self.t_bottom) .. ","
    s += "\"rh\":" .. self.num_or_null(self.rh) .. ","
    s += "\"top_seen\":" .. self.boolstr(self.top_seen) .. ","
    s += "\"mid_seen\":" .. self.boolstr(self.mid_seen) .. ","
    s += "\"bottom_seen\":" .. self.boolstr(self.bottom_seen) .. ","
    s += "\"hum_seen\":" .. self.boolstr(self.hum_seen) .. ","
    s += "\"startup_waiting_for_sensors\":" .. self.boolstr(self.startup_waiting_for_sensors) .. ","
    s += "\"compressor_on\":" .. self.boolstr(self.compressor_on) .. ","
    s += "\"fan_on\":" .. self.boolstr(self.fan_on) .. ","
    s += "\"humidifier_on\":" .. self.boolstr(self.humidifier_on) .. ","
    s += "\"alarm_on\":" .. self.boolstr(self.alarm_on) .. ","
    s += "\"alarm_reason\":\"" .. self.alarm_reason .. "\","
    s += "\"door_open\":" .. self.boolstr(self.door_open) .. ","
    s += "\"fail_safe\":" .. self.boolstr(self.fail_safe) .. ","
    s += "\"pending_compressor_on_s\":" .. str(self.sec_from_ms(self.compressor_wait_to_on_ms())) .. ","
    s += "\"pending_compressor_off_s\":" .. str(self.sec_from_ms(self.compressor_wait_to_off_ms())) .. ","
    s += "\"pending_compressor_off_by_door_s\":" .. str(self.sec_from_ms(self.compressor_wait_to_off_by_door_ms())) .. ","
    s += "\"sim_enabled\":" .. self.boolstr(self.sim_enabled)
    s += "}"
    return s
  end

  def publish_status_mqtt(force)
    if !self.mqtt_status_enabled && !force return end
    var now = self.millis()
    if !force && ((now - self.last_mqtt_status_ms) < self.mqtt_status_interval_ms) return end
    mqtt.publish(self.mqtt_status_topic, self.build_status_json(), false)
    self.last_mqtt_status_ms = now
  end

  def print_sim_status()
    self.log("==== SIMULATION ====")
    self.log("sim_enabled=" .. str(self.sim_enabled))
    self.log("sim_top=" .. str(self.sim_top))
    self.log("sim_mid=" .. str(self.sim_mid))
    self.log("sim_bottom=" .. str(self.sim_bottom))
    self.log("sim_hum=" .. str(self.sim_hum))
    self.log("sim_door_open=" .. str(self.sim_door_open))
  end

  def print_status()
    self.evaluate()

    self.log("==== CONFIG ====")
    self.log("sensor_top_name=" .. self.sensor_top_name)
    self.log("sensor_mid_name=" .. self.sensor_mid_name)
    self.log("sensor_bottom_name=" .. self.sensor_bottom_name)
    self.log("cool_on=" .. str(self.cool_on))
    self.log("cool_off=" .. str(self.cool_off))
    self.log("hum_on=" .. str(self.hum_on))
    self.log("hum_off=" .. str(self.hum_off))
    self.log("too_cold_trip=" .. str(self.too_cold_trip))
    self.log("too_cold_reset=" .. str(self.too_cold_reset))
    self.log("cal_top_temp=" .. str(self.cal_top_temp))
    self.log("cal_mid_temp=" .. str(self.cal_mid_temp))
    self.log("cal_bottom_temp=" .. str(self.cal_bottom_temp))
    self.log("cal_humidity=" .. str(self.cal_humidity))
    self.log("startup_sensor_grace_ms=" .. str(self.startup_sensor_grace_ms))
    self.log("startup_comp_lockout_ms=" .. str(self.startup_comp_lockout_ms))

    self.log("==== RAW VALUES ====")
    self.log("raw_t_top=" .. str(self.raw_t_top))
    self.log("raw_t_mid=" .. str(self.raw_t_mid))
    self.log("raw_t_bottom=" .. str(self.raw_t_bottom))
    self.log("raw_rh=" .. str(self.raw_rh))

    self.log("==== CALIBRATED VALUES ====")
    self.log("t_top=" .. str(self.t_top))
    self.log("t_mid=" .. str(self.t_mid))
    self.log("t_bottom=" .. str(self.t_bottom))
    self.log("rh=" .. str(self.rh))
    self.log("top_seen=" .. str(self.top_seen))
    self.log("mid_seen=" .. str(self.mid_seen))
    self.log("bottom_seen=" .. str(self.bottom_seen))
    self.log("hum_seen=" .. str(self.hum_seen))

    self.log("==== OUTPUT STATES ====")
    self.log("compressor_on=" .. str(self.compressor_on))
    self.log("fan_on=" .. str(self.fan_on))
    self.log("humidifier_on=" .. str(self.humidifier_on))
    self.log("alarm_on=" .. str(self.alarm_on))
    self.log("alarm_reason=" .. self.alarm_reason)
    self.log("door_open=" .. str(self.door_open))

    self.log("==== STARTUP STATE ====")
    self.log("startup_waiting_for_sensors=" .. str(self.startup_waiting_for_sensors))
    self.log("startup_sensor_grace_active=" .. str(self.startup_sensor_grace_active()))

    self.log("==== PROTECTION STATES ====")
    self.log("too_cold_latched=" .. str(self.too_cold_latched))
    self.log("fail_safe=" .. str(self.fail_safe))
    self.log("high_temp_alarm_latched=" .. str(self.high_temp_alarm_latched))
    self.log("door_alarm_latched=" .. str(self.door_alarm_latched))
    self.log("runtime_alarm_latched=" .. str(self.runtime_alarm_latched))
    self.log("err_top=" .. str(self.err_top))
    self.log("err_mid=" .. str(self.err_mid))
    self.log("err_bottom=" .. str(self.err_bottom))
    self.log("err_hum=" .. str(self.err_hum))

    self.log("==== DELAYS ====")
    self.log("pending compressor ON in " .. str(self.sec_from_ms(self.compressor_wait_to_on_ms())) .. " s")
    self.log("pending compressor OFF in " .. str(self.sec_from_ms(self.compressor_wait_to_off_ms())) .. " s")
    self.log("pending compressor OFF by door in " .. str(self.sec_from_ms(self.compressor_wait_to_off_by_door_ms())) .. " s")

    self.print_sim_status()
  end

  def set_param(key, val)
    if key == "cool_on" self.cool_on = val; return true end
    if key == "cool_off" self.cool_off = val; return true end
    if key == "hum_on" self.hum_on = self.clamp(val, 0, 100); return true end
    if key == "hum_off" self.hum_off = self.clamp(val, 0, 100); return true end
    if key == "too_cold_trip" self.too_cold_trip = val; return true end
    if key == "too_cold_reset" self.too_cold_reset = val; return true end
    if key == "cal_top_temp" self.cal_top_temp = val; return true end
    if key == "cal_mid_temp" self.cal_mid_temp = val; return true end
    if key == "cal_bottom_temp" self.cal_bottom_temp = val; return true end
    if key == "cal_humidity" self.cal_humidity = val; return true end
    if key == "min_comp_on_ms" self.min_comp_on_ms = int(val); return true end
    if key == "min_comp_off_ms" self.min_comp_off_ms = int(val); return true end
    if key == "fan_postrun_ms" self.fan_postrun_ms = int(val); return true end
    if key == "door_recover_ms" self.door_recover_ms = int(val); return true end
    if key == "door_open_comp_off_delay_ms" self.door_open_comp_off_delay_ms = int(val); return true end
    if key == "watchdog_timeout_ms" self.watchdog_timeout_ms = int(val); return true end
    if key == "mix_cycle_period_ms" self.mix_cycle_period_ms = int(val); return true end
    if key == "mix_cycle_run_ms" self.mix_cycle_run_ms = int(val); return true end
    if key == "startup_comp_lockout_ms" self.startup_comp_lockout_ms = int(val); return true end
    if key == "high_temp_alarm_on" self.high_temp_alarm_on = val; return true end
    if key == "high_temp_alarm_off" self.high_temp_alarm_off = val; return true end
    if key == "high_temp_alarm_delay_ms" self.high_temp_alarm_delay_ms = int(val); return true end
    if key == "door_alarm_delay_ms" self.door_alarm_delay_ms = int(val); return true end
    if key == "max_comp_runtime_ms" self.max_comp_runtime_ms = int(val); return true end
    if key == "humidifier_post_cool_lockout_ms" self.humidifier_post_cool_lockout_ms = int(val); return true end
    if key == "sensor_stuck_timeout_ms" self.sensor_stuck_timeout_ms = int(val); return true end
    if key == "startup_sensor_grace_ms" self.startup_sensor_grace_ms = int(val); return true end
    if key == "mqtt_status_interval_ms" self.mqtt_status_interval_ms = int(val); return true end
    return false
  end

  def print_help()
    self.log("commands:")
    self.log("  FC help")
    self.log("  FC status")
    self.log("  FC eval")
    self.log("  FC save")
    self.log("  FC bypass on")
    self.log("  FC mqtt on|off|status|publish")
    self.log("  FC sim on|off|status")
    self.log("  FC sim door open|closed")
    self.log("  FC set startup_sensor_grace_ms 60000")
    self.log("  FC set <key> <value>")
  end

  def handle_console_line(line)
    if line == nil
      self.print_help()
      return
    end

    line = self.normalize_spaces(line)

    if line == "help"
      self.print_help()
      return
    end
    if line == "status"
      self.print_status()
      return
    end
    if line == "eval"
      self.evaluate()
      self.log("manual evaluate done")
      return
    end
    if line == "save"
      self.save_persisted_config()
      self.log("configuration saved")
      return
    end
    if line == "bypass on"
      self.bypass_start_compressor()
      return
    end
    if line == "mqtt on"
      self.mqtt_status_enabled = true
      self.save_persisted_config()
      self.log("MQTT status enabled")
      return
    end
    if line == "mqtt off"
      self.mqtt_status_enabled = false
      self.save_persisted_config()
      self.log("MQTT status disabled")
      return
    end
    if line == "mqtt status"
      self.log("mqtt_status_enabled=" .. str(self.mqtt_status_enabled))
      self.log("mqtt_status_topic=" .. self.mqtt_status_topic)
      self.log("mqtt_status_interval_ms=" .. str(self.mqtt_status_interval_ms))
      return
    end
    if line == "mqtt publish"
      self.publish_status_mqtt(true)
      self.log("MQTT status published")
      return
    end
    if line == "sim on"
      self.set_sim_enabled(true)
      self.evaluate()
      return
    end
    if line == "sim off"
      self.set_sim_enabled(false)
      return
    end
    if line == "sim status"
      self.print_sim_status()
      return
    end
    if line == "sim door open"
      self.set_sim_door("open")
      self.evaluate()
      self.log("simulation door updated")
      return
    end
    if line == "sim door closed"
      self.set_sim_door("closed")
      self.evaluate()
      self.log("simulation door updated")
      return
    end

    if string.find(line, "set ") == 0
      var rest = string.replace(line, "set ", "")
      var parts = string.split(rest, " ")
      if size(parts) >= 2
        var key = parts[0]
        var val = self.to_num(parts[1])
        if val != nil
          if self.set_param(key, val)
            self.save_persisted_config()
            self.evaluate()
            self.log("saved: " .. key .. "=" .. str(val))
            return
          end
        end
      end
      self.log("usage: FC set <key> <value>")
      return
    end

    self.log("unknown command")
    self.print_help()
  end

  def every_second()
    self.evaluate()
    self.publish_status_mqtt(false)
  end
end

fc = FlowerCooler()

def fc_console_cmd(cmd, idx, payload, payload_json)
  fc.handle_console_line(payload)
end

tasmota.add_cmd("FC", fc_console_cmd)
