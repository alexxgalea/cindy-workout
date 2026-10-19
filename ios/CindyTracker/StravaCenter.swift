import AuthenticationServices
import BackgroundTasks
import Network
import UIKit
import CindyCore

/// What this build was given for Strava, from the two build settings `Config/Strava.xcconfig` sets
/// (see `Config/Base.xcconfig`). A build without that file has empty values and so no Strava at all:
/// no menu row, no Help section, no tutorial bullet, and nothing uploaded.
enum StravaBuild {
    static let config: StravaConfig = {
        func read(_ key: String) -> String {
            let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
            // A build setting nobody defined is left as its own `$(NAME)`.
            return value.hasPrefix("$(") ? "" : value
        }
        #if DEBUG
        // The simulator's UI tests have no Strava.xcconfig to read, and still need to see what a build
        // that has Strava shows. Never in a release build, which would otherwise be one launch argument
        // away from believing it has credentials it does not.
        if ProcessInfo.processInfo.arguments.contains("-CindyStrava") {
            return StravaConfig(clientId: "0", clientSecret: "ui-test", applicationId: Bundle.main.bundleIdentifier ?? "com.cindy.tracker")
        }
        #endif
        return StravaConfig(clientId: read("StravaClientID"), clientSecret: read("StravaClientSecret"),
                            applicationId: Bundle.main.bundleIdentifier ?? "com.cindy.tracker")
    }()

    static var available: Bool { config.available }
}

/// A line to say to the athlete, once. Equatable by id, so saying the same words twice shows twice.
struct StravaNotice: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

/// Strava, handed to the system: the Keychain, OAuth through the Strava app or a web sheet, and the
/// uploads that Android's WorkManager runs on its own.
///
/// iOS has no such scheduler for an app that is not running, so the ledger (`StravaUploads`) is the
/// persisted queue and `StravaUploadQueue` drains it whenever the app is able to: at once after a
/// saved session (inside a background task, so the phone finishing the send is not at the mercy of
/// the screen locking), again whenever the app comes forward, when a network appears, when a backed-off
/// retry falls due, and when a background refresh runs. An upload can therefore wait until the app is
/// next opened, which Help and the README say.
@MainActor
final class StravaCenter: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = StravaCenter()

    let config = StravaBuild.config
    let tokens: StravaTokenStore
    let ledger: StravaUploads
    /// Bumped whenever the grant, the settings or the ledger change, so a screen redraws.
    @Published private(set) var revision = 0
    @Published private(set) var notice: StravaNotice?

    private let transport: HttpTransport
    private let connectFlow: StravaConnect
    private let queue: StravaUploadQueue
    private var webSession: ASWebAuthenticationSession?
    private var wake: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var started = false

    private static var taskID: String { "\(Bundle.main.bundleIdentifier ?? "com.cindy.tracker").strava-upload" }

    override init() {
        let keychain = StravaKeychainStorage()
        // The Keychain outlives the app on iOS and the records do not, so a fresh install would
        // otherwise find a connection and a ledger that belong to attempts that are gone.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "strava.installed") {
            for key in keychain.keys() { keychain.set(nil, forKey: key) }
            defaults.set(true, forKey: "strava.installed")
        }
        // The storage tells the center when it is written to, from wherever the upload is running.
        let box = ChangeBox()
        let storage = ObservedStravaStorage(keychain, changed: { box.fire() })
        let tokens = StravaTokenStore(storage: storage)
        let ledger = StravaUploads(storage: storage)
        let config = StravaBuild.config
        let transport = URLSessionTransport()
        self.transport = transport
        self.tokens = tokens
        self.ledger = ledger
        connectFlow = StravaConnect(tokens: tokens, config: config)
        let run = StravaUploadRun(
            config: config, transport: transport, tokens: tokens, ledger: ledger,
            attempt: { at in RecordStore().all().first { $0.atMillis == at } },
            trace: { HeartRateStore().load(atMillis: $0) },
            body: { Profile().body(nowYear: Calendar.current.component(.year, from: Date())) },
            utcOffsetSeconds: { Zone(TimeZone.current.identifier).offsetSeconds(atEpochMs: $0) })
        queue = StravaUploadQueue(ledger: ledger, run: { try await run.run(atMillis: $0) })
        super.init()
        box.onChange = { [weak self] in Task { @MainActor in self?.revision += 1 } }
    }

    /// Called as the app launches. Nothing happens in a build without Strava credentials.
    func start() {
        guard config.available, !started else { return }
        started = true

        // Registering has to happen before the app finishes launching.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in self?.refresh(task) }
        }
        let notifications = NotificationCenter.default
        notifications.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.drain(force: true) }
        }
        notifications.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        // A network appearing is the other thing WorkManager waited for. The monitor reports the
        // current path as soon as it starts, which is the drain at launch.
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.drain(force: true) }
        }
        monitor.start(queue: DispatchQueue(label: "strava.network"))
    }

    // MARK: - what the screens ask

    var menuStatus: StravaStatus? { StravaMenu.status(config: config, tokens: tokens) }

    /// A session was just saved: upload it by itself if the athlete is connected and wants that.
    func attemptSaved(atMillis: Int64) {
        if ledger.attemptSaved(atMillis: atMillis, config: config, tokens: tokens) { sendNow() }
    }

    /// The results row's UPLOAD, or its retry.
    func upload(atMillis: Int64) {
        ledger.queue(atMillis: atMillis)
        sendNow()
    }

    func openActivity(_ id: Int64) {
        if let url = URL(string: StravaApi.activityUrl(id)) { UIApplication.shared.open(url) }
    }

    /// Forgets the grant on the phone at once, then asks Strava to end it.
    func disconnect() {
        let auth = StravaAuth(transport: transport, config: config)
        let tokens = self.tokens
        Task { @MainActor in
            await StravaDisconnect.run(tokens: tokens, auth: auth)
            self.revision += 1
        }
    }

    /// Clears what the app remembers of its uploads, when the record board is cleared.
    func forgetUploads() {
        ledger.clear()
        revision += 1
    }

    // MARK: - sending

    /// Drains inside a background task, so that a send begun as the athlete locks the phone still
    /// finishes. The system gives roughly thirty seconds; what is not done stays pending.
    private func sendNow() {
        let time = BackgroundTime()
        let work = Task { @MainActor in
            await self.drain(force: true)
            time.end()
        }
        time.id = UIApplication.shared.beginBackgroundTask(withName: "strava-upload") {
            // Out of time: what is not sent stays pending for the next drain.
            work.cancel()
            MainActor.assumeIsolated { time.end() }
        }
    }

    func drain(force: Bool) async {
        guard config.available else { return }
        let drained = await queue.drain(force: force)
        revision += 1
        arm(drained.nextDueMs)
        scheduleRefresh()
    }

    /// Wakes the queue when a backed-off retry falls due, while the app is running.
    private func arm(_ dueMs: Int64?) {
        wake?.cancel()
        guard let dueMs = dueMs else { return }
        let wait = max(dueMs - Int64(Date().timeIntervalSince1970 * 1000), 0)
        wake = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            if !Task.isCancelled { await self.drain(force: false) }
        }
    }

    /// Asks iOS to run the app briefly later, if anything is still waiting to be sent.
    private func scheduleRefresh() {
        guard !queue.pending().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func refresh(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            await self.drain(force: true)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: - connecting

    /// Opens Strava's own consent page, once the athlete has tapped Strava's own button: in the
    /// Strava app when it is installed, in a web sheet otherwise.
    func connect(_ origin: StravaOrigin) {
        let web = connectFlow.begin(origin)
        let appURL = Self.stravaAppURL(for: web)
        if let appURL = appURL, let probe = URL(string: "strava://"), UIApplication.shared.canOpenURL(probe) {
            UIApplication.shared.open(appURL) { [weak self] opened in
                if !opened { Task { @MainActor in self?.openWeb(web) } }
            }
        } else {
            openWeb(web)
        }
    }

    /// Strava's app takes the same query on its own scheme.
    private static func stravaAppURL(for web: String) -> URL? {
        let prefix = "\(StravaConfig.oauthBase)/mobile/authorize"
        guard web.hasPrefix(prefix) else { return nil }
        return URL(string: "strava://oauth/mobile/authorize" + web.dropFirst(prefix.count))
    }

    private func openWeb(_ web: String) {
        guard let url = URL(string: web) else { return couldNotOpen() }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.applicationId) { [weak self] callback, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.webSession = nil
                if let callback = callback {
                    await self.handleRedirect(callback.absoluteString)
                } else {
                    // The sheet was closed without an answer.
                    self.connectFlow.cancel()
                }
            }
        }
        session.presentationContextProvider = self
        webSession = session
        if !session.start() { couldNotOpen() }
    }

    private func couldNotOpen() {
        connectFlow.cancel()
        say("Connecting needs the Strava app or a web browser")
    }

    /// The athlete came back from Strava, by the Strava app's redirect or the web sheet's.
    func handleRedirect(_ url: String) async {
        let handler = StravaRedirectHandler(config: config, transport: transport, tokens: tokens, ledger: ledger)
        switch await handler.handle(url) {
        case .ignored:
            break
        case .finished(let message, let connected):
            say(message)
            revision += 1
            if connected { await drain(force: true) }
        }
    }

    private func say(_ text: String) { notice = StravaNotice(text: text) }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

/// The system's grant of a little more time for a send begun as the screen locks.
@MainActor
private final class BackgroundTime {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Lets the storage the center is built from tell the center, which does not exist yet while it is built.
private final class ChangeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    var onChange: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }

    func fire() { onChange?() }
}
