import Foundation

/// Maps short natural-language commands to registered app actions without
/// contacting the LLM. Used by CoCaptain and command surfaces for fast local
/// intent handling.
public struct CommandIntentResolver {
    public init() {}

    /// Returns an action only when the normalized input positively matches an
    /// alias for an action that is currently available.
    public func resolve(_ input: String, availableActions: [AppActionDefinition]) -> AppActionID? {
        let normalizedInput = Self.normalized(input)
        guard !normalizedInput.isEmpty else { return nil }
        guard !Self.hasNegation(in: normalizedInput) else { return nil }

        let availableIDs = Set(availableActions.map(\.id))
        return AppActionID.allCases.first { id in
            availableIDs.contains(id) && aliases(for: id).contains { alias in
                Self.matches(normalizedInput, alias: alias)
            }
        }
    }

    /// Alias lists intentionally include English and Arabic phrases. Keep them
    /// conservative so casual chat is not accidentally interpreted as a command.
    private func aliases(for id: AppActionID) -> [String] {
        switch id {
        case .goRoot:
            return [
                "go root",
                "go home",
                "home",
                "root",
                "take me to root",
                "take me home",
                "open root",
                "الجذر",
                "اذهب للجذر",
                "اذهب الى الجذر",
                "افتح الجذر",
                "صفحة الجذر"
            ]
        case .goBack:
            return [
                "go back",
                "back",
                "return",
                "ارجع",
                "رجوع",
                "عد للخلف",
                "ارجع للخلف"
            ]
        case .createNode:
            return [
                "create mini-app",
                "create mini app",
                "new mini-app",
                "new mini app",
                "add mini-app",
                "add mini app",
                "create node",
                "create a node",
                "new node",
                "add node",
                "add a node",
                "انشاء عقدة",
                "انشاء عقدة جديدة",
                "أضف عقدة",
                "اضف عقدة",
                "عقدة جديدة",
                "سوي عقدة"
            ]
        case .summonCoCaptain:
            return [
                "summon cocaptain",
                "open cocaptain",
                "open co captain",
                "show cocaptain",
                "افتح المساعد",
                "افتح مساعد الذكاء الاصطناعي",
                "استدع المساعد"
            ]
        case .summonCopilotVoice:
            return [
                "voice call",
                "call copilot",
                "voice copilot",
                "start voice call",
                "مكالمة صوتية",
                "اتصل بالمساعد",
                "صوت المساعد"
            ]
        case .summonCopilotVideo:
            return [
                "screen share",
                "share screen",
                "video call",
                "screen share with copilot",
                "مشاركة الشاشة",
                "شارك الشاشة",
                "مكالمة فيديو"
            ]
        case .undo:
            return [
                "undo",
                "undo last",
                "تراجع",
                "تراجع عن اخر تغيير",
                "الغاء اخر تغيير"
            ]
        case .redo:
            return [
                "redo",
                "redo last",
                "اعادة",
                "اعد",
                "اعد اخر تغيير"
            ]
        case .openFile:
            return [
                "open file",
                "choose file",
                "افتح ملف",
                "اختر ملف"
            ]
        case .toggleGrid:
            return [
                "toggle grid",
                "show grid",
                "hide grid",
                "الشبكة",
                "اظهر الشبكة",
                "اخف الشبكة"
            ]
        case .shareCanvas:
            return [
                "share canvas",
                "share project",
                "share",
                "مشاركة اللوحة",
                "مشاركة المشروع",
                "شارك اللوحة",
                "شارك المشروع",
                "مشاركة"
            ]
        case .proSubscription:
            return [
                "pro subscription",
                "upgrade",
                "subscribe",
                "اشتراك",
                "اشترك",
                "ترقية",
                "الاشتراك الاحترافي"
            ]
        case .signIn:
            return [
                "sign in",
                "login",
                "log in",
                "تسجيل الدخول",
                "سجل الدخول",
                "ادخل"
            ]
        case .openSettings:
            return [
                "open settings",
                "settings",
                "اعدادات",
                "الإعدادات",
                "افتح الاعدادات",
                "افتح الإعدادات"
            ]
        case .openProfile:
            return [
                "open profile",
                "profile",
                "الحساب",
                "الملف الشخصي",
                "افتح الحساب",
                "افتح الملف الشخصي"
            ]
        case .help:
            return [
                "help",
                "open help",
                "help center",
                "open help center",
                "documentation",
                "docs",
                "مساعدة",
                "المساعدة",
                "افتح المساعدة",
                "مركز المساعدة",
                "التوثيق"
            ]
        case .moveNode:
            return ["move node", "تحريك", "انقل"]
        case .themeNode:
            return ["change theme", "theme", "تغيير المظهر", "تغيير الثيم"]
        case .transformNode:
            return ["change type", "transform", "تغيير النوع", "تحويل"]
        case .organizeNodes:
            return [
                "organize nodes",
                "organize",
                "arrange nodes",
                "arrange",
                "magic wand",
                "clean up",
                "ترتيب العقد",
                "رتب العقد",
                "نظم العقد",
                "ترتيب"
            ]
        case .openSnapshotBrowser:
            return [
                "open snapshot browser",
                "snapshot browser",
                "browse checkpoints",
                "checkpoints",
                "show checkpoints",
                "نقاط الاستعادة",
                "سجل التغييرات",
                "عرض نقاط الاستعادة"
            ]
        case .toggleHUD:
            return [
                "toggle hud",
                "show hud",
                "hide hud",
                "اظهر الواجهة",
                "اخف الواجهة",
                "الواجهة",
                "تبديل الواجهة"
            ]
        case .showActionsList:
            return [
                "show actions list",
                "show actions",
                "command palette",
                "actions list",
                "قائمة الإجراءات",
                "قائمة الاجراءات",
                "عرض قائمة الإجراءات",
                "عرض قائمة الاجراءات"
            ]
        case .createSubCanvas:
            return [
                "create sub canvas",
                "create subcanvas",
                "new sub canvas",
                "new subcanvas",
                "add sub canvas",
                "add subcanvas",
                "create nested canvas",
                "new nested canvas",
                "انشاء مساحة فرعية",
                "مساحة فرعية جديدة",
                "أضف مساحة فرعية",
                "اضف مساحة فرعية",
                "سوي مساحة فرعية",
                "انشاء لوحة فرعية",
                "لوحة فرعية جديدة"
            ]
        case .openActivity:
            return [
                "open activity",
                "activity",
                "show activity",
                "النشاط",
                "الفعالية",
                "افتح النشاط",
                "سجل النشاط"
            ]
        case .openDaily:
            return [
                "open daily",
                "daily",
                "daily challenges",
                "اليومي",
                "التحديات اليومية",
                "افتح اليومي",
                "التحدي اليومي"
            ]
        case .openWhatsApp:
            return [
                "open whatsapp",
                "whatsapp",
                "message azzam",
                "contact azzam",
                "واتساب",
                "واتس",
                "افتح واتساب",
                "راسل عزام"
            ]
        case .openAppIcon:
            return [
                "app icon",
                "change app icon",
                "alternate icon",
                "home screen icon",
                "ايقونة التطبيق",
                "أيقونة التطبيق",
                "غير ايقونة التطبيق",
                "تغيير ايقونة التطبيق"
            ]
        case .changeCopilot:
            return [
                "change copilot",
                "switch copilot",
                "choose copilot",
                "change co pilot",
                "switch co pilot",
                "change cocaptain",
                "switch costar",
                "غير المساعد",
                "تبديل المساعد",
                "اختر المساعد",
                "غير الكوبايلوت"
            ]
        case .openUsage:
            return [
                "usage",
                "view usage",
                "open usage",
                "token usage",
                "tokens",
                "quota",
                "limits",
                "free tier",
                "mini app limit",
                "استخدام",
                "الاستخدام",
                "افتح الاستخدام",
                "عرض الاستخدام",
                "الحد",
                "الحصة"
            ]
        }
    }

    /// Normalization removes punctuation and diacritics so aliases can match
    /// common voice/input variations across English and Arabic.
    static func normalizedCommandInput(_ value: String) -> String {
        normalized(value)
    }

    /// Normalization removes punctuation and diacritics so aliases can match
    /// common voice/input variations across English and Arabic.
    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Single-word aliases require exact matches; multi-word aliases may appear
    /// inside a longer request such as "please create a project".
    private static func matches(_ normalizedInput: String, alias: String) -> Bool {
        let normalizedAlias = normalized(alias)
        guard !normalizedAlias.isEmpty else { return false }
        guard normalizedInput != normalizedAlias else { return true }
        guard normalizedAlias.contains(" ") else { return false }
        return " \(normalizedInput) ".contains(" \(normalizedAlias) ")
    }

    /// Refuses commands with explicit negation so phrases like "do not create a
    /// project" cannot trigger a mutating action.
    static func hasNegation(in normalizedInput: String) -> Bool {
        let negations = [
            "dont",
            "do not",
            "never",
            "لا",
            "لات",
            "مو",
            "مش"
        ]

        return negations.contains { negation in
            " \(normalizedInput) ".contains(" \(normalized(negation)) ")
        }
    }
}
