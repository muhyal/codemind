import SwiftUI
import AppKit // NSPasteboard ve NSImage için gerekli

enum ScreenshotError: Error {
    case captureFailed(Int32)
    case pasteboardError
    case noImageInPasteboard
    case dataConversionError
}

struct ScreenshotService {
    
    /// Kullanıcının interaktif olarak bir ekran alanı seçmesini sağlar ve görüntüyü panoya kopyalar,
    /// ardından panodan Data olarak alır.
    /// - Throws: ScreenshotError fırlatabilir.
    /// - Returns: Yakalanan görüntünün PNG Data'sı veya işlem iptal edilirse/başarısız olursa nil.
    func captureInteractiveScreenshotToClipboard() async throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interaktif mod, -c: panoya kopyala
        process.arguments = ["-ic"] 

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            // Kullanıcı Esc ile iptal ettiyse status 1 dönebilir, bu bir hata değil.
            guard status == 0 else {
                // Kullanıcı iptal ettiyse (genellikle status 1) nil dönelim, diğer durumlarda hata fırlatalım.
                if status == 1 { 
                    print("Screenshot capture cancelled by user.")
                    return nil 
                } else {
                   throw ScreenshotError.captureFailed(status)
                }
            }

            // Panodan görüntüyü al
            guard let pasteboard = NSPasteboard.general.pasteboardItems?.first,
                  // TIFF veya PNG formatını kontrol et
                  let imageType = pasteboard.types.first(where: { $0 == .tiff || $0 == .png }),
                  let imageData = pasteboard.data(forType: imageType) else {
                throw ScreenshotError.noImageInPasteboard
            }
            
            // PNG'ye dönüştürme
            if imageType == .png {
                 print("Screenshot captured as PNG.")
                 return imageData // Zaten PNG, doğrudan döndür
            } else if imageType == .tiff {
                 // TIFF ise PNG'ye çevir
                 guard let tiffImage = NSImage(data: imageData), // Önce NSImage oluştur
                       let imageTiffData = tiffImage.tiffRepresentation, // Sonra tiffRepresentation al
                       let bitmapRep = NSBitmapImageRep(data: imageTiffData), // BitmapRep oluştur
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) // PNG Data al
                 else {
                      print("Error converting TIFF to PNG.")
                      throw ScreenshotError.dataConversionError
                 }
                 print("Screenshot captured as TIFF and converted to PNG.")
                 return pngData
            } else {
                 // Desteklenmeyen tip (Bu kod bloğuna girilmemesi lazım guard nedeniyle)
                 print("Unsupported image type found on pasteboard: \(imageType)")
                 throw ScreenshotError.dataConversionError
            }

        } catch {
            // Process.run() hatası veya diğer hatalar
            print("Error during screenshot capture process: \(error)")
            // Eğer hata ScreenshotError değilse, genel bir hata olarak sarmalayabiliriz
            if !(error is ScreenshotError) {
                 throw error // Veya daha spesifik bir hata yönetimi
            } else {
                 throw error // Zaten ScreenshotError
            }
        }
    }
} 