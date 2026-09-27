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
        if (!font) return;
        {
            std::lock_guard lock(m_mutex);
            // A set: adding a face it already holds does nothing.
            if (ContainsLocked(font)) return;
            m_faces.push_back(font);
            m_byFamily[ToLower(std::wstring(font.Family()))].push_back(font);
        }
        RaiseChanged();
        // A face added while it loads joins (or starts) the loading period.
        if (font.Status() == fm::FontFaceStatus::Loading) OnFaceLoading(font);
    }

    void FontFaceSet::Delete(fm::FontFace const& font)
    {
        if (!font) return;
        PeriodEnd end;
        {
            std::lock_guard lock(m_mutex);
            if (!ContainsLocked(font)) return;
            m_faces.erase(std::remove(m_faces.begin(), m_faces.end(), font), m_faces.end());
            auto it = m_byFamily.find(ToLower(std::wstring(font.Family())));
            if (it != m_byFamily.end())
            {
                auto& vec = it->second;
                vec.erase(std::remove(vec.begin(), vec.end(), font), vec.end());
                if (vec.empty()) m_byFamily.erase(it);
            }
            // A removed face no longer holds the set in its loading period.
            if (std::find(m_loadingFaces.begin(), m_loadingFaces.end(), font) != m_loadingFaces.end())
            {
                m_loadingFaces.erase(std::remove(m_loadingFaces.begin(), m_loadingFaces.end(), font), m_loadingFaces.end());
                if (m_loadingFaces.empty()) end = SettleLocked(nullptr, {});
            }
        }
        RaiseChanged();
        Raise(end);
    }

    void FontFaceSet::Clear()
    {
        PeriodEnd end;
        {
            std::lock_guard lock(m_mutex);
            if (m_faces.empty()) return;
            m_faces.clear();
            m_byFamily.clear();
            if (!m_loadingFaces.empty())
            {
                m_loadingFaces.clear();
                end = SettleLocked(nullptr, {});
            }
        }
        RaiseChanged();
        Raise(end);
    }

    bool FontFaceSet::ContainsLocked(fm::FontFace const& face) const
    {
        return std::find(m_faces.begin(), m_faces.end(), face) != m_faces.end();
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

    void FontFaceSet::OnFaceLoading(fm::FontFace const& face)
    {
        bool started = false;
        {
            std::lock_guard lock(m_mutex);
            // The status is read again under the lock: a face that settles meanwhile sets it before
            // calling OnFaceSettled, so it is either tracked here and settled there, or neither.
            if (!ContainsLocked(face) || face.Status() != fm::FontFaceStatus::Loading) return;
            if (std::find(m_loadingFaces.begin(), m_loadingFaces.end(), face) != m_loadingFaces.end()) return;
            started = m_loadingFaces.empty() && m_loadedFaces.empty() && m_failedFaces.empty();
            m_loadingFaces.push_back(face);
        }
        if (!started) return;
        m_statusChanged(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loading, face, hstring(L"")));
        m_loading(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loading, face, hstring(L"")));
    }

    void FontFaceSet::OnFaceSettled(fm::FontFace const& face, hstring const& error)
    {
        PeriodEnd end;
        bool member = false;
        {
            std::lock_guard lock(m_mutex);
            member = ContainsLocked(face);
            auto it = std::find(m_loadingFaces.begin(), m_loadingFaces.end(), face);
            if (it != m_loadingFaces.end())
            {
                m_loadingFaces.erase(it);
                end = SettleLocked(face, error);
            }
        }
        if (member) RaiseChanged();
        Raise(end);
    }

    FontFaceSet::PeriodEnd FontFaceSet::SettleLocked(fm::FontFace const& face, hstring const& error)
    {
        if (face)
        {
            if (error.empty()) m_loadedFaces.push_back(face);
            else
            {
                m_failedFaces.push_back(face);
                m_lastError = error;
            }
        }
        PeriodEnd end;
        if (!m_loadingFaces.empty()) return end;
        end.ended = true;
        end.loaded.swap(m_loadedFaces);
        end.failed.swap(m_failedFaces);
        end.error = m_lastError;
        m_lastError = hstring();
        return end;
    }

    void FontFaceSet::Raise(PeriodEnd const& end)
    {
        if (!end.ended) return;
        fm::FontFace first = end.loaded.empty() ? nullptr : end.loaded.front();
        m_statusChanged(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, first, hstring(L"")));
        m_loadingDone(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, first, hstring(L""), end.loaded));
        if (!end.failed.empty())
        {
            m_loadingError(*this, winrt::make<FontFaceSetEventArgs>(fm::FontFaceSetStatus::Loaded, end.failed.front(), end.error, end.failed));
        }
    }

    void FontFaceSet::RaiseChanged()
    {
        m_changed(*this, nullptr);
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

        // A member face reports its load to this set itself (OnFaceLoading / OnFaceSettled).
        hstring err = co_await face.LoadAsync();

        std::vector<fm::FontFace> result{ face };
        if (err.empty()) co_return single_threaded_vector(std::move(result)).GetView();

        throw hresult_error(E_FAIL, err);
    }

    IVectorView<fm::FontFace> FontFaceSet::GetArray()
    {
        std::lock_guard lock(m_mutex);
        std::vector<fm::FontFace> copy(m_faces.begin(), m_faces.end());
        return single_threaded_vector(std::move(copy)).GetView();
    }
}
