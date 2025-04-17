import SwiftUI

// Simple view to display the summary in a sheet
struct SummaryView: View {
    let summary: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Chat Summary")
                    .font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.bottom)
            
            ScrollView {
                Text(summary)
                    .textSelection(.enabled)
            }
            Spacer() // Push content to top
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300) // Give sheet a reasonable size
    }
} 