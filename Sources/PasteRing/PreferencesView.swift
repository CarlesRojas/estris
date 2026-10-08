import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Style", selection: $settings.style) {
                ForEach(OverlayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.radioGroup)

            LabeledContent("History size") {
                HStack {
                    TextField("History size", value: maxItems, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Stepper("History size", value: maxItems, in: AppSettings.maxItemsRange, step: 5)
                        .labelsHidden()
                    Text("entries")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }

    private var maxItems: Binding<Int> {
        Binding(
            get: { settings.maxItems },
            set: { settings.maxItems = min(max($0, AppSettings.maxItemsRange.lowerBound), AppSettings.maxItemsRange.upperBound) }
        )
    }
}
