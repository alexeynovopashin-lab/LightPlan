import SwiftUI

/// Экран-заглушка скелета. Настоящие экраны приходят с итерации 17.
public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("Light Plan")
            .font(.largeTitle)
    }
}

#Preview {
    RootView()
}
