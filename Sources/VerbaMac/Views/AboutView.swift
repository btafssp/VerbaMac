import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VerbaMac")
                        .font(.title.weight(.semibold))
                    Text("Latin & Greek morphology and lexica")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Group {
                Text("Credits & Licenses")
                    .font(.headline)
                credit(
                    "VerbaMac",
                    "© 2026 Brian T. Austin. Licensed under the GNU General Public License v3.0."
                )
                Text("Built with the help of Grok Bot 0.70.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                credit(
                    "Lewis & Short / Liddell–Scott–Jones",
                    "Text provided under a CC BY-SA 4.0 license by the Perseus Digital Library, Tufts University, with funding from the National Endowment for the Humanities. github.com/PerseusDL/lexica. The bundled databases include corrections based on the Thesaurus Linguae Latinae, shared under CC BY-SA 4.0."
                )
                credit(
                    "Morpheus",
                    "Morphological analyzer from the Perseus Project. Mozilla Public License 2.0. github.com/perseids-tools/morpheus"
                )
                credit(
                    "Whitaker’s WORDS",
                    "By William A. Whitaker (1936–2010). Freely given for any and all use. github.com/mk270/whitakers-words"
                )
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
