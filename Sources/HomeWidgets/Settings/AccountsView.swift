import SwiftUI
import AppKit

struct AccountsView: View {
    @ObservedObject private var github = GitHubService.shared
    @ObservedObject private var mail = MailService.shared
    @State private var token = ""
    @State private var connecting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub").font(.headline)
                        Text("Used by the GitHub, Contributions and Cairn Notes widgets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if github.isConnected {
                        if let avatar = github.avatar {
                            Image(nsImage: avatar).resizable().frame(width: 28, height: 28).clipShape(Circle())
                        }
                        Text(github.login.map { "@" + $0 } ?? "Connected")
                            .foregroundStyle(.secondary)
                    }
                }

                if github.isConnected {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
                        Spacer()
                        Button("Refresh Now") { github.refresh() }
                        Button("Disconnect", role: .destructive) { github.disconnect() }
                    }
                    if let error = github.error {
                        Text(error).font(.caption).foregroundStyle(Color.orange)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Create a token on GitHub (the button picks the right permissions: repo, notifications, read:user).")
                        Button("Create a Token on GitHub…") { NSWorkspace.shared.open(GitHubService.tokenURL) }
                        Text("2. Paste it here:")
                        HStack {
                            SecureField("ghp_…", text: $token)
                                .textFieldStyle(.roundedBorder)
                            Button(connecting ? "Checking…" : "Connect") { connect() }
                                .buttonStyle(.borderedProminent)
                                .disabled(token.isEmpty || connecting)
                        }
                        if let message {
                            Text(message).font(.caption).foregroundStyle(Color.orange)
                        }
                        Text("Your token is stored in your Mac's Keychain and only sent to api.github.com.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Cairn Notes") {
                Text("Cairn syncs your notes to a GitHub repository, so the Cairn widget uses your GitHub token. Add a Cairn Notes widget, then right-click it › Edit Widget and type your notes repo (for example you/notes). Quick capture adds lines to an Inbox note and commits them, so the token needs the repo permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if CairnService.cairnAppURL != nil {
                    Label("Cairn app found. Clicking a note opens Cairn.", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.green)
                } else {
                    Label("Cairn app not found in Applications. Notes will open on GitHub instead.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mail (Gmail, iCloud, Outlook…)") {
                Text("The Mail widget reads Apple's Mail app, so any account you've added there works, including Gmail. No password or token is needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Add an Account in System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Toggle("Open Mail in the background when needed", isOn: Binding(
                    get: { mail.launchInBackground },
                    set: { mail.launchInBackground = $0 }))
                Text("The first time, macOS asks to let Home Widgets control Mail. Click OK.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { github.loadToken() }
    }

    private func connect() {
        connecting = true
        message = nil
        github.connect(token: token) { error in
            connecting = false
            message = error
            if error == nil { token = "" }
        }
    }
}
