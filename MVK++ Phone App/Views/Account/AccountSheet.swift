//
//  AccountSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// Fiók és felhős mentés (web `AccountModal`): passkey sign-up or sign-in,
/// then the sync status and its actions.
struct AccountSheet: View {
    private enum Mode { case new, existing }

    @State private var session = AccountSession.current
    @State private var mode: Mode = .new
    @State private var email = ""
    @State private var busy = false
    @State private var error: String?
    @State private var status: BackupStatus?
    @State private var statusBusy = false
    @State private var actionNote: String?
    @State private var confirmPull = false
    @State private var confirmLogout = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: "person", title: "Fiók és felhős mentés")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session {
                        signedIn(session)
                    } else {
                        signedOut
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: session) { await loadStatus() }
        .confirmationDialog("Ez az eszköz összes beállítását a felhőben lévő állapotra cseréli. Folytatod?", isPresented: $confirmPull, titleVisibility: .visible) {
            Button("Betöltés a felhőből", role: .destructive) { Task { await pullFromCloud() } }
            Button("Mégse", role: .cancel) {}
        }
        .confirmationDialog("Kijelentkezel erről az eszközről? A felhőben mentett adat megmarad.", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Kijelentkezés", role: .destructive) {
                Task {
                    await AccountService.logout()
                    session = nil
                    status = nil
                }
            }
            Button("Mégse", role: .cancel) {}
        }
    }

    // MARK: - Signed out

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                modeButton("Új fiók", .new)
                modeButton("Van már fiókom", .existing)
            }
            .padding(4)
            .background(Theme.muted.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel("E-mail cím")
                TextField("", text: $email, prompt: Text("pl. nev@pelda.hu").foregroundStyle(Theme.mutedForeground))
                    .textFieldStyle(MVKTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { Task { await authenticate() } }
                Button {
                    Task { await authenticate() }
                } label: {
                    Label(busy ? "Várakozás a hitelesítőre…" : (mode == .new ? "Passkey létrehozása" : "Bejelentkezés passkey-vel"), systemImage: "touchid")
                        .symbolEffect(.pulse, isActive: busy)
                }
                .buttonStyle(.mvk(.primary, fullWidth: true))
                .disabled(busy || !email.contains("@"))
            }

            if let error {
                DestructiveNote(text: error)
            }
        }
    }

    private func modeButton(_ title: String, _ value: Mode) -> some View {
        let isOn = mode == value
        return Button { mode = value } label: {
            Text(title)
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(isOn ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func authenticate() async {
        guard !busy, email.contains("@") else { return }
        busy = true
        error = nil
        let address = email.trimmingCharacters(in: .whitespaces)
        let result = mode == .new ? await AccountService.register(email: address) : await AccountService.login(email: address)
        busy = false
        switch result {
        case .success(let value): session = value
        case .failure(.reason(let reason)): error = reason
        }
    }

    // MARK: - Signed in

    private func signedIn(_ session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.primary)
                    Text(session.email)
                        .font(Theme.sans(14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(statusBusy ? "Állapot lekérdezése…" : "Utolsó szinkron: \(Self.when(status?.lastBackupAt)) · \(status?.credentialCount ?? 1) passkey")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.muted.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

            HStack(spacing: 8) {
                Button { Task { await syncNow() } } label: {
                    Label("Szinkron most", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(.mvk(.outline, size: .small, fullWidth: true))
                Button("Betöltés a felhőből") { confirmPull = true }
                    .buttonStyle(.mvk(.outline, size: .small, fullWidth: true))
            }
            .disabled(statusBusy)

            if let actionNote {
                Text(actionNote)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Text("Minden beállításod (figyelt megállók, kedvencek, értesítések, térkép- és szűrőbeállítások) automatikusan szinkronban van az összes bejelentkezett eszközöddel: ami itt változik, másodpercek alatt megjelenik a többin is. Ütközésnél a később módosított érték nyer.")
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Button { Task { await addDevice() } } label: {
                Label("Új eszköz/passkey hozzáadása", systemImage: "touchid")
            }
            .buttonStyle(.mvk(.ghost, size: .small, fullWidth: true))
            .disabled(statusBusy)

            Button { confirmLogout = true } label: {
                Label("Kijelentkezés erről az eszközről", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(Theme.mutedForeground)
            }
            .buttonStyle(.mvk(.ghost, size: .small, fullWidth: true))
        }
    }

    private static func when(_ unix: Double?) -> String {
        guard let unix, unix > 0 else { return "még nem történt mentés" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: unix))
    }

    private func loadStatus() async {
        guard session != nil else { return }
        statusBusy = true
        if case .success(let value) = await AccountService.status() { status = value } else { status = nil }
        statusBusy = false
    }

    private func syncNow() async {
        statusBusy = true
        actionNote = nil
        let sync = CloudSync.shared
        await sync.push()
        let changed = await sync.pull()
        if sync.state == .error {
            actionNote = sync.error ?? "A szinkron nem sikerült."
        } else {
            actionNote = changed.isEmpty ? "Szinkronizálva." : "Szinkronizálva: \(changed.count) beállítás érkezett a felhőből."
        }
        if case .success(let value) = await AccountService.status() { status = value }
        statusBusy = false
        // The screens must see the downloaded settings, or the next local edit
        // would overwrite them with the stale in-memory value.
        if !changed.isEmpty {
            try? await Task.sleep(for: .milliseconds(900))
            AppReloader.shared.reload()
        }
    }

    private func pullFromCloud() async {
        statusBusy = true
        actionNote = nil
        let changed = await CloudSync.shared.pull(full: true)
        statusBusy = false
        if changed.isEmpty {
            actionNote = "Ezen az eszközön már a felhőben lévő állapot van."
        } else {
            AppReloader.shared.reload()
        }
    }

    private func addDevice() async {
        statusBusy = true
        actionNote = nil
        switch await AccountService.addPasskey() {
        case .success: actionNote = "Új passkey hozzáadva ehhez a fiókhoz."
        case .failure(.reason(let reason)): actionNote = reason
        }
        statusBusy = false
    }
}
