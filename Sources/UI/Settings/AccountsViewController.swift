import UIKit

final class AccountsViewController: SettingsTableController {
    private var traktPoll: TraktAccount.PollHandle?
    private var traktCode: TraktAccount.DeviceCode?
    private var busy: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Accounts"
        navigationItem.largeTitleDisplayMode = .never
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .accountsChanged, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { traktPoll?.cancel() }
    }

    @objc private func changed() { rebuild() }

    override func buildSections() -> [Section] {
        var out: [Section] = []
        if let b = busy { out.append(Section(title: nil, footer: nil, rows: [.info(b, nil)])) }
        out.append(stremioSection())
        out.append(traktSection())
        out.append(nuvioSection())
        return out
    }

    private func setBusy(_ text: String?) {
        busy = text
        rebuild()
    }

    private func report(_ title: String, _ result: Result<Int, Error>, noun: String) {
        setBusy(nil)
        switch result {
        case .success(let n): showAlert(title, n == 0 ? "Everything was already up to date." : "Imported \(n) \(noun).")
        case .failure(let e): showAlert("Import failed", e.localizedDescription)
        }
    }

    // MARK: Stremio

    private func stremioSection() -> Section {
        let a = StremioAccount.shared
        guard a.isSignedIn else {
            return Section(title: "Stremio", footer: "Import your Stremio addons, library and watch progress.", rows: [
                .action("Sign In to Stremio", destructive: false) { [weak self] _ in self?.stremioSignIn() },
            ])
        }
        return Section(title: "Stremio", footer: nil, rows: [
            .info("Signed in", a.email),
            .action("Import Addons", destructive: false) { [weak self] _ in
                self?.setBusy("Importing Stremio addons…")
                a.importAddons { self?.report("Stremio", $0, noun: "addons") }
            },
            .action("Import Library & Progress", destructive: false) { [weak self] _ in
                self?.setBusy("Importing Stremio library…")
                a.importLibrary { self?.report("Stremio", $0, noun: "items") }
            },
            .action("Sign Out", destructive: true) { _ in a.signOut() },
        ])
    }

    private func stremioSignIn() {
        credentialsPrompt(title: "Stremio", message: "Sign in with your Stremio account.") { [weak self] email, password in
            self?.setBusy("Signing in to Stremio…")
            StremioAccount.shared.signIn(email: email, password: password) { error in
                self?.setBusy(nil)
                if let e = error {
                    self?.showAlert("Couldn't sign in", e.localizedDescription)
                } else {
                    self?.offerStremioImport()
                }
            }
        }
    }

    private func offerStremioImport() {
        let alert = UIAlertController(title: "Signed in to Stremio",
                                      message: "Import your addons, library and progress now?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
            self?.setBusy("Importing from Stremio…")
            StremioAccount.shared.importAddons { r1 in
                StremioAccount.shared.importLibrary { r2 in
                    let n = ((try? r1.get()) ?? 0) + ((try? r2.get()) ?? 0)
                    if case .failure(let e) = r1 {
                        self?.report("Stremio", .failure(e), noun: "")
                    } else {
                        self?.report("Stremio", .success(n), noun: "addons and items")
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    // MARK: Trakt

    private func traktSection() -> Section {
        let a = TraktAccount.shared
        let setupFooter = "Trakt needs your own free API app: on trakt.tv go to Settings → Your API Apps → New Application, use urn:ietf:wg:oauth:2.0:oob as the redirect URI, then paste its Client ID and Secret here."
        if a.isSignedIn {
            return Section(title: "Trakt", footer: "While connected, Lumen scrobbles what you watch to Trakt.", rows: [
                .info("Connected", a.username),
                .action("Import Continue Watching", destructive: false) { [weak self] _ in
                    self?.setBusy("Importing from Trakt…")
                    a.importPlayback { result in
                        AccountSync.fillMissingTitles()
                        self?.report("Trakt", result, noun: "items")
                    }
                },
                .action("Disconnect", destructive: true) { _ in a.signOut() },
            ])
        }
        var rows: [Row] = [
            .value("API App", a.hasApp ? "Client ID set" : "Not set up") { [weak self] _ in self?.traktSetup() },
        ]
        if let code = traktCode, traktPoll != nil {
            rows.append(.info("Enter code \(code.userCode)", "at \(code.verificationURL)"))
            rows.append(.action("Open Trakt Activation Page", destructive: false) { _ in
                if let url = URL(string: code.verificationURL) { UIApplication.shared.open(url, options: [:]) }
            })
            rows.append(.action("Cancel", destructive: true) { [weak self] _ in
                self?.traktPoll?.cancel()
                self?.traktPoll = nil
                self?.traktCode = nil
                self?.rebuild()
            })
        } else if a.hasApp {
            rows.append(.action("Connect Trakt", destructive: false) { [weak self] _ in self?.traktConnect() })
        }
        return Section(title: "Trakt", footer: setupFooter, rows: rows)
    }

    private func traktSetup() {
        let alert = UIAlertController(title: "Trakt API App", message: "Paste the Client ID and Client Secret from your Trakt API app.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Client ID"
            tf.text = TraktAccount.shared.clientId
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addTextField { tf in
            tf.placeholder = "Client Secret"
            tf.text = TraktAccount.shared.clientSecret
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            TraktAccount.shared.clientId = alert?.textFields?[0].text ?? ""
            TraktAccount.shared.clientSecret = alert?.textFields?[1].text ?? ""
            self?.rebuild()
        })
        present(alert, animated: true)
    }

    private func traktConnect() {
        setBusy("Contacting Trakt…")
        TraktAccount.shared.startDeviceAuth { [weak self] result in
            guard let self = self else { return }
            self.setBusy(nil)
            switch result {
            case .failure(let e):
                self.showAlert("Couldn't connect", e.localizedDescription)
            case .success(let code):
                UIPasteboard.general.string = code.userCode
                let handle = TraktAccount.PollHandle()
                self.traktPoll = handle
                self.traktCode = code
                self.rebuild()
                let alert = UIAlertController(
                    title: "Code: \(code.userCode)",
                    message: "Open \(code.verificationURL) and enter this code (it's been copied). Come back here when you're done.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Open Trakt", style: .default) { _ in
                    if let url = URL(string: code.verificationURL) { UIApplication.shared.open(url, options: [:]) }
                })
                alert.addAction(UIAlertAction(title: "Later", style: .cancel))
                self.present(alert, animated: true)

                TraktAccount.shared.poll(code, handle: handle) { [weak self] result in
                    guard let self = self else { return }
                    self.traktPoll = nil
                    self.traktCode = nil
                    self.rebuild()
                    switch result {
                    case .success:
                        self.setBusy("Importing from Trakt…")
                        TraktAccount.shared.importPlayback { result in
                            AccountSync.fillMissingTitles()
                            self.report("Trakt connected", result, noun: "items")
                        }
                    case .failure(let e):
                        self.showAlert("Trakt", e.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: Nuvio

    private func nuvioSection() -> Section {
        let a = NuvioAccount.shared
        let footer = "Sign in to a Nuvio server to import and sync your addons, library and progress. Nuvio's official servers don't publish the details other apps need, so this works with self-hosted Nuvio servers."
        guard a.isSignedIn else {
            return Section(title: "Nuvio", footer: footer, rows: [
                .action("Connect to a Nuvio Server", destructive: false) { [weak self] _ in self?.nuvioDiscover() },
                .action("Enter Server Details Manually", destructive: false) { [weak self] _ in self?.nuvioManual() },
            ])
        }
        return Section(title: "Nuvio", footer: "Library changes and watch progress sync back to Nuvio automatically.", rows: [
            .info("Signed in", [a.email, a.server?.label].compactMap { $0 }.joined(separator: " · ")),
            .value("Profile", a.profileName ?? "Profile \(a.profileIndex)") { [weak self] src in self?.nuvioPickProfile(from: src) },
            .action("Import Addons", destructive: false) { [weak self] _ in
                self?.setBusy("Importing Nuvio addons…")
                a.importAddons { self?.report("Nuvio", $0, noun: "addons") }
            },
            .action("Import Library & Progress", destructive: false) { [weak self] _ in self?.nuvioImportAll() },
            .action("Sign Out", destructive: true) { _ in a.signOut() },
        ])
    }

    private func nuvioDiscover() {
        let alert = UIAlertController(title: "Nuvio Server", message: "Enter your Nuvio server's address.", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "nuvio.example.com"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            let input = alert?.textFields?.first?.text ?? ""
            self?.setBusy("Checking server…")
            NuvioAccount.shared.discover(input) { result in
                self?.setBusy(nil)
                switch result {
                case .success(let server): self?.nuvioSignIn(server)
                case .failure(let e): self?.showAlert("Can't use this server", e.localizedDescription)
                }
            }
        })
        present(alert, animated: true)
    }

    private func nuvioManual() {
        let alert = UIAlertController(title: "Server Details",
                                      message: "For self-hosted servers: the backend URL and publishable (anon) key from your server's configuration.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://backend.example.com"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addTextField { tf in
            tf.placeholder = "Publishable key"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            var backend = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (alert?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            while backend.hasSuffix("/") { backend.removeLast() }
            guard let host = URL(string: backend)?.host, !key.isEmpty else {
                self?.showAlert("Missing details", "Enter both the backend URL and the key.")
                return
            }
            self?.nuvioSignIn(NuvioAccount.Server(backendUrl: backend, publishableKey: key, label: host))
        })
        present(alert, animated: true)
    }

    private func nuvioSignIn(_ server: NuvioAccount.Server) {
        credentialsPrompt(title: "Nuvio", message: "Sign in to \(server.label).") { [weak self] email, password in
            self?.setBusy("Signing in to Nuvio…")
            NuvioAccount.shared.signIn(server: server, email: email, password: password) { error in
                self?.setBusy(nil)
                if let e = error {
                    self?.showAlert("Couldn't sign in", e.localizedDescription)
                    return
                }
                NuvioAccount.shared.fetchProfiles { result in
                    let profiles = (try? result.get()) ?? []
                    if profiles.count > 1, let self = self {
                        self.nuvioPickProfile(from: self.view, profiles: profiles, thenImport: true)
                    } else {
                        if let p = profiles.first { NuvioAccount.shared.selectProfile(p) }
                        self?.nuvioImportAll()
                    }
                }
            }
        }
    }

    private func nuvioPickProfile(from source: UIView, profiles: [NuvioAccount.Profile]? = nil, thenImport: Bool = false) {
        guard let list = profiles else {
            setBusy("Loading profiles…")
            NuvioAccount.shared.fetchProfiles { [weak self] result in
                self?.setBusy(nil)
                switch result {
                case .success(let p) where !p.isEmpty: self?.nuvioPickProfile(from: source, profiles: p)
                case .success: self?.showAlert("No profiles", "This account has no profiles yet.")
                case .failure(let e): self?.showAlert("Couldn't load profiles", e.localizedDescription)
                }
            }
            return
        }
        let sheet = UIAlertController(title: "Choose Profile", message: nil, preferredStyle: .actionSheet)
        for p in list {
            let current = p.index == NuvioAccount.shared.profileIndex
            sheet.addAction(UIAlertAction(title: (current ? "✓ " : "") + p.name, style: .default) { [weak self] _ in
                NuvioAccount.shared.selectProfile(p)
                if thenImport { self?.nuvioImportAll() }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }

    private func nuvioImportAll() {
        setBusy("Importing from Nuvio…")
        let a = NuvioAccount.shared
        a.importAddons { r1 in
            a.importLibrary { r2 in
                a.importProgress { [weak self] r3 in
                    AccountSync.fillMissingTitles()
                    let results = [r1, r2, r3]
                    if let failure = results.compactMap({ r -> Error? in
                        if case .failure(let e) = r { return e }
                        return nil
                    }).first, results.allSatisfy({ (try? $0.get()) == nil }) {
                        self?.report("Nuvio", .failure(failure), noun: "")
                    } else {
                        let n = results.reduce(0) { $0 + ((try? $1.get()) ?? 0) }
                        self?.report("Nuvio", .success(n), noun: "addons and items")
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func credentialsPrompt(title: String, message: String, _ submit: @escaping (String, String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Email"
            tf.keyboardType = .emailAddress
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.textContentType = .username
        }
        alert.addTextField { tf in
            tf.placeholder = "Password"
            tf.isSecureTextEntry = true
            tf.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak alert] _ in
            let email = (alert?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespaces)
            let password = alert?.textFields?[1].text ?? ""
            guard !email.isEmpty, !password.isEmpty else { return }
            submit(email, password)
        })
        present(alert, animated: true)
    }
}
