import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ServerConfig?
    @State private var latency: Duration?

    var body: some View {
        NavigationStack {
            List {
                Section("服务器") {
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
                            Button("删除", systemImage: "trash", role: .destructive) { model.remove(server) }
                            Button("编辑", systemImage: "pencil") { editing = server }
                        }
                    }
                    Button("添加服务器") {
                        editing = ServerConfig(name: "", url: "", username: "", password: "")
                    }
                    .foregroundStyle(Theme.cool)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(item: $editing) { ServerForm(server: $0) }
            .task(id: model.activeID) { latency = await model.client?.ping() }
        }
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
                    TextField("名称", text: $server.name)
                    TextField("地址", text: $server.url, prompt: Text("https://emby.example.com"))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextField("用户名", text: $server.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $server.password)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(Theme.secondary) }
                }
            }
            .navigationTitle(model.servers.contains { $0.id == server.id } ? "编辑服务器" : "添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if testing { ProgressView() } else {
                        Button("连接", systemImage: "checkmark") { Task { await save() } }
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
            Button("连接 Emby 服务器") { adding = true }
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
                    Button("重试") { Task { await model.connect() } }
                    Button("服务器") { showSettings = true }
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
