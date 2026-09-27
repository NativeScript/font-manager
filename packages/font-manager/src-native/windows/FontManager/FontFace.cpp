#include "pch.h"
#include "FontFace.h"
#include "FontFace.g.cpp"
#include "FontDescriptors.h"
#include "FontFaceSet.h"
#include "CssFontParser.h"
#include "FontResolver.h"
#include <cwctype>
#include <filesystem>

namespace css = ::NativeScript::FontManager::css;
namespace resolver = ::NativeScript::FontManager::resolver;

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Collections;
using namespace winrt::Windows::Storage::Streams;

namespace
{
    namespace fm = winrt::NativeScript::FontManager;

    bool StartsWith(std::wstring const& s, std::wstring const& prefix)
    {
        return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
    }

    std::wstring ToLower(std::wstring s)
    {
        for (auto& ch : s) ch = static_cast<wchar_t>(towlower(ch));
        return s;
    }

    hstring BuildAppDataUri(std::wstring const& fileName, std::wstring const& family)
    {
        if (fileName.empty()) return hstring(L"");
        std::wstring uri = L"ms-appdata:///local/ns_fonts/" + fileName;
        if (!family.empty()) uri += L"#" + family;
        return hstring(uri);
    }
}

namespace winrt::NativeScript::FontManager::implementation
{
    fm::FontFace FontFace::FromFamily(hstring const& family)
    {
        auto face = winrt::make<FontFace>();
        auto self = winrt::get_self<FontFace>(face);
        self->m_descriptors = winrt::make<FontManager::implementation::FontDescriptors>(family);
        return face;
    }

    fm::FontFace FontFace::FromFamilySource(hstring const& family, hstring const& source)
    {
        auto face = FromFamily(family);
        winrt::get_self<FontFace>(face)->m_source = source;
        return face;
    }

    fm::FontFace FontFace::FromFamilyData(hstring const& family, IBuffer const& data)
    {
        auto face = FromFamily(family);
        winrt::get_self<FontFace>(face)->m_data = data;
        return face;
    }

    fm::FontFace FontFace::FromDescriptor(fm::FontDescriptors const& descriptor)
    {
        auto face = winrt::make<FontFace>();
        winrt::get_self<FontFace>(face)->m_descriptors = descriptor;
        return face;
    }

    fm::FontFace FontFace::FromDescriptorSource(fm::FontDescriptors const& descriptor, hstring const& source)
    {
        auto face = FromDescriptor(descriptor);
        winrt::get_self<FontFace>(face)->m_source = source;
        return face;
    }

    fm::FontFace FontFace::FromDescriptorData(fm::FontDescriptors const& descriptor, IBuffer const& data)
    {
        auto face = FromDescriptor(descriptor);
        winrt::get_self<FontFace>(face)->m_data = data;
        return face;
    }

    void FontFace::SetFontStyle(hstring const& value, hstring const& angle)
    {
        std::wstring v(value), a(angle);
        std::wstring combined = !a.empty() ? (v + L" " + a) : v;
        m_descriptors.SetFontStyleFromString(hstring(combined));
    }

    IAsyncOperation<hstring> FontFace::LoadAsync()
    {
        auto lifetime = get_strong();

        std::shared_ptr<PendingLoad> pending;
        bool owner = false;
        {
            std::lock_guard lock(m_loadMutex);
            if (Status() != fm::FontFaceStatus::Loaded)
            {
                if (!m_pendingLoad)
                {
                    m_pendingLoad = std::make_shared<PendingLoad>();
                    m_status = static_cast<int32_t>(fm::FontFaceStatus::Loading);
                    owner = true;
                }
                pending = m_pendingLoad;
            }
        }
        if (!pending) co_return hstring(L"");

        auto* set = winrt::get_self<FontFaceSet>(fm::FontFaceSet::Instance());
        if (owner) set->OnFaceLoading(*this);

        // A load is already running: settle with its result instead of loading again.
        if (!owner)
        {
            co_await resume_on_signal(pending->done.get());
            co_return pending->error;
        }

        hstring error;
        try { error = co_await LoadInternalAsync(); }
        catch (hresult_error const& e) { error = e.message().empty() ? hstring(L"Failed to load font") : e.message(); }
        catch (...) { error = L"Failed to load font"; }

        m_status = static_cast<int32_t>(error.empty() ? fm::FontFaceStatus::Loaded : fm::FontFaceStatus::Error);
        pending->error = error;
        {
            std::lock_guard lock(m_loadMutex);
            m_pendingLoad = nullptr;
        }
        SetEvent(pending->done.get());
        // After the status is final, so the set can't track this load again once it has settled.
        set->OnFaceSettled(*this, error);
        co_return error;
    }

    // Resolves the source to a font file, validates it and sets m_fontUri. Resolves to an error
    // message (empty on success) or throws; LoadAsync owns m_status.
    IAsyncOperation<hstring> FontFace::LoadInternalAsync()
    {
        co_await resume_background();

        std::wstring family(m_descriptors.Family());
        std::wstring src(m_source);
        std::wstring resolvedFamily, err;

        // Data-only path: persist the bytes, then validate the file (mirrors NSCFontFace
        // _loadInternal data branch).
        if (m_data && src.empty())
        {
            auto fileName = resolver::PersistFontData(m_data);
            if (fileName.empty()) co_return hstring(L"Failed to register font");
            auto path = resolver::FontCachePath(fileName);
            if (!resolver::ValidateAndExtractFamilyFromFile(path, resolvedFamily, err))
            {
                std::error_code ec;
                std::filesystem::remove(path, ec);
                co_return hstring(err.empty() ? L"Failed to register font" : err);
            }
            m_fontUri = BuildAppDataUri(fileName, resolvedFamily.empty() ? family : resolvedFamily);
            co_return hstring(L"");
        }

        // No source and no data: a system/generic family — nothing to download.
        if (src.empty()) co_return hstring(L"");

        std::wstring lowerSrc = ToLower(src);
        bool remote = StartsWith(lowerSrc, L"http://") || StartsWith(lowerSrc, L"https://");
        std::wstring fileName, path;
        if (remote)
        {
            // URL-keyed cached copy; throws with the download failure.
            fileName = std::wstring(co_await resolver::DownloadFontAsync(hstring(src)));
            path = resolver::FontCachePath(fileName);
        }
        else
        {
            // Validated in place, never read into memory.
            path = std::wstring(co_await resolver::ResolveLocalFontPathAsync(hstring(src)));
            if (path.empty()) co_return hstring(L"Failed to load font data");
        }

        if (!resolver::ValidateAndExtractFamilyFromFile(path, resolvedFamily, err))
        {
            // Drop an unusable download so the next load fetches it again (never a local source).
            if (remote)
            {
                std::error_code ec;
                std::filesystem::remove(path, ec);
            }
            co_return hstring(err.empty() ? L"Failed to register font" : err);
        }

        std::wstring famSuffix = resolvedFamily.empty() ? family : resolvedFamily;
        // Remote fonts are referenced through their cached copy; a local file / ms-appx source is
        // already addressable, so just append the resolved family.
        m_fontUri = remote ? BuildAppDataUri(fileName, famSuffix) : hstring(src + L"#" + famSuffix);
        co_return hstring(L"");
    }

    IAsyncOperation<IVectorView<fm::FontFace>> FontFace::ImportFromRemoteAsync(hstring url, bool load)
    {
        IBuffer buffer = co_await resolver::FetchFontDataAsync(url);
        if (!buffer) throw hresult_error(E_FAIL, L"Failed to fetch font stylesheet");

        // Decode the stylesheet bytes as UTF-8.
        uint32_t len = buffer.Length();
        std::vector<uint8_t> bytes(len);
        auto reader = DataReader::FromBuffer(buffer);
        reader.ReadBytes(bytes);
        std::string utf8(bytes.begin(), bytes.end());
        std::wstring css(to_hstring(utf8));

        auto rules = css::ParseFontFaceRules(css);
        std::vector<fm::FontFace> faces;
        std::vector<IAsyncOperation<hstring>> loads;
        auto set = FontFaceSet::Instance();

        for (auto const& rule : rules)
        {
            auto famIt = rule.find(L"font-family");
            if (famIt == rule.end() || famIt->second.empty()) continue;

            hstring family(famIt->second);
            auto srcIt = rule.find(L"src");
            fm::FontFace face = (srcIt != rule.end() && !srcIt->second.empty())
                ? FromFamilySource(family, hstring(srcIt->second))
                : FromFamily(family);

            if (auto it = rule.find(L"font-style"); it != rule.end()) face.SetFontStyle(hstring(it->second), hstring(L""));
            if (auto it = rule.find(L"font-weight"); it != rule.end()) face.SetFontWeight(hstring(it->second));
            if (auto it = rule.find(L"font-display"); it != rule.end()) face.SetFontDisplay(hstring(it->second));

            set.Add(face);
            if (load) loads.push_back(face.LoadAsync());
            faces.push_back(face);
        }

        // The loads run concurrently; each face reports its own failure through Status, as before.
        for (auto& op : loads) co_await op;

        co_return single_threaded_vector(std::move(faces)).GetView();
    }
}
