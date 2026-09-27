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
                             hstring const& error,
                             std::vector<winrt::NativeScript::FontManager::FontFace> faces = {})
            : m_status(status), m_face(face), m_faces(winrt::single_threaded_vector(std::move(faces)).GetView()), m_error(error) {}

        winrt::NativeScript::FontManager::FontFaceSetStatus Status() const noexcept { return m_status; }
        winrt::NativeScript::FontManager::FontFace Face() const { return m_face; }
        winrt::Windows::Foundation::Collections::IVectorView<winrt::NativeScript::FontManager::FontFace> Faces() const { return m_faces; }
        hstring Error() const { return m_error; }

    private:
        winrt::NativeScript::FontManager::FontFaceSetStatus m_status{ winrt::NativeScript::FontManager::FontFaceSetStatus::Loaded };
        winrt::NativeScript::FontManager::FontFace m_face{ nullptr };
        winrt::Windows::Foundation::Collections::IVectorView<winrt::NativeScript::FontManager::FontFace> m_faces{ nullptr };
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

        winrt::event_token Changed(winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::Windows::Foundation::IInspectable> const& handler)
        {
            return m_changed.add(handler);
        }
        void Changed(winrt::event_token const& token) noexcept { m_changed.remove(token); }

        void OnFaceLoading(winrt::NativeScript::FontManager::FontFace const& face);
        void OnFaceSettled(winrt::NativeScript::FontManager::FontFace const& face, hstring const& error);

    private:
        struct PeriodEnd
        {
            bool ended{ false };
            std::vector<winrt::NativeScript::FontManager::FontFace> loaded;
            std::vector<winrt::NativeScript::FontManager::FontFace> failed;
            hstring error;
        };

        winrt::NativeScript::FontManager::FontFace ResolveBest(hstring const& font);
        bool ContainsLocked(winrt::NativeScript::FontManager::FontFace const& face) const;
        PeriodEnd SettleLocked(winrt::NativeScript::FontManager::FontFace const& face, hstring const& error);
        void Raise(PeriodEnd const& end);
        void RaiseChanged();

        std::mutex m_mutex;
        std::vector<winrt::NativeScript::FontManager::FontFace> m_faces;
        std::map<std::wstring, std::vector<winrt::NativeScript::FontManager::FontFace>> m_byFamily;
        std::vector<winrt::NativeScript::FontManager::FontFace> m_loadingFaces;
        std::vector<winrt::NativeScript::FontManager::FontFace> m_loadedFaces;
        std::vector<winrt::NativeScript::FontManager::FontFace> m_failedFaces;
        hstring m_lastError;

        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_statusChanged;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loading;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loadingDone;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::NativeScript::FontManager::FontFaceSetEventArgs>> m_loadingError;
        winrt::event<winrt::Windows::Foundation::TypedEventHandler<
            winrt::NativeScript::FontManager::FontFaceSet, winrt::Windows::Foundation::IInspectable>> m_changed;
    };
}

namespace winrt::NativeScript::FontManager::factory_implementation
{
    struct FontFaceSet : FontFaceSetT<FontFaceSet, implementation::FontFaceSet>
    {
    };
}
