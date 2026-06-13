#pragma once
#include "FontFace.g.h"
#include <atomic>

namespace winrt::NativeScript::FontManager::implementation
{
    struct FontFace : FontFaceT<FontFace>
    {
        FontFace() = default;

        // Static factories (WinRT-friendly equivalents of the ObjC init overloads).
        static winrt::NativeScript::FontManager::FontFace FromFamily(hstring const& family);
        static winrt::NativeScript::FontManager::FontFace FromFamilySource(hstring const& family, hstring const& source);
        static winrt::NativeScript::FontManager::FontFace FromFamilyData(hstring const& family, winrt::Windows::Storage::Streams::IBuffer const& data);
        static winrt::NativeScript::FontManager::FontFace FromDescriptor(winrt::NativeScript::FontManager::FontDescriptors const& descriptor);
        static winrt::NativeScript::FontManager::FontFace FromDescriptorSource(winrt::NativeScript::FontManager::FontDescriptors const& descriptor, hstring const& source);
        static winrt::NativeScript::FontManager::FontFace FromDescriptorData(winrt::NativeScript::FontManager::FontDescriptors const& descriptor, winrt::Windows::Storage::Streams::IBuffer const& data);

        hstring Family() const { return m_descriptors.Family(); }
        winrt::NativeScript::FontManager::FontFaceStatus Status() const noexcept
        {
            return static_cast<winrt::NativeScript::FontManager::FontFaceStatus>(m_status.load());
        }
        winrt::NativeScript::FontManager::FontDescriptors Descriptors() const { return m_descriptors; }
        hstring FontUri() const { return m_fontUri; }

        winrt::NativeScript::FontManager::FontDisplay Display() const { return m_descriptors.Display(); }
        winrt::NativeScript::FontManager::FontWeight Weight() const { return m_descriptors.Weight(); }
        hstring Style() const { return m_descriptors.Style(); }
        hstring Stretch() const { return m_descriptors.Stretch(); }
        hstring UnicodeRange() const { return m_descriptors.UnicodeRange(); }
        hstring FeatureSettings() const { return m_descriptors.FeatureSettings(); }
        hstring VariationSettings() const { return m_descriptors.VariationSettings(); }
        hstring AscentOverride() const { return m_descriptors.AscentOverride(); }
        hstring DescentOverride() const { return m_descriptors.DescentOverride(); }
        hstring LineGapOverride() const { return m_descriptors.LineGapOverride(); }
        hstring Kerning() const { return m_descriptors.Kerning(); }
        hstring VariantLigatures() const { return m_descriptors.VariantLigatures(); }

        void SetFontWeight(hstring const& value) { m_descriptors.SetFontWeightFromString(value); }
        void SetFontStyle(hstring const& value, hstring const& angle);
        void SetFontDisplay(hstring const& value) { m_descriptors.SetFontDisplayFromString(value); }
        void SetFontStretch(hstring const& value) { m_descriptors.Stretch(value); }
        void SetFontUnicodeRange(hstring const& value) { m_descriptors.UnicodeRange(value); }
        void SetFontFeatureSettings(hstring const& value) { m_descriptors.FeatureSettings(value); }
        void SetFontVariationSettings(hstring const& value) { m_descriptors.VariationSettings(value); }
        void SetFontAscentOverride(hstring const& value) { m_descriptors.AscentOverride(value); }
        void SetFontDescentOverride(hstring const& value) { m_descriptors.DescentOverride(value); }
        void SetFontLineGapOverride(hstring const& value) { m_descriptors.LineGapOverride(value); }
        void SetFontKerning(hstring const& value) { m_descriptors.Kerning(value); }
        void SetFontVariantLigatures(hstring const& value) { m_descriptors.VariantLigatures(value); }
        void UpdateDescriptor(hstring const& css) { m_descriptors.Update(css); }

        winrt::Windows::Foundation::IAsyncOperation<hstring> LoadAsync();

        static winrt::Windows::Foundation::IAsyncOperation<
            winrt::Windows::Foundation::Collections::IVectorView<winrt::NativeScript::FontManager::FontFace>>
            ImportFromRemoteAsync(hstring url, bool load);

    private:
        winrt::NativeScript::FontManager::FontDescriptors m_descriptors{ nullptr };
        hstring m_source;
        winrt::Windows::Storage::Streams::IBuffer m_data{ nullptr };
        hstring m_fontUri;
        std::atomic<int32_t> m_status{ 0 }; // FontFaceStatus::Unloaded
    };
}

namespace winrt::NativeScript::FontManager::factory_implementation
{
    struct FontFace : FontFaceT<FontFace, implementation::FontFace>
    {
    };
}
