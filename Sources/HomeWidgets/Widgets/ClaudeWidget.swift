import SwiftUI

enum ClaudeKeys {
    static let showUsage = ConfigKey("showUsage", true)
    static let showIdle = ConfigKey("showIdle", true)
}

struct ClaudeWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var claude = ClaudeMonitor.shared

    private var sessions: [ClaudeMonitor.Session] {
        model[ClaudeKeys.showIdle] ? claude.sessions : claude.sessions.filter { $0.state != .idle }
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            Group {
                if !claude.isInstalled {
                    WidgetMessage(symbol: "terminal",
                                  title: "Claude Code not found",
                                  detail: "Install Claude Code and run `claude` in Terminal. Sessions will show up here.")
                } else {
                    switch model.size {
                    case .small: small(now)
                    case .medium: list(now, limit: 3)
                    case .large: list(now, limit: 7)
                    }
                }
            }
        }
        .monitoring(ClaudeMonitor.shared)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ClaudeMark()
                .fill(Palette.claude)
                .frame(width: 15, height: 15)
            Text("Claude Code")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 4)
            if claude.workingCount > 0 {
                Text("\(claude.workingCount) working")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.claude)
            }
            if claude.waitingCount > 0 {
                Text("\(claude.waitingCount) waiting")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
        }
    }

    private func small(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ClaudeMark().fill(Palette.claude).frame(width: 16, height: 16)
                Text("Claude").font(.system(size: 12.5, weight: .semibold))
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(claude.activeCount)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text(claude.activeCount == 1 ? "session" : "sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let latest = sessions.first {
                HStack(spacing: 5) {
                    StatusDot(state: latest.state)
                    Text(latest.projectName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                Text(latest.state == .idle ? Fmt.ago(latest.lastActivity, now: now) : latest.state.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(claude.hasLoaded ? "No sessions yet" : "Looking…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let latest = sessions.first { claude.open(latest) }
        }
        .widgetPadding()
    }

    private func list(_ now: Date, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if sessions.isEmpty {
                Spacer(minLength: 0)
                Text(claude.hasLoaded ? "No recent sessions. Start one with `claude` in Terminal." : "Looking for sessions…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(sessions.prefix(limit)) { session in
                    ClaudeSessionRow(session: session, now: now, detailed: model.size == .large)
                }
            }
            Spacer(minLength: 0)
            if model.size == .large && model[ClaudeKeys.showUsage] {
                Divider().opacity(0.5)
                usageFooter
            }
        }
        .widgetPadding()
    }

    private var usageFooter: some View {
        HStack(spacing: 14) {
            usageStat("Tokens today", Fmt.count(claude.usageToday.total))
            usageStat("Output", Fmt.count(claude.usageToday.output))
            usageStat("Replies", Fmt.count(claude.usageToday.messages))
            usageStat("Sessions", "\(claude.sessionsToday)")
        }
    }

    private func usageStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClaudeSessionRow: View {
    let session: ClaudeMonitor.Session
    let now: Date
    var detailed = false
    @State private var hovering = false

    private var statusColor: Color {
        switch session.state {
        case .working: return Palette.claude
        case .waiting: return .green
        case .idle: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(state: session.state)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if detailed, let branch = session.branch {
                        Text(branch)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .lineLimit(1)
                    }
                }
                Text(session.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if detailed, session.state == .waiting, let reply = session.lastReply {
                    Text(reply)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(session.state == .idle ? Fmt.ago(session.lastActivity, now: now) : session.state.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                if detailed, let model = session.model {
                    Text(model)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { ClaudeMonitor.shared.open(session) }
        .help(session.state == .idle ? "Resume this session in Terminal" : "Show the terminal running this session")
        .contextMenu {
            if session.state != .idle {
                Button("Show Terminal") { ClaudeMonitor.shared.open(session) }
            }
            Button("Resume in New Terminal Window") { ClaudeMonitor.shared.resume(session) }
            Button("New Session in “\(session.projectName)”") { ClaudeMonitor.shared.newSession(in: session.projectPath) }
            Divider()
            Button("Open Project Folder") { ClaudeMonitor.shared.revealProject(session) }
            Button("Copy Session ID") { ClaudeMonitor.shared.copySessionID(session) }
        }
    }
}
