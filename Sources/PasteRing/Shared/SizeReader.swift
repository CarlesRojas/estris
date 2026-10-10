import SwiftUI

/// Reports the size of the view it is the background of, whenever it changes.
struct SizeReader: View {
    let onChange: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onChange(proxy.size) }
                .onChange(of: proxy.size) { size in onChange(size) }
        }
    }
}
