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
    // ms-appx:. Returns nullptr for data: / unsupported schemes or I/O failure.
    winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::Streams::IBuffer>
        FetchFontDataAsync(winrt::hstring src);

    // Local copy of a remote font, keyed by URL: the first call downloads into the font cache dir,
    // later calls (including after a restart) return the existing file without touching the network. Resolves to the cached file name; throws hresult_error
    // describing the failure (HTTP status, truncated body, timeout).
    winrt::Windows::Foundation::IAsyncOperation<winrt::hstring> DownloadFontAsync(winrt::hstring url);

    // Resolves a local source (file://, bare path, ms-appx:) to an absolute on-disk path, so it can be
    // validated in place instead of being read into memory. Empty when it can't be resolved.
    winrt::Windows::Foundation::IAsyncOperation<winrt::hstring> ResolveLocalFontPathAsync(winrt::hstring src);

    // Validates an on-disk font file via DirectWrite and extracts its real (Win32/typographic) family
    // name into `outFamily`. Memoized per path + size + write time. Returns false with `error` set
    // when the file isn't a usable sfnt font.
    bool ValidateAndExtractFamilyFromFile(std::wstring const& path, std::wstring& outFamily, std::wstring& error);

    // Persists font bytes under the font cache dir, named by content hash so identical bytes dedupe
    // to one file. Returns the bare file name written (empty on failure).
    std::wstring PersistFontData(winrt::Windows::Storage::Streams::IBuffer const& data);

    // Full path of `fileName` in the font cache dir: ApplicationData LocalFolder\ns_fonts, or the temp
    // dir when unpackaged (e.g. the native test harness). The caller builds the
    // ms-appdata:///local/ns_fonts/<name> URI from the bare name.
    std::wstring FontCachePath(std::wstring const& fileName);
}
