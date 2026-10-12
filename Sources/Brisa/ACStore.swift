import Foundation
import Observation
import ServiceManagement

struct ACDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

/// What the connected unit supports, read from its ThinQ profile.
struct Capabilities {
    var modes: [String] = ["COOL", "AIR_DRY", "FAN", "AUTO"]
    var fanSpeeds: [String] = ["LOW", "MID", "HIGH", "AUTO"]
    var hasJet = false
    var hasEco = false
    var hasSleep = false
    var hasSwingVertical = false
    var hasSwingHorizontal = false
    var usesTemperatureInUnits = true
    var minC = 16.0, maxC = 30.0
    var minF = 60.0, maxF = 86.0
}

enum Airflow: String, CaseIterable { case fixed, vertical, horizontal, both }

@MainActor @Observable
final class ACStore {
    // Settings
    var token: String = Keychain.readToken() ?? ""
    var deviceID: String = UserDefaults.standard.string(forKey: "deviceID") ?? "" {
        didSet { UserDefaults.standard.set(deviceID, forKey: "deviceID") }
    }
    var useFahrenheit: Bool = UserDefaults.standard.bool(forKey: "useFahrenheit") {
        didSet { UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit"); Task { await refresh() } }
    }
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do { launchAtLogin ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { lastError = error.localizedDescription }
        }
    }

    // Live state
    var devices: [ACDevice] = []
    var caps = Capabilities()
    var isOn = false
    var mode = "COOL"
    var fan = "AUTO"
    var currentTemp: Double?
    var targetTemp: Double?
    var eco = false
    var sleepHours = 0
    var airflow = Airflow.fixed
    var isConnected = false
    var lastError: String?
    var isBusy = false

    /// Called whenever the menu bar title should be redrawn.
    var onChange: (() -> Void)?

    private var profileLoadedFor: String?
    private var pollTask: Task<Void, Never>?
    private var holdUntil = Date.distantPast

    var unit: String { useFahrenheit ? "F" : "C" }
    var minTemp: Double { useFahrenheit ? caps.minF : caps.minC }
    var maxTemp: Double { useFahrenheit ? caps.maxF : caps.maxC }
    var jet: Bool { fan == "POWER" }
    var hasToken: Bool { !token.isEmpty }

    private var client: ThinQClient? {
        guard hasToken else { return nil }
        return ThinQClient(token: token, country: Locale.current.region?.identifier ?? "BR", clientID: Self.clientID)
    }

    private static var clientID: String {
        if let id = UserDefaults.standard.string(forKey: "clientID") { return id }
        let id = "brisa-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "clientID")
        return id
    }

    // MARK: Polling

    /// Polls every `interval` seconds, replacing any previous schedule.
    func startPolling(every interval: TimeInterval, refreshNow: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if refreshNow { await self?.refresh() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    func saveToken(_ newToken: String) async {
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.saveToken(token)
        profileLoadedFor = nil
        await loadDevices()
        await refresh()
    }

    func loadDevices() async {
        guard let client else { return }
        do {
            let list = try await client.devices()
            devices = list.compactMap { entry in
                guard let id = entry["deviceId"] as? String,
                      let info = entry["deviceInfo"] as? [String: Any],
                      (info["deviceType"] as? String) == "DEVICE_AIR_CONDITIONER" else { return nil }
                return ACDevice(id: id, name: info["alias"] as? String ?? info["modelName"] as? String ?? id)
            }
            if !devices.contains(where: { $0.id == deviceID }) { deviceID = devices.first?.id ?? "" }
            lastError = devices.isEmpty ? L("No air conditioners on this account") : nil
        } catch {
            fail(error)
        }
    }

    func refresh() async {
        guard let client else { isConnected = false; onChange?(); return }
        if deviceID.isEmpty { await loadDevices() }
        guard !deviceID.isEmpty else { return }
        do {
            if profileLoadedFor != deviceID {
                caps = Self.parseCapabilities(try await client.profile(deviceID))
                profileLoadedFor = deviceID
            }
            let state = try await client.state(deviceID)
            // Skip stale reads right after a command; the cloud lags a few seconds.
            if Date() >= holdUntil { apply(state) }
            isConnected = true
            lastError = nil
        } catch {
            fail(error)
        }
        onChange?()
    }

    private func fail(_ error: Error) {
        isConnected = false
        lastError = error.localizedDescription
        onChange?()
    }

    // MARK: Commands (optimistic, then confirmed by a later refresh)

    func setPower(_ on: Bool) {
        isOn = on
        send(["operation": ["airConOperationMode": on ? "POWER_ON" : "POWER_OFF"]])
    }

    func setMode(_ m: String) {
        mode = m
        send(["airConJobMode": ["currentJobMode": m]])
    }

    func setFan(_ f: String) {
        fan = f
        send(["airFlow": ["windStrength": f]])
    }

    func setJet(_ on: Bool) {
        if on { eco = false }
        setFan(on ? "POWER" : "AUTO")
    }

    func setEco(_ on: Bool) {
        eco = on
        if on && jet { fan = "AUTO" }
        send(["powerSave": ["powerSaveEnabled": on]])
    }

    func setTarget(_ t: Double) {
        let value = min(max(t.rounded(), minTemp), maxTemp)
        targetTemp = value
        if caps.usesTemperatureInUnits {
            send(["temperatureInUnits": ["targetTemperature": value, "unit": unit]])
        } else {
            let celsius = useFahrenheit ? (((value - 32) * 5 / 9) * 2).rounded() / 2 : value
            send(["temperature": ["targetTemperature": celsius, "unit": "C"]])
        }
    }

    func setSleep(hours: Int) {
        sleepHours = hours
        if hours == 0 {
            send(["sleepTimer": ["relativeStopTimer": "UNSET"]])
        } else {
            send(["sleepTimer": ["relativeHourToStop": hours, "relativeMinuteToStop": 0]])
        }
    }

    func setAirflow(_ a: Airflow) {
        airflow = a
        var payload: [String: Any] = [:]
        if caps.hasSwingVertical { payload["rotateUpDown"] = a == .vertical || a == .both }
        if caps.hasSwingHorizontal { payload["rotateLeftRight"] = a == .horizontal || a == .both }
        send(["windDirection": payload])
    }

    private func send(_ payload: [String: Any]) {
        onChange?()
        guard let client, !deviceID.isEmpty else { return }
        holdUntil = Date().addingTimeInterval(4)
        let id = deviceID
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await client.control(id, payload)
                try? await Task.sleep(for: .seconds(4))
                await refresh()
            } catch {
                fail(error)
                holdUntil = .distantPast
                await refresh()
            }
        }
    }

    // MARK: Parsing

    private func apply(_ s: [String: Any]) {
        if let op = Self.resource(s, "operation")?["airConOperationMode"] as? String { isOn = op == "POWER_ON" }
        if let m = Self.resource(s, "airConJobMode")?["currentJobMode"] as? String { mode = m }
        if let f = Self.resource(s, "airFlow")?["windStrength"] as? String { fan = f }
        if let e = Self.resource(s, "powerSave")?["powerSaveEnabled"] as? Bool { eco = e }
        if let sl = Self.resource(s, "sleepTimer") {
            sleepHours = (sl["relativeStopTimer"] as? String) == "UNSET" ? 0 : (sl["relativeHourToStop"] as? Int) ?? 0
        }
        if let wd = Self.resource(s, "windDirection") {
            let v = wd["rotateUpDown"] as? Bool ?? false
            let h = wd["rotateLeftRight"] as? Bool ?? false
            airflow = v && h ? .both : v ? .vertical : h ? .horizontal : .fixed
        }
        let temps = Self.temperatures(s, unit: unit)
        currentTemp = temps.current
        targetTemp = temps.target
    }

    /// Finds current/target temperature in the requested unit, converting if the unit is missing.
    private static func temperatures(_ s: [String: Any], unit: String) -> (current: Double?, target: Double?) {
        var entries: [[String: Any]] = []
        if let list = s["temperatureInUnits"] as? [[String: Any]] { entries += list }
        if let d = s["temperatureInUnits"] as? [String: Any] { entries.append(d) }
        if let list = s["temperature"] as? [[String: Any]] { entries += list }
        if let d = s["temperature"] as? [String: Any] { entries.append(d) }
        if let match = entries.first(where: { ($0["unit"] as? String) == unit }) {
            return (number(match["currentTemperature"]), number(match["targetTemperature"]))
        }
        guard let any = entries.first else { return (nil, nil) }
        let from = any["unit"] as? String ?? "C"
        func convert(_ v: Double?) -> Double? {
            guard let v else { return nil }
            if from == unit { return v }
            return unit == "F" ? (v * 9 / 5 + 32).rounded() : ((v - 32) * 5 / 9).rounded()
        }
        return (convert(number(any["currentTemperature"])), convert(number(any["targetTemperature"])))
    }

    static func parseCapabilities(_ profile: [String: Any]) -> Capabilities {
        var c = Capabilities()
        let props = resource(profile, "property") ?? profile
        func writable(_ res: String, _ prop: String) -> Any? {
            guard let p = resource(props, res)?[prop] as? [String: Any] else { return nil }
            let modeList = p["mode"] as? [String] ?? ["r", "w"]
            guard modeList.contains("w") else { return nil }
            let value = p["value"] as? [String: Any]
            return value?["w"] ?? value ?? p
        }
        if let m = writable("airConJobMode", "currentJobMode") as? [String], !m.isEmpty { c.modes = m }
        if let f = writable("airFlow", "windStrength") as? [String], !f.isEmpty {
            c.hasJet = f.contains("POWER")
            c.fanSpeeds = f.filter { $0 != "POWER" }
        }
        c.hasEco = writable("powerSave", "powerSaveEnabled") != nil
        c.hasSleep = writable("sleepTimer", "relativeHourToStop") != nil
        c.hasSwingVertical = writable("windDirection", "rotateUpDown") != nil
        c.hasSwingHorizontal = writable("windDirection", "rotateLeftRight") != nil
        // Units that expose a writable `temperature.targetTemperature` reject writes to temperatureInUnits.
        c.usesTemperatureInUnits = writable("temperature", "targetTemperature") == nil

        // Target range: temperatureInUnits lists one entry per unit, each with its own min/max.
        var tempEntries: [[String: Any]] = []
        for key in ["temperatureInUnits", "temperature"] {
            if let list = props[key] as? [[String: Any]] { tempEntries += list }
            if let d = props[key] as? [String: Any] { tempEntries.append(d) }
        }
        for entry in tempEntries {
            for (key, suffix) in [("targetTemperature", ""), ("coolTargetTemperature", ""),
                                  ("targetTemperatureC", "C"), ("targetTemperatureF", "F")] {
                guard let p = entry[key] as? [String: Any],
                      let v = (p["value"] as? [String: Any]).flatMap({ $0["w"] as? [String: Any] ?? $0 }),
                      let lo = number(v["min"]), let hi = number(v["max"]) else { continue }
                let u = suffix.isEmpty ? (entry["unit"] as? String ?? "C") : suffix
                if u == "F" { c.minF = lo; c.maxF = hi } else { c.minC = lo; c.maxC = hi }
            }
        }
        return c
    }

    private static func resource(_ dict: [String: Any], _ key: String) -> [String: Any]? {
        if let d = dict[key] as? [String: Any] { return d }
        return (dict[key] as? [[String: Any]])?.first
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}
