import SwiftUI

struct Choice<Value>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

struct ChoiceSection<Value>: Identifiable {
    var id: String { title }
    let title: String
    let choices: [Choice<Value>]
}

/// A searchable, sectioned list to pick a key, button or action from.
struct ChoiceList<Value>: View {
    let sections: [ChoiceSection<Value>]
    let choose: (Value) -> Void
    @State private var search = ""

    private var results: [ChoiceSection<Value>] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            if section.title.localizedCaseInsensitiveContains(query) { return section }
            let choices = section.choices.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return choices.isEmpty ? nil : ChoiceSection(title: section.title, choices: choices)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $search)
                .padding(12)
            List {
                ForEach(results) { section in
                    Section(section.title) {
                        ForEach(section.choices) { choice in
                            Button {
                                choose(choice.value)
                            } label: {
                                Text(choice.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

/// The choices offered for each side of a mapping.
enum Choices {
    static func inputs(for device: InputDevice) -> [ChoiceSection<RemapInput>] {
        let keys = keySections { RemapInput.key($0.usage) }
        let buttons = ChoiceSection(title: String(localized: "Mouse Buttons"), choices: MouseButtons.remappable.map {
            Choice(id: "button-\($0)", title: MouseButtons.name($0), value: RemapInput.mouseButton($0))
        })
        return device.kind == .mouse ? [buttons] + keys : keys + [buttons]
    }

    static func outputs(for input: RemapInput?) -> [ChoiceSection<RemapOutput>] {
        let actions = SystemAction.Section.allCases.map { section in
            ChoiceSection(title: section.title, choices: SystemAction.allCases.filter { $0.section == section }.map {
                Choice(id: "action-\($0.rawValue)", title: $0.title, value: RemapOutput.action($0))
            })
        }
        let buttons = ChoiceSection(title: String(localized: "Mouse Buttons"), choices: (0...4).map {
            Choice(id: "button-\($0)", title: MouseButtons.name($0), value: RemapOutput.mouseButton($0))
        })
        // Keys without a macOS key code can only stand in for another key, on the keyboard itself.
        var onlyTypeable = true
        if case .key = input { onlyTypeable = false }
        let keys = keySections(onlyTypeable: onlyTypeable) { RemapOutput.key($0.usage) }
        let nothing = ChoiceSection(title: String(localized: "Off"), choices: [Choice(id: "nothing", title: RemapOutput.nothing.title, value: RemapOutput.nothing)])
        return actions + [buttons] + keys + [nothing]
    }

    private static func keySections<Value>(onlyTypeable: Bool = false, _ value: (KeyInfo) -> Value) -> [ChoiceSection<Value>] {
        KeyInfo.Section.allCases.compactMap { section in
            let keys = KeyCatalog.all.filter { $0.section == section && (!onlyTypeable || $0.keyCode != nil) }
            guard !keys.isEmpty else { return nil }
            return ChoiceSection(title: section.title, choices: keys.map {
                Choice(id: "key-\($0.usage)", title: $0.name, value: value($0))
            })
        }
    }
}
