//
//  HomeView.swift
//  CaptureMobile

import SwiftUI
import Combine
import PostHog

// MARK: - Image Cache (Memory + Disk)

final class ImageCache {
    static let shared = ImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024

        let diskCache = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        let config = URLSessionConfiguration.default
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        memoryCache.setObject(image, forKey: url.absoluteString as NSString)
    }

    func data(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
                    .onAppear { loadImage() }
            }
        }
    }

    private func loadImage() {
        guard let url, !isLoading else { return }

        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        Task {
            do {
                let data = try await ImageCache.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    ImageCache.shared.store(uiImage, for: url)
                    await MainActor.run { self.image = uiImage }
                }
            } catch {
                print("Image load failed: \(error)")
            }
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Relative Time Text

struct RelativeTimeText: View {
    let date: Date
    @State private var text: String = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .onAppear { text = timeAgo(from: date) }
            .onReceive(timer) { _ in text = timeAgo(from: date) }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86400))d ago" }
        return "\(Int(seconds / 604_800))w ago"
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @ObservedObject var processingState = CaptureProcessingState.shared
    @State private var selectedCategory: String = "all"

    private let categories = ["all", "restaurant", "event", "movie", "book", "clothing", "note", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerView
                        categoryChip

                        if processingState.isProcessing && !processingState.hasPendingFailure {
                            processingCard
                        }

                        if captureHistory.captures.isEmpty && !processingState.isProcessing && !captureHistory.isLoading {
                            emptyState
                        }

                        if processingState.hasPendingFailure {
                            failedCard
                        }

                        capturesList
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                processingState.checkForFailure()
                Task { await captureHistory.loadCaptures(category: selectedCategory) }
            }
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Your Captures")
                .font(.system(size: 32, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Category Chip (Dropdown Menu)

    private var categoryChip: some View {
        HStack {
            Menu {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                        Task { await captureHistory.loadCaptures(category: cat) }
                    } label: {
                        HStack {
                            Text(categoryDisplayName(cat))
                            if selectedCategory == cat {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(categoryDisplayName(selectedCategory))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.95, green: 0.91, blue: 0.88), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func categoryDisplayName(_ cat: String) -> String {
        cat == "all" ? "All" : cat.capitalized + "s"
    }

    // MARK: - Processing Card

    private var processingCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.black.opacity(0.1)).frame(width: 32, height: 32)
                ProgressView().scaleEffect(0.8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing capture...")
                    .font(.system(size: 16, weight: .semibold))
                Text("Extracting data")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
        .padding(.horizontal, 20)
    }

    // MARK: - Failed Card

    private var failedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture failed").font(.system(size: 16, weight: .semibold))
                Text("Please try again").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { processingState.clearFailure() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary).padding(8)
            }.buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.15)))
        .padding(.horizontal, 20)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No captures yet")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
            Text("Take a screenshot, photo, or write a note to get started.")
                .font(.system(size: 14)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    // MARK: - Captures List

    private var capturesList: some View {
        LazyVStack(spacing: 16) {
            ForEach(captureHistory.captures, id: \.id) { capture in
                NavigationLink(value: capture.id) {
                    CaptureCardView(capture: capture)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .navigationDestination(for: String.self) { captureID in
            if let capture = captureHistory.captures.first(where: { $0.id == captureID }) {
                CaptureDetailView(capture: capture)
            }
        }
    }
}

// MARK: - Capture Card

struct CaptureCardView: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CachedAsyncImage(url: URL(string: capture.imageUrl ?? "")) {
                    ZStack {
                        Color(red: 0.96, green: 0.96, blue: 0.96)
                        Image(systemName: capture.categoryIcon)
                            .font(.system(size: 22)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 80, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(capture.methodLabel)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        RelativeTimeText(date: capture.timeCaptured)
                    }

                    Text(capture.title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(2)

                    if !capture.tags.isEmpty {
                        TagChipsRow(tags: capture.tags)
                    }
                }
            }

            if !capture.extractedData.isEmpty {
                extractedDataView
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06)))
    }

    @ViewBuilder
    private var extractedDataView: some View {
        let pairs = extractedDataPairs
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("EXTRACTED")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.7, green: 0.45, blue: 0.3))

                ForEach(pairs.prefix(3), id: \.key) { pair in
                    HStack {
                        Text(pair.key.capitalized)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(pair.value)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(Color(red: 251/255, green: 244/255, blue: 242/255), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var extractedDataPairs: [(key: String, value: String)] {
        capture.extractedData.compactMap { key, value in
            if key == "tags" { return nil }
            let str = "\(value)"
            guard !str.isEmpty, str != "<null>", str.count < 100 else { return nil }
            return (key: key, value: str)
        }
        .sorted { $0.key < $1.key }
    }
}

// MARK: - Capture Detail View

struct CaptureDetailView: View {
    let capture: Capture
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @State private var showFullscreenImage = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let urlStr = capture.imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            Color(red: 0.96, green: 0.96, blue: 0.96)
                            Image(systemName: capture.categoryIcon)
                                .font(.system(size: 40)).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture { showFullscreenImage = true }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(capture.title)
                        .font(.system(size: 26, weight: .bold))

                    HStack(spacing: 8) {
                        Text(capture.methodLabel)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.quaternary)
                        RelativeTimeText(date: capture.timeCaptured)
                    }

                    if !capture.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(capture.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.systemGray6), in: Capsule())
                            }
                        }
                    }
                }

                if !capture.extractedData.isEmpty {
                    detailExtractedData
                }

                Spacer(minLength: 20)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete Capture")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageView(url: URL(string: capture.imageUrl ?? ""))
        }
        .alert("Delete Capture", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await captureHistory.deleteCapture(id: capture.id)
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete this capture? This cannot be undone.")
        }
    }

    @ViewBuilder
    private var detailExtractedData: some View {
        let pairs = allExtractedPairs
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("EXTRACTED DATA")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.7, green: 0.45, blue: 0.3))

                ForEach(pairs, id: \.key) { pair in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pair.key.capitalized)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(pair.value)
                            .font(.system(size: 15))
                    }
                    if pair.key != pairs.last?.key {
                        Divider()
                    }
                }
            }
            .padding(16)
            .background(Color(red: 251/255, green: 244/255, blue: 242/255), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var allExtractedPairs: [(key: String, value: String)] {
        capture.extractedData.compactMap { key, value in
            if key == "tags" { return nil }
            let str = "\(value)"
            guard !str.isEmpty, str != "<null>" else { return nil }
            return (key: key, value: str)
        }
        .sorted { $0.key < $1.key }
    }
}

// MARK: - Fullscreen Image View

struct FullscreenImageView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url {
                CachedAsyncImage(url: url) {
                    ProgressView().tint(.white)
                }
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = max(scale, 1.0)
                            scale = max(scale, 1.0)
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(20)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tag Chips Row (single line with overflow)

struct TagChipsRow: View {
    let tags: [String]

    var body: some View {
        GeometryReader { geo in
            let result = layoutTags(tags, maxWidth: geo.size.width)
            HStack(spacing: 6) {
                ForEach(result.visible, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6), in: Capsule())
                }
                if result.overflow > 0 {
                    Text("+\(result.overflow)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6), in: Capsule())
                }
            }
        }
        .frame(height: 24)
    }

    private func layoutTags(_ tags: [String], maxWidth: CGFloat) -> (visible: [String], overflow: Int) {
        var usedWidth: CGFloat = 0
        var visible: [String] = []
        let spacing: CGFloat = 6
        let overflowWidth: CGFloat = 40

        for (i, tag) in tags.enumerated() {
            let chipWidth = textWidth(tag) + 16
            let remaining = tags.count - visible.count - 1
            let needsOverflow = remaining > 0
            let reservedWidth = needsOverflow ? overflowWidth + spacing : 0

            if usedWidth + chipWidth + reservedWidth <= maxWidth || i == 0 {
                visible.append(tag)
                usedWidth += chipWidth + spacing
            } else {
                break
            }
        }
        return (visible, tags.count - visible.count)
    }

    private func textWidth(_ text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width)
    }
}

// MARK: - Flow Layout (wrapping tags for detail view)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(subviews: subviews, in: proposal.width ?? 0)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (positions, y + rowHeight)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
