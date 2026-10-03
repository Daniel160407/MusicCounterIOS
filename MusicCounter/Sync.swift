import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Syncs with the browser extension (and any other device) through Firestore, using the
/// same layout as the extension's sync.js:
///
///     users/{uid}                              historyRetention, settingsUpdatedAt, favoritesUpdatedAt
///     users/{uid}/favorites/{key}              key, id, title, artist, source, addedAt
///     users/{uid}/devices/{deviceID}           platform, name, updatedAt, total, firstSeen, sources, parts
///     users/{uid}/devices/{deviceID}/parts/{n} json   (tracks, artists, days-YYYY, history-YYYY-MM-N)
///
/// Each device writes only its own document; `parts` maps part names to content hashes so
/// only changed parts are uploaded or fetched. Favorites and the retention setting are shared.
@MainActor
final class Sync: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var error: String?
    @Published private(set) var otherDevices: [String] = []

    /// False until GoogleService-Info.plist is added to the app.
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    private let store: Store
    private var db: Firestore { Firestore.firestore() }
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var listeners: [ListenerRegistration] = []
    private var pushTask: Task<Void, Never>?

    /// Other devices' metadata and the parts fetched for them so far.
    private var deviceMeta: [String: (name: String, platform: String, total: Double, sources: [String: Double])] = [:]
    private var fetched: [String: [String: (hash: String, json: String)]] = [:]
    /// The newest hash seen for each part, so a slow fetch can't overwrite a newer one.
    private var expected: [String: [String: String]] = [:]
    private var lastRemoteRetention: String?

    let deviceID: String = {
        let key = "syncDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    init(store: Store) {
        self.store = store
    }

    func start() {
        guard Self.isConfigured, authHandle == nil else { return }
        store.onChange = { [weak self] in self?.schedulePush() }
        store.onFavoriteChange = { [weak self] key, fav in self?.writeFavorite(key: key, favorite: fav) }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.userChanged(user) }
        }
    }

    // MARK: - Sign-in

    func signIn() async {
        guard let clientID = FirebaseApp.app()?.options.clientID, let presenter = Self.topViewController() else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { return }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
            error = nil
        } catch let err as NSError where err.domain == kGIDSignInErrorDomain && err.code == GIDSignInError.canceled.rawValue {
            // Closed the account picker; nothing to report.
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private func userChanged(_ user: User?) {
        listeners.forEach { $0.remove() }
        listeners = []
        deviceMeta = [:]
        fetched = [:]
        expected = [:]
        lastRemoteRetention = nil
        store.setRemote([:])
        otherDevices = []
        email = user?.email
        guard let user else { return }

        mergeLocalFavorites(uid: user.uid)
        listen(uid: user.uid)
        push(force: true)
    }

    // MARK: - Listening

    private func listen(uid: String) {
        let user = db.collection("users").document(uid)

        listeners.append(user.addSnapshotListener { [weak self] snapshot, _ in
            let data = snapshot?.data() ?? [:]
            Task { @MainActor in self?.applySettings(data) }
        })

        listeners.append(user.collection("favorites").addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            var favorites: [String: Favorite] = [:]
            for doc in snapshot.documents {
                let d = doc.data()
                guard let key = d["key"] as? String else { continue }
                favorites[key] = Favorite(
                    id: d["id"] as? String ?? "",
                    title: d["title"] as? String ?? "",
                    artist: d["artist"] as? String ?? "",
                    addedAt: Date(timeIntervalSince1970: ((d["addedAt"] as? NSNumber)?.doubleValue ?? 0) / 1000),
                    source: d["source"] as? String)
            }
            Task { @MainActor in self?.store.replaceFavorites(favorites) }
        })

        listeners.append(user.collection("devices").addSnapshotListener { [weak self] snapshot, err in
            guard let snapshot else {
                let message = err?.localizedDescription
                Task { @MainActor in self?.error = message }
                return
            }
            let docs = snapshot.documents.map { ($0.documentID, $0.data()) }
            Task { @MainActor in await self?.devicesChanged(uid: uid, docs) }
        })
    }

    /// One-off fetch of the other devices, for a background refresh, where the live
    /// listeners may not deliver before iOS suspends the app again.
    func refresh() async {
        guard Self.isConfigured, let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await db.collection("users").document(uid).collection("devices").getDocuments()
            await devicesChanged(uid: uid, snapshot.documents.map { ($0.documentID, $0.data()) })
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applySettings(_ data: [String: Any]) {
        guard let value = data["historyRetention"] as? String, let retention = Retention(shared: value) else { return }
        lastRemoteRetention = value
        if UserDefaults.standard.string(forKey: Retention.storageKey) != retention.rawValue {
            // ContentView's @AppStorage sees this and prunes the history.
            UserDefaults.standard.set(retention.rawValue, forKey: Retention.storageKey)
        }
    }

    private func devicesChanged(uid: String, _ docs: [(String, [String: Any])]) async {
        var wanted: [(device: String, name: String, hash: String)] = []
        var meta: [String: (name: String, platform: String, total: Double, sources: [String: Double])] = [:]

        for (id, data) in docs where id != deviceID {
            meta[id] = (data["name"] as? String ?? "",
                        data["platform"] as? String ?? "",
                        (data["total"] as? NSNumber)?.doubleValue ?? 0,
                        (data["sources"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue })
            let parts = data["parts"] as? [String: String] ?? [:]
            expected[id] = parts
            var kept: [String: (hash: String, json: String)] = [:]
            for (name, hash) in parts {
                if let have = fetched[id]?[name], have.hash == hash {
                    kept[name] = have
                } else {
                    wanted.append((id, name, hash))
                }
            }
            fetched[id] = kept
        }
        for id in fetched.keys where meta[id] == nil {
            fetched[id] = nil
            expected[id] = nil
        }
        deviceMeta = meta

        let devices = db.collection("users").document(uid).collection("devices")
        for w in wanted {
            do {
                let snapshot = try await devices.document(w.device).collection("parts").document(w.name).getDocument()
                guard let json = snapshot.data()?["json"] as? String, expected[w.device]?[w.name] == w.hash else { continue }
                fetched[w.device, default: [:]][w.name] = (w.hash, json)
            } catch {
                self.error = error.localizedDescription
            }
        }

        rebuildRemote()
        lastSync = Date()
    }

    private func rebuildRemote() {
        let decoder = JSONDecoder()
        var devices: [String: RemoteDevice] = [:]
        for (id, m) in deviceMeta {
            var device = RemoteDevice(name: m.name, platform: m.platform, total: m.total, sources: m.sources)
            for (name, part) in fetched[id] ?? [:] {
                let data = Data(part.json.utf8)
                if name == "tracks" {
                    device.tracks = (try? decoder.decode([String: Shared.Track].self, from: data)) ?? [:]
                } else if name.hasPrefix("days-"), let days = try? decoder.decode([String: Shared.Day].self, from: data) {
                    device.days.merge(days) { $1 }
                } else if name.hasPrefix("history-"), let plays = try? decoder.decode([Shared.Play].self, from: data) {
                    device.history += plays
                }
            }
            devices[id] = device
        }
        store.setRemote(devices)
        otherDevices = devices.values.map(\.name).sorted()
    }

    // MARK: - Writing

    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Uploads at most once a minute while music plays.
    private func schedulePush() {
        guard Auth.auth().currentUser != nil, pushTask == nil else { return }
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            self?.pushTask = nil
            self?.push()
        }
    }

    /// Uploads the parts of this phone's stats that changed since the last upload.
    func push(force: Bool = false) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let parts = SyncParts.build(store.stats)
        let hashKey = "syncPartHashes.\(uid)"
        let previous = UserDefaults.standard.dictionary(forKey: hashKey) as? [String: String] ?? [:]
        let hashes = parts.mapValues(SyncParts.hash)
        let changed = hashes.filter { previous[$0.key] != $0.value }.map(\.key)
        let removed = previous.keys.filter { hashes[$0] == nil }
        guard force || !changed.isEmpty || !removed.isEmpty else { return }

        let device = db.collection("users").document(uid).collection("devices").document(deviceID)
        let batch = db.batch()
        for name in changed {
            batch.setData(["json": parts[name] ?? ""], forDocument: device.collection("parts").document(name))
        }
        for name in removed {
            batch.deleteDocument(device.collection("parts").document(name))
        }
        let total = store.localSeconds
        let firstSeen: Any = store.stats.daily.keys.min()
            .flatMap { Self.dayParser.date(from: $0) }
            .map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? NSNull()
        batch.setData([
            "schema": 1,
            "platform": "ios",
            "name": UIDevice.current.name,
            "updatedAt": Self.now,
            "total": total,
            "firstSeen": firstSeen,
            "sources": ["ios": total],
            "parts": hashes,
        ], forDocument: device)

        // Recorded now rather than on success: Firestore keeps the batch and retries it
        // until it reaches the server, even across launches.
        UserDefaults.standard.set(hashes, forKey: hashKey)
        batch.commit { [weak self] err in
            Task { @MainActor in
                if let err {
                    UserDefaults.standard.removeObject(forKey: hashKey)
                    self?.error = err.localizedDescription
                } else {
                    self?.error = nil
                    self?.lastSync = Date()
                }
            }
        }
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func favoriteData(key: String, _ fav: Favorite) -> [String: Any] {
        [
            "key": key,
            "id": fav.source == nil ? fav.id : WebLink.rawID(key),
            "title": fav.title,
            "artist": fav.artist,
            "source": fav.source ?? "ios",
            "addedAt": (fav.addedAt.timeIntervalSince1970 * 1000).rounded(),
        ]
    }

    private func favoriteRef(uid: String, key: String) -> DocumentReference {
        // A key can hold a title, and a slash would read as a path separator.
        db.collection("users").document(uid).collection("favorites")
            .document(key.replacingOccurrences(of: "/", with: "_"))
    }

    private func writeFavorite(key: String, favorite: Favorite?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let batch = db.batch()
        let ref = favoriteRef(uid: uid, key: key)
        if let favorite {
            batch.setData(favoriteData(key: key, favorite), forDocument: ref)
        } else {
            batch.deleteDocument(ref)
        }
        batch.setData(["favoritesUpdatedAt": Self.now], forDocument: db.collection("users").document(uid), merge: true)
        batch.commit { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.error = err.localizedDescription }
        }
    }

    /// Stars made before signing in join the shared list rather than being replaced by it.
    private func mergeLocalFavorites(uid: String) {
        let local = store.stats.favorites
        guard !local.isEmpty else { return }
        let batch = db.batch()
        for (id, fav) in local {
            let key = Store.sharedKey(id)
            batch.setData(favoriteData(key: key, fav), forDocument: favoriteRef(uid: uid, key: key))
        }
        batch.setData(["favoritesUpdatedAt": Self.now], forDocument: db.collection("users").document(uid), merge: true)
        batch.commit()
    }

    /// Shares a retention change made on this phone.
    func retentionChanged() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let value = Store.currentRetention.shared
        guard value != lastRemoteRetention else { return }
        lastRemoteRetention = value
        db.collection("users").document(uid).setData(
            ["historyRetention": value, "settingsUpdatedAt": Self.now], merge: true)
    }
}
