# codemind 🧠✨

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.x-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Modern-green.svg)](https://developer.apple.com/xcode/swiftui/)

Google'ın Gemini AI modelleriyle sohbet etmek için kusursuz, klavye odaklı bir arayüz sağlayan yerel bir macOS uygulamasıdır. Modern bir kullanıcı deneyimi için SwiftUI ile oluşturulmuştur.

## 🚀 Temel Özellikler

*   **Anında Erişim:** Global bir klavye kısayolu (Hızlıca çift **Option (⌥)** tuşu) kullanarak sohbet arayüzünü anında çağırın.
*   **Gemini Gücü:** Google'ın hızlı ve yetenekli `gemini-2.0-flash` modelinden yararlanın.
*   **Oturum Yönetimi:** Konuşmalarınızı ayrı sohbet oturumları halinde düzenleyin.
*   **Kenar Çubuğu Kontrolleri:** Sohbetleri filtreleyin (Tümü/Favoriler), oturumları yeniden adlandırın, favori olarak işaretleyin, başlıkları kopyalayın ve içerik menüsü aracılığıyla kolayca silin.
*   **Metadata Gösterimi:** Her AI yanıtı için kelime sayısı, token kullanımı (mevcutsa), yanıt süresi ve kullanılan model gibi ayrıntılı bilgileri görün.
*   **Yerel Kalıcılık:** Sohbet geçmişiniz cihazınızda `UserDefaults` kullanılarak güvenli bir şekilde saklanır.
*   **Güvenli API Anahtarı Saklama:** Gemini API anahtarınız sistem Anahtar Zinciri'nde (Keychain) güvenli bir şekilde saklanır.
*   **SwiftUI Arayüzü:** Tamamen SwiftUI ile oluşturulmuş modern, duyarlı arayüz.
*   **Erişilebilirlik Entegrasyonu:** Global klavye kısayolu için gereken Erişilebilirlik izinlerini uygun şekilde ister.

## 📸 Ekran Görüntüleri

<!-- Uygulamanın arayüzünü gösteren ekran görüntüleri veya GIF'ler ekleyin -->
*Kenar Çubuğu, Sohbet Balonları, Ayarlar Ekranı vb.*

## 🛠️ Kurulum

1.  **Depoyu Klonlayın:**
    ```bash
    git clone https://github.com/muhyal/codemind.git
    ```
2.  **Dizine Gidin:**
    ```bash
    cd codemind
    ```
3.  **Projeyi Xcode'da Açın:**
    ```bash
    open codemind.xcodeproj
    ```
4.  **İmzalama (Signing & Capabilities):** Gerekirse kendi Apple Geliştirici hesabınız için Xcode'da imzalama ayarlarını yapılandırın.
5.  **Derleyin ve Çalıştırın:** Xcode'da `Cmd + R` tuşlarına basın.

## 💡 Kullanım

1.  **Başlatma:** Uygulama arka planda çalışır. Başlangıçta standart bir ana pencere açılmaz.
2.  **Sohbeti Açma/Kapatma:** macOS'un herhangi bir yerindeyken **Option (⌥)** tuşuna hızlıca iki kez basın. Sohbet penceresi açılacaktır. Tekrar aynı işlemi yapmak pencereyi kapatır.
3.  **İlk Çalıştırma ve İzinler:** İlk çalıştırmada, Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik bölümünden **Erişilebilirlik** iznini vermeniz istenebilir. Bu, global klavye kısayolunun çalışması için gereklidir.
4.  **API Anahtarı:** Uygulamanın çalışması için bir Google AI Gemini API anahtarına ihtiyacınız vardır.
    *   [Google AI Studio](https://aistudio.google.com/app/apikey) adresinden bir anahtar edinin.
    *   Sohbet penceresinin kenar çubuğu başlığındaki **Ayarlar (⚙️)** düğmesine tıklayarak anahtarınızı uygulamaya ekleyin.
5.  **Sohbet Etme:** Kenar çubuğundan bir sohbet oturumu seçin (veya '+' düğmesiyle yeni bir tane oluşturun). Sorgunuzu alttaki giriş alanına yazın ve Enter tuşuna basın veya gönder düğmesine tıklayın.
6.  **Sohbetleri Yönetme:** Kenar çubuğundaki bir sohbet oturumuna sağ tıklayarak (veya Control tuşuna basılı tutarak tıklayarak) Başlığı Düzenle, Başlığı Kopyala, Favori/Favoriden Çıkar ve Sil gibi seçeneklere erişin. Kenar çubuğunun üstündeki filtreyi kullanarak Tüm Sohbetleri veya sadece Favorileri görüntüleyin.

## ⚙️ Yapılandırma

*   **Gemini API Anahtarı:** Uygulamanın temel işlevi için zorunludur. Ayarlar ekranından eklenmelidir.
*   **Global Kısayol:** Şu anda `AppDelegate.swift` dosyasında çift **Option** tuşuna basma olarak kodlanmıştır.

## 💻 Teknoloji Yığını

*   Swift 5.x
*   SwiftUI
*   GoogleGenerativeAI SDK (`gemini-2.0-flash` modeli)
*   AppKit (AppDelegate, NSWindow, NSEvent izleme, Erişilebilirlik API'ları için)
*   Combine (ObservableObject için)
*   UserDefaults (Oturum kalıcılığı için)
*   Keychain Services (API anahtarı saklama için)

## ✨ Katkıda Bulunma

Katkılarınız memnuniyetle karşılanır! Lütfen bir Pull Request göndermekten çekinmeyin.

## 📄 Lisans

Bu proje, kaynak kodunu inceleme, değiştirme ve kişisel, eğitim veya kar amacı gütmeyen projelerde kullanma özgürlüğü sunan açık kaynaklı bir yazılımdır.

**Ancak, bu yazılımın veya türevlerinin herhangi bir ticari amaçla kullanılması kesinlikle yasaktır.** Ticari kullanım için ayrı bir lisans anlaşması gereklidir. Daha fazla bilgi için lütfen proje sahibiyle iletişime geçin. 