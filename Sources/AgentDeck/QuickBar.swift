import SwiftUI
import AppKit

/// One-click launcher strip for the daily dashboards. Edit `links` to taste.
struct QuickBar: View {
    static let links: [(symbol: String, url: String, help: String)] = [
        ("chart.bar.xaxis", "https://us.posthog.com/project/293507", "PostHog — RTO"),
        ("arrow.triangle.branch", "https://github.com/Case-Interview-AI/AI-casing/pulls", "AI-casing PRs"),
        ("play.rectangle.fill", "https://studio.youtube.com", "YouTube Studio"),
        ("slider.horizontal.3", "https://www.roadtooffer.com/admin", "RTO admin"),
        ("link.circle", "https://app.ahrefs.com", "Ahrefs"),
        ("magnifyingglass", "https://search.google.com/search-console?resource_id=sc-domain:roadtooffer.com", "Search Console"),
        ("triangle.fill", "https://vercel.com/dashboard", "Vercel"),
        ("creditcard.fill", "https://dashboard.stripe.com", "Stripe"),
        ("cylinder.split.1x2", "https://supabase.com/dashboard", "Supabase"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.links, id: \.url) { LinkButton(link: $0) }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }
}

private struct LinkButton: View {
    let link: (symbol: String, url: String, help: String)
    @State private var hover = false

    var body: some View {
        Button {
            if let u = URL(string: link.url) { NSWorkspace.shared.open(u) }
        } label: {
            Image(systemName: link.symbol)
                .font(.system(size: 10))
                .foregroundStyle(hover ? Color.primary : Color(nsColor: .tertiaryLabelColor))
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(link.help)
    }
}
