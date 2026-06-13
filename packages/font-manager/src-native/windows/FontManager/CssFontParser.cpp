#include "pch.h"
#include "CssFontParser.h"
#include <regex>
#include <cwctype>

namespace
{
    std::wstring Trim(std::wstring const& s)
    {
        size_t start = 0;
        size_t end = s.size();
        while (start < end && iswspace(s[start])) start++;
        while (end > start && iswspace(s[end - 1])) end--;
        return s.substr(start, end - start);
    }

    std::wstring ToLower(std::wstring s)
    {
        for (auto& ch : s) ch = static_cast<wchar_t>(towlower(ch));
        return s;
    }

    std::wstring StripQuotes(std::wstring const& s)
    {
        size_t start = 0;
        size_t end = s.size();
        while (start < end && (s[start] == L'\'' || s[start] == L'"')) start++;
        while (end > start && (s[end - 1] == L'\'' || s[end - 1] == L'"')) end--;
        return s.substr(start, end - start);
    }

    bool StartsWith(std::wstring const& s, std::wstring const& prefix)
    {
        return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
    }

    // True only when `token` is exactly an integer 100..900 (matches NSCFontParser's
    // "the numeric form round-trips" check, which rejects "16px" etc.).
    bool TryNumericWeight(std::wstring const& token, int& out)
    {
        if (token.empty()) return false;
        for (wchar_t ch : token)
        {
            if (ch < L'0' || ch > L'9') return false;
        }
        int value = _wtoi(token.c_str());
        if (value >= 100 && value <= 900)
        {
            out = value;
            return true;
        }
        return false;
    }

    void FlushFamilyBuffer(std::wstring& buffer, std::vector<std::wstring>& families)
    {
        std::wstring trimmed = Trim(buffer);
        if (!trimmed.empty())
        {
            families.push_back(trimmed);
            buffer.clear();
        }
    }
}

namespace NativeScript::FontManager::css
{
    FontShorthand ParseShorthand(std::wstring const& input)
    {
        FontShorthand result;

        // Tokenizer mirrors NSCFontParser tokenRegex: quoted strings, bare runs, or a comma.
        static const std::wregex tokenRegex(LR"('[^']*'|"[^"]*"|[^,\s]+|,)");

        std::wstring style = L"normal";
        int weight = 400;
        int sizePx = -1;
        std::optional<double> lineHeight;
        std::vector<std::wstring> families;
        std::wstring familyBuffer;
        bool readingFamilies = false;

        auto begin = std::wsregex_iterator(input.begin(), input.end(), tokenRegex);
        auto end = std::wsregex_iterator();
        for (auto it = begin; it != end; ++it)
        {
            std::wstring token = it->str();

            if (token == L",")
            {
                FlushFamilyBuffer(familyBuffer, families);
                continue;
            }

            if (token == L"italic")
            {
                style = L"italic";
            }
            else if (StartsWith(token, L"oblique"))
            {
                std::wstring angle = Trim(token.substr(std::wstring(L"oblique").size()));
                style = angle.empty() ? L"oblique" : (L"oblique " + angle);
            }
            else if (token == L"bold")
            {
                weight = 700;
            }
            else
            {
                int numericWeight = 0;
                if (TryNumericWeight(token, numericWeight))
                {
                    weight = numericWeight;
                }
                else if (!readingFamilies && token.find(L"px") != std::wstring::npos)
                {
                    // size[/line-height] — match "px" anywhere so the "16px/1.4" form parses too
                    // (iOS only checks a trailing "px"); guarded by !readingFamilies so a later
                    // family token containing "px" is never mistaken for the size.
                    std::wstring sizePart = token;
                    std::wstring lineHeightPart;
                    size_t slash = token.find(L'/');
                    if (slash != std::wstring::npos)
                    {
                        sizePart = token.substr(0, slash);
                        lineHeightPart = token.substr(slash + 1);
                    }
                    // strip "px"
                    size_t pxPos = sizePart.find(L"px");
                    if (pxPos != std::wstring::npos) sizePart = sizePart.substr(0, pxPos);
                    sizePx = _wtoi(Trim(sizePart).c_str());
                    if (!lineHeightPart.empty())
                    {
                        lineHeight = _wtof(lineHeightPart.c_str());
                    }
                    readingFamilies = true;
                }
                else if (readingFamilies)
                {
                    if (!familyBuffer.empty()) familyBuffer.append(L" ");
                    // strip embedded quotes (matches iOS replacing both ' and ")
                    std::wstring clean;
                    clean.reserve(token.size());
                    for (wchar_t ch : token)
                    {
                        if (ch != L'\'' && ch != L'"') clean.push_back(ch);
                    }
                    familyBuffer.append(clean);
                }
            }
        }

        FlushFamilyBuffer(familyBuffer, families);

        if (sizePx < 0)
        {
            return result; // valid = false
        }

        result.style = style;
        result.weight = weight;
        result.sizePx = sizePx;
        result.lineHeight = lineHeight;
        result.families = families;
        result.valid = true;
        return result;
    }

    std::vector<std::map<std::wstring, std::wstring>> ParseFontFaceRules(std::wstring const& css)
    {
        std::vector<std::map<std::wstring, std::wstring>> results;

        static const std::wregex blockRegex(LR"(@font-face\s*\{([\s\S]*?)\})");
        static const std::wregex propRegex(LR"(([a-zA-Z-]+)\s*:\s*([^;]+);)");
        static const std::wregex srcUrlRegex(LR"(url\(([^)]+)\))");

        auto blocksBegin = std::wsregex_iterator(css.begin(), css.end(), blockRegex);
        auto blocksEnd = std::wsregex_iterator();
        for (auto bit = blocksBegin; bit != blocksEnd; ++bit)
        {
            std::wstring block = (*bit)[1].str();
            std::map<std::wstring, std::wstring> props;

            auto propsBegin = std::wsregex_iterator(block.begin(), block.end(), propRegex);
            auto propsEnd = std::wsregex_iterator();
            for (auto pit = propsBegin; pit != propsEnd; ++pit)
            {
                std::wstring key = Trim(ToLower((*pit)[1].str()));
                std::wstring value = Trim((*pit)[2].str());

                if (key == L"src")
                {
                    std::wsmatch urlMatch;
                    if (std::regex_search(value, urlMatch, srcUrlRegex))
                    {
                        props[L"src"] = StripQuotes(Trim(urlMatch[1].str()));
                    }
                    else
                    {
                        props[L"src"] = value;
                    }
                    continue;
                }

                if (key == L"font-family")
                {
                    value = StripQuotes(value);
                }

                props[key] = value;
            }

            results.push_back(std::move(props));
        }

        return results;
    }
}
