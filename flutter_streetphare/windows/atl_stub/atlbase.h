// atl_stub/atlbase.h — Stub ATL minimal pour flutter_local_notifications_windows
// ============================================================================
// Remplace les headers ATL manquants sur les toolchains VS BuildTools sans le
// composant "C++ ATL". Le plugin utilise UNIQUEMENT CW2A.
//
// Pour supprimer ce workaround : installer "C++ ATL for v143/v180 build tools"
// via le VS Installer.
#pragma once

#ifndef _WIN32
#  error "Ce stub ATL est Windows-only."
#endif

#include <windows.h>
#include <string>

// ── CW2A — Wide char to narrow string (UTF-8) ──────────────────────────────
// Équivalent de ATL::CW2A : convertit un LPCWSTR en const char* (UTF-8)
// sans dépendre du runtime ATL.
//
// Seul operator const char*() est exposé (pas operator std::string()) afin
// d'éviter l'ambiguïté de conversion lors d'expressions comme :
//   const std::string s = std::string(CW2A(wideStr));
// Dans ce cas le compilateur choisit le chemin : CW2A → const char* → std::string.
class CW2A {
public:
    explicit CW2A(LPCWSTR wide, UINT codePage = CP_UTF8) {
        if (!wide) return;
        const int len = ::WideCharToMultiByte(
            codePage, 0, wide, -1, nullptr, 0, nullptr, nullptr);
        if (len > 0) {
            m_buf.resize(static_cast<size_t>(len));
            ::WideCharToMultiByte(
                codePage, 0, wide, -1, m_buf.data(), len, nullptr, nullptr);
            // len inclut le '\0' terminal — on le conserve dans le buffer
            // car operator const char*() doit retourner une C-string terminée.
        }
    }

    // Conversion implicite vers const char* — utilisé par std::string(CW2A(x))
    // et tous les appels attendant un LPCSTR / const char*.
    operator const char*() const noexcept {
        return m_buf.empty() ? "" : m_buf.c_str();
    }

    // Accès direct
    const char* c_str() const noexcept {
        return m_buf.empty() ? "" : m_buf.c_str();
    }

private:
    std::string m_buf;
};
