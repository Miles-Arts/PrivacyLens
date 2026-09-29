//
//  MeetXcodeApp.swift
//  PrivaLock
//
//  Creado para PrivaLock - Aplicación de Redacción y Protección de Datos On-Device.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Punto de entrada principal para la aplicación PrivaLock en iOS y macOS.
///
/// Implementa monitoreo del ciclo de vida (`ScenePhase`) para superponer un escudo
/// de privacidad (`PrivacyOverlayView`) cuando la aplicación entra en segundo plano,
/// previniendo la captura inadvertida de documentos sensibles en el selector de aplicaciones.
@main
struct MeetXcodeApp: App {

    /// Estado de la escena actual para monitorear transiciones de segundo plano.
    @Environment(\.scenePhase) private var scenePhase

    /// Tamaño de fuente predeterminado persistido con AppStorage.
    @AppStorage("privalock_font_size") private var appFontSize: Double = 14.0

    /// Idioma de la aplicación persistido con AppStorage ("es" por defecto).
    @AppStorage("privalock_language") private var appLanguage: String = "es"

    /// Modo Privado (Zero-Knowledge) persistido con AppStorage (false por defecto).
    @AppStorage("privalock_is_private_mode") private var isPrivateMode: Bool = false

    /// Inicializador principal de la aplicación.
    init() {
        // Purga preventiva de cualquier residuo temporal de sesiones anteriores
        ExportManager.cleanupTemporaryFiles()

        #if canImport(AppKit)
        // Inyecta el icono de la aplicación en el Dock de macOS al iniciar
        if let appIcon = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = appIcon
        } else if let iconPath = Bundle.main.path(forResource: "icon_1024", ofType: "png"),
                  let iconImage = NSImage(contentsOfFile: iconPath) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    // Muestra el escudo de seguridad cuando la app pasa al App Switcher o a segundo plano
                    if scenePhase != .active {
                        PrivacyOverlayView(lang: appLanguage)
                    }
                }
        }

        #if os(macOS)
        // Soporte nativo para el atajo estándar de Ajustes en macOS (⌘,)
        Settings {
            PrivaLockSettingsSheet(
                fontSize: $appFontSize,
                appLanguage: $appLanguage,
                isPrivateMode: $isPrivateMode,
                strings: AppStrings(lang: appLanguage)
            )
        }
        #endif
    }
}

/// Vista que difumina y oculta el contenido de la pantalla cuando PrivaLock entra en segundo plano.
struct PrivacyOverlayView: View {
    /// Código del idioma activo ("es" o "en").
    let lang: String

    private var isEnglish: Bool {
        lang == "en"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text(isEnglish ? "PrivaLock Protected" : "PrivaLock Protegido")
                    .font(.title2)
                    .bold()

                Text(isEnglish
                     ? "Screen is hidden while PrivaLock is in the background."
                     : "La pantalla se oculta mientras PrivaLock esté en segundo plano.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(32)
        }
    }
}
