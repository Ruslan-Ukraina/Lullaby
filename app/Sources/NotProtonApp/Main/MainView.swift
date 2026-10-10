// The NotProton window (Phase 8, ROADMAP §9, with the owner's edits): icon, name, a line
// of state, one button (Install, Update or Delete), the credits signature at the bottom
// left and ⚙︎ at the bottom right; the title bar is part of the background. A failure is a system alert; the same button
// tries again. System controls only.

import AppKit
import SwiftUI

struct MainView: View {
    @Environment(MainModel.self) private var model
    @State private var showsGear = false
    @Environment(\.openWindow) private var openWindow
    @State private var hoveringCredits = false

    static let size = CGSize(width: 360, height: 220)

    var body: some View {
        let screen = model.screen
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text(verbatim: "NotProton")
                .font(.title3.weight(.semibold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(screen.status)
                .font(.callout)
                .foregroundStyle(screen.tone == .problem ? AnyShapeStyle(.red)
                    : screen.tone == .attention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 1)
            mainButton(screen)
                .padding(.top, 12)
            progress(screen)
                .frame(height: 10)
                .padding(.top, 10)
            Spacer(minLength: 0)
            footer(screen)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .confirmationDialog(questionTitle, isPresented: questionShown, titleVisibility: .visible,
                            presenting: model.question) { question in
            questionButtons(question)
        } message: { question in
            Text(questionMessage(question))
        }
        .alert(screen.problemKind.map(FlowProblem.title) ?? "", isPresented: alertShown,
               presenting: screen.problem) { problem in
            if let pane = problem.settingsPane {
                Button(tr("Open Settings")) { Remedy.openSettings(pane) }
            }
            Button(tr("OK"), role: .cancel) {}
        } message: { problem in
            Text(problem.message)
        }
    }

    // MARK: Parts

    private func mainButton(_ screen: MainScreen) -> some View {
        Button { Task { await model.press() } } label: {
            Text(MainScreen.label(screen.button))
                .frame(minWidth: 120)
        }
        .buttonStyle(screen.button == .delete ? AnyPrimitiveButtonStyle(.bordered)
            : AnyPrimitiveButtonStyle(.borderedProminent))
        .controlSize(.large)
        .keyboardShortcut(screen.button == .delete ? nil : .defaultAction)
        .disabled(!screen.buttonEnabled)
        .accessibilityHint(hint(screen.button))
    }

    private func hint(_ button: MainScreen.Button) -> String {
        switch button {
        case .install: tr("Installs the engine and adds NotProton to Steam.")
        case .update: tr("Updates the engine, the Steam bridge, Steam support and NotProton.")
        case .delete: tr("Removes NotProton from Steam. Asks first.")
        }
    }

    @ViewBuilder
    private func progress(_ screen: MainScreen) -> some View {
        if let progress = screen.progress {
            ProgressView(value: Double(progress.step), total: Double(max(progress.of, 1)))
                .progressViewStyle(.linear)
                .frame(width: 200)
                .accessibilityLabel(tr("Progress"))
                .accessibilityValue(tr("Step \(String(progress.step + 1)) of \(String(progress.of))"))
        } else {
            Color.clear
        }
    }

    /// The signature at the bottom left, ⚙︎ at the bottom right (owner, 10.10).
    private func footer(_ screen: MainScreen) -> some View {
        HStack(alignment: .bottom) {
            Button { openWindow(id: CreditsView.windowID) } label: {
                Text(verbatim: "Ruslan_Ukraina")
                    .font(.caption2.weight(.light))
                    .foregroundStyle(.tertiary)
                    .underline(hoveringCredits)
            }
            .buttonStyle(.plain)
            .onHover { hoveringCredits = $0 }
            .help(tr("Credits and licenses"))
            .accessibilityLabel(tr("Credits and licenses"))

            Spacer()

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
        }
    }

    // MARK: Questions and the alert

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alertShown && model.screen.problem != nil }, set: { model.alertShown = $0 })
    }

    private var questionShown: Binding<Bool> {
        Binding(get: { model.question != nil }, set: { if !$0 { model.question = nil } })
    }

    private var questionTitle: String {
        switch model.question {
        case .closeSteam?: tr("Close Steam?")
        case .delete?: tr("Delete NotProton?")
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
            Button(tr("Delete"), role: .destructive) { Task { await model.confirmDelete() } }
            Button(tr("Cancel"), role: .cancel) {}
        case .steamUpdatesOff:
            Button(tr("Turn Off")) { Task { await model.confirmSteamUpdatesOff() } }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private func questionMessage(_ question: MainModel.Question) -> String {
        switch question {
        case .closeSteam:
            tr("Steam is open. NotProton will close it, then you can open it again.")
        case .delete:
            tr("NotProton is removed from Steam, and Steam goes back to how it was. Game prefixes and their backups, game settings and the Game Porting Toolkit stay.")
        case .steamUpdatesOff:
            tr("Steam won't update at all, even to versions NotProton supports. You can turn this back on here.")
        }
    }
}

/// `.buttonStyle` takes one concrete type; the button switches between two.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let body: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        body = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { body(configuration) }
}
