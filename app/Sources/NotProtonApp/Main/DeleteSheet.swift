// Delete's question (ROADMAP §9.3): what goes, what stays, and the box for game
// prefixes, off by default because a prefix can hold saves that are not in Steam Cloud.

import SwiftUI

struct DeleteSheet: View {
    @Environment(MainModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Delete NotProton?"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(tr("NotProton is removed from Steam, and Steam goes back to how it was. The engine and the Steam bridge are deleted too. Your game settings stay."))
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $model.deletePrefixes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Also delete game prefixes"))
                    Text(tr("They can hold saves of games without Steam Cloud."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(tr("Cancel"), role: .cancel) { model.question = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Delete"), role: .destructive) {
                    dismiss()
                    Task { await model.confirmDelete() }
                }
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
