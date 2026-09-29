//
//  ContentView.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Modos de visualización del lienzo principal.
enum ViewMode: String, CaseIterable, Identifiable {
    /// Modo interactivo con cajas de detección resaltadas.
    case detections = "detections"
    /// Vista previa en tiempo real de la imagen con la redacción aplicada.
    case redactedPreview = "redactedPreview"

    var id: String { rawValue }

    func title(for strings: AppStrings) -> String {
        switch self {
        case .detections: return strings.viewModeDetections
        case .redactedPreview: return strings.viewModeRedacted
        }
    }
}

/// Vista principal de la interfaz de usuario de PrivaLock conforme a las guías de diseño de Apple (HIG).
struct ContentView: View {
    // MARK: - Contador de Archivos Exportados (Persistente)
    @AppStorage("privalock_export_counter") private var exportCounter: Int = 1

    // MARK: - Tamaño de Letra e Idioma Configurables
    @AppStorage("privalock_font_size") private var appFontSize: Double = 14.0
    @AppStorage("privalock_language") private var appLanguage: String = "es"

    // MARK: - Modo Privado vs Modo Normal (Persistente)
    @AppStorage("privalock_is_private_mode") private var isPrivateMode: Bool = false

    @State private var isSettingsSheetPresented: Bool = false
    @State private var loadedFileSizeBytes: Int64 = 0

    private var strings: AppStrings {
        AppStrings(lang: appLanguage)
    }

    // MARK: - Interruptores Interactivos de Características de Protección
    @State private var isDetectFacesEnabled: Bool = true
    @State private var isDetectTextEnabled: Bool = true
    @State private var isDetectBarcodesEnabled: Bool = true
    @State private var isStripEXIFEnabled: Bool = true
    @State private var isDestructiveFlattenEnabled: Bool = true

    // MARK: - Estado de Zoom, Desplazamiento (Pan) y Centrado del Lienzo
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero

    // MARK: - Estado de Medios e Importación
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented: Bool = false
    @State private var isDocumentPickerPresented: Bool = false
    @State private var loadedImage: PlatformImage?
    @State private var customExportFileName: String = ""
    @State private var isLoadingMedia: Bool = false
    @State private var isAnalyzingVision: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // MARK: - Estado de Detección y Redacción
    @State private var detectedRegions: [DetectedPrivacyRegion] = []
    @State private var undoStack: [[DetectedPrivacyRegion]] = []
    @State private var redoStack: [[DetectedPrivacyRegion]] = []
    @State private var selectedRedactionStyle: RedactionStyle = .blackBar
    @State private var currentViewMode: ViewMode = .redactedPreview
    @State private var redactedImage: PlatformImage?
    @State private var isSavingImage: Bool = false
    @State private var isManualDrawingActive: Bool = false

    private let privacyDetector = PrivacyDetector()
    private let redactionEngine = RedactionEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Banner de Privacidad On-Device
                    PrivacyBannerView(strings: strings, fontSize: appFontSize)

                    // MARK: - Lienzo Principal y Controles de Medios
                    if let loadedImage {
                        VStack(spacing: 18) {
                            // Barra de Nombre de Archivo Personalizable y Contador
                            HStack(spacing: 10) {
                                Image(systemName: "pencil.line")
                                    .foregroundStyle(.tint)
                                
                                Text(strings.fileNameLabel)
                                    .font(.system(size: appFontSize, weight: .medium))
                                    .foregroundStyle(.secondary)

                                TextField(strings.fileNamePlaceholder, text: $customExportFileName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: appFontSize))

                                Text(".jpg")
                                    .font(.system(size: appFontSize))
                                    .foregroundStyle(.secondary)

                                Button(role: .destructive) {
                                    clearSelectedMedia()
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 4)

                            // Toolbar de Modos, Dibujo Manual y Estilo Global (Adaptable y Responsiva)
                            VStack(spacing: 12) {
                                Picker("Modo de Vista", selection: $currentViewMode) {
                                    ForEach(ViewMode.allCases) { mode in
                                        Text(mode.title(for: strings)).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                ViewThatFits(in: .horizontal) {
                                    // Modo horizontal para pantallas amplias (Mac, iPad, Landscape)
                                    HStack(spacing: 14) {
                                        Button {
                                            isManualDrawingActive.toggle()
                                        } label: {
                                            Label(
                                                isManualDrawingActive ? strings.cancelDrawingButton : strings.drawBoxButton,
                                                systemImage: isManualDrawingActive ? "xmark.circle.fill" : "hand.draw.fill"
                                            )
                                            .font(.system(size: appFontSize, weight: .semibold))
                                            .lineLimit(1)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(isManualDrawingActive ? .orange : .blue)

                                        Spacer()

                                        HStack(spacing: 8) {
                                            Text(strings.globalStyleLabel)
                                                .font(.system(size: appFontSize))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            
                                            Picker("Estilo", selection: $selectedRedactionStyle) {
                                                ForEach(RedactionStyle.allCases) { style in
                                                    Label(style.rawValue, systemImage: style.iconName).tag(style)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        }
                                    }

                                    // Modo compacto para pantallas móviles angostas (iPhone SE)
                                    HStack(spacing: 8) {
                                        Button {
                                            isManualDrawingActive.toggle()
                                        } label: {
                                            Label(
                                                isManualDrawingActive ? strings.cancelDrawingButton : strings.drawBoxButton,
                                                systemImage: isManualDrawingActive ? "xmark.circle.fill" : "hand.draw.fill"
                                            )
                                            .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(isManualDrawingActive ? .orange : .blue)

                                        Spacer()

                                        // Botones de Deshacer y Rehacer (Undo / Redo)
                                        HStack(spacing: 4) {
                                            Button {
                                                undoLastAction()
                                            } label: {
                                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                                    .font(.system(size: 18))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(undoStack.isEmpty ? Color.secondary.opacity(0.3) : Color.blue)
                                            .disabled(undoStack.isEmpty)
                                            .help(strings.undoButton)

                                            Button {
                                                redoLastAction()
                                            } label: {
                                                Image(systemName: "arrow.uturn.forward.circle.fill")
                                                    .font(.system(size: 18))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(redoStack.isEmpty ? Color.secondary.opacity(0.3) : Color.blue)
                                            .disabled(redoStack.isEmpty)
                                            .help(strings.redoButton)
                                        }

                                        Picker("", selection: $selectedRedactionStyle) {
                                            ForEach(RedactionStyle.allCases) { style in
                                                Label(style.rawValue, systemImage: style.iconName).tag(style)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                            }

                            // MARK: - Lienzo Fotográfico Centrado con Desplazamiento y Zoom
                            VStack(spacing: 12) {
                                PrivaLockCanvasContainer(
                                    loadedImage: loadedImage,
                                    redactedImage: redactedImage,
                                    currentViewMode: currentViewMode,
                                    detectedRegions: $detectedRegions,
                                    selectedRedactionStyle: selectedRedactionStyle,
                                    isManualDrawingActive: isManualDrawingActive,
                                    isAnalyzingVision: isAnalyzingVision,
                                    zoomScale: $zoomScale,
                                    panOffset: panOffset,
                                    dragTranslation: $dragTranslation,
                                    strings: strings,
                                    fontSize: appFontSize,
                                    onAddManualRegion: { rect in
                                        addManualRegion(rect)
                                    },
                                    onDragEnded: { translation in
                                        panOffset.width += translation.width
                                        panOffset.height += translation.height
                                        dragTranslation = .zero
                                    }
                                )

                                FloatingZoomBar(
                                    zoomScale: $zoomScale,
                                    panOffset: $panOffset,
                                    dragTranslation: $dragTranslation,
                                    strings: strings,
                                    fontSize: appFontSize
                                )
                            }

                            // Panel de Resumen de Análisis Vision
                            if !isAnalyzingVision && !detectedRegions.isEmpty {
                                VisionSummaryPanel(
                                    detectedRegions: $detectedRegions,
                                    strings: strings,
                                    fontSize: appFontSize,
                                    onToggleCategory: { category in
                                        toggleCategory(category)
                                    }
                                )
                            }

                            // Botón de Guardado Principal
                            Button {
                                saveProtectedImage()
                            } label: {
                                HStack(spacing: 8) {
                                    if isSavingImage {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "square.and.arrow.down.fill")
                                    }
                                    Text(strings.saveProtectedButton)
                                        .font(.system(size: appFontSize + 2, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isSavingImage || isAnalyzingVision)

                            // Botones de Compartir, Imprimir, Copiar y Cambiar Foto
                            VStack(spacing: 12) {
                                // Fila 1: Compartir e Imprimir
                                HStack(spacing: 12) {
                                    Button {
                                        shareProtectedImage()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "square.and.arrow.up.fill")
                                            Text(strings.shareButton)
                                                .font(.system(size: appFontSize, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .help(strings.shareHelp)
                                    .disabled(isSavingImage || isAnalyzingVision)

                                    Button {
                                        printProtectedImage()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "printer.fill")
                                            Text(strings.printButton)
                                                .font(.system(size: appFontSize, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.bordered)
                                    .help(strings.printHelp)
                                    .disabled(isSavingImage || isAnalyzingVision)
                                }

                                // Fila 2: Copiar al Portapapeles y Cambiar Foto
                                HStack(spacing: 12) {
                                    Button {
                                        copyProtectedImageToClipboard()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "doc.on.doc.fill")
                                            Text(strings.copyClipboardButton)
                                                .font(.system(size: appFontSize, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isSavingImage || isAnalyzingVision)

                                    Button {
                                        clearSelectedMedia()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "photo.badge.plus")
                                            Text(strings.changePhotoButton)
                                                .font(.system(size: appFontSize, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            // Mensajes de Alerta y Notificación
                            if let successMessage {
                                BannerNotificationView(message: successMessage, type: .success) {
                                    self.successMessage = nil
                                }
                            }
                            if let errorMessage {
                                BannerNotificationView(message: errorMessage, type: .error) {
                                    self.errorMessage = nil
                                }
                            }
                        }
                    } else {
                        // MARK: - Estado Vacío (Selector de Fotos y Documentos)
                        EmptyStateMediaPicker(
                            isPhotoPickerPresented: $isPhotoPickerPresented,
                            isDocumentPickerPresented: $isDocumentPickerPresented,
                            isLoadingMedia: isLoadingMedia,
                            strings: strings,
                            fontSize: appFontSize
                        )
                    }

                    // MARK: - Lista Interactiva de Características de Protección
                    SecurityFeaturesListView(
                        isDetectFacesEnabled: $isDetectFacesEnabled,
                        isDetectTextEnabled: $isDetectTextEnabled,
                        isDetectBarcodesEnabled: $isDetectBarcodesEnabled,
                        isStripEXIFEnabled: $isStripEXIFEnabled,
                        isDestructiveFlattenEnabled: $isDestructiveFlattenEnabled,
                        strings: strings,
                        fontSize: appFontSize
                    )
                }
                .padding()
            }
            .navigationTitle("PrivaLock")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        // Indicador / Botón de Modo Privado vs Modo Normal
                        Button {
                            isSettingsSheetPresented = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isPrivateMode ? "eye.slash.fill" : "shield.lefthalf.filled")
                                Text(isPrivateMode ? strings.privateModeBadge : strings.normalModeBadge)
                                    .font(.system(size: max(11, appFontSize - 3), weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isPrivateMode ? Color.purple.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(isPrivateMode ? Color.purple : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help(isPrivateMode ? strings.privateModeSubtitle : strings.auditHistoryTitle)

                        // Botón de Ajustes (Engranaje)
                        Button {
                            isSettingsSheetPresented = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.body)
                        }
                        .help(strings.settingsTitle)
                    }
                }
            }
            .sheet(isPresented: $isSettingsSheetPresented) {
                PrivaLockSettingsSheet(
                    fontSize: $appFontSize,
                    appLanguage: $appLanguage,
                    isPrivateMode: $isPrivateMode,
                    strings: strings
                )
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .fileImporter(
                isPresented: $isDocumentPickerPresented,
                allowedContentTypes: [.pdf, .png, .jpeg, .tiff],
                allowsMultipleSelection: false
            ) { result in
                handleDocumentSelection(result)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
            .onChange(of: selectedRedactionStyle) { _, _ in
                updateRedactedImage()
            }
            .onChange(of: isDetectFacesEnabled) { _, _ in reanalyzeImage() }
            .onChange(of: isDetectTextEnabled) { _, _ in reanalyzeImage() }
            .onChange(of: isDetectBarcodesEnabled) { _, _ in reanalyzeImage() }
        }
    }

    // MARK: - Manejo y Carga de Medios

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingMedia = true
        errorMessage = nil

        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = PlatformImage(data: data) {
                    await MainActor.run {
                        self.loadedFileSizeBytes = Int64(data.count)
                        self.loadedImage = image
                        let autoName = String(format: "PrivaLock-Protegido-%04d", exportCounter)
                        self.customExportFileName = autoName
                        self.isLoadingMedia = false
                        self.selectedPhotoItem = nil
                        self.resetCanvasTransform()
                        self.analyzeLoadedImage(image)
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingMedia = false
                        self.selectedPhotoItem = nil
                        self.errorMessage = "No se pudo decodificar el archivo seleccionado."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMedia = false
                    self.selectedPhotoItem = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleDocumentSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let selectedURL = urls.first else { return }

            guard selectedURL.startAccessingSecurityScopedResource() else {
                errorMessage = "Permiso denegado para acceder al documento."
                return
            }
            defer { selectedURL.stopAccessingSecurityScopedResource() }

            isLoadingMedia = true
            errorMessage = nil

            if let optimizedImage = HighResolutionManager.shared.loadOptimizedImage(from: selectedURL) {
                let resources = try? selectedURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resources?.fileSize ?? 0)

                self.loadedFileSizeBytes = fileSize
                self.loadedImage = optimizedImage
                let baseName = selectedURL.deletingPathExtension().lastPathComponent
                self.customExportFileName = "\(baseName)-Protegido"
                self.isLoadingMedia = false
                self.resetCanvasTransform()
                self.analyzeLoadedImage(optimizedImage)
            } else {
                isLoadingMedia = false
                errorMessage = "No se pudo cargar el archivo o documento seleccionado."
            }
        } catch {
            isLoadingMedia = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pipeline de Detección e Inferencia

    private func analyzeLoadedImage(_ image: PlatformImage) {
        isAnalyzingVision = true
        detectedRegions.removeAll()

        Task {
            do {
                let regions = try await privacyDetector.detectPrivacyRegions(
                    in: image,
                    detectFaces: isDetectFacesEnabled,
                    detectText: isDetectTextEnabled,
                    detectBarcodes: isDetectBarcodesEnabled
                )

                await MainActor.run {
                    self.detectedRegions = regions
                    self.undoStack.removeAll()
                    self.redoStack.removeAll()
                    self.isAnalyzingVision = false
                    self.updateRedactedImage()
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzingVision = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func reanalyzeImage() {
        guard let loadedImage else { return }
        analyzeLoadedImage(loadedImage)
    }

    private func updateRedactedImage() {
        guard let loadedImage else { return }

        let activeRegions = detectedRegions.filter { $0.isEnabled }

        guard !activeRegions.isEmpty else {
            redactedImage = loadedImage
            return
        }

        let result = redactionEngine.redactImage(
            loadedImage,
            regions: activeRegions,
            style: selectedRedactionStyle,
            isDestructiveFlatten: isDestructiveFlattenEnabled
        )

        redactedImage = result
    }

    // MARK: - Historial Deshacer / Rehacer (Undo / Redo)

    private func recordUndoState() {
        undoStack.append(detectedRegions)
        if undoStack.count > 25 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func undoLastAction() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(detectedRegions)
        detectedRegions = previous
        HapticManager.impact(.light)
        updateRedactedImage()
    }

    private func redoLastAction() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(detectedRegions)
        detectedRegions = next
        HapticManager.impact(.light)
        updateRedactedImage()
    }

    // MARK: - Dibujo Manual e Interacción

    private func addManualRegion(_ normalizedRect: CGRect) {
        recordUndoState()
        let newRegion = DetectedPrivacyRegion(
            type: .manual,
            category: .generalText,
            boundingBox: normalizedRect,
            label: "Manual",
            isEnabled: true,
            customStyle: selectedRedactionStyle
        )
        detectedRegions.append(newRegion)
        updateRedactedImage()
    }

    private func toggleCategory(_ category: SensitiveDataCategory) {
        let matching = detectedRegions.filter { $0.category == category }
        guard !matching.isEmpty else { return }
        recordUndoState()

        let shouldEnable = !matching.allSatisfy { $0.isEnabled }
        for index in detectedRegions.indices where detectedRegions[index].category == category {
            detectedRegions[index].isEnabled = shouldEnable
        }
        updateRedactedImage()
    }

    // MARK: - Exportación, Compartir e Impresión

    private func shareProtectedImage() {
        guard let finalImage = redactedImage ?? loadedImage else { return }
        let resolvedFileName = ExportManager.sanitizeFileName(customExportFileName)

        ExportManager.shareImage(finalImage, fileName: resolvedFileName)

        let activeCount = detectedRegions.filter { $0.isEnabled }.count
        SecurityAuditManager.shared.recordOperation(
            fileName: resolvedFileName,
            fileType: "JPG",
            fileSizeBytes: loadedFileSizeBytes,
            redactedCount: activeCount,
            isPrivateMode: isPrivateMode
        )
    }

    private func printProtectedImage() {
        guard let finalImage = redactedImage ?? loadedImage else { return }
        ExportManager.printImage(finalImage)
    }

    private func saveProtectedImage() {
        guard let finalImage = redactedImage ?? loadedImage else { return }

        isSavingImage = true
        errorMessage = nil
        successMessage = nil

        let resolvedFileName = ExportManager.sanitizeFileName(customExportFileName)

        Task {
            do {
                let resultMessage = try await ExportManager.saveRedactedImage(
                    finalImage,
                    defaultFileName: resolvedFileName,
                    stripEXIF: isStripEXIFEnabled
                )

                await MainActor.run {
                    self.isSavingImage = false
                    self.successMessage = resultMessage
                    self.exportCounter += 1

                    let activeCount = self.detectedRegions.filter { $0.isEnabled }.count
                    SecurityAuditManager.shared.recordOperation(
                        fileName: resolvedFileName,
                        fileType: "JPG",
                        fileSizeBytes: self.loadedFileSizeBytes,
                        redactedCount: activeCount,
                        isPrivateMode: self.isPrivateMode
                    )
                }
            } catch {
                await MainActor.run {
                    self.isSavingImage = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func copyProtectedImageToClipboard() {
        guard let finalImage = redactedImage ?? loadedImage else { return }
        let success = ExportManager.copyToClipboard(finalImage)
        if success {
            successMessage = strings.copySuccess
        } else {
            errorMessage = strings.copyError
        }
    }

    private func resetCanvasTransform() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
            dragTranslation = .zero
        }
    }

    private func clearSelectedMedia() {
        selectedPhotoItem = nil
        loadedImage = nil
        redactedImage = nil
        detectedRegions.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        customExportFileName = ""
        errorMessage = nil
        successMessage = nil
        zoomScale = 1.0
        panOffset = .zero
        dragTranslation = .zero
        loadedFileSizeBytes = 0
    }
}

// MARK: - Contenedor del Lienzo Fotográfico Desplazable y Zoom

struct PrivaLockCanvasContainer: View {
    let loadedImage: PlatformImage
    let redactedImage: PlatformImage?
    let currentViewMode: ViewMode
    @Binding var detectedRegions: [DetectedPrivacyRegion]
    let selectedRedactionStyle: RedactionStyle
    let isManualDrawingActive: Bool
    let isAnalyzingVision: Bool
    @Binding var zoomScale: CGFloat
    let panOffset: CGSize
    @Binding var dragTranslation: CGSize
    let strings: AppStrings
    let fontSize: Double
    let onAddManualRegion: (CGRect) -> Void
    let onDragEnded: (CGSize) -> Void

    // Gesto de magnificación con dos dedos en iPhone (Pinch-to-zoom)
    @GestureState private var gestureScale: CGFloat = 1.0

    // Detección de puntero sobre el lienzo en macOS para rueda del ratón (Mouse Wheel)
    @State private var isHoveringCanvas: Bool = false

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    @State private var mouseWheelMonitor: Any?
    #endif

    #if os(macOS)
    private let canvasHeight: CGFloat = 430
    #else
    private let canvasHeight: CGFloat = 350
    #endif

    private var effectiveZoomScale: CGFloat {
        max(0.5, min(zoomScale * gestureScale, 5.0))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.12))
                .frame(height: canvasHeight)

            Group {
                if currentViewMode == .redactedPreview, let redactedImage {
                    Image(platformImage: redactedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: canvasHeight)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .overlay {
                            InteractiveRegionOverlayView(
                                regions: $detectedRegions,
                                globalStyle: selectedRedactionStyle,
                                isManualDrawingActive: isManualDrawingActive,
                                onAddManualRegion: onAddManualRegion
                            )
                        }
                } else {
                    Image(platformImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: canvasHeight)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .overlay {
                            InteractiveRegionOverlayView(
                                regions: $detectedRegions,
                                globalStyle: selectedRedactionStyle,
                                isManualDrawingActive: isManualDrawingActive,
                                onAddManualRegion: onAddManualRegion
                            )
                        }
                }
            }
            .offset(
                x: panOffset.width + dragTranslation.width,
                y: panOffset.height + dragTranslation.height
            )
            .scaleEffect(effectiveZoomScale)
            .blur(radius: isAnalyzingVision ? 12 : 0)
            .opacity(isAnalyzingVision ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.45), value: isAnalyzingVision)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: zoomScale)
            .gesture(
                isManualDrawingActive ? nil :
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            dragTranslation = value.translation
                        }
                        .onEnded { value in
                            onDragEnded(value.translation)
                        },
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            let newScale = zoomScale * value
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoomScale = max(0.5, min(newScale, 5.0))
                            }
                        }
                )
            )

            if isAnalyzingVision {
                AnalyzingOverlayView(strings: strings, fontSize: fontSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: canvasHeight, alignment: .center)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering in
            isHoveringCanvas = hovering
        }
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        .onAppear {
            setupMouseWheelMonitor()
        }
        .onDisappear {
            removeMouseWheelMonitor()
        }
        #endif
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private func setupMouseWheelMonitor() {
        guard mouseWheelMonitor == nil else { return }
        mouseWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHoveringCanvas, !isManualDrawingActive else { return event }
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.05 {
                let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.04
                let newScale = zoomScale + (delta * sensitivity)
                zoomScale = max(0.5, min(newScale, 5.0))
                return nil
            }
            return event
        }
    }

    private func removeMouseWheelMonitor() {
        if let monitor = mouseWheelMonitor {
            NSEvent.removeMonitor(monitor)
            mouseWheelMonitor = nil
        }
    }
    #endif
}

/// Barra flotante con controles de Zoom y botón de centrado automático.
struct FloatingZoomBar: View {
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var dragTranslation: CGSize
    let strings: AppStrings
    let fontSize: Double

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    zoomScale = max(0.5, zoomScale - 0.25)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale <= 0.5)
            .help(strings.zoomOutHelp)

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: fontSize - 2, weight: .semibold))
                .monospacedDigit()
                .frame(width: 52)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    zoomScale = min(5.0, zoomScale + 0.25)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale >= 5.0)
            .help(strings.zoomInHelp)

            Divider()
                .frame(height: 14)

            // Botón de Centrado: restablece posición a (0,0) y escala a 1.0
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    zoomScale = 1.0
                    panOffset = .zero
                    dragTranslation = .zero
                }
            } label: {
                Label(strings.centerButton, systemImage: "arrow.counterclockwise")
                    .font(.system(size: fontSize - 2, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(strings.centerHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Subvistas Auxiliares

/// Sheet de Ajustes de la Aplicación (Settings) con Modo Privado, Historial de Operaciones y Seguridad.
struct PrivaLockSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var appLanguage: String
    @Binding var isPrivateMode: Bool
    let strings: AppStrings

    @Environment(\.dismiss) private var dismiss
    @State private var auditLogs: [AuditLogEntry] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Sección 1: Selector de Modo (Normal vs Privado)
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $isPrivateMode) {
                            HStack(spacing: 8) {
                                Image(systemName: isPrivateMode ? "eye.slash.fill" : "clock.arrow.circlepath")
                                    .foregroundStyle(isPrivateMode ? .purple : .blue)
                                Text(isPrivateMode ? strings.privateModeTitle : strings.normalModeBadge)
                                    .font(.headline)
                            }
                        }
                        .toggleStyle(.switch)

                        Text(isPrivateMode ? strings.privateModeSubtitle : "Modo Normal ACTIVO: Los metadatos operativos (tipo, peso, hora, zonas protegidas) se guardan localmente para tu control. Nunca se almacenan fotos ni datos reales.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    // Sección 2: Historial Forense Local de Operaciones
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundStyle(.blue)
                            Text(strings.auditHistoryTitle)
                                .font(.headline)
                            Spacer()

                            if !auditLogs.isEmpty {
                                Button(role: .destructive) {
                                    SecurityAuditManager.shared.clearAllLogs()
                                    auditLogs = []
                                } label: {
                                    Label(strings.clearHistoryButton, systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if auditLogs.isEmpty {
                            Text(strings.auditHistoryEmpty)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(auditLogs.prefix(5)) { log in
                                    HStack(spacing: 12) {
                                        Image(systemName: log.fileType == "PDF" ? "doc.fill" : "photo.fill")
                                            .foregroundStyle(log.fileType == "PDF" ? .red : .blue)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(log.fileName)
                                                .font(.caption)
                                                .bold()
                                                .lineLimit(1)
                                            Text("\(log.fileSizeFormatted) • \(log.timestamp.formatted(date: .numeric, time: .shortened))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 3) {
                                            Text("\(log.redactedCount)")
                                                .font(.caption2)
                                                .bold()
                                            Image(systemName: "shield.checkered")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    // Sección 3: Blindaje de Seguridad y Anti-Tracking
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "shield.badge.checkmark.fill")
                                .foregroundStyle(.green)
                            Text(strings.auditSecurityBlindage)
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(strings.auditSQLInjectionProtected)
                                    .font(.caption)
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(strings.auditNoTrackingInfo)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    // Sección 4: Selector de Idioma
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            Text(strings.settingsLanguageSection)
                                .font(.headline)
                        }

                        Picker("Idioma", selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.title).tag(lang.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    // Sección 5: Tipografía y Accesibilidad Dinámica
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "textformat.size")
                                .foregroundStyle(.purple)
                            Text(strings.settingsTypographySection)
                                .font(.headline)
                        }

                        HStack {
                            Text("Aa")
                                .font(.system(size: 11, weight: .bold))
                            Slider(value: $fontSize, in: 11...20, step: 1)
                            Text("Aa")
                                .font(.system(size: 20, weight: .bold))
                        }

                        HStack {
                            Text("Mín: 11 pt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(strings.settingsResetFont) {
                                fontSize = 14.0
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tint)
                            Spacer()
                            Text("Máx: 20 pt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    // Sección 6: Vista Previa en Vivo
                    VStack(alignment: .leading, spacing: 6) {
                        Text(strings.settingsPreviewLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(strings.settingsPreviewSample)
                            .font(.system(size: fontSize))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Sección 7: Auditoría de Rendimiento & Memoria
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "gauge.with.needle.fill")
                                .foregroundStyle(.green)
                            Text(appLanguage == "en" ? "Performance & RAM Audit" : "Auditoría de Rendimiento & RAM")
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Text(String(format: "%.1f MB RAM", HighResolutionManager.shared.currentResidentMemoryMB()))
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }

                        HStack(spacing: 8) {
                            Label(
                                appLanguage == "en" ? "ImageIO 48MP+" : "ImageIO 48MP+",
                                systemImage: "bolt.shield.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            Spacer()

                            Label(
                                appLanguage == "en" ? "PDFKit Vectorial" : "PDFKit Vectorial",
                                systemImage: "doc.text.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(24)
            }
            #if os(macOS)
            .frame(width: 490, height: 580)
            #endif
            .onAppear {
                auditLogs = SecurityAuditManager.shared.getLogs()
            }
            .navigationTitle(strings.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.settingsDone) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Overlay con indicador de progreso durante el análisis de Vision AI.
struct AnalyzingOverlayView: View {
    let strings: AppStrings
    let fontSize: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .cornerRadius(16)
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(strings.analyzingText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Panel de resumen con contadores de la detección automática.
struct VisionSummaryPanel: View {
    @Binding var detectedRegions: [DetectedPrivacyRegion]
    let strings: AppStrings
    let fontSize: Double
    let onToggleCategory: (SensitiveDataCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.visionSummaryTitle, systemImage: "sparkles")
                    .font(.system(size: fontSize + 1, weight: .bold))
                Spacer()
                Text(strings.protectedCountText(
                    enabled: detectedRegions.filter(\.isEnabled).count,
                    total: detectedRegions.count
                ))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryBadge(
                        title: strings.badgeFaces,
                        icon: "person.crop.artframe",
                        count: detectedRegions.filter({ $0.type == .face }).count,
                        color: .blue
                    )
                    CategoryBadge(
                        title: strings.badgeEmails,
                        icon: "envelope.fill",
                        count: detectedRegions.filter({ $0.category == .email }).count,
                        color: .red
                    )
                    CategoryBadge(
                        title: strings.badgePhones,
                        icon: "phone.fill",
                        count: detectedRegions.filter({ $0.category == .phone }).count,
                        color: .orange
                    )
                    CategoryBadge(
                        title: strings.badgeID,
                        icon: "person.text.rectangle.fill",
                        count: detectedRegions.filter({ $0.category == .identityDocument }).count,
                        color: .purple
                    )
                    CategoryBadge(
                        title: strings.badgePlates,
                        icon: "car.fill",
                        count: detectedRegions.filter({ $0.category == .licensePlate }).count,
                        color: .teal
                    )
                    CategoryBadge(
                        title: strings.badgeTaxID,
                        icon: "doc.plaintext.fill",
                        count: detectedRegions.filter({ $0.category == .taxID }).count,
                        color: .mint
                    )
                    CategoryBadge(
                        title: strings.badgeQR,
                        icon: "qrcode.viewfinder",
                        count: detectedRegions.filter({ $0.type == .barcode }).count,
                        color: .indigo
                    )
                    CategoryBadge(
                        title: strings.badgeManual,
                        icon: "hand.draw.fill",
                        count: detectedRegions.filter({ $0.type == .manual }).count,
                        color: .yellow
                    )
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Badge de contador para categorías de privacidad.
struct CategoryBadge: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(title): \(count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(count > 0 ? color.opacity(0.18) : Color.gray.opacity(0.1))
        .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
        .cornerRadius(8)
    }
}

/// Vista de estado vacío para seleccionar imagen o documento.
struct EmptyStateMediaPicker: View {
    @Binding var isPhotoPickerPresented: Bool
    @Binding var isDocumentPickerPresented: Bool
    let isLoadingMedia: Bool
    let strings: AppStrings
    let fontSize: Double

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text(strings.welcomeTitle)
                    .font(.system(size: fontSize + 4, weight: .bold))
                Text(strings.welcomeSubtitle)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            if isLoadingMedia {
                ProgressView(strings.loadingMediaText)
                    .padding(.top, 8)
            } else {
                HStack(spacing: 12) {
                    Button {
                        isPhotoPickerPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                            Text(strings.importPhotoButton)
                                .font(.system(size: min(fontSize, 14), weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        isDocumentPickerPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus")
                            Text(strings.importDocumentButton)
                                .font(.system(size: min(fontSize, 14), weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Lista interactiva de características de protección que se pueden encender o apagar.
struct SecurityFeaturesListView: View {
    @Binding var isDetectFacesEnabled: Bool
    @Binding var isDetectTextEnabled: Bool
    @Binding var isDetectBarcodesEnabled: Bool
    @Binding var isStripEXIFEnabled: Bool
    @Binding var isDestructiveFlattenEnabled: Bool
    let strings: AppStrings
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.securityFeaturesTitle)
                    .font(.system(size: fontSize + 1, weight: .bold))
                Spacer()
                Text(strings.securityFeaturesSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                FeatureToggleRow(
                    title: strings.featFacesTitle,
                    description: strings.featFacesDesc,
                    icon: "person.crop.artframe",
                    color: .blue,
                    fontSize: fontSize,
                    isOn: $isDetectFacesEnabled
                )
                Divider()
                FeatureToggleRow(
                    title: strings.featTextTitle,
                    description: strings.featTextDesc,
                    icon: "doc.text.magnifyingglass",
                    color: .green,
                    fontSize: fontSize,
                    isOn: $isDetectTextEnabled
                )
                Divider()
                FeatureToggleRow(
                    title: strings.featBarcodesTitle,
                    description: strings.featBarcodesDesc,
                    icon: "qrcode",
                    color: .indigo,
                    fontSize: fontSize,
                    isOn: $isDetectBarcodesEnabled
                )
                Divider()
                FeatureToggleRow(
                    title: strings.featEXIFTitle,
                    description: strings.featEXIFDesc,
                    icon: "location.slash.fill",
                    color: .orange,
                    fontSize: fontSize,
                    isOn: $isStripEXIFEnabled
                )
                Divider()
                FeatureToggleRow(
                    title: strings.featFlattenTitle,
                    description: strings.featFlattenDesc,
                    icon: "shield.checkerboard",
                    color: .purple,
                    fontSize: fontSize,
                    isOn: $isDestructiveFlattenEnabled
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Fila individual de interruptor con icono, título descriptivo y control de activación.
struct FeatureToggleRow: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let fontSize: Double
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: fontSize + 4))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: fontSize, weight: .semibold))
                    Text(description)
                        .font(.system(size: max(10, fontSize - 3)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}

/// Banner decorativo superior que confirma el procesamiento local.
struct PrivacyBannerView: View {
    let strings: AppStrings
    let fontSize: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: fontSize + 10))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.privacyBannerTitle)
                    .font(.system(size: fontSize + 1, weight: .bold))
                Text(strings.privacyBannerSubtitle)
                    .font(.system(size: max(10, fontSize - 2)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Notificación de alerta tipo banner con animación.
struct BannerNotificationView: View {
    let message: String
    let type: BannerType
    let onDismiss: () -> Void

    enum BannerType {
        case success, error
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(type == .success ? .green : .orange)

            Text(message)
                .font(.subheadline)
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            (type == .success ? Color.green : Color.orange).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
