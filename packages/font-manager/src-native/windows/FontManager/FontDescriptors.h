#pragma once
#include "FontDescriptors.g.h"

namespace winrt::NativeScript::FontManager::implementation
{
    struct FontDescriptors : FontDescriptorsT<FontDescriptors>
    {
        FontDescriptors() = default;
        FontDescriptors(hstring const& family);

        winrt::NativeScript::FontManager::FontWeight Weight() const noexcept { return m_weight; }
        void Weight(winrt::NativeScript::FontManager::FontWeight value) { m_weight = value; }

        hstring Family() const { return m_family; }

        hstring Style() const { return m_style; }
        void Style(hstring const& value) { m_style = value; }

        hstring ObliqueAngle() const { return m_obliqueAngle; }
        void ObliqueAngle(hstring const& value) { m_obliqueAngle = value; }

        hstring Variant() const { return m_variant; }
        void Variant(hstring const& value) { m_variant = value; }

        hstring AscentOverride() const { return m_ascentOverride; }
        void AscentOverride(hstring const& value) { m_ascentOverride = value; }

        hstring DescentOverride() const { return m_descentOverride; }
        void DescentOverride(hstring const& value) { m_descentOverride = value; }

        winrt::NativeScript::FontManager::FontDisplay Display() const noexcept { return m_display; }
        void Display(winrt::NativeScript::FontManager::FontDisplay value) { m_display = value; }

        hstring Stretch() const { return m_stretch; }
        void Stretch(hstring const& value) { m_stretch = value; }

        hstring UnicodeRange() const { return m_unicodeRange; }
        void UnicodeRange(hstring const& value) { m_unicodeRange = value; }

        hstring FeatureSettings() const { return m_featureSettings; }
        void FeatureSettings(hstring const& value) { m_featureSettings = value; }

        hstring LineGapOverride() const { return m_lineGapOverride; }
        void LineGapOverride(hstring const& value) { m_lineGapOverride = value; }

        hstring VariationSettings() const { return m_variationSettings; }
        void VariationSettings(hstring const& value) { m_variationSettings = value; }

        hstring Kerning() const { return m_kerning; }
        void Kerning(hstring const& value) { m_kerning = value; }

        hstring VariantLigatures() const { return m_variantLigatures; }
        void VariantLigatures(hstring const& value) { m_variantLigatures = value; }

        void Update(hstring const& value);
        void SetFontWeightFromString(hstring const& value);
        void SetFontStyleFromString(hstring const& value);
        void SetFontDisplayFromString(hstring const& value);

    private:
        winrt::NativeScript::FontManager::FontWeight m_weight{ winrt::NativeScript::FontManager::FontWeight::Normal };
        hstring m_family;
        hstring m_style{ L"normal" };
        hstring m_obliqueAngle;
        hstring m_variant{ L"normal" };
        hstring m_ascentOverride{ L"normal" };
        hstring m_descentOverride{ L"normal" };
        winrt::NativeScript::FontManager::FontDisplay m_display{ winrt::NativeScript::FontManager::FontDisplay::Auto };
        hstring m_stretch{ L"normal" };
        hstring m_unicodeRange{ L"U+0-10FFFF" };
        hstring m_featureSettings{ L"normal" };
        hstring m_lineGapOverride{ L"normal" };
        hstring m_variationSettings{ L"normal" };
        hstring m_kerning{ L"auto" };
        hstring m_variantLigatures{ L"normal" };
    };
}

namespace winrt::NativeScript::FontManager::factory_implementation
{
    struct FontDescriptors : FontDescriptorsT<FontDescriptors, implementation::FontDescriptors>
    {
    };
}
