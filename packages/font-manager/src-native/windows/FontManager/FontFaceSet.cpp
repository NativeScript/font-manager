#include "pch.h"
#include "FontFaceSet.h"
#include "FontFaceSetEventArgs.g.cpp"
#include "FontFaceSet.g.cpp"
#include "CssFontParser.h"
#include "FontResolver.h"
#include <cwctype>
#include <cstdlib>

namespace css = ::NativeScript::FontManager::css;
namespace resolver = ::NativeScript::FontManager::resolver;

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Collections;

namespace
{
    namespace fm = winrt::NativeScript::FontManager;

    std::wstring ToLower(std::wstring s)
    {
        for (auto& ch : s) ch = static_cast<wchar_t>(towlower(ch));
        return s;
    }
}

namespace winrt::NativeScript::FontManager::implementation
{
    fm::FontFaceSet FontFaceSet::Instance()
    {
        // Function-local static => one shared instance for the process (mirrors +instance).
        static fm::FontFaceSet instance = winrt::make<FontFaceSet>();
        return instance;
    }

    uint32_t FontFaceSet::Size()
    {
        std::lock_guard lock(m_mutex);
        return static_cast<uint32_t>(m_faces.size());
    }

    void FontFaceSet::Add(fm::FontFace const& font)
    {
        std::lock_guard lock(m_mutex);
        m_faces.push_back(font);
        std::wstring key = ToLower(std::wstring(font.Family()));
        m_byFamily[key].push_back(font);
    }

    void FontFaceSet::Delete(fm::FontFace const& font)
    {
        std::lock_guard lock(m_mutex);
        m_faces.erase(std::remove(m_faces.begin(), m_faces.end(), font), m_faces.end());
        std::wstring key = ToLower(std::wstring(font.Family()));
        auto it = m_byFamily.find(key);
        if (it != m_byFamily.end())
        {
            auto& vec = it->second;
            vec.erase(std::remove(vec.begin(), vec.end(), font), vec.end());
            if (vec.empty()) m_byFamily.erase(it);
        }
    }

    void FontFaceSet::Clear()
    {
        std::lock_guard lock(m_mutex);
        m_faces.clear();
        m_byFamily.clear();
    }

    bool FontFaceSet::Has(fm::FontFace const& font)
    {
        std::lock_guard lock(m_mutex);
        return std::find(m_faces.begin(), m_faces.end(), font) != m_faces.end();
    }

    // Ports NSCFontFaceSet _resolveFonts: pick the best weight/style match across the parsed
    // families; bail (nullptr) at the first generic family with no registered candidates.
    fm::FontFace FontFaceSet::ResolveBest(hstring const& font)
    {
        auto parsed = css::ParseShorthand(std::wstring(font));
        if (!parsed.valid) return nullptr;

        std::lock_guard lock(m_mutex);
        for (auto const& family : parsed.families)
        {
            std::wstring key = ToLower(family);
            auto it = m_byFamily.find(key);
            if (it == m_byFamily.end() || it->second.empty())
            {
                if (resolver::IsGenericFamily(family)) return nullptr;
                continue;
            }

            fm::FontFace best{ nullptr };
            long bestScore = LONG_MAX;
            for (auto const& face : it->second)
            {
                long weightDiff = std::labs(static_cast<long>(face.Weight()) - static_cast<long>(parsed.weight));
                long styleDiff = (std::wstring(face.Style()) == parsed.style) ? 0 : 1000;
                long score = weightDiff + styleDiff;
                if (score < bestScore) { bestScore = score; best = face; }
            }
            if (best) return best;
        }
        return nullptr;
    }

    bool FontFaceSet::Check(hstring const& font, hstring const& /*text*/)
    {
        return ResolveBest(font) != nullptr;
    }

    void FontFaceSet::BeginLoad(fm::FontFace const& face)
    {
        m_pending++;
        m_statusChanged(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loading, face, hstring(L"")));
        m_loading(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loading, face, hstring(L"")));
    }

    void FontFaceSet::EndLoadSuccess(fm::FontFace const& face)
    {
        m_loadingDone(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, face, hstring(L"")));
        if (--m_pending <= 0)
        {
            m_statusChanged(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, face, hstring(L"")));
        }
    }

    void FontFaceSet::EndLoadError(fm::FontFace const& face, hstring const& error)
    {
        m_loadingError(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, face, error));
        if (--m_pending <= 0)
        {
            m_statusChanged(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, face, hstring(L"")));
        }
    }

    IAsyncOperation<IVectorView<fm::FontFace>> FontFaceSet::LoadAsync(hstring font, hstring text)
    {
        auto lifetime = get_strong();

        auto parsed = css::ParseShorthand(std::wstring(font));
        if (!parsed.valid) throw hresult_invalid_argument(L"Failed to parse font");

        fm::FontFace face = ResolveBest(font);
        if (!face)
        {
            // No matching registered face — resolves empty (mirrors iOS callback(@[], nil)).
            co_return single_threaded_vector<fm::FontFace>().GetView();
        }

        BeginLoad(face);
        hstring err = co_await face.LoadAsync();

        std::vector<fm::FontFace> result{ face };
        if (err.empty())
        {
            EndLoadSuccess(face);
            co_return single_threaded_vector(std::move(result)).GetView();
        }

        EndLoadError(face, err);
        throw hresult_error(E_FAIL, err);
    }

    IVectorView<fm::FontFace> FontFaceSet::GetArray()
    {
        std::lock_guard lock(m_mutex);
        std::vector<fm::FontFace> copy(m_faces.begin(), m_faces.end());
        return single_threaded_vector(std::move(copy)).GetView();
    }
}
