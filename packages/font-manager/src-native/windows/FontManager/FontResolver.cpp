#include "pch.h"
#include "FontResolver.h"

// DirectWrite font validation/extraction — included here (not in pch.h) to keep COM headers out of
// the shared PCH (mirrors widgets-cpp FontHelper.cpp).
#include <dwrite_3.h>
#pragma comment(lib, "dwrite.lib")
#include <robuffer.h> // IBufferByteAccess (raw bytes behind an IBuffer)
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Headers.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.System.Threading.h>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <unordered_map>
#include <cwctype>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::System::Threading;
using namespace winrt::Windows::Web::Http;
using namespace winrt::Windows::Security::Cryptography;

namespace
{
    constexpr uint64_t kRequestTimeoutMs = 15'000;
    constexpr size_t kMaxFamilyEntries = 256;

    std::wstring ToLower(std::wstring s)
    {
        for (auto& ch : s) ch = static_cast<wchar_t>(towlower(ch));
        return s;
    }

    bool StartsWith(std::wstring const& s, std::wstring const& prefix)
    {
        return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
    }

    // Raw bytes behind an IBuffer (the loader/DirectWrite copy them, so the pointer is only needed
    // for the duration of the call).
    uint8_t* BufferBytes(IBuffer const& buffer, uint32_t& size)
    {
        size = buffer ? buffer.Length() : 0;
        if (!size) return nullptr;
        auto access = buffer.as<::Windows::Storage::Streams::IBufferByteAccess>();
        uint8_t* data = nullptr;
        check_hresult(access->Buffer(&data));
        return data;
    }

    IBuffer BytesToBuffer(std::vector<uint8_t> const& bytes)
    {
        return CryptographicBuffer::CreateFromByteArray(bytes);
    }

    // Extracts the en-us (or first) string from an IDWriteLocalizedStrings. (From FontHelper.cpp.)
    std::wstring LocalizedString(IDWriteLocalizedStrings* strings)
    {
        if (!strings || strings->GetCount() == 0) return L"";
        UINT32 index = 0;
        BOOL exists = FALSE;
        if (FAILED(strings->FindLocaleName(L"en-us", &index, &exists)) || !exists) index = 0;
        UINT32 length = 0;
        if (FAILED(strings->GetStringLength(index, &length)) || length == 0) return L"";
        std::wstring value;
        value.resize(static_cast<size_t>(length) + 1);
        if (FAILED(strings->GetString(index, value.data(), length + 1))) return L"";
        value.resize(length);
        return value;
    }

    std::wstring FontProperty(IDWriteFontSet* fontSet, UINT32 index, DWRITE_FONT_PROPERTY_ID prop)
    {
        BOOL exists = FALSE;
        com_ptr<IDWriteLocalizedStrings> strings;
        if (FAILED(fontSet->GetPropertyValues(index, prop, &exists, strings.put())) || !exists) return L"";
        return LocalizedString(strings.get());
    }

    std::wstring FamilyFromFontSet(IDWriteFontSet* fontSet)
    {
        if (!fontSet || fontSet->GetFontCount() == 0) return L"";
        std::wstring family = FontProperty(fontSet, 0, DWRITE_FONT_PROPERTY_ID_WIN32_FAMILY_NAME);
        if (family.empty()) family = FontProperty(fontSet, 0, DWRITE_FONT_PROPERTY_ID_TYPOGRAPHIC_FAMILY_NAME);
        if (family.empty()) family = FontProperty(fontSet, 0, DWRITE_FONT_PROPERTY_ID_WEIGHT_STRETCH_STYLE_FAMILY_NAME);
        return family;
    }

    // Created once: the shared factory is free-threaded. Deliberately leaked so nothing is released
    // while the DLL unloads.
    com_ptr<IDWriteFactory5> DWriteFactory()
    {
        static IDWriteFactory5* const factory = [] {
            com_ptr<IDWriteFactory5> created;
            check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory5),
                reinterpret_cast<::IUnknown**>(created.put())));
            return created.detach();
        }();
        com_ptr<IDWriteFactory5> result;
        result.copy_from(factory);
        return result;
    }

    // One client for every request so connections are reused. Leaked for the same reason as the
    // factory.
    HttpClient SharedHttpClient()
    {
        static void* const abi = detach_abi(HttpClient());
        HttpClient client{ nullptr };
        copy_from_abi(client, abi);
        return client;
    }

    // Downloads `url` into memory. Windows.Web.Http has no request timeout, so cancel once no bytes
    // have arrived for kRequestTimeoutMs. Throws hresult_error on timeout, network failure, a non-2xx
    // status or a truncated/empty body.
    IAsyncOperation<IBuffer> DownloadBufferAsync(hstring url)
    {
        IAsyncOperationWithProgress<HttpResponseMessage, HttpProgress> request{ nullptr };
        try { request = SharedHttpClient().GetAsync(Uri{ url }); }
        catch (hresult_error const& e) { throw hresult_error(E_FAIL, L"Download of " + url + L" failed: " + e.message()); }

        auto lastActivity = std::make_shared<std::atomic<uint64_t>>(GetTickCount64());
        request.Progress([lastActivity](IAsyncOperationWithProgress<HttpResponseMessage, HttpProgress> const&, HttpProgress const&) {
            lastActivity->store(GetTickCount64());
        });
        auto watchdog = ThreadPoolTimer::CreatePeriodicTimer([request, lastActivity](ThreadPoolTimer const&) {
            if (GetTickCount64() - lastActivity->load() > kRequestTimeoutMs) request.Cancel();
        }, std::chrono::seconds(1));

        HttpResponseMessage response{ nullptr };
        hstring failure;
        try { response = co_await request; }
        catch (hresult_canceled const&) { failure = L"Download of " + url + L" timed out"; }
        catch (hresult_error const& e) { failure = L"Download of " + url + L" failed: " + e.message(); }
        catch (...) { watchdog.Cancel(); throw; }
        watchdog.Cancel();
        if (!failure.empty()) throw hresult_error(E_FAIL, failure);

        if (!response.IsSuccessStatusCode())
        {
            throw hresult_error(E_FAIL, L"Download of " + url + L" failed with HTTP "
                + to_hstring(static_cast<int32_t>(response.StatusCode())));
        }

        auto content = response.Content();
        IBuffer buffer = co_await content.ReadAsBufferAsync();
        uint32_t received = buffer ? buffer.Length() : 0;

        // Encoded responses announce the encoded length.
        auto headers = content.Headers();
        auto encodings = headers.ContentEncoding();
        bool identity = encodings.Size() == 0
            || (encodings.Size() == 1 && ToLower(std::wstring(encodings.GetAt(0).ContentCoding())) == L"identity");
        auto expected = headers.ContentLength();
        if (identity && expected && expected.Value() != received)
        {
            throw hresult_error(E_FAIL, L"Download of " + url + L" ended after " + to_hstring(received)
                + L" of " + to_hstring(expected.Value()) + L" bytes");
        }
        if (received == 0) throw hresult_error(E_FAIL, L"Download of " + url + L" was empty");
        co_return buffer;
    }

    // file:// URI or bare filesystem path -> filesystem path.
    std::filesystem::path LocalPath(std::wstring const& src)
    {
        std::wstring path = src;
        if (StartsWith(ToLower(src), L"file://"))
        {
            path = src.substr(std::wstring(L"file://").size());
            // file:///C:/... -> strip the leading slash before a drive letter
            if (path.size() >= 3 && path[0] == L'/' && path[2] == L':') path = path.substr(1);
        }
        return std::filesystem::path(path);
    }

    // Resolved once; directories are (re)created by WriteCacheFile.
    std::filesystem::path const& FontCacheDir()
    {
        static std::filesystem::path const dir = [] {
            try
            {
                auto local = ApplicationData::Current().LocalFolder().Path();
                return std::filesystem::path(std::wstring(local)) / L"ns_fonts";
            }
            catch (...)
            {
                return std::filesystem::temp_directory_path() / L"ns_fonts";
            }
        }();
        return dir;
    }

    // FNV-1a: keys cache files by content or URL (collision-resistant enough for either).
    uint64_t Fnv1a(void const* data, size_t size)
    {
        auto bytes = static_cast<uint8_t const*>(data);
        uint64_t h = 1469598103934665603ULL;
        for (size_t i = 0; i < size; i++) { h ^= bytes[i]; h *= 1099511628211ULL; }
        return h;
    }

    // Extension from the sfnt signature (DirectWrite reads ttf/otf/ttc; default ttf).
    wchar_t const* SfntExtension(uint8_t const* ptr, uint32_t size)
    {
        if (size >= 4)
        {
            if (ptr[0] == 'O' && ptr[1] == 'T' && ptr[2] == 'T' && ptr[3] == 'O') return L".otf";
            if (ptr[0] == 't' && ptr[1] == 't' && ptr[2] == 'c' && ptr[3] == 'f') return L".ttc";
        }
        return L".ttf";
    }

    std::wstring CacheFileName(wchar_t const* prefix, uint64_t hash, wchar_t const* ext)
    {
        wchar_t name[64];
        swprintf_s(name, L"%s_%016llx%s", prefix, static_cast<unsigned long long>(hash), ext);
        return name;
    }

    // Writes through a temp file + rename, so a crash mid-write never leaves a truncated file under
    // the final name (both caches trust any file that exists). Losing a rename race to an identical
    // concurrent write counts as success.
    bool WriteCacheFile(std::wstring const& fileName, uint8_t const* ptr, uint32_t size)
    {
        static std::atomic<uint32_t> counter{ 0 };
        auto const& dir = FontCacheDir();
        std::error_code ec;
        std::filesystem::create_directories(dir, ec);

        auto target = dir / fileName;
        auto temp = dir / (fileName + L"." + std::to_wstring(GetCurrentProcessId()) + L"_"
            + std::to_wstring(counter++) + L".part");
        std::ofstream out(temp, std::ios::binary);
        out.write(reinterpret_cast<const char*>(ptr), static_cast<std::streamsize>(size));
        out.close();
        if (!out)
        {
            std::filesystem::remove(temp, ec);
            return false;
        }

        std::filesystem::rename(temp, target, ec);
        if (ec)
        {
            std::filesystem::remove(temp, ec);
            return std::filesystem::exists(target, ec);
        }
        return true;
    }

    // Resolved family per font file, keyed by path + size + write time so a replaced file is read
    // again.
    std::mutex g_familyMutex;
    std::unordered_map<std::wstring, std::wstring> g_familyByFile;

    bool FileKey(std::wstring const& path, std::wstring& key)
    {
        WIN32_FILE_ATTRIBUTE_DATA attrs{};
        if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attrs)) return false;
        uint64_t size = (static_cast<uint64_t>(attrs.nFileSizeHigh) << 32) | attrs.nFileSizeLow;
        uint64_t written = (static_cast<uint64_t>(attrs.ftLastWriteTime.dwHighDateTime) << 32)
            | attrs.ftLastWriteTime.dwLowDateTime;
        key = path + L"|" + std::to_wstring(size) + L"|" + std::to_wstring(written);
        return true;
    }
}

namespace NativeScript::FontManager::resolver
{
    std::wstring ResolveGenericFamily(std::wstring const& family)
    {
        static const std::map<std::wstring, std::wstring> generics = {
            { L"serif", L"Times New Roman" },
            { L"sans-serif", L"Segoe UI" },
            { L"monospace", L"Consolas" },
            { L"cursive", L"Segoe Script" },
            { L"fantasy", L"Impact" },
            { L"system-ui", L"Segoe UI" },
            { L"ui-serif", L"Times New Roman" },
            { L"ui-sans-serif", L"Segoe UI" },
            { L"ui-monospace", L"Consolas" },
            { L"ui-rounded", L"Segoe UI" },
            { L"emoji", L"Segoe UI Emoji" },
        };
        auto it = generics.find(ToLower(family));
        return it != generics.end() ? it->second : family;
    }

    bool IsGenericFamily(std::wstring const& family)
    {
        static const std::vector<std::wstring> generics = {
            L"serif", L"sans-serif", L"monospace", L"cursive", L"fantasy",
            L"system-ui", L"ui-serif", L"ui-sans-serif", L"ui-monospace",
            L"ui-rounded", L"math", L"emoji", L"fangsong"
        };
        std::wstring f = ToLower(family);
        for (auto const& g : generics) if (g == f) return true;
        return false;
    }

    IAsyncOperation<IBuffer> FetchFontDataAsync(hstring src)
    {
        std::wstring s(src);
        std::wstring lower = ToLower(s);

        if (StartsWith(lower, L"http://") || StartsWith(lower, L"https://"))
        {
            try
            {
                IBuffer buffer = co_await DownloadBufferAsync(src);
                co_return buffer;
            }
            catch (...) { co_return nullptr; }
        }

        if (StartsWith(lower, L"ms-appx:"))
        {
            try
            {
                auto file = co_await StorageFile::GetFileFromApplicationUriAsync(Uri{ src });
                IBuffer buffer = co_await FileIO::ReadBufferAsync(file);
                co_return buffer;
            }
            catch (...) { co_return nullptr; }
        }

        if (StartsWith(lower, L"data:"))
        {
            co_return nullptr; // data: URIs are decoded in the JS layer, mirrors iOS returning nil
        }

        // file:// or a bare filesystem path. Read off the calling thread via std streams (works
        // packaged and unpackaged, avoids StorageFile broad-filesystem-access restrictions).
        auto path = LocalPath(s);

        co_await resume_background();
        try
        {
            std::ifstream in(path, std::ios::binary);
            if (!in) co_return nullptr;
            std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            if (bytes.empty()) co_return nullptr;
            co_return BytesToBuffer(bytes);
        }
        catch (...) { co_return nullptr; }
    }

    IAsyncOperation<hstring> DownloadFontAsync(hstring url)
    {
        std::wstring_view key(url);
        uint64_t hash = Fnv1a(key.data(), key.size() * sizeof(wchar_t));

        // The extension comes from the downloaded bytes, so probe each one DirectWrite reads.
        std::error_code ec;
        for (auto ext : { L".ttf", L".otf", L".ttc" })
        {
            auto name = CacheFileName(L"url", hash, ext);
            if (std::filesystem::exists(FontCacheDir() / name, ec)) co_return hstring(name);
        }

        IBuffer buffer = co_await DownloadBufferAsync(url);
        uint32_t size = 0;
        uint8_t* ptr = BufferBytes(buffer, size);
        auto name = CacheFileName(L"url", hash, SfntExtension(ptr, size));
        if (!WriteCacheFile(name, ptr, size))
        {
            throw hresult_error(E_FAIL, L"Could not write the download of " + url + L" to the font cache");
        }
        co_return hstring(name);
    }

    IAsyncOperation<hstring> ResolveLocalFontPathAsync(hstring src)
    {
        std::wstring s(src);
        std::wstring lower = ToLower(s);

        if (StartsWith(lower, L"ms-appx:"))
        {
            try
            {
                auto file = co_await StorageFile::GetFileFromApplicationUriAsync(Uri{ src });
                co_return file.Path();
            }
            catch (...) { co_return hstring(); }
        }

        if (StartsWith(lower, L"data:") || StartsWith(lower, L"http://") || StartsWith(lower, L"https://"))
        {
            co_return hstring();
        }

        std::error_code ec;
        auto path = std::filesystem::absolute(LocalPath(s), ec);
        if (ec) co_return hstring();
        co_return hstring(path.make_preferred().wstring());
    }

    bool ValidateAndExtractFamilyFromFile(std::wstring const& path, std::wstring& outFamily, std::wstring& error)
    {
        std::wstring key;
        if (!FileKey(path, key)) { error = L"Failed to open font file"; return false; }
        {
            std::lock_guard lock(g_familyMutex);
            if (auto it = g_familyByFile.find(key); it != g_familyByFile.end())
            {
                outFamily = it->second;
                return true;
            }
        }

        try
        {
            auto factory = DWriteFactory();
            com_ptr<IDWriteFontFile> file;
            if (FAILED(factory->CreateFontFileReference(path.c_str(), nullptr, file.put())) || !file)
            {
                error = L"Failed to open font file";
                return false;
            }
            BOOL isSupported = FALSE;
            DWRITE_FONT_FILE_TYPE fileType = DWRITE_FONT_FILE_TYPE_UNKNOWN;
            DWRITE_FONT_FACE_TYPE faceType = DWRITE_FONT_FACE_TYPE_UNKNOWN;
            UINT32 numberOfFaces = 0;
            file->Analyze(&isSupported, &fileType, &faceType, &numberOfFaces);
            if (!isSupported) { error = L"Unsupported font file"; return false; }

            com_ptr<IDWriteFontSetBuilder1> builder;
            check_hresult(factory->CreateFontSetBuilder(builder.put()));
            builder->AddFontFile(file.get());
            com_ptr<IDWriteFontSet> set;
            check_hresult(builder->CreateFontSet(set.put()));
            outFamily = FamilyFromFontSet(set.get());
        }
        catch (winrt::hresult_error const& e) { error = e.message().c_str(); return false; }
        catch (...) { error = L"Failed to register font file"; return false; }

        std::lock_guard lock(g_familyMutex);
        if (g_familyByFile.size() >= kMaxFamilyEntries) g_familyByFile.clear();
        g_familyByFile.emplace(std::move(key), outFamily);
        return true;
    }

    std::wstring PersistFontData(IBuffer const& data)
    {
        uint32_t size = 0;
        uint8_t* ptr = nullptr;
        try { ptr = BufferBytes(data, size); }
        catch (...) { return L""; }
        if (!ptr || !size) return L"";

        // Content hash so identical bytes dedupe to one file (mirrors the spirit of iOS's
        // length-keyed cache, but collision-resistant).
        auto fileName = CacheFileName(L"font", Fnv1a(ptr, size), SfntExtension(ptr, size));
        std::error_code ec;
        if (std::filesystem::exists(FontCacheDir() / fileName, ec)) return fileName;
        return WriteCacheFile(fileName, ptr, size) ? fileName : L"";
    }

    std::wstring FontCachePath(std::wstring const& fileName)
    {
        return (FontCacheDir() / fileName).wstring();
    }
}
