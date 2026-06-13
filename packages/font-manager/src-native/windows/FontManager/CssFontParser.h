#pragma once
#include <string>
#include <vector>
#include <map>
#include <optional>

// Pure C++ CSS helpers (no WinRT projection). Ports the iOS NSCFontParser (the `font:` shorthand
// parser) and NSCFontDescriptors +font-face rule parsing, so Windows resolves fonts identically.
namespace NativeScript::FontManager::css
{
    // Result of parsing a CSS `font:` shorthand value.
    struct FontShorthand
    {
        std::wstring style = L"normal";
        int weight = 400;
        int sizePx = -1; // -1 => no size found (iOS returns nil in this case)
        std::optional<double> lineHeight;
        std::vector<std::wstring> families;
        bool valid = false; // false mirrors NSCFontParser returning nil
    };

    // Parses a CSS `font:` shorthand, e.g. "italic bold 16px/1.4 'Open Sans', sans-serif".
    // Mirrors NSCFontParser parse:.
    FontShorthand ParseShorthand(std::wstring const& input);

    // Parses every `@font-face { ... }` block in `css` into a property map with lowercased keys.
    // `src` values are reduced to the first url(...) target with surrounding quotes stripped and
    // `font-family` values are unquoted — mirrors NSCFontDescriptors parseFontFaceRules:.
    std::vector<std::map<std::wstring, std::wstring>> ParseFontFaceRules(std::wstring const& css);
}
