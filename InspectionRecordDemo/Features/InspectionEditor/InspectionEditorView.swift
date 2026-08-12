import ComposableArchitecture
import Foundation
import SwiftUI
import UIKit

struct InspectionEditorView: View {
    @Bindable var store: StoreOf<InspectionEditorFeature>
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationStack {
            Form {
                Section("점검 대상") {
                    LabeledContent("대상", value: store.target.name)
                    LabeledContent("장비 번호", value: store.target.equipmentNumber)
                }
                
                Section("위치") {
                    if store.isLocationLoading {
                        Text("위치 확인 중...")
                            .foregroundStyle(.secondary)
                    } else if let latitude = store.latitude,
                              let longitude = store.longitude {
                        LabeledContent("위도", value: String(format: "%.6f", latitude))
                        LabeledContent("경도", value: String(format: "%.6f", longitude))
                        LabeledContent(
                            "주소",
                            value: store.isAddressLoading
                                ? "주소 확인 중..."
                                : (store.address ?? "주소 정보 없음")
                        )
                    } else {
                        Text("위치 정보 없음")
                            .foregroundStyle(.secondary)
                    }
                    
                    if store.mode == .create {
                        Button {
                            store.send(.locationRefreshButtonTapped)
                        } label: {
                            Label("현재 위치 다시 확인", systemImage: "location.fill")
                        }
                        .disabled(store.isLocationLoading)
                    }
                }
                
                InspectionEditorPhotoSection(store: store)
                
                Section("상태") {
                    if store.mode.isEditable {
                        Picker("상태", selection: $store.status) {
                            Text("선택 안 함")
                                .tag(Optional<InspectionStatus>.none)
                            
                            ForEach(InspectionStatus.allCases, id: \.self) { status in
                                Text(status.title)
                                    .tag(Optional<InspectionStatus>.some(status))
                            }
                        }
                    } else {
                        Text(store.status?.title ?? "상태 미지정")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("메모") {
                    if store.mode.isEditable {
                        TextEditor(text: $store.memo)
                            .frame(minHeight: 140)
                    } else if store.memo.isEmpty {
                        Text("메모 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.memo)
                    }
                }
            }
            .navigationTitle(store.mode.navigationTitle)
            .task {
                await store.send(.locationPreparationRequested).finish()
                await store.send(.addressPreparationRequested).finish()
            }
            .alert(
                store.locationPrompt == .permissionDenied ? "위치 권한 필요" : "위치 기록 안내",
                isPresented: Binding(
                    get: {
                        store.locationPrompt != nil
                    },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }
                        
                        if store.locationPrompt == .permissionDenied {
                            store.send(.locationPermissionDeniedDismissed)
                        } else {
                            store.send(.locationIntroductionDismissed)
                        }
                    }
                )
            ) {
                if store.locationPrompt == .permissionDenied {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        store.send(.locationPermissionDeniedDismissed)
                    }
                    Button("확인", role: .cancel) {
                        store.send(.locationPermissionDeniedDismissed)
                    }
                } else {
                    Button("확인") {
                        store.send(.locationIntroductionConfirmed)
                    }
                    Button("나중에", role: .cancel) {
                        store.send(.locationIntroductionDismissed)
                    }
                }
            } message: {
                Text(
                    store.locationPrompt == .permissionDenied
                    ? "위치 권한이 거부되어 점검 당시 위치를 기록할 수 없습니다. 위치 정보를 기록하려면 설정에서 권한을 허용해주세요."
                    : "점검 당시 위치를 자동으로 기록합니다. 위치 권한을 허용하면 점검 저장 시 위도와 경도를 함께 보관할 수 있습니다."
                )
            }
            .toolbar {
                if store.mode.isEditable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            store.send(.cancelButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            store.send(.saveButtonTapped)
                        }
                        .disabled(store.isSaving)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            store.send(.closeButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("수정") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { store.isCameraPresented },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }
                        
                        store.send(.cameraDismissed)
                    }
                )
            ) {
                SystemCameraView(
                    onImagePicked: { image in
                        guard let data = InspectionPhotoDataNormalizer.normalizedData(from: image) else {
                            store.send(.photoLoadingFailed)
                            return
                        }
                        
                        store.send(.cameraImageCaptured(data))
                    },
                    onCancel: {
                        store.send(.cameraDismissed)
                    }
                )
                .ignoresSafeArea()
            }
            .alert(
                store.cameraError?.title ?? "카메라 오류",
                isPresented: Binding(
                    get: { store.cameraError != nil },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }
                        
                        store.send(.cameraErrorDismissed)
                    }
                )
            ) {
                if store.cameraError?.canOpenSettings == true {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        store.send(.cameraErrorDismissed)
                    }
                }
                
                Button("확인", role: .cancel) {
                    store.send(.cameraErrorDismissed)
                }
            } message: {
                Text(store.cameraError?.message ?? "카메라를 사용할 수 없습니다.")
            }
        }
    }
}
