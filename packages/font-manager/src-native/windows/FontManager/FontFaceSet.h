#pragma once
#include "FontFaceSetEventArgs.g.h"
#include "FontFaceSet.g.h"
#include <vector>
#include <map>
#include <mutex>
#include <atomic>

namespace winrt::NativeScript::FontManager::implementation
{
    struct FontFaceSetEventArgs : FontFaceSetEventArgsT<FontFaceSetEventArgs>
    {
        FontFaceSetEventArgs() = default;
        FontFaceSetEventArgs(winrt::NativeScript::FontManager::FontFaceSetStatus status,
                             winrt::NativeScript::FontManager::FontFace const& face,
                             hstring const& error)
            : m_status(status), m_face(face), m_error(error) {}

        winrt::NativeScript::FontManager::FontFaceSetStatus Status() const noexcept { return m_status; }
        winrt::NativeScript::FontManager::FontFace Face() const { return m_face; }
        hstring Error() const { return m_error; }

    private:
        winrt::NativeScript::FontManager::FontFaceSetStatus m_status{ winrt::NativeScript::FontManager::FontFaceSetStatus::Loaded };
        winrt::NativeScript::FontManager::FontFace m_face{ nullptr };
        hstring m_error;
    };

    struct FontFaceSet : FontFaceSetT<FontFaceSet>
    {
        FontFaceSet() = default;

        static winrt::NativeScript::FontManager::FontFaceSet Instance();

        uint32_t Size();

        void Add(winrt::NativeScript::FontManager::FontFace const& font);
        void Delete(winrt::NativeScript::FontManager::FontFace const& font);
        void Clear();
        bool Has(winrt::NativeScript::FontManager::FontFace const& font);

        bool Check(hstring const& font, hstring const& text);
        winrt::Windows::Foundation::IAsyncOperation<
            winrt::Windows::Foundation::Collections::IVectorView<winrt::NativeScript::FontManager::FontFace>>
            LoadAsync(hstring font, hstring text);

        winrt::Windows::Foundation::Collections::IVectorView<winrt::NativeScript::FontManager::FontFace> GetArray();

        winrt::event_token StatusChanged(winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs> const& handler)
        {
            return m_statusChanged.add(handler);
        }
        void StatusChanged(winrt::event_token const& token) noexcept { m_statusChanged.remove(token); }

        winrt::event_token Loading(winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs> const& handler)
        {
            return m_loading.add(handler);
        }
        void Loading(winrt::event_token const& token) noexcept { m_loading.remove(token); }

        winrt::event_token LoadingDone(winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs> const& handler)
        {
            return m_loadingDone.add(handler);
        }
        void LoadingDone(winrt::event_token const& token) noexcept { m_loadingDone.remove(token); }

        winrt::event_token LoadingError(winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs> const& handler)
        {
            return m_loadingError.add(handler);
        }
        void LoadingError(winrt::event_token const& token) noexcept { m_loadingError.remove(token); }

    private:
        winrt::NativeScript::FontManager::FontFace ResolveBest(hstring const& font);
        void BeginLoad(winrt::NativeScript::FontManager::FontFace const& face);
        void EndLoadSuccess(winrt::NativeScript::FontManager::FontFace const& face);
        void EndLoadError(winrt::NativeScript::FontManager::FontFace const& face, hstring const& error);

        std::mutex m_mutex;
        std::vector<winrt::NativeScript::FontManager::FontFace> m_faces;
        std::map<std::wstring, std::vector<winrt::NativeScript::FontManager::FontFace>> m_byFamily;
        std::atomic<int32_t> m_pending{ 0 };

        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_statusChanged;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loading;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loadingDone;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loadingError;
    };
}

namespace winrt::NativeScript::FontManager::factory_implementation
{
    struct FontFaceSet : FontFaceSetT<FontFaceSet, implementation::FontFaceSet>
    {
    };
}
