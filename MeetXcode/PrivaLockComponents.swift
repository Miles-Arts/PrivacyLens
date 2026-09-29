//
//  PrivaLockComponents.swift
//  PrivaLock
//
//  Componentes modulares de interfaz de usuario de PrivaLock.
//  Incluye el contenedor del lienzo con zoom y pan, ajustes, panel de visión y controles de seguridad.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI
import PhotosUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(strings.securityFeaturesTitle)
                        .font(.system(size: fontSize + 1, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                }
                Text(strings.securityFeaturesSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
