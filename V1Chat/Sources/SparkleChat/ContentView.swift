import SwiftUI
import UniformTypeIdentifiers

struct Message: Identifiable {
    let id = UUID()
    let role: String // user or assistant
    var content: String
    var imageData: Data?
}

@MainActor
class ChatModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var selectedImage: NSImage?
    @Published var selectedImageData: Data?
    @Published var streamTick = 0
    
    // Opinionated: smallest model, one port, no knobs - streaming
    let endpoint = "http://127.0.0.1:8081/v1/chat/completions"
    let model = "/Users/user/models/gemma-4-e4b-it-4bit-mlx"
    
    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImageData != nil else { return }
        guard !isLoading else { return }
        
        let userContent: String = trimmed
        let imageData = selectedImageData
        
        let userMsg = Message(role: "user", content: trimmed.isEmpty ? "[image]" : trimmed, imageData: imageData)
        messages.append(userMsg)
        input = ""
        selectedImage = nil
        selectedImageData = nil
        isLoading = true
        
        // Create empty assistant message that will be streamed into
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
        var messagesPayload: [[String: Any]] = []
        if let data = imageData {
            let b64 = data.base64EncodedString()
            let mime = "image/jpeg"
            let contentArray: [[String: Any]] = [
                ["type": "text", "text": prompt.isEmpty ? "Describe this image" : prompt],
                ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(b64)"]]
            ]
            messagesPayload.append(["role": "user", "content": contentArray])
        } else {
            messagesPayload.append(["role": "user", "content": prompt])
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": messagesPayload,
            "max_tokens": 512,
            "temperature": 0.7,
            "stream": true
        ]
        
        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = data
        req.timeoutInterval = 120
        
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "MLX", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))"])
        }
        
        var full = ""
        for try await line in bytes.lines {
            // Each line is like: data: {"choices":[{"delta":{"content":" Hello"}}]}
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first else { continue }
            // delta.content for stream, or message.content as fallback
            var deltaText: String?
            if let delta = first["delta"] as? [String: Any] {
                deltaText = delta["content"] as? String
            } else if let msg = first["message"] as? [String: Any] {
                deltaText = msg["content"] as? String
            }
            if let t = deltaText, !t.isEmpty {
                full += t
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].content = full
                    streamTick += 1
                }
            }
        }
        // Ensure final content set
        if full.isEmpty, messages.indices.contains(assistantIndex), messages[assistantIndex].content.isEmpty {
            messages[assistantIndex].content = "(no content)"
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
}

struct ContentView: View {
    @StateObject private var model = ChatModel()
    @FocusState private var focused: Bool
    
    var body: some View {
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
                Text("MLX 8081")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("Smallest model audit ready")
                                .font(.system(size: 13, weight: .medium))
                            Text("Type, drop an image, press Return. No knobs.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Test image loading by dropping a JPG/PNG here")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
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
                TextField("Ask or drop image, press Return", text: $model.input, axis: .vertical)
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
        .onAppear { focused = true }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { model.messages.removeAll() }
                    .font(.system(size: 11))
            }
        }
    }
}
