import SwiftUI

// Sohbet öğesi üzerinde kaydırma jestini ve eylem düğmelerini yöneten bir ViewModifier.
struct SwipeActionsModifier: ViewModifier {
    let leadingActions: [SwipeAction]
    let trailingActions: [SwipeAction]
    let maxLeadingOffset: CGFloat
    let maxTrailingOffset: CGFloat
    let minSwipeDistance: CGFloat = 30
    let allowsFullSwipe: Bool // Tam kaydırma ile ilk eylemi tetikleme

    @State private var hOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var activeActionType: ActionType? = nil
    @State private var dragDirectionConfirmed: Bool = false // Sürükleme yönü kesinleşti mi?
    @State private var triggeredAction: (() -> Void)? = nil // Tam kaydırma ile tetiklenen eylem

    enum ActionType { case leading, trailing }

    init(leading: [SwipeAction] = [], trailing: [SwipeAction] = [], allowsFullSwipe: Bool = false) {
        self.leadingActions = leading
        self.trailingActions = trailing
        self.maxLeadingOffset = CGFloat(leading.reduce(0) { $0 + $1.width })
        self.maxTrailingOffset = CGFloat(trailing.reduce(0) { $0 + $1.width })
        self.allowsFullSwipe = allowsFullSwipe
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            // Arka Plan Eylemleri (Leading ve Trailing)
            HStack(spacing: 0) {
                // Leading Actions (Sağa Kaydırma)
                ForEach(leadingActions) { action in
                    actionView(action: action, alignment: .leading)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hOffset > 0 ? 1 : 0)

            HStack(spacing: 0) {
                Spacer()
                // Trailing Actions (Sola Kaydırma)
                ForEach(trailingActions) { action in
                    actionView(action: action, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(hOffset < 0 ? 1 : 0)

            // Asıl İçerik
            content
                .background(.background)
                .offset(x: hOffset)
                .contentShape(Rectangle())
                .gesture(dragGesture())
                .clipped()
        }
        .clipped() // Ana ZStack taşmaları önler
        .onChange(of: isDragging) { newValue in
            if !newValue {
                // Tam kaydırma eylemi tetiklendiyse onu çalıştır
                if let actionClosure = triggeredAction {
                    // Artık doğrudan closure'ı çağırıyoruz
                    actionClosure()
                    // Reset offset smoothly after action trigger
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         withAnimation(.spring()) {
                             hOffset = 0
                         }
                    }
                } else {
                    snapToPosition()
                }
                triggeredAction = nil // Sıfırla
                dragDirectionConfirmed = false // Sıfırla
            }
        }
    }

    // Eylem Alanı Oluşturucu (Menu veya TapGesture)
    @ViewBuilder
    private func actionView(action: SwipeAction, alignment: HorizontalAlignment) -> some View {
        // Görsel kısım (ikon, etiket vs.)
        let labelView = VStack(spacing: 4) {
            Image(systemName: action.icon)
                .font(action.label == nil ? .title2 : .body)
            if let label = action.label {
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .frame(width: action.width, height: 60)
        .background(action.tint)
        .foregroundColor(.white)
        .contentShape(Rectangle())
        // Tam kaydırma görsel ipucu
        .overlay(alignment: alignment == .leading ? .trailing : .leading) {
             if allowsFullSwipe && ((alignment == .leading && action.id == leadingActions.first?.id) || (alignment == .trailing && action.id == trailingActions.first?.id)) {
                 Image(systemName: "arrowshape.left.fill")
                      .rotationEffect(.degrees(alignment == .leading ? 180 : 0))
                      .font(.caption)
                      .foregroundColor(.white.opacity(0.7))
                      .padding(alignment == .leading ? .trailing : .leading, 10)
                      .opacity(abs(hOffset) > (alignment == .leading ? maxLeadingOffset : maxTrailingOffset) + 20 ? 1 : 0)
                      .animation(.easeInOut, value: hOffset)
             }
        }

        // Menu içeriği varsa Menu olarak, yoksa normal View olarak göster
        if let menuContentBuilder = action.menuContent {
            Menu {
                menuContentBuilder()
            } label: {
                labelView
            }
            .menuStyle(.borderlessButton)
            .frame(width: action.width, height: 60)
        } else {
            labelView
                .onTapGesture {
                    // action nil olmamalı (initializer garantiliyor)
                    if let tapAction = action.action {
                         handleActionTap(actionClosure: tapAction)
                    }
                }
        }
    }

    // Eylem Tıklama Yardımcısı (Sadece action closure alır)
    private func handleActionTap(actionClosure: @escaping () -> Void) {
        withAnimation(.spring()) { hOffset = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            actionClosure()
        }
    }

    // Sürükleme Jesti (Tam kaydırma mantığı eklendi)
    func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    triggeredAction = nil // Başlangıçta tetiklenen eylem yok
                    dragDirectionConfirmed = false // Yön henüz kesin değil
                }

                let dragWidth = value.translation.width

                // Başlangıçta yönü belirle ve kilitle
                if !dragDirectionConfirmed && abs(dragWidth) > 10 { // Küçük bir eşik
                    activeActionType = dragWidth > 0 ? .leading : .trailing
                    // Sadece izin verilen yönde eylem varsa devam et
                    if (activeActionType == .leading && leadingActions.isEmpty) || (activeActionType == .trailing && trailingActions.isEmpty) {
                        activeActionType = nil // İzin verilmeyen yön, jesti durdur
                        isDragging = false // Sürüklemeyi bitir
                        return
                    }
                    dragDirectionConfirmed = true
                }

                guard dragDirectionConfirmed, let currentActionType = activeActionType else { return }

                // Aktif yöne göre offset'i hesapla
                var currentOffset = dragWidth
                let fullSwipeThresholdMultiplier: CGFloat = 1.5 // Tam kaydırma için ne kadar ekstra çekilmeli
                let fullSwipeActivationOffset: CGFloat = 60 // Tam kaydırmanın aktifleşeceği ekstra mesafe

                switch currentActionType {
                case .leading:
                    let maxOffset = maxLeadingOffset
                    currentOffset = max(0, min(currentOffset, maxOffset + (allowsFullSwipe ? fullSwipeActivationOffset : 0)))
                    hOffset = currentOffset
                    // Tam kaydırma kontrolü
                    if allowsFullSwipe, let firstAction = leadingActions.first, currentOffset > maxOffset + fullSwipeThresholdMultiplier * firstAction.width / 2 {
                        // Doğrudan action closure'ını ata
                        triggeredAction = firstAction.action
                    } else {
                        triggeredAction = nil
                    }

                case .trailing:
                    let maxOffset = maxTrailingOffset
                    currentOffset = min(0, max(currentOffset, -maxOffset - (allowsFullSwipe ? fullSwipeActivationOffset : 0)))
                    hOffset = currentOffset
                    // Tam kaydırma kontrolü
                    if allowsFullSwipe, let firstAction = trailingActions.first, abs(currentOffset) > maxOffset + fullSwipeThresholdMultiplier * firstAction.width / 2 {
                        // Doğrudan action closure'ını ata
                        triggeredAction = firstAction.action
                    } else {
                        triggeredAction = nil
                    }
                }
            }
            .onEnded { value in
                isDragging = false
                // Burada snapToPosition veya tetiklenen eylemi çalıştırma onChange içinde yapılıyor
            }
    }

    // Kaydırmanın bitiş konumunu ayarlar
    private func snapToPosition() {
         guard let currentActionType = activeActionType else { hOffset = 0; return }

         withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { // Biraz daha yumuşak animasyon
             switch currentActionType {
             case .leading:
                 let threshold: CGFloat = maxLeadingOffset / 2
                 if hOffset > threshold && hOffset > minSwipeDistance {
                     hOffset = maxLeadingOffset
                 } else {
                     hOffset = 0
                 }
             case .trailing:
                 let threshold: CGFloat = maxTrailingOffset / 2
                 if abs(hOffset) > threshold && abs(hOffset) > minSwipeDistance {
                     hOffset = -maxTrailingOffset
                 } else {
                     hOffset = 0
                 }
             }
         }
         // Aktif eylem tipini sıfırla (animasyon başladıktan hemen sonra)
         activeActionType = nil
    }
}

// SwipeAction struct (Non-generic, AnyView menuContent)
struct SwipeAction: Identifiable {
    let id = UUID()
    let tint: Color
    let icon: String
    let label: String? // Opsiyonel etiket
    let width: CGFloat // Buton genişliği
    let action: (() -> Void)? // Normal eylem
    let menuContent: (() -> AnyView)? // Opsiyonel menü içeriği (AnyView)

    // Initializer for regular actions
    init(tint: Color, icon: String, label: String? = nil, width: CGFloat = 80, action: @escaping () -> Void) {
        self.tint = tint
        self.icon = icon
        self.label = label
        self.width = width
        self.action = action
        self.menuContent = nil
    }

    // Initializer for menu actions (accepts some View, wraps in AnyView)
    init<MenuView: View>(tint: Color, icon: String, label: String? = nil, width: CGFloat = 80, @ViewBuilder menuContent: @escaping () -> MenuView) {
        self.tint = tint
        self.icon = icon
        self.label = label
        self.width = width
        self.action = nil
        // Gelen View'ı AnyView ile sarmala
        self.menuContent = { AnyView(menuContent()) }
    }
}

// ViewModifier'ı kolayca kullanmak için bir extension (leading/trailing parametreleri eklendi)
extension View {
    func swipeActions(leading: [SwipeAction] = [], trailing: [SwipeAction] = [], allowsFullSwipe: Bool = false) -> some View {
        self.modifier(SwipeActionsModifier(leading: leading, trailing: trailing, allowsFullSwipe: allowsFullSwipe))
    }

    // Sık kullanılan durumlar için Overload'lar (opsiyonel, ama kullanışlı)

    // Sadece trailing action'lar (non-menu)
    func swipeActions(trailing: [SwipeAction], allowsFullSwipe: Bool = false) -> some View {
        self.modifier(SwipeActionsModifier(leading: [], trailing: trailing, allowsFullSwipe: allowsFullSwipe))
    }

    // Sadece leading action'lar (non-menu)
    func swipeActions(leading: [SwipeAction], allowsFullSwipe: Bool = false) -> some View {
        self.modifier(SwipeActionsModifier(leading: leading, trailing: [], allowsFullSwipe: allowsFullSwipe))
    }

    // Hiç action yok
    func swipeActions(allowsFullSwipe: Bool = false) -> some View {
        self.modifier(SwipeActionsModifier(leading: [], trailing: [], allowsFullSwipe: allowsFullSwipe))
    }
}

// SwiftUI Önizlemesi için Örnek Kullanım
struct ChatListGestureHandler_Previews: PreviewProvider {
    static var previews: some View {
        List {
            Text("Sohbet 1 (Trailing & Leading)")
                .listRowInsets(EdgeInsets())
                .swipeActions(
                    leading: [
                        SwipeAction(tint: .green, icon: "pin.fill") { print("Pin 1") },
                        SwipeAction(tint: .gray, icon: "bell.slash.fill") { print("Mute 1") }
                    ],
                    trailing: [
                        SwipeAction(tint: .red, icon: "trash.fill", label: "Delete") { print("Delete 1") },
                        // Örnek Menu Action Preview (gerçek menü içeriği yerine Text)
                        SwipeAction(tint: .blue, icon: "archivebox.fill", label: "Archive") {
                            Text("Archive Menu Item 1")
                            Text("Archive Menu Item 2")
                        }
                    ]
                )
                .frame(height: 60)

            Text("Sohbet 2 (Trailing Only, Full Swipe)")
                .listRowInsets(EdgeInsets())
                .swipeActions(trailing: [
                     SwipeAction(tint: .orange, icon: "trash.fill", label: "Delete") { print("Delete 2 (Full Swipe)") }
                ], allowsFullSwipe: true)
                .frame(height: 60)

            Text("Sohbet 3 (Jest Yok)")
                 .frame(height: 60)
        }
        .listStyle(.plain)
    }
} 