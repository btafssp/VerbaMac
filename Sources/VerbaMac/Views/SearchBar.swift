import SwiftUI

struct SearchBar: View {
    @ObservedObject var state: AppState
    var focus: FocusState<PaneFocus?>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!state.canGoBack)
            .help("Back")

            Button {
                state.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!state.canGoForward)
            .help("Forward")

            TextField("Latin or Greek word form…", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: .search)
                .onSubmit { state.parseCurrentQuery() }
                .help("Type a form and press Return to parse (⌘⌥F to focus)")

            Picker("Language", selection: Binding(
                get: { state.language },
                set: { lang in
                    // Defer: the segmented control can commit mid view-update
                    // ("Publishing changes from within view updates").
                    DispatchQueue.main.async { state.setLanguage(lang) }
                }
            )) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .labelsHidden()
            .help("Restrict parse language (⌘0 Both, ⌘1 Latin, ⌘2 Greek; ⌘}/⌘{ cycle)")

            Toggle(isOn: $state.greekIgnoreAccents) {
                Text("−n")
                    .font(.caption.monospaced())
            }
            .toggleStyle(.checkbox)
            .help("Ignore accents in Greek")
            .accessibilityLabel("Greek ignore accents")

            // No .defaultAction shortcut — Return in the field uses onSubmit,
            // and analyses-pane Enter must transfer focus to the lexicon.
            Button("Parse") {
                state.parseCurrentQuery()
            }
            .disabled(state.isParsing || state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if state.isParsing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
