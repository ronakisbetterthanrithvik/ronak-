import Foundation

extension String {
    /// Splits a combined artist credit like "Playboi Carti & Travis Scott" into
    /// individual names, so a multi-artist track doesn't get lumped into its own
    /// one-off group (Auto-Sort) and does match a filter for any of its credited
    /// artists (Smart Control) instead of only the exact combined string.
    func splitArtistCredits() -> [String] {
        let separators = [" & ", ", ", " x ", " X ", " feat. ", " Feat. ", " featuring ", " Featuring "]
        var names = [self]
        for separator in separators {
            names = names.flatMap { $0.components(separatedBy: separator) }
        }
        return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
