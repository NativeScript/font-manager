#include "pch.h"
#include <iostream>
#include <chrono>

// Standalone native test harness for the NativeScript.FontManager C++/WinRT component. The
// component is headless, so this console app exercises every code path directly (paralleling the
// role of src-native/ios/Demo). It calls the implementation statics directly so it needs no COM
// activation-factory registration. Visual XAML font rendering is validated separately through
// apps/demo on the NativeScript Windows runtime.
//
// Usage: Demo.exe [path-to-font.ttf] [remote-css-url]

#include "CssFontParser.h"
#include "FontResolver.h"
#include "FontDescriptors.h"
#include "FontFace.h"
#include "FontFaceSet.h"

using namespace winrt;
namespace fmimpl = winrt::NativeScript::FontManager::implementation;
namespace fm = winrt::NativeScript::FontManager;
namespace css = ::NativeScript::FontManager::css;
namespace resolver = ::NativeScript::FontManager::resolver;

int wmain(int argc, wchar_t** argv)
{
    winrt::init_apartment();

    int failures = 0;
    auto check = [&](bool cond, const char* msg) {
        std::cout << (cond ? "[PASS] " : "[FAIL] ") << msg << "\n";
        if (!cond) failures++;
    };

    // 1. CSS `font:` shorthand parser.
    {
        auto p = css::ParseShorthand(L"italic bold 16px/1.4 'Open Sans', sans-serif");
        check(p.valid && p.weight == 700 && p.style == L"italic" && p.sizePx == 16 && p.families.size() == 2,
              "ParseShorthand(italic bold 16px/1.4 'Open Sans', sans-serif)");
    }

    // 2. @font-face rule parser.
    {
        auto rules = css::ParseFontFaceRules(
            L"@font-face { font-family: 'Foo Bar'; src: url('foo.ttf') format('truetype'); font-weight: 700; font-style: italic; }");
        bool ok = rules.size() == 1
            && rules[0].at(L"font-family") == L"Foo Bar"
            && rules[0].at(L"src") == L"foo.ttf"
            && rules[0].at(L"font-weight") == L"700"
            && rules[0].at(L"font-style") == L"italic";
        check(ok, "ParseFontFaceRules(single block, url + format + weight + style)");
    }

    // 3. FontDescriptors string setters.
    {
        auto d = winrt::make<fmimpl::FontDescriptors>(hstring(L"Roboto"));
        d.SetFontWeightFromString(L"bold");
        d.SetFontStyleFromString(L"oblique 14deg");
        d.SetFontDisplayFromString(L"swap");
        bool ok = d.Weight() == fm::FontWeight::Bold
            && std::wstring(d.Style()) == L"oblique"
            && std::wstring(d.ObliqueAngle()) == L"14deg"
            && d.Display() == fm::FontDisplay::Swap;
        check(ok, "FontDescriptors Set* string parsing");
    }

    // 4. Data-font load via DirectWrite (requires a real .ttf/.otf path as argv[1]).
    if (argc > 1)
    {
        try
        {
            auto buffer = resolver::FetchFontDataAsync(hstring(argv[1])).get();
            if (!buffer)
            {
                check(false, "load data font (could not read file)");
            }
            else
            {
                auto face = fmimpl::FontFace::FromFamilyData(hstring(L"DemoFont"), buffer);
                auto err = face.LoadAsync().get();
                check(err.empty() && face.Status() == fm::FontFaceStatus::Loaded, "FontFace.FromFamilyData + LoadAsync");
                std::wcout << L"      declared family = " << std::wstring(face.Family())
                           << L"\n      font uri        = " << std::wstring(face.FontUri()) << L"\n";
            }
        }
        catch (hresult_error const& e)
        {
            std::wcout << L"[FAIL] data font load threw: " << std::wstring(e.message()) << L"\n";
            failures++;
        }
    }
    else
    {
        std::cout << "[SKIP] data font load — pass a .ttf/.otf path as argument 1\n";
    }

    // 5. FontFaceSet add / size / check (weight+style scoring).
    {
        auto set = fmimpl::FontFaceSet::Instance();
        set.Clear();
        auto regular = fmimpl::FontFace::FromFamily(hstring(L"Demo Sans"));
        auto bold = fmimpl::FontFace::FromFamily(hstring(L"Demo Sans"));
        bold.SetFontWeight(L"700");
        set.Add(regular);
        set.Add(bold);
        check(set.Size() == 2, "FontFaceSet.Add / Size");
        check(set.Check(L"bold 16px 'Demo Sans'", L""), "FontFaceSet.Check matches registered family");
        check(!set.Check(L"16px 'Nope Family'", L""), "FontFaceSet.Check rejects unknown family");
        check(!set.Check(L"16px monospace", L""), "FontFaceSet.Check rejects unmatched generic");

        auto arr = set.GetArray();
        check(arr.Size() == 2, "FontFaceSet.GetArray snapshot");
    }

    // 6. Remote @font-face import (parse only; needs network). Optional.
    std::wstring cssUrl = argc > 2 ? argv[2] : L"https://fonts.googleapis.com/css?family=Roboto:400,700";
    {
        try
        {
            auto fonts = fmimpl::FontFace::ImportFromRemoteAsync(hstring(cssUrl), false).get();
            check(fonts.Size() > 0, "FontFace.ImportFromRemoteAsync parses remote @font-face rules");
            std::wcout << L"      imported " << fonts.Size() << L" face(s)\n";
        }
        catch (hresult_error const& e)
        {
            std::wcout << L"[SKIP] remote import (network?): " << std::wstring(e.message()) << L"\n";
        }
    }

    // 7. Remote import + load, twice: the second pass creates fresh faces for the same URLs, so it
    // measures the URL-keyed download cache rather than the per-face Loaded short-circuit.
    for (int pass = 1; pass <= 2; pass++)
    {
        try
        {
            auto start = std::chrono::steady_clock::now();
            auto fonts = fmimpl::FontFace::ImportFromRemoteAsync(hstring(cssUrl), true).get();
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
            bool allLoaded = fonts.Size() > 0;
            for (auto const& face : fonts)
            {
                allLoaded = allLoaded && face.Status() == fm::FontFaceStatus::Loaded && !face.FontUri().empty();
            }
            check(allLoaded, pass == 1 ? "ImportFromRemoteAsync(load) loads every face" : "ImportFromRemoteAsync(load) again loads every face");
            std::wcout << L"      pass " << pass << L": " << fonts.Size() << L" face(s) in " << ms << L" ms";
            if (fonts.Size() > 0) std::wcout << L", e.g. " << std::wstring(fonts.GetAt(0).FontUri());
            std::wcout << L"\n";
        }
        catch (hresult_error const& e)
        {
            std::wcout << L"[SKIP] remote import + load (network?): " << std::wstring(e.message()) << L"\n";
        }
    }

    // 8. Local file source + concurrent LoadAsync on one face (both callers must settle).
    if (argc > 1)
    {
        try
        {
            auto face = fmimpl::FontFace::FromFamilySource(hstring(L"DemoFile"), hstring(argv[1]));
            auto first = face.LoadAsync();
            auto second = face.LoadAsync();
            auto firstErr = first.get();
            auto secondErr = second.get();
            check(firstErr.empty() && secondErr.empty() && face.Status() == fm::FontFaceStatus::Loaded,
                  "FontFace.FromFamilySource(file) + concurrent LoadAsync");
            std::wcout << L"      font uri        = " << std::wstring(face.FontUri()) << L"\n";

            auto missing = fmimpl::FontFace::FromFamilySource(hstring(L"Missing"), hstring(L"C:\\nope\\missing.ttf"));
            auto err = missing.LoadAsync().get();
            check(!err.empty() && missing.Status() == fm::FontFaceStatus::Error, "FontFace.LoadAsync reports a missing file");

            auto notFound = fmimpl::FontFace::FromFamilySource(hstring(L"NotFound"), hstring(L"https://fonts.gstatic.com/s/ns-font-manager-missing.ttf"));
            auto httpErr = notFound.LoadAsync().get();
            check(!httpErr.empty() && notFound.Status() == fm::FontFaceStatus::Error, "FontFace.LoadAsync reports a failed download");
            std::wcout << L"      error           = " << std::wstring(httpErr) << L"\n";
        }
        catch (hresult_error const& e)
        {
            std::wcout << L"[FAIL] file source load threw: " << std::wstring(e.message()) << L"\n";
            failures++;
        }
    }

    std::cout << "\n" << (failures ? "RESULT: FAILURES\n" : "RESULT: ALL PASS\n");
    return failures;
}
