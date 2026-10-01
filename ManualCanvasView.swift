//
//  ManualCanvasView.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Lienzo interactivo con detección de regiones, dibujo manual, menús contextuales y hápticos.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI

/// Lienzo interactivo superpuesto para visualizar, seleccionar y dibujar regiones de privacidad.
typealias ManualCanvasOverlayView = InteractiveRegionOverlayView

struct InteractiveRegionOverlayView: View {
    @Binding var regions: [DetectedPrivacyRegion]
    let globalStyle: RedactionStyle
    let isManualDrawingActive: Bool
    var onWillModifyRegion: (() -> Void)? = nil
    let onAddManualRegion: (CGRect) -> Void

    @State private var dragStartLocation: CGPoint?
    @State private var currentDragLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // 1. Dibuja los recuadros interactivos de privacidad existentes
                ForEach($regions) { $region in
                    InteractiveRegionBox(
                        region: $region,
                        globalStyle: globalStyle,
                        containerSize: proxy.size,
                        onWillModify: onWillModifyRegion,
                        onDelete: {
                            onWillModifyRegion?()
                            if let index = regions.firstIndex(where: { $0.id == region.id }) {
                                regions.remove(at: index)
                                HapticManager.impact(.medium)
                            }
                        }
                    )
                }

                // 2. Lienzo de captura para el dibujo manual de rectángulos
                if isManualDrawingActive {
                    Color.black.opacity(0.01)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if dragStartLocation == nil {
                                        dragStartLocation = value.startLocation
                                    }
                                    currentDragLocation = value.location
                                }
                                .onEnded { value in
                                    if let start = dragStartLocation {
                                        let end = value.location
                                        let minX = min(start.x, end.x)
                                        let minY = min(start.y, end.y)
                                        let width = abs(end.x - start.x)
                                        let height = abs(end.y - start.y)

                                        if width > 15 && height > 15 {
                                            let normalizedBox = CGRect(
                                                x: minX / proxy.size.width,
                                                y: minY / proxy.size.height,
                                                width: width / proxy.size.width,
                                                height: height / proxy.size.height
                                            )
                                            onAddManualRegion(normalizedBox)
                                            HapticManager.notification(.success)
                                        }
                                    }
                                    dragStartLocation = nil
                                    currentDragLocation = nil
                                }
                        )

                    // Rectángulo de previsualización en vivo durante el arrastre
                    if let start = dragStartLocation, let current = currentDragLocation {
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        Rectangle()
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .background(Color.yellow.opacity(0.2))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }
}

/// Recuadro individual con soporte para Clic Izquierdo (Menú) y Doble Clic (Activar/Desactivar).
struct InteractiveRegionBox: View {
    @Binding var region: DetectedPrivacyRegion
    let globalStyle: RedactionStyle
    let containerSize: CGSize
    var onWillModify: (() -> Void)? = nil
    let onDelete: () -> Void

    @State private var isMenuPresented: Bool = false

    private var pixelRect: CGRect {
        CGRect(
            x: region.boundingBox.origin.x * containerSize.width,
            y: region.boundingBox.origin.y * containerSize.height,
            width: region.boundingBox.size.width * containerSize.width,
            height: region.boundingBox.size.height * containerSize.height
        )
    }

    var body: some View {
        let rect = pixelRect
        let effectiveStyle = region.customStyle ?? globalStyle
        let boxColor = color(for: region)

        ZStack(alignment: .topLeading) {
            // Fondo semitransparente o transparente según esté habilitado
            Rectangle()
                .fill(region.isEnabled ? boxColor.opacity(0.35) : Color.clear)
                .frame(width: max(rect.width, 24), height: max(rect.height, 24))

            // Borde exterior
            Rectangle()
                .stroke(
                    region.isEnabled ? boxColor : Color.gray.opacity(0.4),
                    style: StrokeStyle(lineWidth: region.isEnabled ? 2.5 : 1.5, dash: region.isEnabled ? [] : [4])
                )
                .frame(width: rect.width, height: rect.height)

            // Indicador de estilo / icono en la esquina superior izquierda
            if region.isEnabled && rect.width > 24 && rect.height > 18 {
                HStack(spacing: 3) {
                    Image(systemName: effectiveStyle.iconName)
                        .font(.system(size: min(10, rect.height * 0.45)))
                    if let label = region.label, rect.width > 70 {
                        Text(label)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(boxColor, in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.white)
                .offset(x: 2, y: 2)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        // Hit-Testing: Expande el área táctil invisible a un mínimo de 44x44 pt (Apple HIG)
        .contentShape(Rectangle().size(width: max(rect.width, 44), height: max(rect.height, 44)))
        // 1. Doble toque: Alterna rápidamente el estado protegido / desprotegido
        .onTapGesture(count: 2) {
            onWillModify?()
            region.isEnabled.toggle()
            HapticManager.selection()
        }
        // 2. Un toque: Despliega el menú de opciones directamente
        .onTapGesture(count: 1) {
            isMenuPresented = true
            HapticManager.impact(.light)
        }
        // Menú Emergente (Popover) para Un Toque
        .popover(isPresented: $isMenuPresented, arrowEdge: .top) {
            RegionActionMenuView(
                region: $region,
                onWillModify: onWillModify,
                onDismiss: { isMenuPresented = false },
                onDelete: onDelete
            )
        }
        // Menú secundario nativo para clic derecho o pulsación larga
        .contextMenu {
            Button {
                onWillModify?()
                region.isEnabled.toggle()
                HapticManager.selection()
            } label: {
                Label(region.isEnabled ? "Desproteger (Mostrar Texto)" : "Proteger", systemImage: region.isEnabled ? "eye" : "lock.fill")
            }

            Divider()

            Button {
                onWillModify?()
                region.customStyle = .blackBar
                region.isEnabled = true
                HapticManager.selection()
            } label: {
                Label("Usar Barra Negra (⬛)", systemImage: "square.fill")
            }

            Button {
                onWillModify?()
                region.customStyle = .blur
                region.isEnabled = true
                HapticManager.selection()
            } label: {
                Label("Usar Desenfoque Blur (💧)", systemImage: "drop.fill")
            }

            Button {
                onWillModify?()
                region.customStyle = .pixelate
                region.isEnabled = true
                HapticManager.selection()
            } label: {
                Label("Usar Pixelado Mosaico (🏁)", systemImage: "checkerboard.rectangle")
            }

            Button {
                onWillModify?()
                region.customStyle = nil
                HapticManager.selection()
            } label: {
                Label("Usar Estilo Global", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Eliminar Recuadro", systemImage: "trash")
            }
        }
    }

    private func color(for region: DetectedPrivacyRegion) -> Color {
        if region.type == .face { return .blue }
        if region.type == .barcode { return .indigo }
        if region.type == .manual { return .yellow }

        switch region.category {
        case .email: return .red
        case .phone: return .orange
        case .identityDocument: return .purple
        case .licensePlate: return .teal
        case .taxID: return .mint
        case .bankAccount: return .pink
        case .address: return .yellow
        case .url: return .indigo
        case .generalText: return .gray
        }
    }
}

/// Menú flotante interactivo que aparece al pulsar sobre un recuadro.
struct RegionActionMenuView: View {
    @Binding var region: DetectedPrivacyRegion
    var onWillModify: (() -> Void)? = nil
    let onDismiss: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(region.label ?? "Zona Protegida", systemImage: "shield.fill")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button {
                onWillModify?()
                region.isEnabled.toggle()
                HapticManager.selection()
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: region.isEnabled ? "eye.slash.fill" : "eye.fill")
                    Text(region.isEnabled ? "Desactivar Protección" : "Activar Protección")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)

            Button {
                onWillModify?()
                region.customStyle = .blackBar
                region.isEnabled = true
                HapticManager.selection()
                onDismiss()
            } label: {
                Label("Cambiar a Barra Negra (⬛)", systemImage: "square.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button {
                onWillModify?()
                region.customStyle = .blur
                region.isEnabled = true
                HapticManager.selection()
                onDismiss()
            } label: {
                Label("Cambiar a Desenfoque Blur (💧)", systemImage: "drop.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button {
                onWillModify?()
                region.customStyle = .pixelate
                region.isEnabled = true
                HapticManager.selection()
                onDismiss()
            } label: {
                Label("Cambiar a Pixelado (🏁)", systemImage: "checkerboard.rectangle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button {
                onWillModify?()
                region.customStyle = nil
                HapticManager.selection()
                onDismiss()
            } label: {
                Label("Usar Estilo Global", systemImage: "gearshape")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                onDelete()
                onDismiss()
            } label: {
                Label("Eliminar Recuadro", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 250)
    }
}
