#include "pch.h"
#include "FontResolver.h"

// DirectWrite font validation/extraction — included here (not in pch.h) to keep COM headers out of
// the shared PCH (mirrors widgets-cpp FontHelper.cpp).
#include <dwrite_3.h>
#pragma comment(lib, "dwrite.lib")
#include <robuffer.h> // IBufferByteAccess (raw bytes behind an IBuffer)
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <cwctype>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Web::Http;
using namespace winrt::Windows::Security::Cryptography;

namespace
{
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

    com_ptr<IDWriteFactory5> DWriteFactory()
    {
        com_ptr<IDWriteFactory5> factory;
        check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory5),
            reinterpret_cast<::IUnknown**>(factory.put())));
        return factory;
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
                HttpClient client;
                Uri uri{ src };
                IBuffer buffer = co_await client.GetBufferAsync(uri);
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
        std::wstring path = s;
        if (StartsWith(lower, L"file://"))
        {
            path = s.substr(std::wstring(L"file://").size());
            // file:///C:/... -> strip the leading slash before a drive letter
            if (path.size() >= 3 && path[0] == L'/' && path[2] == L':') path = path.substr(1);
        }

        co_await resume_background();
        try
        {
            std::ifstream in(std::filesystem::path(path), std::ios::binary);
            if (!in) co_return nullptr;
            std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            if (bytes.empty()) co_return nullptr;
            co_return BytesToBuffer(bytes);
        }
        catch (...) { co_return nullptr; }
    }

    bool ValidateAndExtractFamily(IBuffer const& data, std::wstring& outFamily, std::wstring& error)
    {
        uint32_t size = 0;
        uint8_t* ptr = nullptr;
        try { ptr = BufferBytes(data, size); }
        catch (...) { error = L"Invalid font buffer"; return false; }
        if (!ptr || !size) { error = L"Empty font data"; return false; }

        try
        {
            auto factory = DWriteFactory();
            com_ptr<IDWriteInMemoryFontFileLoader> loader;
            check_hresult(factory->CreateInMemoryFontFileLoader(loader.put()));
            check_hresult(factory->RegisterFontFileLoader(loader.get()));

            com_ptr<IDWriteFontFile> file;
            HRESULT hr = loader->CreateInMemoryFontFileReference(factory.get(), ptr, size, nullptr, file.put());
            if (FAILED(hr) || !file)
            {
                factory->UnregisterFontFileLoader(loader.get());
                error = L"Failed to create in-memory font reference";
                return false;
            }

            BOOL isSupported = FALSE;
            DWRITE_FONT_FILE_TYPE fileType = DWRITE_FONT_FILE_TYPE_UNKNOWN;
            DWRITE_FONT_FACE_TYPE faceType = DWRITE_FONT_FACE_TYPE_UNKNOWN;
            UINT32 numberOfFaces = 0;
            file->Analyze(&isSupported, &fileType, &faceType, &numberOfFaces);
            if (!isSupported)
            {
                factory->UnregisterFontFileLoader(loader.get());
                error = L"Unsupported font file";
                return false;
            }

            com_ptr<IDWriteFontSetBuilder1> builder;
            check_hresult(factory->CreateFontSetBuilder(builder.put()));
            builder->AddFontFile(file.get());
            com_ptr<IDWriteFontSet> set;
            check_hresult(builder->CreateFontSet(set.put()));
            outFamily = FamilyFromFontSet(set.get());

            factory->UnregisterFontFileLoader(loader.get());
            return true;
        }
        catch (winrt::hresult_error const& e)
        {
            error = e.message().c_str();
            return false;
        }
        catch (...)
        {
            error = L"Failed to register font";
            return false;
        }
    }

    bool ValidateAndExtractFamilyFromFile(std::wstring const& path, std::wstring& outFamily, std::wstring& error)
    {
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
            return true;
        }
        catch (winrt::hresult_error const& e) { error = e.message().c_str(); return false; }
        catch (...) { error = L"Failed to register font file"; return false; }
    }

    std::wstring PersistFontData(IBuffer const& data)
    {
        uint32_t size = 0;
        uint8_t* ptr = nullptr;
        try { ptr = BufferBytes(data, size); }
        catch (...) { return L""; }
        if (!ptr || !size) return L"";

        // Pick an extension from the sfnt signature (DirectWrite reads ttf/otf/ttc; default ttf).
        std::wstring ext = L".ttf";
        if (size >= 4)
        {
            if (ptr[0] == 'O' && ptr[1] == 'T' && ptr[2] == 'T' && ptr[3] == 'O') ext = L".otf";
            else if (ptr[0] == 't' && ptr[1] == 't' && ptr[2] == 'c' && ptr[3] == 'f') ext = L".ttc";
        }

        // FNV-1a content hash so identical bytes dedupe to one file (mirrors the spirit of iOS's
        // length-keyed cache, but collision-resistant).
        uint64_t h = 1469598103934665603ULL;
        for (uint32_t i = 0; i < size; i++) { h ^= ptr[i]; h *= 1099511628211ULL; }

        std::filesystem::path dir;
        try
        {
            auto local = ApplicationData::Current().LocalFolder().Path();
            dir = std::filesystem::path(std::wstring(local)) / L"ns_fonts";
        }
        catch (...)
        {
            dir = std::filesystem::temp_directory_path() / L"ns_fonts";
        }

        std::error_code ec;
        std::filesystem::create_directories(dir, ec);

        wchar_t name[64];
        swprintf_s(name, L"font_%016llx%s", static_cast<unsigned long long>(h), ext.c_str());
        auto full = dir / name;

        if (!std::filesystem::exists(full, ec))
        {
            std::ofstream out(full, std::ios::binary);
            if (!out) return L"";
            out.write(reinterpret_cast<const char*>(ptr), static_cast<std::streamsize>(size));
            if (!out) return L"";
        }

        return std::wstring(name);
    }
}
