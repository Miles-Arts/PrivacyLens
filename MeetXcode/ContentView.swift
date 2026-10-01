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
    @State private var loadedDocumentURL: URL?
    @State private var currentPDFPageIndex: Int = 0
    @State private var totalPDFPages: Int = 1
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
                            // Barra de Nombre de Archivo Personalizable y Contador (Responsiva para iPhone SE)
                            HStack(spacing: 6) {
                                Image(systemName: "pencil.line")
                                    .foregroundStyle(.tint)
                                    .font(.system(size: 14))

                                Text(strings.fileNameLabel)
                                    .font(.system(size: min(appFontSize, 13), weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .layoutPriority(1)

                                TextField(strings.fileNamePlaceholder, text: $customExportFileName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: min(appFontSize, 13)))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(".jpg")
                                    .font(.system(size: min(appFontSize, 12)))
                                    .foregroundStyle(.secondary)
                                    .layoutPriority(1)

                                Button(role: .destructive) {
                                    clearSelectedMedia()
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 2)
                                }
                                .buttonStyle(.plain)
                                .layoutPriority(1)
                            }
                            .padding(.horizontal, 2)

                            // Barra de Navegación de Páginas para Documentos PDF Multipágina
                            if totalPDFPages > 1 {
                                HStack {
                                    Button {
                                        switchPDFPage(to: currentPDFPageIndex - 1)
                                    } label: {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentPDFPageIndex <= 0)
                                    .foregroundStyle(currentPDFPageIndex <= 0 ? Color.secondary.opacity(0.3) : Color.blue)

                                    Spacer()

                                    Text(strings.pdfPageIndicator(current: currentPDFPageIndex + 1, total: totalPDFPages))
                                        .font(.system(size: appFontSize, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())

                                    Spacer()

                                    Button {
                                        switchPDFPage(to: currentPDFPageIndex + 1)
                                    } label: {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentPDFPageIndex >= totalPDFPages - 1)
                                    .foregroundStyle(currentPDFPageIndex >= totalPDFPages - 1 ? Color.secondary.opacity(0.3) : Color.blue)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }

                            // Toolbar de Modos, Dibujo Manual y Estilo Global (Adaptable y Responsiva)
                            VStack(spacing: 12) {
                                Picker("Modo de Vista", selection: $currentViewMode) {
                                    ForEach(ViewMode.allCases) { mode in
                                        Text(mode.title(for: strings)).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                // Barra de Herramientas Compacta y Perfectamente Diseñada bajo Apple HIG para iPhone SE
                                HStack(spacing: 8) {
                                    // 1. Botón Dibujar Recuadro / Cancelar (Etiqueta concisa para evitar truncamiento)
                                    Button {
                                        isManualDrawingActive.toggle()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: isManualDrawingActive ? "xmark.circle.fill" : "hand.draw.fill")
                                                .font(.system(size: 13, weight: .bold))
                                            Text(isManualDrawingActive ? "Cancelar" : "Dibujar")
                                                .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isManualDrawingActive ? .orange : .blue)
                                    .accessibilityLabel(isManualDrawingActive ? strings.cancelDrawingButton : strings.drawBoxButton)

                                    Spacer(minLength: 2)

                                    // 2. Botones de Deshacer y Rehacer (Undo / Redo) - Patrón de Diseño Apple HIG
                                    // - Contenedor circular nítido con stroke y contraste accesible
                                    // - Iconos SF Symbols nativos (arrow.uturn.backward / forward)
                                    // - Hit-testing estándar Apple de 44x44 pt
                                    HStack(spacing: 6) {
                                        Button {
                                            undoLastAction()
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(undoStack.isEmpty ? Color(white: 0.18) : Color.blue.opacity(0.2))
                                                    .frame(width: 34, height: 34)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(undoStack.isEmpty ? Color.white.opacity(0.18) : Color.blue.opacity(0.5), lineWidth: 1)
                                                    )
                                                Image(systemName: "arrow.uturn.backward")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(undoStack.isEmpty ? Color(white: 0.5) : Color.blue)
                                            }
                                            .contentShape(Rectangle().size(width: 44, height: 44))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(undoStack.isEmpty)
                                        .help(strings.undoButton)
                                        .accessibilityLabel(strings.undoButton)

                                        Button {
                                            redoLastAction()
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(redoStack.isEmpty ? Color(white: 0.18) : Color.blue.opacity(0.2))
                                                    .frame(width: 34, height: 34)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(redoStack.isEmpty ? Color.white.opacity(0.18) : Color.blue.opacity(0.5), lineWidth: 1)
                                                    )
                                                Image(systemName: "arrow.uturn.forward")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(redoStack.isEmpty ? Color(white: 0.5) : Color.blue)
                                            }
                                            .contentShape(Rectangle().size(width: 44, height: 44))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(redoStack.isEmpty)
                                        .help(strings.redoButton)
                                        .accessibilityLabel(strings.redoButton)
                                    }

                                    Spacer(minLength: 2)

                                    // 3. Selector de Estilo de Redacción con Menú Desplegable Compacto Apple HIG
                                    Menu {
                                        ForEach(RedactionStyle.allCases) { style in
                                            Button {
                                                selectedRedactionStyle = style
                                                HapticManager.selection()
                                            } label: {
                                                Label(style.rawValue, systemImage: style.iconName)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: selectedRedactionStyle.iconName)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(selectedRedactionStyle.shortTitle)
                                                .font(.system(size: min(appFontSize, 12), weight: .medium))
                                                .lineLimit(1)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 7)
                                        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .lineLimit(1)
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
                                    onWillModifyRegion: {
                                        recordUndoState()
                                    },
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
                                        .font(.system(size: min(appFontSize + 1, 16), weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isSavingImage || isAnalyzingVision)

                            // Botones de Compartir, Imprimir, Copiar y Cambiar Foto
                            VStack(spacing: 12) {
                                // Fila 1: Compartir e Imprimir (Responsivo para iPhone SE)
                                HStack(spacing: 8) {
                                    Button {
                                        shareProtectedImage()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "square.and.arrow.up.fill")
                                            Text(strings.shareButton)
                                                .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
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
                                        HStack(spacing: 5) {
                                            Image(systemName: "printer.fill")
                                            Text(strings.printButton)
                                                .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.bordered)
                                    .help(strings.printHelp)
                                    .disabled(isSavingImage || isAnalyzingVision)
                                }

                                // Fila 2: Copiar al Portapapeles y Cambiar Foto (Responsivo para iPhone SE)
                                HStack(spacing: 8) {
                                    Button {
                                        copyProtectedImageToClipboard()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "doc.on.doc.fill")
                                            Text(strings.copyClipboardButton)
                                                .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isSavingImage || isAnalyzingVision)

                                    Button {
                                        clearSelectedMedia()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "photo.badge.plus")
                                            Text(strings.changePhotoButton)
                                                .font(.system(size: min(appFontSize, 13), weight: .semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
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
            .onChange(of: detectedRegions) { _, _ in
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

            // Verificar si es PDF para registrar el total de páginas
            if selectedURL.pathExtension.lowercased() == "pdf" {
                let pages = HighResolutionManager.shared.getPDFPageCount(at: selectedURL)
                self.totalPDFPages = max(1, pages)
                self.currentPDFPageIndex = 0
                self.loadedDocumentURL = selectedURL
            } else {
                self.totalPDFPages = 1
                self.currentPDFPageIndex = 0
                self.loadedDocumentURL = nil
            }

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

    private func switchPDFPage(to pageIndex: Int) {
        guard let url = loadedDocumentURL,
              pageIndex >= 0, pageIndex < totalPDFPages else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        isLoadingMedia = true
        if let newPageImage = HighResolutionManager.shared.renderPDFPage(at: url, pageIndex: pageIndex) {
            self.currentPDFPageIndex = pageIndex
            self.loadedImage = newPageImage
            self.isLoadingMedia = false
            self.resetCanvasTransform()
            self.analyzeLoadedImage(newPageImage)
            HapticManager.selection()
        } else {
            self.isLoadingMedia = false
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

    private func recordAuditLog(for fileName: String) {
        let activeCount = detectedRegions.filter { $0.isEnabled }.count
        SecurityAuditManager.shared.recordOperation(
            fileName: fileName,
            fileType: "JPG",
            fileSizeBytes: loadedFileSizeBytes,
            redactedCount: activeCount,
            isPrivateMode: isPrivateMode
        )
    }

    // MARK: - Exportación, Compartir e Impresión

    private func shareProtectedImage() {
        guard let finalImage = redactedImage ?? loadedImage else { return }
        let resolvedFileName = ExportManager.sanitizeFileName(customExportFileName)

        ExportManager.shareImage(finalImage, fileName: resolvedFileName)

        recordAuditLog(for: resolvedFileName)
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

                    self.recordAuditLog(for: resolvedFileName)
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
        loadedDocumentURL = nil
        currentPDFPageIndex = 0
        totalPDFPages = 1
        redactedImage = nil
        detectedRegions.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        customExportFileName = ""
        errorMessage = nil
        successMessage = nil
        resetCanvasTransform()
        loadedFileSizeBytes = 0
    }
}
