//
//  GlobalHotKey.swift
//  TidyRAM
//
//  Systemweites Tastenkürzel ⌃⌥⌘R ("R" wie RAM), das überall funktioniert –
//  auch wenn das TidyRAM-Fenster geschlossen ist.
//
//  Verwendet wird die alte, aber weiterhin unterstützte Carbon-Funktion
//  `RegisterEventHotKey`. Vorteil: Sie braucht KEINE Bedienungshilfen-
//  Berechtigung, weil sie nur genau dieses eine Kürzel abfängt und keine
//  Tastatureingaben mitliest.
//

import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    /// Wird beim Drücken ausgeführt. Statisch, weil der C-Callback unten keine
    /// Variablen "einfangen" darf.
    private static var action: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Anzeigetext für die Oberfläche.
    static let displayString = "⌃⌥⌘R"

    /// Registriert ⌃⌥⌘R. Ein vorher registriertes Kürzel wird ersetzt.
    func register(action: @escaping @MainActor () -> Void) {
        unregister()
        Self.action = action

        // Auf das Ereignis "Hotkey gedrückt" lauschen.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon ruft das auf dem Haupt-Thread auf.
            MainActor.assumeIsolated { GlobalHotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        // Kürzel anmelden: Taste R + Control + Option + Command.
        let id = EventHotKeyID(signature: OSType(0x5452_414D), id: 1)  // 'TRAM'
        RegisterEventHotKey(UInt32(kVK_ANSI_R),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Meldet das Kürzel wieder ab.
    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        Self.action = nil
    }
}
