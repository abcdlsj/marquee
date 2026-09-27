import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ServerConfig?
    @State private var latency: Duration?
    @State private var tmdbDraft = ""
    @State private var tmdbStatus: String?
    @State private var tmdbChecking = false
    @State private var editingTMDB = false

    var body: some View {
        NavigationStack {
            List {
                Section("Servers") {
                    ForEach(model.servers) { server in
                        Button {
                            if server.id != model.activeID { model.activate(server) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(server.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.fg)
                                    Text("\(server.username) · \(server.host)").caption(11)
                                }
                                Spacer()
                                if server.id == model.activeID { status }
                            }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { model.remove(server) }
                            Button("Edit", systemImage: "pencil") { editing = server }
                        }
                    }
                    Button("Add Server") {
                        editing = ServerConfig(name: "", url: "", username: "", password: "")
                    }
                    .foregroundStyle(Theme.cool)
                }

                Section("TMDB") {
                    if model.tmdbKey.isEmpty || editingTMDB {
                        HStack {
                            SecureField("API Key", text: $tmdbDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { Task { await saveTMDB() } }
                            if tmdbChecking { ProgressView() }
                            else if let tmdbStatus { Text(tmdbStatus).caption(11, Theme.secondary) }
                        }
                        if editingTMDB {
                            Button("Cancel") { editingTMDB = false; tmdbDraft = ""; tmdbStatus = nil }
                                .foregroundStyle(Theme.secondary)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: tmdbStatus == nil ? "checkmark.seal.fill" : "exclamationmark.circle")
                                .foregroundStyle(tmdbStatus == nil ? Theme.cool : Theme.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tmdbStatus ?? "Connected").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.fg)
                                Text("Key ••••\(model.tmdbKey.suffix(4))").caption(11).monospacedDigit()
                            }
                            Spacer()
                            if tmdbChecking { ProgressView() }
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                model.tmdbKey = ""; tmdbStatus = nil
                            }
                        }
                        Button("Change Key") { editingTMDB = true }
                            .foregroundStyle(Theme.cool)
                    }
                }
            }
            .task(id: model.tmdbKey) { await recheckTMDB() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(item: $editing) { ServerForm(server: $0) }
            .task(id: model.activeID) { latency = await model.client?.ping() }
        }
    }

    private func saveTMDB() async {
        let key = tmdbDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { model.tmdbKey = ""; tmdbStatus = nil; return }
        tmdbChecking = true
        defer { tmdbChecking = false }
        if let error = await TMDB.shared.validate(key) {
            tmdbStatus = error
        } else {
            tmdbStatus = nil
            tmdbDraft = ""
            editingTMDB = false
            model.tmdbKey = key
        }
    }

    /// A saved key is re-checked quietly on open; the row shows its state instead of asking again.
    private func recheckTMDB() async {
        guard !model.tmdbKey.isEmpty, !editingTMDB else { return }
        tmdbChecking = true
        defer { tmdbChecking = false }
        tmdbStatus = await TMDB.shared.validate(model.tmdbKey)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .ready:
            Text(latency.map { "\(Int($0 / .milliseconds(1))) ms" } ?? "")
                .caption(11, Theme.cool).monospacedDigit()
        case .connecting: ProgressView()
        case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.secondary)
        case .idle: EmptyView()
        }
    }
}

struct ServerForm: View {
    @State var server: ServerConfig
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $server.name)
                    TextField("Address", text: $server.url, prompt: Text("https://emby.example.com"))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextField("Username", text: $server.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $server.password)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(Theme.secondary) }
                }
            }
            .navigationTitle(model.servers.contains { $0.id == server.id } ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if testing { ProgressView() } else {
                        Button("Connect", systemImage: "checkmark") { Task { await save() } }
                            .disabled(server.url.isEmpty || server.username.isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        testing = true
        defer { testing = false }
        do {
            let auth = try await EmbyClient.login(server: server.url, username: server.username, password: server.password)
            server.userID = auth.userID
            server.token = auth.token
            if server.name.isEmpty { server.name = server.host }
            model.upsert(server)
            model.activate(server)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WelcomeView: View {
    @State private var adding = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("MARQUEE").font(.system(size: 13, weight: .medium)).tracking(5).foregroundStyle(Theme.fg)
            Button("Connect to Emby") { adding = true }
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .sheet(isPresented: $adding) { ServerForm(server: ServerConfig(name: "", url: "", username: "", password: "")) }
    }
}

struct SplashView: View {
    let phase: AppModel.Phase
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("MARQUEE").font(.system(size: 13, weight: .medium)).tracking(5).foregroundStyle(Theme.fg)
            if case .failed(let msg) = phase {
                Text(msg).caption(11).multilineTextAlignment(.center).padding(.horizontal, 48)
                HStack(spacing: 28) {
                    Button("Retry") { Task { await model.connect() } }
                    Button("Servers") { showSettings = true }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            } else {
                ProgressView().tint(Theme.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
