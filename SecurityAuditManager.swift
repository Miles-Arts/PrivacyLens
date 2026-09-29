//
//  SecurityAuditManager.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Gestor de Auditoría Forense Local, Blindaje Zero-Knowledge y Modo Privado / Modo Normal.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation

/// Registro inmutable que almacena exclusivamente metadatos operacionales
/// (tipo de archivo, peso en bytes, fecha y cantidad de zonas protegidas).
/// **Nunca se almacenan imágenes, píxeles ni contenido sensible del usuario.**
struct AuditLogEntry: Identifiable, Codable, Sendable {
    /// Identificador único universal del registro.
    let id: UUID
    /// Nombre desinfectado del archivo procesado.
    let fileName: String
    /// Extensión o tipo del archivo (ej. JPG, PDF, PNG).
    let fileType: String
    /// Peso original del archivo en bytes.
    let fileSizeBytes: Int64
    /// Representación legible del tamaño (ej. "2.4 MB").
    let fileSizeFormatted: String
    /// Marca temporal exacta en la que se ejecutó la operación.
    let timestamp: Date
    /// Número de zonas redactadas exitosamente en la imagen.
    let redactedCount: Int

    /// Inicializa una entrada de auditoría forense calculando automáticamente el formato legible del peso.
    init(
        id: UUID = UUID(),
        fileName: String,
        fileType: String,
        fileSizeBytes: Int64,
        timestamp: Date = Date(),
        redactedCount: Int
    ) {
        self.id = id
        // Sanitización preventiva contra secuencias maliciosas en el nombre de archivo
        self.fileName = fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        self.fileType = fileType.uppercased()
        self.fileSizeBytes = fileSizeBytes
        self.timestamp = timestamp
        self.redactedCount = redactedCount

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        self.fileSizeFormatted = formatter.string(fromByteCount: fileSizeBytes)
    }
}

/// Administrador centralizado de seguridad, auditoría local y blindaje de datos.
///
/// ### Principios de Seguridad Implementados:
/// 1. **Zero-Knowledge en Modo Privado**: Cuando `isPrivateMode` está activo, las operaciones son volátiles; no se escribe ningún dato en disco ni en memoria persistente.
/// 2. **Inmunidad a SQL Injection**: No se emplean bases de datos relacionales ni motores SQL. La persistencia se realiza mediante serialización binaria nativa `Codable` en un sandbox cerrado.
/// 3. **Rotación Automática**: El historial retiene un máximo de 50 entradas para preservar el espacio en disco y el rendimiento.
final class SecurityAuditManager: @unchecked Sendable {

    /// Instancia singleton compartida.
    static let shared = SecurityAuditManager()

    /// Clave interna de almacenamiento en UserDefaults.
    private let storageKey = "privalock_audit_entries"

    /// Cola concurrente privada para serialización asíncrona fuera del hilo principal.
    private let queue = DispatchQueue(label: "com.privalock.security.audit", qos: .utility)

    private init() {}

    /// Registra de forma asíncrona una operación de redacción.
    ///
    /// - Parameters:
    ///   - fileName: Nombre del archivo procesado.
    ///   - fileType: Extensión o tipo del archivo.
    ///   - fileSizeBytes: Tamaño del archivo en bytes.
    ///   - redactedCount: Cantidad de regiones protegidas.
    ///   - isPrivateMode: Si es `true`, descarta la operación inmediatamente sin escribir nada a disco.
    func recordOperation(
        fileName: String,
        fileType: String,
        fileSizeBytes: Int64,
        redactedCount: Int,
        isPrivateMode: Bool
    ) {
        // En Modo Privado descartamos inmediatamente cualquier dato sin escribir a disco (Zero-Knowledge)
        if isPrivateMode {
            return
        }

        queue.async {
            let entry = AuditLogEntry(
                fileName: fileName,
                fileType: fileType,
                fileSizeBytes: fileSizeBytes,
                redactedCount: redactedCount
            )

            var currentLogs = self.loadLogsSynchronously()
            currentLogs.insert(entry, at: 0)

            // Limitamos a los últimos 50 registros para mantener la app ligera y segura
            if currentLogs.count > 50 {
                currentLogs = Array(currentLogs.prefix(50))
            }

            if let encoded = try? JSONEncoder().encode(currentLogs) {
                UserDefaults.standard.set(encoded, forKey: self.storageKey)
            }
        }
    }

    /// Obtiene la lista actual de registros de operaciones guardados en Modo Normal.
    ///
    /// - Returns: Arreglo cronológico de registros `[AuditLogEntry]`.
    func getLogs() -> [AuditLogEntry] {
        return loadLogsSynchronously()
    }

    /// Elimina permanentemente todo el historial de auditoría almacenado en disco.
    func clearAllLogs() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Carga sincrónicamente los registros almacenados en el sandbox.
    private func loadLogsSynchronously() -> [AuditLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let logs = try? JSONDecoder().decode([AuditLogEntry].self, from: data) else {
            return []
        }
        return logs
    }
}
