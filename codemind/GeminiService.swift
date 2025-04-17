import Foundation
import GoogleGenerativeAI

/// `GeminiService` tarafından fırlatılabilecek olası hataları tanımlar.
enum GeminiError: Error, LocalizedError {
    case apiKeyMissing
    case modelInitializationFailed(Error)
    case contentGenerationFailed(Error)
    case invalidResponse

    /// Kullanıcıya gösterilecek hata açıklaması.
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API Anahtarı eksik. Lütfen ayarlardan ekleyin."
        case .modelInitializationFailed(let underlyingError):
            return "AI modeli başlatılamadı: \(underlyingError.localizedDescription)"
        case .contentGenerationFailed(let underlyingError):
            return "İçerik üretilemedi: \(underlyingError.localizedDescription)"
        case .invalidResponse:
            return "API'den geçersiz bir yanıt alındı."
        }
    }
}

/// Üretim sonucunu ve ilgili meta verileri içeren struct.
struct GenerationResult {
    /// Üretilen metin.
    let text: String
    /// Metindeki kelime sayısı.
    let wordCount: Int
    /// İstek (prompt) için kullanılan token sayısı.
    let promptTokenCount: Int?
    /// Yanıt adayları (candidates) için kullanılan token sayısı.
    let candidatesTokenCount: Int?
    /// Toplam kullanılan token sayısı.
    let totalTokenCount: Int?
    /// Yanıtın milisaniye cinsinden süresi.
    let responseTimeMs: Int
    /// Kullanılan modelin adı.
    let modelName: String
}

/// Gemini API ile etkileşim kurmak için servis struct'ı.
struct GeminiService {
    
    // TODO: Model adını dinamik veya yapılandırılabilir hale getirmeyi düşünün.
    private let modelName = "gemini-2.0-flash" // Model adını burada güncelleyebilirsiniz.

    /// Gemini API'den yanıt üretir.
    /// - Parameters:
    ///   - history: Konuşma geçmişi. `[ModelContent]` dizisi.
    ///   - latestPromptParts: Kullanıcının gönderdiği son mesajın parçaları (metin ve/veya görüntü).
    ///   - apiKey: Gemini API anahtarı.
    ///     *Not: Daha güvenli uygulamalar için API anahtarını her çağrıda geçmek yerine
    ///     servis başlatılırken veya güvenli bir depodan (örn. Keychain) almak daha iyidir.*
    /// - Returns: Başarılı olursa `GenerationResult` içeren, başarısız olursa `GeminiError` içeren bir `Result`.
    func generateResponse(history: [ModelContent], latestPromptParts: [ModelContent.Part], apiKey: String) async -> Result<GenerationResult, GeminiError> {
        // API anahtarının boş olmadığını kontrol et
        guard !apiKey.isEmpty else {
            return .failure(.apiKeyMissing)
        }
        // Son prompt'un boş olmadığından emin ol (hem metin hem görüntü gönderilmemiş olabilir)
        guard !latestPromptParts.isEmpty else {
             // Belki özel bir hata dönebilir veya boş bir başarı sonucu?
             // Şimdilik, content generation failed gibi davranalım.
             return .failure(.contentGenerationFailed(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Prompt parts cannot be empty."])))
        }

        // GenerativeModel'ı API anahtarı ile başlat
        // Not: Hata yönetimi için model başlatmayı da `do-catch` içine almayı düşünebilirsiniz,
        // ancak `sendMessage` genellikle başlatma hatalarını da yakalar.
        let model = GenerativeModel(name: modelName, apiKey: apiKey)
        
        // Sağlanan geçmişle bir sohbet oturumu başlat
        let chat = model.startChat(history: history)
        
        let startTime = Date()

        do {
            // Son istem parça dizisini içeren ModelContent'i bir dizi içine sararak gönder
            let response = try await chat.sendMessage([ModelContent(parts: latestPromptParts)])
            
            let endTime = Date()
            let responseTimeMs = Int(endTime.timeIntervalSince(startTime) * 1000)

            // Yanıttan metni çıkar
            guard let text = response.text else {
                // Yanıt metni boşsa veya yoksa hata döndür
                return .failure(.invalidResponse)
            }
            
            // Kelime sayısını hesapla
            let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
            
            // Token sayılarını çıkar (response.usageMetadata'nın var olduğunu varsayarak)
            let promptTokenCount = response.usageMetadata?.promptTokenCount
            let candidatesTokenCount = response.usageMetadata?.candidatesTokenCount
            let totalTokenCount = response.usageMetadata?.totalTokenCount

            // Sonuç struct'ını oluştur
            let result = GenerationResult(
                text: text,
                wordCount: wordCount,
                promptTokenCount: promptTokenCount,
                candidatesTokenCount: candidatesTokenCount,
                totalTokenCount: totalTokenCount,
                responseTimeMs: responseTimeMs,
                modelName: modelName // `self.` kaldırıldı
            )
            
            return .success(result)
            
        } catch {
            // API iletişimi sırasındaki hataları yakala
            // Geliştirme sırasında hatayı loglamak faydalıdır
            print("Gemini API Hatası: \(error.localizedDescription)")
            return .failure(.contentGenerationFailed(error))
        }
    }
} 