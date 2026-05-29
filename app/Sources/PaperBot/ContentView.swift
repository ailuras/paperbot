import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)

            Text("Welcome to PaperBot macOS")
                .font(.title)
                .bold()

            Text("This is the native SwiftUI rebuild client.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

