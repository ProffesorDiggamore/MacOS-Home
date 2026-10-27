import SwiftUI
import AppKit

struct AccountsView: View {
    @ObservedObject private var github = GitHubService.shared
    @ObservedObject private var mail = MailService.shared
    @ObservedObject private var slate = SlateService.shared
    @State private var token = ""
    @State private var slateToken = ""
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
                        Text("Used by the GitHub, Contributions, GitHub Actions and Slate widgets.")
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

            Section("Slate Notes") {
                Text("Slate (formerly Cairn) syncs your vault to a GitHub repository, so the Slate widgets talk to that repo directly. They reuse your GitHub token above, or you can paste the token you already use in Slate (a fine-grained token with Contents read & write on your notes repo).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if slate.hasOwnToken {
                    HStack {
                        Label("Using your Slate token", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Spacer()
                        Button("Remove") { slate.setOwnToken(nil) }
                    }
                } else {
                    HStack {
                        SecureField("Slate token (optional)", text: $slateToken)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            slate.setOwnToken(slateToken)
                            slateToken = ""
                        }
                        .disabled(slateToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Label(github.isConnected ? "Using your GitHub token." : "Connect GitHub above or paste a Slate token.",
                          systemImage: github.isConnected ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Then add Slate Notes, Slate Today or Slate Streak. Quick capture adds bullets or to-dos to today's daily note, and Slate picks them up on its next sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onAppear { github.loadToken(); slate.loadToken() }
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
