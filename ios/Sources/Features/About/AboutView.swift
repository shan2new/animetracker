import SwiftUI

// About sheet — app blurb + data-source credits. The TMDB block (logo + exact disclaimer
// line) is a condition of TMDB's free API tier, not decoration; keep it intact.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: "About AniTrack",
                    subtitle: "An airing-first tracker for anime and TV."
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(label: "Data sources")

                    credit(
                        name: "AniList",
                        body: "Anime metadata, relations, and airing schedules are provided by the AniList API."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Image("TMDBLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 13)
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .scaledFont(13.5)
                            .foregroundStyle(Theme.text52)
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.fillFaint)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.hairline, lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(22)
                    .foregroundStyle(Theme.text36)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func credit(name: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .scaledFont(15, weight: .semibold)
            Text(text)
                .scaledFont(13.5)
                .foregroundStyle(Theme.text52)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.fillFaint)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        )
    }
}
