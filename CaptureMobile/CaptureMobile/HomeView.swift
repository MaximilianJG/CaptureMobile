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
            .font(CaptureFont.monoSm)
            .foregroundStyle(CaptureColors.textHint)
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
                CaptureColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: CaptureSpacing.lg) {
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
                .font(CaptureFont.display)
                .foregroundStyle(CaptureColors.text)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
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
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                    Text(categoryDisplayName(selectedCategory))
                        .font(CaptureFont.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(CaptureColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(CaptureColors.primaryMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
                .overlay(RoundedRectangle(cornerRadius: CaptureRadius.md).stroke(CaptureColors.primary.opacity(0.10)))
            }
            Spacer()
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    private func categoryDisplayName(_ cat: String) -> String {
        cat == "all" ? "All" : cat.capitalized + "s"
    }

    // MARK: - Processing Card

    private var processingCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(CaptureColors.surface).frame(width: 32, height: 32)
                ProgressView().scaleEffect(0.8).tint(CaptureColors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing capture...")
                    .font(CaptureFont.title)
                    .foregroundStyle(CaptureColors.text)
                Text("Extracting data")
                    .font(CaptureFont.bodySm)
                    .foregroundStyle(CaptureColors.textSecondary)
            }
            Spacer()
        }
        .padding(CaptureSpacing.base)
        .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border))
        .captureShadow(.card)
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Failed Card

    private var failedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(CaptureColors.warning, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture failed")
                    .font(CaptureFont.title)
                    .foregroundStyle(CaptureColors.text)
                Text("Please try again")
                    .font(CaptureFont.bodySm)
                    .foregroundStyle(CaptureColors.textSecondary)
            }
            Spacer()
            Button { processingState.clearFailure() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CaptureColors.textTertiary).padding(8)
            }.buttonStyle(.plain)
        }
        .padding(CaptureSpacing.base)
        .background(CaptureColors.warningMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.warning.opacity(0.15)))
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: CaptureSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: CaptureRadius.xl)
                    .fill(CaptureColors.text.opacity(0.06))
                    .frame(width: 56, height: 56)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 24))
                    .foregroundStyle(CaptureColors.textTertiary)
            }
            Text("No captures yet")
                .font(CaptureFont.heading)
                .foregroundStyle(CaptureColors.textSecondary)
            Text("Take a screenshot, photo, or write a note to get started.")
                .font(CaptureFont.bodySm)
                .foregroundStyle(CaptureColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, CaptureSpacing.xxxl)
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Captures List

    private var capturesList: some View {
        LazyVStack(spacing: CaptureSpacing.cardGap) {
            ForEach(captureHistory.captures, id: \.id) { capture in
                NavigationLink(value: capture.id) {
                    CaptureCardView(capture: capture)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
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
        VStack(alignment: .leading, spacing: CaptureSpacing.md) {
            HStack(alignment: .top, spacing: 14) {
                if let urlStr = capture.imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            CaptureColors.surface
                            Image(systemName: capture.categoryIcon)
                                .font(.system(size: 22)).foregroundStyle(CaptureColors.textTertiary)
                        }
                    }
                    .frame(width: 80, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: CaptureRadius.lg))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(capture.methodLabel)
                            .font(CaptureFont.monoSm)
                            .foregroundStyle(CaptureColors.textTertiary)
                        Spacer()
                        RelativeTimeText(date: capture.timeCaptured)
                    }

                    Text(capture.title)
                        .font(CaptureFont.title)
                        .foregroundStyle(CaptureColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if !capture.tags.isEmpty {
                        TagChipsRow(tags: capture.tags)
                    }
                }
            }

            if !capture.extractedData.isEmpty {
                extractedDataView
            }
        }
        .padding(CaptureSpacing.cardPadding)
        .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border, lineWidth: 0.5))
        .captureShadow(.card)
    }

    @ViewBuilder
    private var extractedDataView: some View {
        let pairs = extractedDataPairs
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("EXTRACTED")
                        .font(CaptureFont.monoSection)
                        .tracking(0.5)
                }
                .foregroundStyle(CaptureColors.primary)

                ForEach(pairs.prefix(3), id: \.key) { pair in
                    HStack {
                        Text(pair.key.capitalized)
                            .font(CaptureFont.bodySm)
                            .foregroundStyle(CaptureColors.textTertiary)
                        Spacer()
                        Text(pair.value)
                            .font(CaptureFont.bodySm)
                            .fontWeight(.medium)
                            .foregroundStyle(CaptureColors.text)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(CaptureSpacing.extractedPadding)
            .background(CaptureColors.primaryMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
            .overlay(RoundedRectangle(cornerRadius: CaptureRadius.md).stroke(CaptureColors.primary.opacity(0.05)))
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
    @State private var editedContent: String = ""
    @State private var isSavingContent = false
    @State private var showReanalyzingBanner = false
    @Environment(\.dismiss) private var dismiss

    private var originalContent: String {
        capture.content
            ?? (capture.extractedData["content"] as? String)
            ?? ""
    }

    private var contentHasChanged: Bool {
        editedContent != originalContent
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: CaptureSpacing.lg) {
                if let urlStr = capture.imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            CaptureColors.surface
                            Image(systemName: capture.categoryIcon)
                                .font(.system(size: 40)).foregroundStyle(CaptureColors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: CaptureRadius.xl))
                    .onTapGesture { showFullscreenImage = true }
                }

                VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
                    Text(capture.title)
                        .font(CaptureFont.headingLg)
                        .foregroundStyle(CaptureColors.text)

                    HStack(spacing: CaptureSpacing.sm) {
                        Text(capture.methodLabel)
                            .font(CaptureFont.monoSm)
                            .foregroundStyle(CaptureColors.textTertiary)
                        Text("·").foregroundStyle(CaptureColors.textHint)
                        RelativeTimeText(date: capture.timeCaptured)
                    }

                    if !capture.tags.isEmpty {
                        FlowLayout(spacing: CaptureSpacing.tagGap) {
                            ForEach(capture.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(CaptureFont.monoXs)
                                    .foregroundStyle(CaptureColors.textTertiary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
                            }
                        }
                    }
                }

                if capture.content != nil || capture.captureMethod == "note" {
                    contentSection
                }

                if !capture.extractedData.isEmpty {
                    detailExtractedData
                }

                Spacer(minLength: CaptureSpacing.lg)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                        Text("Delete Capture")
                            .font(CaptureFont.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(CaptureColors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CaptureColors.dangerMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(CaptureSpacing.screenHorizontalFeature)
            .padding(.bottom, CaptureSpacing.xxxl)
        }
        .background(CaptureColors.bg)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .onAppear { editedContent = originalContent }
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

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                Text("CONTENT")
                    .font(CaptureFont.monoSection)
                    .tracking(0.5)
            }
            .foregroundStyle(CaptureColors.textTertiary)

            TextEditor(text: $editedContent)
                .font(CaptureFont.body)
                .foregroundStyle(CaptureColors.text)
                .scrollContentBackground(.hidden)
                .padding(CaptureSpacing.md)
                .frame(minHeight: 100)
                .background(CaptureColors.surface, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: CaptureRadius.md)
                        .stroke(contentHasChanged ? CaptureColors.primary.opacity(0.3) : CaptureColors.border)
                )

            if showReanalyzingBanner {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(CaptureColors.primary)
                    Text("Re-analyzing capture...")
                        .font(CaptureFont.bodySm)
                        .foregroundStyle(CaptureColors.textSecondary)
                }
                .padding(.vertical, 4)
            }

            if contentHasChanged {
                Button {
                    saveContent()
                } label: {
                    HStack(spacing: 6) {
                        if isSavingContent {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                        }
                        Text("Save & Re-analyze")
                            .font(CaptureFont.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CaptureColors.primary, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(isSavingContent)
            }
        }
    }

    private func saveContent() {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        isSavingContent = true
        Task {
            let success = await APIService.shared.updateCaptureContent(
                captureID: capture.id, userID: userID, content: editedContent
            )
            await MainActor.run {
                isSavingContent = false
                if success {
                    showReanalyzingBanner = true
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await captureHistory.loadCaptures()
                        await MainActor.run { showReanalyzingBanner = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailExtractedData: some View {
        let pairs = allExtractedPairs
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("EXTRACTED")
                        .font(CaptureFont.monoSection)
                        .tracking(0.5)
                }
                .foregroundStyle(CaptureColors.primary)

                ForEach(pairs, id: \.key) { pair in
                    HStack {
                        Text(pair.key.capitalized)
                            .font(CaptureFont.bodySm)
                            .foregroundStyle(CaptureColors.textTertiary)
                        Spacer()
                        Text(pair.value)
                            .font(CaptureFont.bodySm)
                            .fontWeight(.medium)
                            .foregroundStyle(CaptureColors.text)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(CaptureSpacing.extractedPadding)
            .background(CaptureColors.primaryMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
            .overlay(RoundedRectangle(cornerRadius: CaptureRadius.md).stroke(CaptureColors.primary.opacity(0.05)))
        }
    }

    private var allExtractedPairs: [(key: String, value: String)] {
        capture.extractedData.compactMap { key, value in
            if key == "tags" || key == "content" { return nil }
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
            HStack(spacing: CaptureSpacing.tagGap) {
                ForEach(result.visible, id: \.self) { tag in
                    Text(tag)
                        .font(CaptureFont.monoXs)
                        .foregroundStyle(CaptureColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
                }
                if result.overflow > 0 {
                    Text("+\(result.overflow)")
                        .font(CaptureFont.monoXs)
                        .foregroundStyle(CaptureColors.textHint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
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
        let font = CaptureFont.uiFont(size: 9.5, weight: .regular)
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
