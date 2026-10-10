// The NotProton window (Phase 8, ROADMAP §9): icon, name, one status line, Install or
// Delete, Update, the progress or the problem of the running step, ⚙︎ at the bottom
// left and the credits signature at the bottom right. System controls only.

import AppKit
import SwiftUI

struct MainView: View {
    @Environment(MainModel.self) private var model
    @State private var showsGear = false
    @State private var showsCredits = false
    @State private var hoveringCredits = false

    static let size = CGSize(width: 360, height: 220)

    var body: some View {
        let screen = model.screen
        VStack(alignment: .leading, spacing: 0) {
            header(screen)
            Spacer(minLength: 12)
            buttons(screen)
            Spacer(minLength: 8)
            MessageLine(message: screen.message)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            Spacer(minLength: 4)
            footer(screen)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        .confirmationDialog(questionTitle, isPresented: questionShown, titleVisibility: .visible,
                            presenting: model.question) { question in
            questionButtons(question)
        } message: { question in
            questionMessage(question)
        }
        .sheet(isPresented: $showsCredits) { CreditsView() }
        .sheet(isPresented: deleteShown) { DeleteSheet().environment(model) }
    }

    // MARK: Parts

    private func header(_ screen: MainScreen) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "NotProton")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(screen.status)
                    .font(.callout)
                    .foregroundStyle(screen.tone == .problem ? AnyShapeStyle(.red)
                        : screen.tone == .attention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(model.versionsLine)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private func buttons(_ screen: MainScreen) -> some View {
        HStack(spacing: 10) {
            switch screen.primary {
            case .install:
                Button(tr("Install")) { Task { await model.pressInstall() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!screen.primaryEnabled)
                    .accessibilityHint(tr("Installs the engine and adds NotProton to Steam."))
            case .delete:
                Button(tr("Delete…")) { model.pressDelete() }
                    .buttonStyle(.bordered)
                    .disabled(!screen.primaryEnabled)
                    .accessibilityHint(tr("Removes NotProton from Steam. Asks first."))
            }
            if screen.showsUpdate {
                Button(tr("Update")) { Task { await model.pressUpdate() } }
                    .buttonStyle(screen.updateEnabled ? AnyPrimitiveButtonStyle(.borderedProminent)
                        : AnyPrimitiveButtonStyle(.bordered))
                    .keyboardShortcut("u", modifiers: .command)
                    .disabled(!screen.updateEnabled)
                    .accessibilityHint(screen.updateEnabled
                        ? tr("Updates the engine, the Steam bridge, Steam support and NotProton.")
                        : tr("Everything is up to date."))
            }
        }
        .controlSize(.large)
    }

    private func footer(_ screen: MainScreen) -> some View {
        HStack {
            Button {
                model.gearOpened()
                showsGear = true
            } label: {
                Image(systemName: "gearshape")
                    .overlay(alignment: .topTrailing) {
                        if model.showsBadge {
                            Circle().fill(.red).frame(width: 8, height: 8).offset(x: 5, y: -5)
                        }
                    }
            }
            .buttonBorderShape(.circle)
            .buttonStyle(.bordered)
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!screen.gearEnabled)
            .accessibilityLabel(tr("Settings"))
            .accessibilityValue(model.showsBadge ? tr("New") : "")
            .popover(isPresented: $showsGear, arrowEdge: .bottom) {
                GearPanel(close: { showsGear = false })
                    .environment(model)
            }

            Spacer()

            Button { showsCredits = true } label: {
                Text(verbatim: "Ruslan_Ukraina")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline(hoveringCredits)
            }
            .buttonStyle(.plain)
            .onHover { hoveringCredits = $0 }
            .help(tr("Credits and licenses"))
            .accessibilityLabel(tr("Credits and licenses"))
        }
    }

    // MARK: Questions

    private var questionShown: Binding<Bool> {
        Binding(get: { model.question != nil && model.question != .delete },
                set: { if !$0, model.question != .delete { model.question = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { model.question == .delete }, set: { if !$0 { model.question = nil } })
    }

    private var questionTitle: String {
        switch model.question {
        case .closeSteam?: tr("Close Steam?")
        case .delete?: ""
        case .steamUpdatesOff?: tr("Turn off Steam updates?")
        case nil: ""
        }
    }

    @ViewBuilder
    private func questionButtons(_ question: MainModel.Question) -> some View {
        switch question {
        case .closeSteam(let kind):
            Button(tr("Close Steam and Continue")) { Task { await model.confirmCloseSteam(kind) } }
                .keyboardShortcut(.defaultAction)
            Button(tr("Cancel"), role: .cancel) {}
        case .delete:
            EmptyView()
        case .steamUpdatesOff:
            Button(tr("Turn Off")) { Task { await model.confirmSteamUpdatesOff() } }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func questionMessage(_ question: MainModel.Question) -> some View {
        switch question {
        case .closeSteam:
            Text(tr("Steam is open. NotProton will close it, then you can open it again."))
        case .delete:
            EmptyView()
        case .steamUpdatesOff:
            Text(tr("Steam won't update at all, even to versions NotProton supports. You can turn this back on here."))
        }
    }
}

/// The line under the buttons: the running step, the problem with Retry, or the result.
struct MessageLine: View {
    @Environment(MainModel.self) private var model
    let message: MainScreen.Message

    var body: some View {
        switch message {
        case .none:
            EmptyView()
        case .progress(let title, let detail, let step, let count):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(step), total: Double(max(count, 1)))
                    .progressViewStyle(.linear)
                    .accessibilityLabel(tr("Progress"))
                    .accessibilityValue(tr("Step \(String(step + 1)) of \(String(count))"))
                Text(detail.map { "\(title) · \($0)" } ?? title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
        case .problem(let problem):
            HStack(alignment: .top, spacing: 8) {
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(problem.detail)
                Spacer(minLength: 0)
                if let pane = problem.settingsPane {
                    Button(tr("Open Settings")) { Remedy.openSettings(pane) }
                        .controlSize(.small)
                }
                // ⌘R is the old window's Refresh; Retry is reached with Tab.
                Button(tr("Retry")) { Task { await model.retry() } }
                    .controlSize(.small)
            }
        case .done(let text, let openSteam):
            HStack(spacing: 8) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if openSteam {
                    Button(tr("Open Steam")) { model.openSteam() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// `.buttonStyle` takes one concrete type; Update switches between two.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let body: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        body = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { body(configuration) }
}
