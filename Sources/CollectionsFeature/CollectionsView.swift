//
//  CollectionsView.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 10/15/22.
//  Copyright © 2022. All rights reserved.
//

import ComposableArchitecture
import SharedModels
import SwiftUI
import TCACoordinators
import TrackingListClient
import Utilities
import ViewComponents

// MARK: - CollectionsView

public struct CollectionsView: View {
    let store: StoreOf<CollectionsReducer>

    public init(store: StoreOf<CollectionsReducer>) {
        self.store = store
    }

    public var body: some View {
        StackNavigation(title: DeviceUtil.isMac ? nil : "My Collections") {
            ScrollView(.vertical, showsIndicators: false) {
                ExtraTopSafeAreaInset()
                Spacer(minLength: 8)

                WithViewStore(
                    store,
                    observe: \.route
                ) { viewStore in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(CollectionsReducer.Route.allCases, id: \.self) { route in
                                ChipView(text: route.text)
                                    .chipBackgroundColor(route == viewStore.state ? route.selectedColor : nil)
                                    .chipOpacity(1.0)
                                    .foregroundColor(.init(white: 1.0))
                                    .font(.system(size: 14, weight: .semibold))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewStore.send(
                                            .binding(.set(\.$route, route)),
                                            animation: .easeInOut(duration: 0.25)
                                        )
                                    }
                            }
                        }
                        .padding(.horizontal)
                        #if os(macOS)
                            .padding(.horizontal, 40)
                        #endif
                    }
                    .padding(.bottom, 8)

                    LazyVStack(spacing: 24) {
                        switch viewStore.state {
                        case .local:
                            WithViewStore(store, observe: \.local) { viewStore in
                                collectionRow(viewStore.favorites)
                                collectionSection(viewStore.collections)
                            }
                        case .anilist:
                            WithViewStore(store, observe: \.anilist) { viewStore in
                                thirdPartyView("AniList", viewStore.state.map(to: \.lists))
                            }
                        case .myanimelist:
                            WithViewStore(store, observe: \.myanimelist) { viewStore in
                                thirdPartyView("MyAnimeList", viewStore.state)
                            }
                        case .kitsu:
                            WithViewStore(store, observe: \.kitsu) { viewStore in
                                thirdPartyView("Kitsu", viewStore.state.map(to: \.collections))
                            }
                        }
                    }
                    .transition(.opacity)
                }

                ExtraBottomSafeAreaInset()
                Spacer(minLength: 32)
            }
        } buttons: {
            Button {
                ViewStore(store).send(.onAddNewCollectionTapped)
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(.white)
                    .font(.title2.bold())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            ViewStore(store).send(.onAppear)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }
}

extension CollectionsView {
    @ViewBuilder
    func thirdPartyView<C: CollectionState>(
        _ name: String,
        _ state: AuthState<[C]>
    ) -> some View where C.C.Index == Int {
        switch state {
        case .unauthenticated:
            Text("Sign in to \(name) to view your collections!")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .authenticating:
            Text("Loading collections from \(name)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .authenticated(value):
            collectionSection(value)
        case .failed:
            Text("Failed to load collections from \(name).")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    func collectionSection<C: CollectionState>(
        _ collections: [C]
    ) -> some View where C.C.Index == Int {
        ForEach(collections, id: \.id) { collection in
            collectionRow(collection)
        }
    }

    @ViewBuilder
    func collectionsPage(
        _ collection: some CollectionState
    ) -> some View {
        ScrollView {
            LazyVGrid(
                columns: .init(
                    repeating: .init(
                        .flexible(),
                        spacing: 16
                    ),
                    count: DeviceUtil.isPhone ? 2 : 6
                )
            ) {
                ForEach(collection.animes) { anime in
                    AnimeItemView(anime: anime)
                        .onTapGesture {
                            if let animeStore = anime as? AnimeStore {
                                ViewStore(store).send(.onAnimeTapped(animeStore.id))
                            }
                        }
                        .contextMenu {
                            if let collection = collection as? CollectionStore,
                               let anime = anime as? AnimeStore {
                                Button("Remove from collection") {
                                    ViewStore(store).send(.remove(anime.id, collection.id))
                                }
                            }
                        }
                }
            }
            .padding([.top, .horizontal])

            ExtraBottomSafeAreaInset()
            Spacer(minLength: 32)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension CollectionsView {
    @ViewBuilder
    func collectionRow<C: CollectionState>(
        _ collection: C
    ) -> some View where C.C.Index == Int {
        DynamicHStackScrollView(
            idealWidth: DeviceUtil.isPhone ? 140 : 190,
            items: collection.animes
        ) { anime in
            AnimeItemView(anime: anime)
                .onTapGesture {
                    if let animeStore = anime as? AnimeStore {
                        ViewStore(store).send(.onAnimeTapped(animeStore.id))
                    }
                }
                .contextMenu {
                    if let collection = collection as? CollectionStore,
                       let anime = anime as? AnimeStore {
                        Button("Remove from collection") {
                            ViewStore(store).send(.remove(anime.id, collection.id))
                        }
                    } else if let collection = collection as? LocalCollection, collection.title == .favorites {
                        Button("Remove from favorites") {
                            ViewStore(store).send(.removeFromFavories(anime.id))
                        }
                    }
                }
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(collection.name)
                            .font(DeviceUtil.isPhone ? .headline : .title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    Text("\(collection.animes.count) ITEM\(collection.animes.isEmpty || collection.animes.count > 1 ? "S" : "")")
                        .foregroundColor(.gray)
                }

                StackNavigationLink(title: collection.name) {
                    Text("View All")
                        .foregroundColor(.secondaryAccent)
                } destination: {
                    collectionsPage(collection)
                }
                .opacity(collection.animes.isEmpty ? 0 : 1.0)
                .disabled(collection.animes.isEmpty)
            }
            .font(DeviceUtil.isPhone ? .footnote.weight(.semibold) : .body.weight(.semibold))
        }
        .emptyItems(placeholder: "Add to this collection via anime details.")
        .contextMenu {
            if let collection = collection as? CollectionStore {
                if collection.title.canDelete {
                    Button("Delete collection") {
                        ViewStore(store).send(.removeCollection(collection.id))
                    }
                }
            }
        }
    }
}

extension CollectionsReducer.Route {
    var selectedColor: Color {
        switch self {
        case .local:
            return .gray.opacity(0.25)
        case .anilist:
            return .init(red: 0.2078, green: 0.4667, blue: 1.0)
        case .myanimelist:
            return .init(red: 0.1803, green: 0.3177, blue: 0.6352)
        case .kitsu:
            return .init(red: 0.969, green: 0.322, blue: 0.224)
        }
    }
}

// MARK: - CollectionsView_Previews

struct CollectionsView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionsView(
            store: .init(
                initialState: .init(),
                reducer: CollectionsReducer()
            )
        )
        .preferredColorScheme(.dark)
    }
}
