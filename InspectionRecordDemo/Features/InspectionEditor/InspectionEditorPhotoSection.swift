import ComposableArchitecture
import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct InspectionEditorPhotoSection: View {
    @Bindable var store: StoreOf<InspectionEditorFeature>
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Section("사진") {
            if let photoData = store.photoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("사진 없음")
                    .foregroundStyle(.secondary)
            }

            photoActionButtons

            if let photoErrorMessage = store.photoErrorMessage {
                Text(photoErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var photoActionButtons: some View {
        switch store.mode {
        case .create:
            HStack(spacing: 8) {
                cameraButton(title: "촬영")
                photoLibraryButton(title: "선택")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

        case .editing:
            let isPhotoMissing = store.photoData == nil

            HStack(spacing: 8) {
                cameraButton(title: "촬영")
                photoLibraryButton(title: "선택")
                Button(role: .destructive) {
                    store.send(.deletePhotoButtonTapped)
                } label: {
                    Label("삭제", systemImage: "trash")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isPhotoMissing ? Color.secondary.opacity(0.75) : Color.red)
                        .frame(maxWidth: .infinity)
                }
                .tint(isPhotoMissing ? Color.secondary.opacity(0.75) : Color.red)
                .disabled(isPhotoMissing)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

        case .view:
            EmptyView()
        }
    }

    private func cameraButton(title: String) -> some View {
        Button {
            store.send(.cameraButtonTapped)
        } label: {
            Label(title, systemImage: "camera")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func photoLibraryButton(title: String) -> some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else {
                return
            }

            Task { @MainActor in
                defer {
                    selectedPhoto = nil
                }

                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let normalizedData = InspectionPhotoDataNormalizer.normalizedData(from: data)
                    else {
                        store.send(.photoLoadingFailed)
                        return
                    }

                    store.send(.photoDataLoaded(normalizedData))
                } catch {
                    store.send(.photoLoadingFailed)
                }
            }
        }
    }
}
