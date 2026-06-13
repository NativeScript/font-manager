#pragma once
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <string>

// Pure C++/WinRT font I/O helpers (no projection). Ports NSCFontResolver: generic-family mapping,
// fetching font bytes (http / file / ms-appx), DirectWrite validation + real-family extraction, and
// persisting downloaded/in-memory fonts so they can be referenced by a ms-appdata URI.
namespace NativeScript::FontManager::resolver
{
    // Maps a CSS generic family (serif, sans-serif, ...) to a concrete Windows font; returns the
    // input unchanged when it is not a generic keyword. Mirrors NSCFontResolver resolveGenericFamily:.
    std::wstring ResolveGenericFamily(std::wstring const& family);

    // True for CSS generic family keywords. Mirrors NSCFontFaceSet _isGeneric:.
    bool IsGenericFamily(std::wstring const& family);

    // Downloads/reads the raw font bytes for `src`. Supports http(s), file:// + bare paths, and
    // ms-appx:. Returns nullptr (with `error` set) for data: / unsupported schemes or I/O failure.
    winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::Streams::IBuffer>
        FetchFontDataAsync(winrt::hstring src);

    // Validates font bytes via DirectWrite and extracts the font's real (Win32/typographic) family
    // name into `outFamily`. Returns false with `error` set when the bytes aren't a usable sfnt font.
    bool ValidateAndExtractFamily(winrt::Windows::Storage::Streams::IBuffer const& data,
                                  std::wstring& outFamily, std::wstring& error);

    // As above, for an on-disk font file.
    bool ValidateAndExtractFamilyFromFile(std::wstring const& path, std::wstring& outFamily, std::wstring& error);

    // Persists font bytes under ApplicationData LocalFolder\ns_fonts (or the temp dir when unpackaged,
    // e.g. the native test harness). Returns the bare file name written (empty on failure); the caller
    // builds the ms-appdata:///local/ns_fonts/<name> URI from it.
    std::wstring PersistFontData(winrt::Windows::Storage::Streams::IBuffer const& data);
}
