#include "pch.h"
#include "FontFace.h"
#include "FontFace.g.cpp"
#include "FontDescriptors.h"
#include "FontFaceSet.h"
#include "CssFontParser.h"
#include "FontResolver.h"
#include <cwctype>

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

        if (Status() == fm::FontFaceStatus::Loaded) co_return hstring(L"");
        m_status = static_cast<int32_t>(fm::FontFaceStatus::Loading);

        co_await resume_background();

        std::wstring family(m_descriptors.Family());
        std::wstring src(m_source);

        // Data-only path: register the bytes directly (mirrors NSCFontFace _loadInternal data branch).
        if (m_data && src.empty())
        {
            std::wstring resolvedFamily, err;
            if (resolver::ValidateAndExtractFamily(m_data, resolvedFamily, err))
            {
                auto fileName = resolver::PersistFontData(m_data);
                m_fontUri = BuildAppDataUri(fileName, resolvedFamily.empty() ? family : resolvedFamily);
                m_status = static_cast<int32_t>(fm::FontFaceStatus::Loaded);
                co_return hstring(L"");
            }
            m_status = static_cast<int32_t>(fm::FontFaceStatus::Error);
            co_return hstring(err.empty() ? L"Failed to register font" : err);
        }

        // No source and no data: a system/generic family — nothing to download.
        if (src.empty())
        {
            m_status = static_cast<int32_t>(fm::FontFaceStatus::Loaded);
            co_return hstring(L"");
        }

        IBuffer buffer = co_await resolver::FetchFontDataAsync(hstring(src));
        if (!buffer)
        {
            m_status = static_cast<int32_t>(fm::FontFaceStatus::Error);
            co_return hstring(L"Failed to load font data");
        }

        std::wstring resolvedFamily, err;
        if (!resolver::ValidateAndExtractFamily(buffer, resolvedFamily, err))
        {
            m_status = static_cast<int32_t>(fm::FontFaceStatus::Error);
            co_return hstring(err.empty() ? L"Failed to register font" : err);
        }

        m_data = buffer;
        std::wstring famSuffix = resolvedFamily.empty() ? family : resolvedFamily;
        std::wstring lowerSrc = ToLower(src);

        if (StartsWith(lowerSrc, L"http://") || StartsWith(lowerSrc, L"https://"))
        {
            // Remote font: persist a local copy so it can be referenced by a ms-appdata URI.
            auto fileName = resolver::PersistFontData(buffer);
            m_fontUri = BuildAppDataUri(fileName, famSuffix);
        }
        else
        {
            // Local file / ms-appx source is already addressable; just append the resolved family.
            m_fontUri = hstring(src + L"#" + famSuffix);
        }

        m_status = static_cast<int32_t>(fm::FontFaceStatus::Loaded);
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
            if (load) co_await face.LoadAsync();
            faces.push_back(face);
        }

        co_return single_threaded_vector(std::move(faces)).GetView();
    }
}
