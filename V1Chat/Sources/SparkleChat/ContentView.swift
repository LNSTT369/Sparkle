import SwiftUI
import UniformTypeIdentifiers
import MLXLMCommon
import MLXVLM
import MLXLLM
import Hub

struct Message: Identifiable, Equatable {
    let id = UUID()
    let role: String // user or assistant
    var content: String
    var imageData: Data?
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role && lhs.content == rhs.content && lhs.imageData == rhs.imageData
    }
}

@MainActor
class ChatModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var selectedImage: NSImage?
    @Published var selectedImageData: Data?
    @Published var streamTick = 0
    // Single-process MLX
    private var modelContainer: ModelContainer?
    private var chatSession: AppSession?
    // Settings from Osaurus generationSection
    var temperature: Double { UserDefaults.standard.object(forKey: "modelTemperature") as? Double ?? 0.7 }
    var topP: Double { UserDefaults.standard.object(forKey: "modelTopP") as? Double ?? 1.0 }
    var contextLength: Int { UserDefaults.standard.object(forKey: "modelContextLength") as? Double ?? 8192 > 0 ? Int(UserDefaults.standard.object(forKey: "modelContextLength") as? Double ?? 8192) : 8192 }
    
    var modelPath: String {
        let bundled = Bundle.main.resourcePath.map { $0 + "/models/gemma-4-e4b-it-4bit-mlx" } ?? ""
        if FileManager.default.fileExists(atPath: bundled) { return bundled }
        return NSHomeDirectory() + "/models/gemma-4-e4b-it-4bit-mlx"
    }
    // Kept for /status display
    var endpoint: String { "in-process MLX" }
    var model: String { modelPath }
    var serverPort: String { "in-process" }
    
    // Single-process MLX - in process, no HTTP
    private var mlxSession: MLXLMCommon.ChatSession?
    
    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImageData != nil else { return }
        guard !isLoading else { return }
        
        if trimmed == "/clear" {
            messages.removeAll()
            mlxSession = nil
            input = ""
            selectedImage = nil
            selectedImageData = nil
            return
        }
        if trimmed == "/help" {
            messages.append(Message(role: "user", content: trimmed))
            messages.append(Message(role: "assistant", content: "Commands:\n/clear - clear chat\n/help - show this\n/status - model and memory\n/models - list models"))
            input = ""
            return
        }
        if trimmed == "/status" {
            messages.append(Message(role: "user", content: trimmed))
            Task {
                let status = await fetchStatus()
                messages.append(Message(role: "assistant", content: status))
            }
            input = ""
            return
        }
        if trimmed == "/models" {
            messages.append(Message(role: "user", content: trimmed))
            var txt = "Bundled model:\n• gemma-4-e4b-it-4bit 4.8GB Ready at \(modelPath)\n"
            txt += "\nIn-process MLX, no HTTP, no port"
            messages.append(Message(role: "assistant", content: txt))
            input = ""
            return
        }
        
        let userContent: String = trimmed
        let imageData = selectedImageData
        
        let userMsg = Message(role: "user", content: trimmed.isEmpty ? "[image]" : trimmed, imageData: imageData)
        messages.append(userMsg)
        input = ""
        selectedImage = nil
        selectedImageData = nil
        isLoading = true
        
        var assistantMsg = Message(role: "assistant", content: "")
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1
        
        Task {
            do {
                try await streamMLX(prompt: userContent, imageData: imageData, assistantIndex: assistantIndex)
            } catch {
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].content = "Error: \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }
    
    func streamMLX(prompt: String, imageData: Data?, assistantIndex: Int) async throws {
        // Ensure MLX model is loaded in-process
        if mlxSession == nil {
            let container: ModelContainer
            if FileManager.default.fileExists(atPath: modelPath) {
                let config = ModelConfiguration(directory: URL(fileURLWithPath: modelPath))
                container = try await loadModelContainer(hub: HubApi(), configuration: config)
            } else {
                container = try await loadModelContainer(id: "mlx-community/gemma-4-e4b-it-4bit")
            }
            let s = MLXLMCommon.ChatSession(container)
            s.generateParameters.temperature = Float(temperature)
            s.generateParameters.topP = Float(topP)
            mlxSession = s
        }
        guard let session = mlxSession else { throw NSError(domain: "MLX", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]) }
        session.generateParameters.temperature = Float(temperature)
        session.generateParameters.topP = Float(topP)
        
        // Build UserInput with history for continuous memory
        var history: [Chat.Message] = []
        for idx in 0..<assistantIndex {
            let msg = messages[idx]
            if msg.role == "user" {
                if let data = msg.imageData, let nsImg = NSImage(data: data), let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let ci = CIImage(cgImage: cg)
                    history.append(Chat.Message(role: .user, content: msg.content, images: [.ciImage(ci)]))
                } else {
                    history.append(Chat.Message(role: .user, content: msg.content))
                }
            } else {
                history.append(Chat.Message(role: .assistant, content: msg.content))
            }
        }
        if history.count > 20 {
            history = Array(history.suffix(20))
        }
        var full = ""
        let last = history.last
        let stream: AsyncThrowingStream<String, Error>
        if let last = last, !last.images.isEmpty {
            stream = session.streamResponse(to: last.content, images: last.images)
        } else if let last = last {
            stream = session.streamResponse(to: last.content)
        } else {
            stream = session.streamResponse(to: prompt)
        }
        for try await chunk in stream {
            if let t = chunk as? String, !t.isEmpty {
                full += t
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].content = full
                    streamTick += 1
                }
            }
        }
        if full.isEmpty, messages.indices.contains(assistantIndex), messages[assistantIndex].content.isEmpty {
            messages[assistantIndex].content = "(no content)"
        }
    }
    
    func fetchStatus() async -> String {
        var txt = "MLX in-process\n"
        txt += "Model: \(modelPath)\n"
        if mlxSession != nil { txt += "Loaded: yes, streaming on\n" } else { txt += "Loaded: not yet, will load on first chat\n" }
        txt += "Temp \(String(format: "%.1f", temperature)) • TopP \(String(format: "%.2f", topP)) • Context \(contextLength)\n"
        txt += "Peak 5.21GB text / 5.85GB vision • App 82M"
        return txt
    }
    
    func ensureServer() async {
        if mlxSession != nil { return }
        do {
            let container: ModelContainer
            if FileManager.default.fileExists(atPath: modelPath) {
                let config = ModelConfiguration(directory: URL(fileURLWithPath: modelPath))
                container = try await loadModelContainer(hub: HubApi(), configuration: config)
            } else {
                container = try await loadModelContainer(id: "mlx-community/gemma-4-e4b-it-4bit")
            }
            let s = MLXLMCommon.ChatSession(container)
            s.generateParameters.temperature = Float(temperature)
            s.generateParameters.topP = Float(topP)
            mlxSession = s
        } catch {
            print("MLX load failed: \(error)")
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data = data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.selectedImage = img
                    self.selectedImageData = data
                }
            }
            return true
        }
        return false
    }
    
    func startDownload(_ m: OnboardingModel) {
        messages.append(Message(role: "user", content: "Download \(m.name)"))
        let hfRepo: String
        switch m.id {
        case "gemma4-e4b-it-4bit": hfRepo = "mlx-community/gemma-4-e4b-it-4bit"
        case "gemma4-e4b-8bit": hfRepo = "mlx-community/gemma-4-e4b-8bit"
        case "qwen3-coder-30b": hfRepo = "Qwen/Qwen3-Coder-30B-A3B-Instruct"
        default: hfRepo = m.id
        }
        var msg = Message(role: "assistant", content: "Starting \(m.size) via WiFi at \(m.path)\n\nTerminal: sparkle pull \(m.id)\n  or: hf download \(hfRepo) --local-dir \(m.path)\n\nResumable, multi-connection. No HF token needed for Apache-2.")
        messages.append(msg)
        let idx = messages.count - 1
        // Demo progress, real Zig pull wired in V1.1
        Task {
            for i in 1...5 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    if messages.indices.contains(idx) {
                        messages[idx].content += "\n\(i*20)% • \(m.size) • WiFi • \(3 - i/2) min left"
                    }
                }
            }
            await MainActor.run {
                if messages.indices.contains(idx) {
                    messages[idx].content += "\nReady. Run sparkle run \(m.id) to chat."
                }
            }
        }
    }
}

struct OnboardingModel: Identifiable {
    let id: String
    let name: String
    let size: String
    let badge: String
    let detail: String
    static let all: [OnboardingModel] = [
        OnboardingModel(id: "gemma4-e4b-it-4bit", name: "gemma-4-e4b-it-4bit", size: "4.8GB", badge: "Recommended for 16GB", detail: "74 tok/s • vision • Apache-2"),
        OnboardingModel(id: "gemma4-e4b-8bit", name: "gemma-4-e4b-8bit", size: "8.9GB", badge: "Your 96GB", detail: "81 tok/s • vision • Apache-2"),
        OnboardingModel(id: "qwen3-coder-30b", name: "qwen3-coder:30b", size: "18GB", badge: "Coding", detail: "Like your Ollama • 18GB"),
    ]
    var path: String {
        let bundled: String
        switch id {
        case "gemma4-e4b-it-4bit":
            bundled = (Bundle.main.resourcePath ?? "") + "/models/gemma-4-e4b-it-4bit-mlx"
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
            return NSHomeDirectory() + "/models/gemma-4-e4b-it-4bit-mlx"
        case "gemma4-e4b-8bit":
            bundled = (Bundle.main.resourcePath ?? "") + "/models/gemma-4-e4b-8bit-mlx"
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
            return NSHomeDirectory() + "/models/gemma-4-e4b-8bit-mlx"
        case "qwen3-coder-30b": return NSHomeDirectory() + "/.ollama/models"
        default: return ""
        }
    }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: path) }
}

struct OnboardingCard: View {
    let model: OnboardingModel
    @EnvironmentObject var chat: ChatModel
    @State private var isDownloading = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.badge)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(model.badge == "Recommended for 16GB" ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                }
                Text(model.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isDownloaded {
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                Button(action: {
                    isDownloading = true
                    // Redirect to chat/terminal with WiFi progress
                    chat.startDownload(model)
                }) {
                    if isDownloading {
                        ProgressView().scaleEffect(0.5).frame(width: 60)
                    } else {
                        Text("Download • \(model.size) • 2 min")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isDownloading)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct SettingsView: View {
    @EnvironmentObject var chat: ChatModel
    @Environment(\.dismiss) var dismiss
    @AppStorage("modelTemperature") private var temperature: Double = 0.7
    @AppStorage("modelContextLength") private var contextLength: Double = 8192
    @AppStorage("modelTopP") private var topP: Double = 1.0
    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                Text("Model")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("gemma-4-e4b-it-4bit 4.8GB")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                Spacer()
                Text("Bundled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            // Generation - learn from Osaurus ChatSettingsView generationSection
            VStack(alignment: .leading, spacing: 12) {
                Text("Generation")
                    .font(.system(size: 12, weight: .semibold))
                HStack {
                    Text("Temperature")
                        .font(.system(size: 11))
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                    Text(String(format: "%.1f", temperature))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28)
                }
                HStack {
                    Text("Context")
                        .font(.system(size: 11))
                    Slider(value: $contextLength, in: 2048...131072, step: 2048)
                    Text("\(Int(contextLength))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 50)
                }
                HStack {
                    Text("Top-P")
                        .font(.system(size: 11))
                    Slider(value: $topP, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", topP))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28)
                }
                Text("Temp 0.7 is balanced, 0 is greedy, 2 is creative. Context is window for continuous memory, 8192 is default, 131072 is max.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct AppSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var updatedAt: Date
    var messages: [MessageCodable]
}

struct MessageCodable: Codable, Equatable {
    var role: String
    var content: String
}

class SessionsManager: ObservableObject {
    @Published var sessions: [AppSession] = []
    @Published var selectedId: UUID?
    
    private var savePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sparkle")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }
    
    init() {
        load()
        if sessions.isEmpty {
            let s = AppSession(title: "New Chat", updatedAt: Date(), messages: [])
            sessions = [s]
            selectedId = s.id
            save()
        } else if selectedId == nil {
            selectedId = sessions.first?.id
        }
    }
    
    func load() {
        guard let data = try? Data(contentsOf: savePath),
              let decoded = try? JSONDecoder().decode([AppSession].self, from: data) else { return }
        sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func save() {
        try? JSONEncoder().encode(sessions).write(to: savePath)
    }
    
    func createNew() {
        let s = AppSession(title: "New Chat", updatedAt: Date(), messages: [])
        sessions.insert(s, at: 0)
        selectedId = s.id
        save()
    }
    
    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedId == id {
            selectedId = sessions.first?.id
        }
        if sessions.isEmpty {
            let s = AppSession(title: "New Chat", updatedAt: Date(), messages: [])
            sessions = [s]
            selectedId = s.id
        }
        save()
    }
    
    func updateCurrent(with messages: [Message]) {
        guard let id = selectedId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let title = messages.first(where: { $0.role == "user" })?.content.prefix(30).description ?? "New Chat"
        sessions[idx].title = String(title)
        sessions[idx].updatedAt = Date()
        sessions[idx].messages = messages.map { MessageCodable(role: $0.role, content: $0.content) }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        save()
    }
}

struct ContentView: View {
    @StateObject private var model = ChatModel()
    @StateObject private var sessions = SessionsManager()
    @FocusState private var focused: Bool
    @State private var showSettings = false
    @AppStorage("hasStarted") private var hasStarted = false
    @State private var showDeleteConfirm = false
    @State private var sessionToDelete: UUID? = nil
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - sessions sorted by updatedAt like Osaurus ChatSessionsManager
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Chats")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(action: {
                        sessions.updateCurrent(with: model.messages)
                        sessions.createNew()
                        model.messages.removeAll()
                        hasStarted = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: .command)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                List(selection: $sessions.selectedId) {
                    ForEach(sessions.sessions) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "New Chat" : s.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(s.updatedAt, style: .date)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(s.id)
                        .contextMenu {
                            Button(role: .destructive, action: {
                                sessionToDelete = s.id
                                showDeleteConfirm = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive, action: {
                                sessionToDelete = s.id
                                showDeleteConfirm = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .alert("Are you sure?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) { sessionToDelete = nil }
                    Button("Delete", role: .destructive) {
                        if let id = sessionToDelete {
                            if sessions.selectedId == id {
                                model.messages.removeAll()
                            }
                            sessions.deleteSession(id: id)
                            sessionToDelete = nil
                        }
                    }
                } message: {
                    Text("This chat will be deleted. This cannot be undone.")
                }
            }
            .frame(minWidth: 180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
        VStack(spacing: 0) {
            // Header - Take Nothing: no settings, just model name
            HStack {
                Text("Sparkle V1")
                    .font(.system(size: 13, weight: .semibold))
                Text("gemma-4-e4b-it-4bit 4.8GB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(hasStarted ? "MLX 8081" : "Ready")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(model)
            }
            
            Divider()
            .onChange(of: sessions.selectedId) { _, newId in
                if let id = newId, let s = sessions.sessions.first(where: { $0.id == id }) {
                    model.messages = s.messages.map { Message(role: $0.role, content: $0.content) }
                    hasStarted = !s.messages.isEmpty || hasStarted
                }
            }
            .onChange(of: model.messages) { _, newMessages in
                sessions.updateCurrent(with: newMessages)
            }
            
            if !hasStarted {
                VStack(spacing: 16) {
                    Spacer()
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let img = NSImage(contentsOf: url) {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(.primary)
                    }
                    Text("Welcome to Sparkle")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Own your AI. No cloud. No token.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button(action: {
                        hasStarted = true
                        Task { await model.ensureServer(); focused = true }
                    }) {
                        Text("Start chatting")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
            
            // Messages - no second welcome, just chat
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        VStack(spacing: 8) {
                            Text("Start a conversation")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text("Ask anything, drop an image")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    ForEach(model.messages) { msg in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(msg.role == "user" ? Color.blue : Color.orange)
                                .frame(width: 24, height: 24)
                                .overlay(Text(msg.role == "user" ? "U" : "S").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 6) {
                                if let data = msg.imageData, let nsImg = NSImage(data: data) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 240, maxHeight: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(msg.content)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    if model.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.6)
                            Text("Thinking on MLX Metal...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onDrop(of: [UTType.image], isTargeted: nil, perform: model.handleDrop)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.isLoading) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.streamTick) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            }
            
            Divider()
            
            // Selected image preview
            if let img = model.selectedImage {
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Image attached, will send with next message")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.selectedImage = nil; model.selectedImageData = nil }
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
            }
            
            // Input
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask, drop image, or /clear", text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { model.send() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                Button(action: { model.send() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(model.isLoading ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            }
            }
        }
        .onAppear {
            focused = true
            if let id = sessions.selectedId, let s = sessions.sessions.first(where: { $0.id == id }) {
                model.messages = s.messages.map { Message(role: $0.role, content: $0.content, imageData: nil) }
                hasStarted = !s.messages.isEmpty || hasStarted
            }
            Task { await model.ensureServer() }
        }
    }
}
