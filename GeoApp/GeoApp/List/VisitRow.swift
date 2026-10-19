import SwiftUI

/// Zeile mit Name, optionalem Zusatz und erstem und letztem Besuch.
struct VisitRow: View {
    let title: String
    var subtitle: String?
    let first: Date
    let last: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                if let subtitle {
                    Spacer()
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(dates)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var dates: String {
        let firstText = first.formatted(date: .abbreviated, time: .omitted)
        let lastText = last.formatted(date: .abbreviated, time: .omitted)
        return firstText == lastText ? firstText : String(localized: "First \(firstText) · last \(lastText)")
    }
}
