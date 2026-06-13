#include "pch.h"
#include "FontDescriptors.h"
#include "FontDescriptors.g.cpp"
#include "CssFontParser.h"
#include <cwctype>
#include <optional>

namespace css = ::NativeScript::FontManager::css;

namespace
{
    std::wstring Trim(std::wstring const& s)
    {
        size_t start = 0, end = s.size();
        while (start < end && iswspace(s[start])) start++;
        while (end > start && iswspace(s[end - 1])) end--;
        return s.substr(start, end - start);
    }

    std::wstring ToLower(std::wstring s)
    {
        for (auto& ch : s) ch = static_cast<wchar_t>(towlower(ch));
        return s;
    }

    bool StartsWith(std::wstring const& s, std::wstring const& prefix)
    {
        return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
    }
}

namespace winrt::NativeScript::FontManager::implementation
{
    namespace fm = winrt::NativeScript::FontManager;

    FontDescriptors::FontDescriptors(hstring const& family)
    {
        m_family = family;
    }

    void FontDescriptors::Update(hstring const& value)
    {
        auto rules = css::ParseFontFaceRules(std::wstring(value));
        if (rules.empty()) return;
        auto const& first = rules.front();

        auto get = [&](wchar_t const* key) -> std::optional<std::wstring> {
            auto it = first.find(key);
            if (it == first.end()) return std::nullopt;
            return it->second;
        };

        if (auto v = get(L"font-weight")) SetFontWeightFromString(hstring(*v));
        if (auto v = get(L"font-style")) SetFontStyleFromString(hstring(*v));
        if (auto v = get(L"font-display")) SetFontDisplayFromString(hstring(*v));
        if (auto v = get(L"font-variant")) m_variant = hstring(*v);
        if (auto v = get(L"font-stretch")) m_stretch = hstring(*v);
        if (auto v = get(L"font-feature-settings")) m_featureSettings = hstring(*v);
        if (auto v = get(L"font-variation-settings")) m_variationSettings = hstring(*v);
        if (auto v = get(L"unicode-range")) m_unicodeRange = hstring(*v);
        if (auto v = get(L"ascent-override")) m_ascentOverride = hstring(*v);
        if (auto v = get(L"descent-override")) m_descentOverride = hstring(*v);
        if (auto v = get(L"line-gap-override")) m_lineGapOverride = hstring(*v);
        if (auto v = get(L"font-kerning")) m_kerning = hstring(*v);
        if (auto v = get(L"font-variant-ligatures")) m_variantLigatures = hstring(*v);
    }

    void FontDescriptors::SetFontWeightFromString(hstring const& value)
    {
        std::wstring trimmed = Trim(std::wstring(value));
        if (trimmed == L"normal") { m_weight = fm::FontWeight::Normal; return; }
        if (trimmed == L"bold") { m_weight = fm::FontWeight::Bold; return; }
        int intValue = _wtoi(trimmed.c_str());
        if (intValue > 0) m_weight = static_cast<fm::FontWeight>(intValue);
    }

    void FontDescriptors::SetFontStyleFromString(hstring const& value)
    {
        std::wstring trimmed = ToLower(Trim(std::wstring(value)));

        if (StartsWith(trimmed, L"oblique"))
        {
            m_style = L"oblique";
            std::wstring rest = Trim(trimmed.substr(std::wstring(L"oblique").size()));
            m_obliqueAngle = rest.empty() ? hstring(L"0deg") : hstring(rest);
            return;
        }

        if (trimmed == L"italic" || trimmed == L"normal")
        {
            m_style = hstring(trimmed);
            m_obliqueAngle = hstring(L"");
        }
    }

    void FontDescriptors::SetFontDisplayFromString(hstring const& value)
    {
        std::wstring trimmed = ToLower(Trim(std::wstring(value)));
        if (trimmed == L"auto") m_display = fm::FontDisplay::Auto;
        else if (trimmed == L"block") m_display = fm::FontDisplay::Block;
        else if (trimmed == L"fallback") m_display = fm::FontDisplay::Fallback;
        else if (trimmed == L"optional") m_display = fm::FontDisplay::Optional;
        else if (trimmed == L"swap") m_display = fm::FontDisplay::Swap;
    }
}
