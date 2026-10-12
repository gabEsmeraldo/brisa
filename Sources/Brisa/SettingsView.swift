import SwiftUI

struct SettingsView: View {
    @Bindable var store: ACStore
    let close: () -> Void
    @State private var tokenDraft = ""
    @State private var saving = false

    private func signInLG() {
        Task {
            do {
                let url = try await store.legacy.loginURL()
                LoginWindow.present(url: url)
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Settings")).font(.system(size: 17, weight: .semibold))
                Spacer()
                if store.hasToken {
                    Button(L("Done"), action: close).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Personal Access Token")).font(.system(size: 12, weight: .medium))
                HStack {
                    SecureField(store.hasToken ? L("Saved in Keychain") : L("Paste your token"), text: $tokenDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(L("Save")) {
                        saving = true
                        Task {
                            await store.saveToken(tokenDraft)
                            tokenDraft = ""
                            saving = false
                        }
                    }
                    .disabled(tokenDraft.isEmpty || saving)
                }
                HStack(spacing: 4) {
                    Text(L("Create one at"))
                    Link("connect-pat.lgthinq.com", destination: URL(string: "https://connect-pat.lgthinq.com")!)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            }

            if store.hasToken {
                Picker(L("Air conditioner"), selection: $store.deviceID) {
                    ForEach(store.devices) { Text($0.name).tag($0.id) }
                }
                .onChange(of: store.deviceID) { Task { await store.refresh() } }

                Picker(L("Temperature unit"), selection: $store.useFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("LG account (Jet mode)")).font(.system(size: 12, weight: .medium))
                HStack {
                    if store.legacyLinked {
                        Label(L("Linked"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        Spacer()
                        Button(L("Unlink")) { store.unlinkLegacy() }
                    } else {
                        Text(L("Jet isn't in LG's official API; sign in on LG's page to enable it."))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button(L("Sign in…")) { signInLG() }
                    }
                }
            }

            Toggle(L("Launch at login"), isOn: $store.launchAtLogin)

            if let error = store.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
            }

            HStack {
                Text(L("Not affiliated with LG Electronics.")).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button(L("Quit Brisa")) { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 11))
        }
        .font(.system(size: 13))
        .task { if store.hasToken && store.devices.isEmpty { await store.loadDevices() } }
    }
}
