//
//  BottomSafeAreaInset+View.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 10/19/22.
//  From https://github.com/FiveStarsBlog/CodeSamples/blob/main/SafeAreaInset/content.swift

import SwiftUI

public extension View {
    @ViewBuilder
    func bottomSafeAreaInset(
        _ overlayContent: some View
    ) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.safeAreaInset(edge: .bottom, spacing: 0) { overlayContent }
        } else {
            modifier(BottomInsetViewModifier(overlayContent: overlayContent))
        }
    }

    @ViewBuilder
    func topSafeAreaInset(
        _ overlayContent: some View
    ) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.safeAreaInset(edge: .top, spacing: 0) { overlayContent }
        } else {
            modifier(TopInsetViewModifier(overlayContent: overlayContent))
        }
    }
}

public extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Spacer()
                    .preference(
                        key: FramePreferenceKey.self,
                        value: geometryProxy.size
                    )
            }
        )
        .onPreferenceChange(FramePreferenceKey.self, perform: onChange)
    }
}

// MARK: - FramePreferenceKey

private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value _: inout CGSize, nextValue _: () -> CGSize) {}
}

// MARK: - BottomInsetViewModifier

struct BottomInsetViewModifier<OverlayContent: View>: ViewModifier {
    @Environment(\.bottomSafeAreaInset)
    var ancestorBottomSafeAreaInset: CGFloat
    var overlayContent: OverlayContent
    @State
    var overlayContentHeight: CGFloat = 0

    func body(content: Self.Content) -> some View {
        content
            .environment(\.bottomSafeAreaInset, overlayContentHeight + ancestorBottomSafeAreaInset)
            .overlay(
                overlayContent
                    .readSize { size in
                        overlayContentHeight = size.height
                    }
                    .padding(.bottom, ancestorBottomSafeAreaInset),

                alignment: .bottom
            )
    }
}

// MARK: - TopInsetViewModifier

struct TopInsetViewModifier<OverlayContent: View>: ViewModifier {
    @Environment(\.topSafeAreaInset)
    var ancestorTopSafeAreaInset: CGFloat
    var overlayContent: OverlayContent
    @State
    var overlayContentHeight: CGFloat = 0

    func body(content: Self.Content) -> some View {
        content
            .environment(\.topSafeAreaInset, overlayContentHeight + ancestorTopSafeAreaInset)
            .overlay(
                overlayContent
                    .readSize { size in
                        overlayContentHeight = size.height
                    }
                    .padding(.bottom, ancestorTopSafeAreaInset),

                alignment: .top
            )
    }
}

// MARK: - TopSafeAreaInsetKey

struct TopSafeAreaInsetKey: EnvironmentKey {
    static var defaultValue: CGFloat = .zero
}

// MARK: - BottomSafeAreaInsetKey

struct BottomSafeAreaInsetKey: EnvironmentKey {
    static var defaultValue: CGFloat = .zero
}

extension EnvironmentValues {
    var bottomSafeAreaInset: CGFloat {
        get { self[BottomSafeAreaInsetKey.self] }
        set { self[BottomSafeAreaInsetKey.self] = newValue }
    }

    var topSafeAreaInset: CGFloat {
        get { self[TopSafeAreaInsetKey.self] }
        set { self[TopSafeAreaInsetKey.self] = newValue }
    }
}

// MARK: - ExtraTopSafeAreaInset

public struct ExtraTopSafeAreaInset: View {
    @Environment(\.topSafeAreaInset)
    var topSafeAreaInset: CGFloat

    public init() {}

    public var body: some View {
        Spacer(minLength: topSafeAreaInset)
    }
}

// MARK: - ExtraBottomSafeAreaInset

public struct ExtraBottomSafeAreaInset: View {
    @Environment(\.bottomSafeAreaInset)
    var bottomSafeAreaInset: CGFloat

    public init() {}

    public var body: some View {
        Spacer(minLength: bottomSafeAreaInset)
    }
}
