import SwiftUI
import MusicKit

struct PlaylistPickerView: View {
    let playlists: [PickablePlaylist]
    let isLoading: Bool
    let errorMessage: String?
    var onSelect: (PickablePlaylist) -> Void
    var onRetry: () -> Void

    @State private var selectedIndex = 0

    /// A manually-dragged display order, persisted across launches -- see
    /// `syncCustomOrder`/`orderedPlaylists`. This only ever changes how Sift *displays*
    /// the carousel; it can't reorder a real Apple Music library playlist in Apple Music
    /// itself (MusicKit has no API for that), so a mixed drag between Sift-made and
    /// library playlists is still just a Sift-side display order, same as either alone.
    @State private var customOrderIDs: [String] = []
    private let customOrderDefaultsKey = "sift.carouselOrder"

    /// iOS-style "jiggle mode" -- long-press a tile to enter it, drag the centered tile
    /// past a neighbor to swap places with it, tap anywhere to leave.
    @State private var isRearranging = false
    /// How far the centered tile has been dragged from rest while rearranging -- only the
    /// centered tile moves by this; its neighbors hold still until a swap happens (see
    /// `attemptReorderSwap`). The carousel has no other drag behavior -- paging is
    /// arrow-buttons-only (see `arrows`).
    @State private var reorderOffset: CGFloat = 0
    /// Flips back and forth forever while rearranging to drive the jiggle -- combined
    /// with each tile's own offset parity (see `tile(for:offset:)`) so neighboring tiles
    /// rock in opposite directions instead of in lockstep.
    @State private var jigglePhase = false

    private enum Cover {
        case single(Artwork)
        case mosaic([Artwork])
        // Not "none" -- that would collide with Optional<Cover>.none when switching over
        // `covers[id]` (a Cover?), silently making this case unreachable.
        case unavailable
    }

    /// Each real library playlist's cover, fetched lazily (via
    /// `MusicLibraryService.loadPlaylistCoverArtwork`) only for playlists the carousel
    /// actually scrolls to, and cached here so none is ever fetched twice. Sift-only
    /// playlists don't need this -- their cover (if any) is already a local file, read
    /// synchronously via `SiftPlaylistStore.coverImage(for:)`.
    @State private var covers: [String: Cover] = [:]

    /// How many tiles show on either side of the selected one before they're clipped off.
    private let sideWindow = 2
    /// The visual gap between adjacent tiles' edges -- see `xOffset(for:)` for why this
    /// replaces a flat spacing constant between tile *centers*.
    private let tileGap: CGFloat = 28

    @State private var showAIGenerator = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.ambientGlow.ignoresSafeArea()

            VStack(spacing: 28) {
                header
                aiGeneratorBanner

                if isLoading || !allCoversReady {
                    Spacer()
                    ProgressView("Loading your playlists…")
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry", action: onRetry)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .glassSurface(Capsule())
                    }
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if playlists.isEmpty {
                    Spacer()
                    Text("No playlists found in your Apple Music library yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    Spacer()
                    carousel
                    if !isRearranging {
                        arrows
                    }
                    Spacer()
                    Text(isRearranging
                        ? "Drag a tile to reorder -- tap anywhere to finish"
                        : "Pick a playlist to open -- your Apple Music library, or one Sift created.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 36)
                }
            }
        }
        .onAppear { loadCustomOrder(); syncCustomOrder() }
        .onChange(of: playlists) { _ in selectedIndex = 0; syncCustomOrder() }
        .task(id: playlists.map(\.id)) { await prefetchAllCovers() }
        .sheet(isPresented: $showAIGenerator) {
            AIPlaylistGeneratorView()
        }
    }

    // MARK: - Reordering

    /// The carousel's actual display order -- `playlists` reordered to match
    /// `customOrderIDs`. Built with `Dictionary(_:uniquingKeysWith:)`, not
    /// `uniqueKeysValues:`, the same defensive pattern used for a real Apple Music
    /// playlist's songs elsewhere -- a duplicate id here would otherwise crash outright.
    private var orderedPlaylists: [PickablePlaylist] {
        let byID = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = customOrderIDs.compactMap { byID[$0] }
        // customOrderIDs is only meaningful once it's been synced against the current
        // playlists (see syncCustomOrder) -- if it hasn't caught up yet for any reason
        // (a transient empty `playlists` mid-reload, a timing race), falling back to
        // `playlists` itself means the carousel always shows every real playlist, just
        // not necessarily in the saved order, rather than going blank.
        return ordered.count == playlists.count ? ordered : playlists
    }

    private func loadCustomOrder() {
        guard customOrderIDs.isEmpty,
              let saved = UserDefaults.standard.array(forKey: customOrderDefaultsKey) as? [String]
        else { return }
        customOrderIDs = saved
    }

    private func saveCustomOrder() {
        UserDefaults.standard.set(customOrderIDs, forKey: customOrderDefaultsKey)
    }

    /// Keeps `customOrderIDs` in step with `playlists` -- drops any id that no longer
    /// exists (a deleted playlist), and appends anything new (a playlist just created, or
    /// the very first time this ever runs) in its original relative order at the end.
    private func syncCustomOrder() {
        // Never sync against an empty `playlists` -- that's always a transient loading
        // state here, not a real "no playlists" fact (that case is handled elsewhere in
        // `body`), and syncing against it would wipe any real saved order down to `[]`
        // and persist that wipe, permanently losing it.
        guard !playlists.isEmpty else { return }
        let currentIDs = Set(playlists.map(\.id))
        var next = customOrderIDs.filter { currentIDs.contains($0) }
        let known = Set(next)
        for item in playlists where !known.contains(item.id) {
            next.append(item.id)
        }
        guard next != customOrderIDs else { return }
        customOrderIDs = next
        saveCustomOrder()
    }

    /// Enters jiggle mode on the tile at `index`, centering it first so the drag gesture
    /// (which only ever moves the centered tile -- see `tile(for:offset:)`) has something
    /// to act on.
    private func beginRearranging(at index: Int) {
        guard !isRearranging else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedIndex = index
            isRearranging = true
        }
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
            jigglePhase.toggle()
        }
    }

    private func endRearranging() {
        guard isRearranging else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            isRearranging = false
            reorderOffset = 0
            jigglePhase = false
        }
    }

    /// Swaps the centered tile past a neighbor once it's been dragged more than half the
    /// gap between their centers -- `while`, not `if`, so a single fast/long drag can
    /// chain through several swaps in one continuous gesture, the same way iOS lets you
    /// drag an icon straight across several others at once.
    private func attemptReorderSwap() {
        let gap = xOffset(for: 1)
        guard gap > 0 else { return }
        while reorderOffset > gap / 2, selectedIndex + 1 < orderedPlaylists.count {
            swapOrder(selectedIndex, selectedIndex + 1)
            selectedIndex += 1
            reorderOffset -= gap
        }
        while reorderOffset < -gap / 2, selectedIndex > 0 {
            swapOrder(selectedIndex, selectedIndex - 1)
            selectedIndex -= 1
            reorderOffset += gap
        }
    }

    private func swapOrder(_ a: Int, _ b: Int) {
        guard customOrderIDs.indices.contains(a), customOrderIDs.indices.contains(b) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            customOrderIDs.swapAt(a, b)
        }
        saveCustomOrder()
    }

    /// Whether every playlist that actually needs an async-loaded cover (see
    /// `needsAsyncCover`) already has one in `covers` -- the carousel stays behind the
    /// loading spinner until this is true, so nobody ever sees `artworkPlaceholder`
    /// appear then get swapped out once a cover loads in.
    private var allCoversReady: Bool {
        playlists.allSatisfy { !needsAsyncCover($0) || covers[$0.id] != nil }
    }

    /// A Sift-only playlist with a custom cover already picked renders it straight from
    /// disk, synchronously -- no network/catalog lookup, so it never needs an entry in
    /// `covers` to be "ready". Everything else (a real library playlist, or a Sift
    /// playlist without a custom cover) does.
    private func needsAsyncCover(_ item: PickablePlaylist) -> Bool {
        if case .sift(let owned) = item, SiftPlaylistStore.shared.coverImage(for: owned) != nil {
            return false
        }
        return true
    }

    /// Loads every playlist's cover concurrently before the carousel is ever shown --
    /// see `allCoversReady`. `loadCover`/`loadSiftMosaic` each already guard against
    /// re-fetching something already in `covers`, so this is cheap to re-run (via the
    /// `.task(id:)` above) whenever the playlist list itself changes, e.g. a new one
    /// gets created.
    private func prefetchAllCovers() async {
        await withTaskGroup(of: Void.self) { group in
            for item in playlists where needsAsyncCover(item) {
                group.addTask {
                    switch item {
                    case .library(let summary):
                        await loadCover(for: summary)
                    case .sift(let owned):
                        await loadSiftMosaic(owned: owned, key: item.id)
                    }
                }
            }
        }
    }

    /// Entry point for building a playlist from anywhere in Apple Music's catalog
    /// (`AIPlaylistGeneratorView`/`CatalogPlaylistGeneratorService`) -- distinct from
    /// Auto-Sort's Vibe tab, which only curates from a playlist already open, so it
    /// lives on this screen rather than nested inside one playlist's own tools.
    private var aiGeneratorBanner: some View {
        Button {
            showAIGenerator = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("AI Playlist Generator")
                            .font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text("HOT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accentGradient))
                    }
                    Text("Describe a vibe -- Sift builds it from all of Apple Music")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.black))
            .glassEdge(Capsule(), lineWidth: 1.25, baseOpacity: 0.4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Playlist")
                    .font(.system(size: 30, weight: .bold))
            }
            Spacer()
            Theme.appIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        }
        .padding(.top, 28)
        .padding(.horizontal, 32)
    }

    // MARK: - Carousel

    private var carousel: some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { index in
                tile(for: orderedPlaylists[index], offset: index - selectedIndex)
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { endRearranging() }
    }

    private var visibleIndices: [Int] {
        (-sideWindow...sideWindow).compactMap { delta in
            let index = selectedIndex + delta
            return orderedPlaylists.indices.contains(index) ? index : nil
        }
    }

    /// A tile's width at a given distance from the selected (centered) one -- shared
    /// with `xOffset(for:)`, which needs every tile's size, not just the one it's
    /// currently placing, to space edges (not centers) evenly.
    private func tileSize(atDistance distance: Int) -> CGFloat {
        distance == 0 ? 220 : (distance == 1 ? 160 : 108)
    }

    /// Where a tile at `offset` steps from the selected one sits horizontally.
    ///
    /// Tiles shrink the farther they are from center (`tileSize(atDistance:)`), but the
    /// old version of this spaced every tile's *center* by the same flat distance
    /// regardless of that -- which, since two differently-sized tiles' edges aren't the
    /// same distance from their centers, produced inconsistent, sometimes near-zero,
    /// sometimes oddly wide gaps between adjacent tiles depending on which sizes happened
    /// to be next to each other. This instead walks outward from the center tile one step
    /// at a time, adding each pair's own two half-widths plus a fixed `tileGap`, so the
    /// visual gap between every adjacent pair of tile *edges* is the same regardless of
    /// their sizes.
    private func xOffset(for offset: Int) -> CGFloat {
        guard offset != 0 else { return 0 }
        let step = offset > 0 ? 1 : -1
        var position: CGFloat = 0
        var previousSize = tileSize(atDistance: 0)
        var current = 0
        while current != offset {
            current += step
            let currentSize = tileSize(atDistance: abs(current))
            position += CGFloat(step) * (previousSize / 2 + currentSize / 2 + tileGap)
            previousSize = currentSize
        }
        return position
    }

    private func tile(for item: PickablePlaylist, offset: Int) -> some View {
        let isSelected = offset == 0
        let distance = abs(offset)
        let size = tileSize(atDistance: distance)
        let dimOpacity = isSelected ? 1.0 : (distance == 1 ? 0.55 : 0.26)
        // Only the centered tile moves with the finger while rearranging -- every
        // neighbor holds its normal position until a swap actually happens, at which
        // point it becomes the new centered tile and picks up this same offset itself.
        // The carousel otherwise never shifts on its own from a drag -- paging is
        // arrow-buttons-only (see `arrows`).
        let xPosition = xOffset(for: offset) + (isRearranging && isSelected ? reorderOffset : 0)
        // Alternates sign by offset parity so adjacent tiles rock opposite ways, like iOS
        // -- `jigglePhase` itself just flips back and forth forever to drive the timing.
        let jiggleAngle: Double = ((offset % 2 == 0) == jigglePhase) ? 1.6 : -1.6

        return VStack(spacing: 10) {
            artwork(for: item, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 22, y: 14)

            if isSelected {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 240)
            }
        }
        .opacity(dimOpacity)
        .offset(x: xPosition)
        .rotationEffect(.degrees(isRearranging ? jiggleAngle : 0))
        .zIndex(isSelected ? 1 : 0)
        .onTapGesture {
            if isRearranging {
                endRearranging()
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isSelected {
                    onSelect(item)
                } else if let tappedIndex = orderedPlaylists.firstIndex(where: { $0.id == item.id }) {
                    selectedIndex = tappedIndex
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            if let tappedIndex = orderedPlaylists.firstIndex(where: { $0.id == item.id }) {
                beginRearranging(at: tappedIndex)
            }
        }
        // `.simultaneousGesture`, not `.gesture` -- this view already has a tap and a
        // long-press gesture of its own, and a plain `.gesture(DragGesture())` here would
        // compete with those for the same touch instead of coexisting, likely why
        // rearranging never actually triggered before. This runs alongside them; the
        // guards below mean it only ever does anything once already rearranging, and
        // only for the tile currently centered.
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard isRearranging, isSelected else { return }
                    reorderOffset = value.translation.width
                    attemptReorderSwap()
                }
                .onEnded { _ in
                    guard isRearranging, isSelected else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        reorderOffset = 0
                    }
                }
        )
    }

    @ViewBuilder
    private func artwork(for item: PickablePlaylist, size: CGFloat) -> some View {
        switch item {
        case .library(let summary):
            switch covers[summary.id] {
            case .single(let artwork):
                // A small margin in case this particular cover isn't perfectly square --
                // see the note on `squareArtwork` for why this is much smaller than a
                // song's own (always exactly square) artwork might suggest it needs.
                squareArtwork(artwork, size: size, overscan: 1.08)
            case .mosaic(let artworks):
                mosaic(artworks, size: size)
            case .unavailable:
                artworkPlaceholder.frame(width: size, height: size)
            case nil:
                artworkPlaceholder
                    .frame(width: size, height: size)
                    .task { await loadCover(for: summary) }
            }
        case .sift(let owned):
            if let nsImage = SiftPlaylistStore.shared.coverImage(for: owned) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                // No custom cover was picked for this Sift-only playlist -- fall back to
                // the same 2x2 mosaic-of-its-own-songs treatment a real library playlist
                // without custom art already gets, rather than a generic placeholder tile.
                switch covers[item.id] {
                case .mosaic(let artworks):
                    mosaic(artworks, size: size)
                case .unavailable, .single:
                    artworkPlaceholder.frame(width: size, height: size)
                case nil:
                    artworkPlaceholder
                        .frame(width: size, height: size)
                        .task { await loadSiftMosaic(owned: owned, key: item.id) }
                }
            }
        }
    }

    private func loadCover(for summary: LibraryPlaylistSummary) async {
        guard covers[summary.id] == nil else { return }
        let result = await MusicLibraryService.shared.loadPlaylistCoverArtwork(id: summary.id)
        if let single = result.single {
            covers[summary.id] = .single(single)
        } else if !result.mosaic.isEmpty {
            covers[summary.id] = .mosaic(result.mosaic)
        } else {
            covers[summary.id] = .unavailable
        }
    }

    /// A Sift-only playlist only stores its songs' library ids, not their artwork, so
    /// building its mosaic (unlike a real library playlist's, which MusicKit hands back
    /// directly) means resolving a few of those songs first.
    private func loadSiftMosaic(owned: SiftOwnedPlaylist, key: String) async {
        guard covers[key] == nil else { return }
        let songs = await MusicLibraryService.shared.resolveSongs(forLibraryIDs: Array(owned.songLibraryIDs.prefix(4)))
        let artworks = songs.compactMap(\.artwork)
        covers[key] = artworks.isEmpty ? .unavailable : .mosaic(artworks)
    }

    /// Matches how Apple Music itself covers a personal playlist with no custom artwork:
    /// a 2x2 grid of album art sampled from the playlist's own songs.
    private func mosaic(_ artworks: [Artwork], size: CGFloat) -> some View {
        let tiles: [Artwork?] = (0..<4).map { $0 < artworks.count ? artworks[$0] : nil }
        let tileSize = size / 2
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                mosaicTile(tiles[0], size: tileSize)
                mosaicTile(tiles[1], size: tileSize)
            }
            GridRow {
                mosaicTile(tiles[2], size: tileSize)
                mosaicTile(tiles[3], size: tileSize)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func mosaicTile(_ artwork: Artwork?, size: CGFloat) -> some View {
        if let artwork {
            squareArtwork(artwork, size: size)
        } else {
            Theme.accentGradient
                .frame(width: size, height: size)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentGradient)
            .overlay(Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(.white.opacity(0.9)))
    }

    // MARK: - Arrows

    private var arrows: some View {
        HStack(spacing: 28) {
            arrowButton(systemName: "chevron.left", disabled: selectedIndex == 0) {
                selectedIndex = max(selectedIndex - 1, 0)
            }
            arrowButton(systemName: "chevron.right", disabled: selectedIndex >= orderedPlaylists.count - 1) {
                selectedIndex = min(selectedIndex + 1, orderedPlaylists.count - 1)
            }
        }
    }

    private func arrowButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 52, height: 52)
                .glassSurface(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}
