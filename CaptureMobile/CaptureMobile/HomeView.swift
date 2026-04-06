//
//  HomeView.swift
//  CaptureMobile
//

import SwiftUI
import Combine
import PostHog

struct HomeView: View {
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @ObservedObject var processingState = CaptureProcessingState.shared
    @State private var selectedCategory: String = "all"
    @State private var timeRefreshTrigger = Date()

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let categories = ["all", "restaurant", "event", "movie", "book", "clothing", "note", "other"]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerView
                    categoryTabs

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
                        .id(timeRefreshTrigger)
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .onReceive(refreshTimer) { _ in timeRefreshTrigger = Date() }
        .onAppear {
            processingState.checkForFailure()
            Task { await captureHistory.loadCaptures(category: selectedCategory) }
        }
        .preferredColorScheme(.light)
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

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                        Task { await captureHistory.loadCaptures(category: cat) }
                    } label: {
                        Text(cat == "all" ? "all" : cat + "s")
                            .font(.system(size: 14, weight: selectedCategory == cat ? .semibold : .regular))
                            .foregroundStyle(selectedCategory == cat ? .black : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == cat
                                    ? Color(red: 0.95, green: 0.91, blue: 0.88)
                                    : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
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
                CaptureCardView(capture: capture)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Capture Card

struct CaptureCardView: View {
    let capture: Capture

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Image thumbnail
            AsyncImage(url: URL(string: capture.imageUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Color(red: 0.96, green: 0.96, blue: 0.96)
                        Image(systemName: capture.categoryIcon)
                            .font(.system(size: 22)).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 90, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Meta row
                HStack(spacing: 4) {
                    Text(capture.methodLabel)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("iPhone").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(capture.capturedAgo)
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                }

                // Title
                Text(capture.title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)

                // Extracted data card
                if !capture.extractedData.isEmpty {
                    extractedDataView
                }

                // Category tag
                Text(capture.category)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6), in: Capsule())
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
            .background(Color(red: 0.98, green: 0.96, blue: 0.94), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var extractedDataPairs: [(key: String, value: String)] {
        capture.extractedData.compactMap { key, value in
            let str = "\(value)"
            guard !str.isEmpty, str != "<null>", str.count < 100 else { return nil }
            return (key: key, value: str)
        }
        .sorted { $0.key < $1.key }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
