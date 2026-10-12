import SwiftUI

enum Theme {
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.55, green: 0.80, blue: 1.0)
    /// Offscreen renders (README screenshots) can't capture glass, so they use the flat look.
    @MainActor static var forceFlat = false
}

struct PopoverView: View {
    @Bindable var store: ACStore
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings || !store.hasToken {
                SettingsView(store: store, close: { showSettings = false })
            } else {
                controls
            }
        }
        .padding(18)
        .frame(width: 430)
        .modifier(PanelBackground())
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
            header
            ACIllustration(isOn: store.isOn)
                .frame(width: 130, height: 50)
                .frame(maxWidth: .infinity)
            HStack(alignment: .center) {
                bigTemperature
                Spacer()
                VStack(spacing: 8) {
                    if store.caps.hasEco {
                        PillToggle(icon: "leaf", title: L("Eco Mode"), isOn: store.eco) { store.setEco($0) }
                    }
                    if store.caps.hasJet {
                        PillToggle(icon: "wind", title: L("Jet Mode"), isOn: store.jet) { store.setJet($0) }
                            .disabled(!store.canJet)
                            .help(store.canJet ? "" : L("Jet works only in Cool mode with the AC on"))
                    }
                }
            }
            TemperatureSlider(store: store)
            tiles
            }
            .disabled(!store.isConnected)
            .opacity(store.isConnected ? 1 : 0.5)
            footer
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "thermometer.medium").foregroundStyle(Theme.secondary)
            Text(L("Room")).foregroundStyle(Theme.secondary)
            Text(store.currentTemp.map { "\(Int($0.rounded()))°\(store.unit)" } ?? "—").fontWeight(.semibold)
            Spacer()
            Button { store.setPower(!store.isOn) } label: {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(store.isOn ? Theme.accent : Theme.secondary)
                    .frame(width: 36, height: 36)
                    .glassCard(Circle(), tint: store.isOn ? Theme.accent : nil)
            }
            .buttonStyle(.plain)
            .help(store.isOn ? L("Turn off") : L("Turn on"))
        }
        .font(.system(size: 13))
    }

    private var bigTemperature: some View {
        HStack(alignment: .top, spacing: 2) {
            Text(store.targetTemp.map { "\(Int($0))" } ?? "--")
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("°\(store.unit)")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)
        }
        .animation(.snappy, value: store.targetTemp)
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            OptionTile(icon: modeIcon(store.mode), title: L("Mode"), value: modeName(store.mode),
                       options: store.caps.modes.map { ($0, modeName($0)) }) { store.setMode($0) }
            OptionTile(icon: "fan", title: L("Fan speed"), value: fanName(store.fan),
                       options: store.caps.fanSpeeds.map { ($0, fanName($0)) }) { store.setFan($0) }
            if store.caps.hasSleep {
                OptionTile(icon: "moon", title: L("Sleep"),
                           value: store.sleepHours == 0 ? L("Off") : "\(store.sleepHours)h",
                           options: [0, 1, 2, 4, 6, 8].map { ("\($0)", $0 == 0 ? L("Off") : "\($0)h") }) {
                    store.setSleep(hours: Int($0) ?? 0)
                }
            }
            if store.caps.hasSwingVertical || store.caps.hasSwingHorizontal {
                OptionTile(icon: "wind", title: L("Airflow"), value: airflowName(store.airflow),
                           options: airflowOptions.map { ($0.rawValue, airflowName($0)) }) {
                    store.setAirflow(Airflow(rawValue: $0) ?? .fixed)
                }
            }
        }
    }

    private var airflowOptions: [Airflow] {
        var list: [Airflow] = [.fixed]
        if store.caps.hasSwingVertical { list.append(.vertical) }
        if store.caps.hasSwingHorizontal { list.append(.horizontal) }
        if store.caps.hasSwingVertical && store.caps.hasSwingHorizontal { list.append(.both) }
        return list
    }

    private var footer: some View {
        HStack {
            if store.isConnected {
                Label(L("Connected"), systemImage: "checkmark.shield")
            } else {
                Label(store.lastError ?? L("Connecting…"), systemImage: "exclamationmark.triangle")
                    .lineLimit(1).truncationMode(.tail)
            }
            if store.isBusy { ProgressView().controlSize(.small) }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain)
                .help(L("Settings"))
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
    }
}

// MARK: Labels

func modeName(_ m: String) -> String {
    switch m {
    case "COOL": return L("Cool")
    case "HEAT": return L("Heat")
    case "AIR_DRY": return L("Dry")
    case "FAN": return L("Fan")
    case "AUTO": return L("Auto")
    case "ENERGY_SAVING": return L("Energy saving")
    case "AIR_CLEAN": return L("Air clean")
    default: return m.capitalized
    }
}

func modeIcon(_ m: String) -> String {
    switch m {
    case "HEAT": return "sun.max"
    case "AIR_DRY": return "drop"
    case "FAN": return "fan"
    case "AUTO": return "arrow.triangle.2.circlepath"
    default: return "snowflake"
    }
}

func fanName(_ f: String) -> String {
    switch f {
    case "LOW": return L("Low")
    case "MID": return L("Medium")
    case "HIGH": return L("High")
    case "AUTO": return L("Auto")
    case "POWER": return L("Jet")
    default: return f.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func airflowName(_ a: Airflow) -> String {
    switch a {
    case .fixed: return L("Fixed")
    case .vertical: return L("Vertical")
    case .horizontal: return L("Horizontal")
    case .both: return L("All")
    }
}

// MARK: Components

struct PillToggle: View {
    let icon: String
    let title: String
    let isOn: Bool
    let action: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(isOn ? Theme.accent : Theme.secondary)
            Text(title).font(.system(size: 13, weight: .medium))
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(width: 170)
        .glassCard(RoundedRectangle(cornerRadius: 12))
    }
}

struct TemperatureSlider: View {
    @Bindable var store: ACStore
    @State private var dragValue: Double?

    private var value: Double { dragValue ?? store.targetTemp ?? store.minTemp }
    private var fraction: Double {
        let span = store.maxTemp - store.minTemp
        return span > 0 ? (value - store.minTemp) / span : 0
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                RoundButton(icon: "minus") { store.setTarget(value - 1) }
                GeometryReader { geo in
                    let knob: CGFloat = 26
                    let x = (geo.size.width - knob) * fraction
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 14).fill(.clear).glassCard(RoundedRectangle(cornerRadius: 14))
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [Theme.accent.opacity(0.15), Theme.accent.opacity(0.45)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: x + knob)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: knob - 6, height: 30)
                            .offset(x: x + 3)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = min(max((g.location.x - knob / 2) / (geo.size.width - knob), 0), 1)
                            dragValue = (store.minTemp + f * (store.maxTemp - store.minTemp)).rounded()
                            store.targetTemp = dragValue
                        }
                        .onEnded { _ in
                            if let v = dragValue { store.setTarget(v) }
                            dragValue = nil
                        })
                }
                .frame(height: 40)
                RoundButton(icon: "plus") { store.setTarget(value + 1) }
            }
            HStack {
                Text("\(Int(store.minTemp))°")
                Spacer()
                Text("\(Int(store.maxTemp))°")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 50)
        }
    }
}

struct RoundButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .glassCard(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct OptionTile: View {
    let icon: String
    let title: String
    let value: String
    let options: [(id: String, label: String)]
    let select: (String) -> Void
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon).font(.system(size: 18))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.bottom, 6)
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.id) { option in
                    Button {
                        select(option.id)
                        open = false
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if option.label == value { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(width: 150)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: Liquid Glass (macOS 26+), with the flat dark look as fallback

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !Theme.forceFlat {
            // The popover itself is glass on macOS 26; keep it see-through.
            content.background(Color.clear)
        } else {
            content.background(Color.black)
        }
    }
}

extension View {
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)  // Liquid Glass needs the macOS 26 SDK
        if #available(macOS 26, *), !Theme.forceFlat {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)).interactive() } ?? .regular.interactive(), in: shape)
        } else {
            flatCard(shape, tint: tint)
        }
        #else
        flatCard(shape, tint: tint)
        #endif
    }

    private func flatCard<S: Shape>(_ shape: S, tint: Color?) -> some View {
        self.background(shape.fill(tint?.opacity(0.18) ?? Theme.card))
            .overlay(shape.stroke(tint?.opacity(0.6) ?? Theme.cardStroke))
    }
}
