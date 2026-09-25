import Foundation

extension String {
    /// A single artist's own name can contain the exact same punctuation used to
    /// separate multiple artists in a combined credit -- "Tyler, The Creator" isn't
    /// "Tyler" featuring "The Creator" any more than "Kanye West, Pusha T & Jadakiss" is
    /// one artist. There's no purely syntactic way to tell those apart, so known
    /// single-artist names that would otherwise get mis-split are listed here instead.
    /// Not exhaustive -- add to it if another one turns up.
    private static let unsplittableArtistCredits: Set<String> = [
        "tyler, the creator",
        "earth, wind & fire",
        "crosby, stills & nash",
        "crosby, stills, nash & young",
        "emerson, lake & palmer",
        "hootie & the blowfish",
        "florence + the machine",
        "derek & the dominos"
    ]

    /// Splits a combined artist credit like "Playboi Carti & Travis Scott" into
    /// individual names, so a multi-artist track doesn't get lumped into its own
    /// one-off group (Auto-Sort) and does match a filter for any of its credited
    /// artists (Smart Control) instead of only the exact combined string.
    func splitArtistCredits() -> [String] {
        if String.unsplittableArtistCredits.contains(self.lowercased()) {
            return [self]
        }
        let separators = [" & ", ", ", " x ", " X ", " feat. ", " Feat. ", " featuring ", " Featuring "]
        var names = [self]
        for separator in separators {
            names = names.flatMap { $0.components(separatedBy: separator) }
        }
        return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
