// Tomodachi Launcher：scripts/build_tomodachi.sh 的圖形介面；選好 .nsp（和 prod.keys），按「Recompilar」，逐步看進度和日誌
// Tomodachi Launcher: a GUI for scripts/build_tomodachi.sh; pick the .nsp (and prod.keys), press Recompilar and follow each step with its log
import SwiftUI
import AppKit
import UniformTypeIdentifiers

let gameID = "010051F0207B2000"
let gameAppPath = "/Applications/Tomodachi Life.app"
let workspace = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(gameID)-work")
let launcherLog = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/nxnative/launcher.log")

enum StepState { case pending, running, done, failed }

struct Step: Identifiable {
    let id: Int
    let title: String
    let detail: String
    var state: StepState = .pending
}

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// 收集子程序的輸出位元組並切成行
/// Collects the child process output bytes and splits them into lines
final class LineSplitter {
    private var buffer = Data()
    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let chunk = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            lines.append(String(decoding: chunk, as: UTF8.self).replacingOccurrences(of: "\r", with: ""))
        }
        return lines
    }
    func flush() -> [String] {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
    }
}

@MainActor
final class Builder: ObservableObject {
    @Published var root: URL?
    @Published var nsp: URL? { didSet { UserDefaults.standard.set(nsp?.path, forKey: "nsp") } }
    @Published var keys: URL? { didSet { UserDefaults.standard.set(keys?.path, forKey: "keys") } }
    @Published var cleanBuild = false
    @Published var freeSpaceAfter = false
    @Published var dropTargeted = false
    @Published var showLog = false
    @Published var steps = Builder.initialSteps()
    @Published var log: [LogLine] = []
    @Published var lastLine = ""
    @Published var running = false
    @Published var result: Bool? = nil
    @Published var message = ""
    @Published var startDate: Date?
    @Published var endDate: Date?
    @Published var metalOK = true

    private var process: Process?
    private var cancelled = false
    private var lineCounter = 0
    private var logFile: FileHandle?

    static func initialSteps() -> [Step] {
        [
            Step(id: 1, title: "Extraer el NSP", detail: "Descifra el juego y saca su código y sus datos"),
            Step(id: 2, title: "Reescribir el código", detail: "Parchea los módulos para que corran nativos en el Mac"),
            Step(id: 3, title: "Traducir los shaders", detail: "La parte larga: la primera vez tarda bastante"),
            Step(id: 4, title: "Compilar el motor", detail: "Host nativo y fuente del juego"),
            Step(id: 5, title: "Crear la app", detail: "Instala Tomodachi Life en Aplicaciones"),
        ]
    }

    init() {
        root = Builder.findRoot()
        let d = UserDefaults.standard
        if let p = d.string(forKey: "nsp"), FileManager.default.fileExists(atPath: p) { nsp = URL(fileURLWithPath: p) }
        if let p = d.string(forKey: "keys"), FileManager.default.fileExists(atPath: p) {
            keys = URL(fileURLWithPath: p)
        } else if let r = root {
            // prod.keys 放在倉庫裡或上一層目錄
            // prod.keys next to the repo or one folder up
            for k in [r.appendingPathComponent("prod.keys"), r.deletingLastPathComponent().appendingPathComponent("prod.keys")]
            where FileManager.default.fileExists(atPath: k.path) { keys = k; break }
        }
        checkMetal()
    }

    /// 與 build_tomodachi.sh 同樣的檢查：沒有 Metal 編譯器（Xcode）就編不了著色器
    /// The same check as build_tomodachi.sh: without the Metal compiler (Xcode) there are no shaders
    func checkMetal() {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["-sdk", "macosx", "metal", "--version"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            var ok = false
            if (try? p.run()) != nil { p.waitUntilExit(); ok = p.terminationStatus == 0 }
            DispatchQueue.main.async { self.metalOK = ok }
        }
    }

    func openXcodeInAppStore() {
        NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
    }

    /// 目錄裡的構建腳本：倉庫的 scripts/ 或單獨放的一份
    /// The build script inside a folder: the repo's scripts/ or a standalone copy
    static func script(in root: URL) -> URL? {
        for rel in ["scripts/build_tomodachi.sh", "build_tomodachi.sh"] {
            let u = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// tomodachi-native 倉庫目錄（有 scripts/build_tomodachi.sh 的那個）
    /// The tomodachi-native repo folder (the one with scripts/build_tomodachi.sh)
    static func findRoot() -> URL? {
        var candidates: [String] = []
        if let p = UserDefaults.standard.string(forKey: "root") { candidates.append(p) }
        if let p = Bundle.main.object(forInfoDictionaryKey: "TomogachiRoot") as? String { candidates.append(p) }
        candidates.append(NSHomeDirectory() + "/Documents/Tomogachi/tomodachi-native")
        for c in candidates where script(in: URL(fileURLWithPath: c)) != nil {
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    var hasExtraction: Bool {
        FileManager.default.fileExists(atPath: workspace.appendingPathComponent("data/v0/RomFS").path)
    }
    var gameAppExists: Bool { FileManager.default.fileExists(atPath: gameAppPath) }
    var canStart: Bool { !running && metalOK && root != nil && nsp != nil && keys != nil }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Elige la carpeta del repo tomodachi-native"
        if panel.runModal() == .OK, let url = panel.url {
            if Builder.script(in: url) != nil {
                root = url
                UserDefaults.standard.set(url.path, forKey: "root")
            } else {
                message = "Esa carpeta no tiene scripts/build_tomodachi.sh."
            }
        }
    }

    func pickNSP() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nsp") ?? .data]
        panel.message = "Elige el .nsp del juego base (v0), no el de la actualización"
        if let r = root { panel.directoryURL = r }
        if panel.runModal() == .OK { nsp = panel.url }
    }

    func pickKeys() {
        let panel = NSOpenPanel()
        panel.message = "Elige tu archivo prod.keys"
        if let r = root { panel.directoryURL = r }
        if panel.runModal() == .OK { keys = panel.url }
    }

    private func append(_ lines: [String]) {
        for l in lines {
            if let fh = logFile, let data = (l + "\n").data(using: .utf8) { fh.write(data) }
            if let n = Builder.stepNumber(l) {
                for i in steps.indices {
                    if steps[i].id < n { steps[i].state = .done }
                    if steps[i].id == n { steps[i].state = .running }
                }
                lastLine = ""
            } else if !l.trimmingCharacters(in: .whitespaces).isEmpty {
                lastLine = l
            }
            lineCounter += 1
            log.append(LogLine(id: lineCounter, text: l))
        }
        if log.count > 4000 { log.removeFirst(log.count - 4000) }
    }

    /// 「== 3. Shaders ...」這類行標出當前步驟
    /// Lines like "== 3. Shaders ..." mark the current step
    static func stepNumber(_ line: String) -> Int? {
        guard line.hasPrefix("== "), line.count > 4 else { return nil }
        let c = line[line.index(line.startIndex, offsetBy: 3)]
        guard let n = c.wholeNumberValue, (1...5).contains(n) else { return nil }
        return n
    }

    func start() {
        guard canStart, let root, let nsp, let keys, let script = Builder.script(in: root) else { return }
        steps = Builder.initialSteps()
        log = []
        lineCounter = 0
        lastLine = ""
        message = ""
        result = nil
        cancelled = false
        startDate = Date()
        endDate = nil
        running = true

        try? FileManager.default.createDirectory(at: launcherLog.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcherLog.path, contents: nil)
        logFile = try? FileHandle(forWritingTo: launcherLog)

        // $1 = 清理、$2 = 腳本、$3 = nsp、$4 = keys（作為參數傳入，不把路徑拼進命令）
        // $1 = clean, $2 = script, $3 = nsp, $4 = keys (passed as arguments, paths never spliced into the command)
        let wrapper = """
        W="$HOME/\(gameID)-work"
        if [ "$1" = 1 ]; then
          echo "Limpiando la extracción anterior..."
          rm -rf "$W/data" "$W/build/patched_v0"
        fi
        exec /bin/zsh "$2" "$3" "$4"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", wrapper, "zsh", cleanBuild ? "1" : "0",
                       script.path, nsp.path, keys.path]
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let splitter = LineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            let lines = splitter.feed(data)
            if lines.isEmpty { return }
            DispatchQueue.main.async { self?.append(lines) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            // 等管道裡剩下的輸出讀完
            // Give the last output left in the pipe time to arrive
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                var tail = splitter.feed(rest)
                tail += splitter.flush()
                self?.append(tail)
                self?.finish(status: status)
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            running = false
            result = false
            message = "No se pudo iniciar: \(error.localizedDescription)"
        }
    }

    private func finish(status: Int32) {
        process = nil
        endDate = Date()
        if status == 0 && !cancelled {
            for i in steps.indices { steps[i].state = .done }
            result = true
            message = "Listo. Tomodachi Life está en Aplicaciones."
            if freeSpaceAfter { freeWorkspace() } else { running = false; closeLog() }
            return
        }
        for i in steps.indices where steps[i].state == .running { steps[i].state = .failed }
        result = false
        if cancelled {
            message = "Cancelado."
        } else if log.contains(where: { $0.text.contains("翻譯鏈工具與鎖文件不符") }) {
            message = "Cambió la versión de Xcode/Metal y no coincide con el lock de shaders (dmsh_chain.lock)."
        } else if let hint = log.reversed().first(where: { $0.text.hasPrefix("Falta") || $0.text.hasPrefix("【紅】") })?.text {
            message = hint
        } else {
            message = "Falló (código \(status)). Abre el registro para ver el error."
        }
        running = false
        closeLog()
    }

    private func freeWorkspace() {
        append(["Borrando la carpeta de trabajo para liberar espacio..."])
        DispatchQueue.global(qos: .utility).async {
            let err = (try? FileManager.default.removeItem(at: workspace)) == nil
            DispatchQueue.main.async {
                self.append([err ? "No se pudo borrar toda la carpeta de trabajo." : "Carpeta de trabajo borrada."])
                self.message += err ? " (no se pudo borrar la carpeta de trabajo)" : " Carpeta de trabajo borrada."
                self.running = false
                self.closeLog()
            }
        }
    }

    private func closeLog() {
        try? logFile?.close()
        logFile = nil
    }

    func cancel() {
        guard let p = process, p.isRunning else { return }
        cancelled = true
        // build_tomodachi.sh 會起 python、dotnet 和 make：要結束整棵程序樹
        // build_tomodachi.sh starts python, dotnet and make: the whole process tree has to go
        let pids = Builder.descendants(of: p.processIdentifier) + [p.processIdentifier]
        for pid in pids { kill(pid, SIGTERM) }
    }

    nonisolated static func descendants(of pid: pid_t) -> [pid_t] {
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-P", "\(pid)"]
        let out = Pipe()
        pg.standardOutput = out
        pg.standardError = Pipe()
        guard (try? pg.run()) != nil else { return [] }
        pg.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let kids = text.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        return kids.flatMap { descendants(of: $0) + [$0] }
    }

    func openGame() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: gameAppPath),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([launcherLog])
    }
}

// MARK: - 視圖 | Views

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}

struct StepRow: View {
    let step: Step
    let liveLine: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch step.state {
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.title3)
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.id). \(step.title)")
                    .fontWeight(step.state == .running ? .semibold : .regular)
                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
                Text(step.state == .running && !liveLine.isEmpty ? liveLine : step.detail)
                    .font(step.state == .running && !liveLine.isEmpty ? .caption.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ContentView: View {
    @StateObject private var b = Builder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if b.root == nil { missingRoot }
                if !b.metalOK { missingMetal }
                filesCard
                progressCard
                actionBar
                logSection
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if b.gameAppExists {
                Image(nsImage: NSWorkspace.shared.icon(forFile: gameAppPath))
                    .resizable().frame(width: 56, height: 56)
            } else {
                Image(systemName: "gamecontroller.fill").font(.system(size: 36)).frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tomodachi Life").font(.title.bold())
                Text("Recompilación nativa para Mac").foregroundStyle(.secondary)
            }
        }
    }

    private var missingRoot: some View {
        Card(title: "No encuentro el proyecto") {
            Text("Elige la carpeta del repo tomodachi-native (la que tiene scripts/build_tomodachi.sh).").foregroundStyle(.secondary)
            Button("Elegir carpeta…") { b.pickRoot() }
        }
    }

    private var missingMetal: some View {
        Card(title: "Falta Xcode") {
            Label("Para traducir los shaders hace falta el compilador de Metal, que viene con Xcode. Instálalo, ábrelo una vez y vuelve a comprobar.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Si ya está instalado, ejecuta en Terminal:  sudo xcode-select -s /Applications/Xcode.app")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Abrir Xcode en el App Store") { b.openXcodeInAppStore() }
                Button("Volver a comprobar") { b.checkMetal() }
            }
        }
    }

    private var filesCard: some View {
        Card(title: "Archivos") {
            // 拖放 .nsp 的區域
            // Drop zone for the .nsp
            HStack(spacing: 12) {
                Image(systemName: b.nsp == nil ? "square.and.arrow.down" : "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(b.nsp == nil ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.nsp?.lastPathComponent ?? "Arrastra aquí el .nsp del juego base")
                        .lineLimit(1).truncationMode(.middle)
                    Text(b.nsp == nil ? "Tiene que ser el juego base (v0), no la actualización" : "Juego base (v0)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Elegir…") { b.pickNSP() }.disabled(b.running)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(b.dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $b.dropTargeted) { providers in
                guard !b.running, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "nsp" else { return }
                    DispatchQueue.main.async { b.nsp = url }
                }
                return true
            }

            HStack(spacing: 12) {
                Image(systemName: "key.fill").font(.title3).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.keys?.lastPathComponent ?? "Falta prod.keys").foregroundStyle(b.keys == nil ? .red : .primary)
                    Text(b.keys?.deletingLastPathComponent().path ?? "Necesario para descifrar el juego")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer()
                Button("Cambiar…") { b.pickKeys() }.disabled(b.running)
            }

            Divider()
            Toggle(isOn: $b.cleanBuild) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compilación limpia")
                    Text(b.hasExtraction
                         ? "Ya hay una extracción previa y se reutilizará. Actívalo si cambiaste de .nsp."
                         : "Vuelve a extraer el .nsp desde cero.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(b.running)
            Toggle(isOn: $b.freeSpaceAfter) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Borrar la carpeta de trabajo al terminar")
                    Text("Libera espacio. La app y tus partidas no se tocan, pero la próxima compilación empieza de cero.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(b.running)
        }
    }

    private var progressCard: some View {
        Card(title: "Progreso") {
            ForEach(b.steps) { s in StepRow(step: s, liveLine: b.lastLine) }
            if let start = b.startDate {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let secs = Int((b.endDate ?? ctx.date).timeIntervalSince(start))
                    Text("Tiempo: \(secs / 60) min \(secs % 60) s")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if b.running {
                Button(role: .destructive) { b.cancel() } label: {
                    Label("Cancelar", systemImage: "stop.fill").frame(minWidth: 140)
                }
                .controlSize(.large)
            } else {
                Button { b.start() } label: {
                    Label("Recompilar", systemImage: "hammer.fill").frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!b.canStart)
                if b.gameAppExists {
                    Button { b.openGame() } label: {
                        Label("Jugar", systemImage: "play.fill").frame(minWidth: 100)
                    }
                    .controlSize(.large)
                }
            }
            if !b.message.isEmpty {
                Label(b.message, systemImage: b.result == false ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(b.result == false ? .red : .green)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var logSection: some View {
        DisclosureGroup(isExpanded: $b.showLog) {
            VStack(alignment: .trailing, spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(b.log) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 240)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .onChange(of: b.log.last?.id) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                Button("Mostrar launcher.log en Finder") { b.revealLog() }
                    .buttonStyle(.link).font(.caption)
            }
        } label: {
            Text("Registro").font(.headline)
        }
    }
}

@main
struct TomodachiLauncherApp: App {
    var body: some Scene {
        WindowGroup("Tomodachi Launcher") { ContentView() }
            .defaultSize(width: 660, height: 760)
    }
}
