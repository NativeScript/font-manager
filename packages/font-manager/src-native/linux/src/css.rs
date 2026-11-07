//! CSS pieces: the `font` shorthand, family lists, `@font-face` rules and `src` lists.

#[derive(Debug, Clone, PartialEq)]
pub struct Shorthand {
    pub italic: bool,
    pub oblique: bool,
    pub weight: i32,
    pub size_px: f64,
    pub line_height: Option<String>,
    pub families: Vec<String>,
}

pub const GENERIC_FAMILIES: &[&str] = &[
    "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-serif", "ui-sans-serif",
    "ui-monospace", "ui-rounded", "math", "emoji", "fangsong",
];

pub fn is_generic(family: &str) -> bool {
    GENERIC_FAMILIES.iter().any(|g| g.eq_ignore_ascii_case(family))
}

/// fontconfig's name for a CSS generic family.
pub fn fontconfig_generic(family: &str) -> Option<&'static str> {
    let lower = family.to_ascii_lowercase();
    Some(match lower.as_str() {
        "serif" | "ui-serif" => "serif",
        "sans-serif" | "system-ui" | "ui-sans-serif" | "ui-rounded" => "sans-serif",
        "monospace" | "ui-monospace" => "monospace",
        "cursive" => "cursive",
        "fantasy" => "fantasy",
        "math" => "math",
        "emoji" => "emoji",
        "fangsong" => "serif",
        _ => return None,
    })
}

pub fn unquote(s: &str) -> &str {
    let s = s.trim();
    let b = s.as_bytes();
    if b.len() >= 2 && (b[0] == b'\'' || b[0] == b'"') && b[b.len() - 1] == b[0] {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

fn tokens(input: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let b = input.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c.is_ascii_whitespace() {
            i += 1;
        } else if c == b',' {
            out.push(",");
            i += 1;
        } else if c == b'\'' || c == b'"' {
            let start = i;
            i += 1;
            while i < b.len() && b[i] != c {
                i += 1;
            }
            i = (i + 1).min(b.len());
            out.push(&input[start..i]);
        } else {
            let start = i;
            while i < b.len() && !b[i].is_ascii_whitespace() && b[i] != b',' {
                i += 1;
            }
            out.push(&input[start..i]);
        }
    }
    out
}

const SIZE_KEYWORDS: &[(&str, f64)] = &[
    ("xx-small", 9.0),
    ("x-small", 10.0),
    ("small", 13.0),
    ("medium", 16.0),
    ("large", 18.0),
    ("x-large", 24.0),
    ("xx-large", 32.0),
    ("xxx-large", 48.0),
    ("smaller", 13.0),
    ("larger", 19.0),
];

/// Length in px, for `font` sizes.
fn parse_size(token: &str) -> Option<f64> {
    let lower = token.to_ascii_lowercase();
    if let Some((_, px)) = SIZE_KEYWORDS.iter().find(|(k, _)| *k == lower) {
        return Some(*px);
    }
    let split = lower
        .find(|c: char| !(c.is_ascii_digit() || c == '.' || c == '+' || c == '-'))
        .filter(|&i| i > 0)?;
    let value: f64 = lower[..split].parse().ok()?;
    let scale = match &lower[split..] {
        "px" => 1.0,
        "pt" => 4.0 / 3.0,
        "pc" => 16.0,
        "in" => 96.0,
        "cm" => 96.0 / 2.54,
        "mm" => 96.0 / 25.4,
        "q" => 96.0 / 101.6,
        "em" | "rem" => 16.0,
        "ex" | "ch" => 8.0,
        "%" => 0.16,
        "vw" | "vh" | "vmin" | "vmax" => 16.0,
        _ => return None,
    };
    (value >= 0.0).then_some(value * scale)
}

fn parse_weight_number(token: &str) -> Option<i32> {
    if !token.bytes().all(|c| c.is_ascii_digit() || c == b'.') {
        return None;
    }
    let value: f64 = token.parse().ok()?;
    (1.0..=1000.0).contains(&value).then_some(value.round() as i32)
}

fn is_angle(token: &str) -> bool {
    let lower = token.to_ascii_lowercase();
    ["deg", "grad", "rad", "turn"]
        .iter()
        .any(|u| lower.strip_suffix(u).is_some_and(|n| !n.is_empty() && n.parse::<f64>().is_ok()))
}

/// Parses a CSS `font` shorthand such as `italic bold 16px/1.4 'Open Sans', sans-serif`.
pub fn parse_shorthand(input: &str) -> Option<Shorthand> {
    let toks = tokens(input);
    let mut out = Shorthand {
        italic: false,
        oblique: false,
        weight: 400,
        size_px: -1.0,
        line_height: None,
        families: Vec::new(),
    };
    let mut i = 0;
    while i < toks.len() {
        let token = toks[i];
        i += 1;
        let lower = token.to_ascii_lowercase();
        match lower.as_str() {
            "italic" => out.italic = true,
            "oblique" => {
                out.oblique = true;
                if toks.get(i).is_some_and(|t| is_angle(t)) {
                    i += 1;
                }
            }
            "bold" | "bolder" => out.weight = 700,
            "lighter" => out.weight = 100,
            "normal" | "small-caps" | "ultra-condensed" | "extra-condensed" | "condensed" | "semi-condensed"
            | "semi-expanded" | "expanded" | "extra-expanded" | "ultra-expanded" => {}
            "," => return None,
            _ => {
                if let Some(weight) = parse_weight_number(&lower) {
                    out.weight = weight;
                    continue;
                }
                let (size, rest) = match token.find('/') {
                    Some(slash) => (&token[..slash], Some(&token[slash + 1..])),
                    None => (token, None),
                };
                out.size_px = parse_size(size)?;
                match rest {
                    Some(lh) if !lh.is_empty() => out.line_height = Some(lh.to_string()),
                    Some(_) => {
                        out.line_height = toks.get(i).map(|t| t.to_string());
                        i += 1;
                    }
                    None if toks.get(i).is_some_and(|t| t.starts_with('/')) => {
                        let t = toks[i];
                        i += 1;
                        if t.len() > 1 {
                            out.line_height = Some(t[1..].to_string());
                        } else {
                            out.line_height = toks.get(i).map(|t| t.to_string());
                            i += 1;
                        }
                    }
                    None => {}
                }
                break;
            }
        }
    }
    if out.size_px < 0.0 {
        return None;
    }
    out.families = family_tokens(&toks[i.min(toks.len())..]);
    (!out.families.is_empty()).then_some(out)
}

fn family_tokens(toks: &[&str]) -> Vec<String> {
    let mut families = Vec::new();
    let mut current = String::new();
    for token in toks {
        if *token == "," {
            if !current.is_empty() {
                families.push(std::mem::take(&mut current));
            }
            continue;
        }
        let word = unquote(token);
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(word);
    }
    if !current.is_empty() {
        families.push(current);
    }
    families
}

/// A CSS `font-family` value as family names, without quotes.
pub fn parse_family_list(value: &str) -> Vec<String> {
    family_tokens(&tokens(value))
}

pub fn strip_comments(css: &str) -> std::borrow::Cow<'_, str> {
    if !css.contains("/*") {
        return css.into();
    }
    let mut out = String::with_capacity(css.len());
    let mut rest = css;
    while let Some(start) = rest.find("/*") {
        out.push_str(&rest[..start]);
        match rest[start + 2..].find("*/") {
            Some(end) => rest = &rest[start + 2 + end + 2..],
            None => return out.into(),
        }
    }
    out.push_str(rest);
    out.into()
}

/// Splits on `sep` outside quotes and parentheses.
fn split_top_level(s: &str, sep: u8) -> Vec<&str> {
    let b = s.as_bytes();
    let mut parts = Vec::new();
    let (mut depth, mut quote, mut start) = (0i32, 0u8, 0usize);
    for (i, &c) in b.iter().enumerate() {
        if quote != 0 {
            if c == quote {
                quote = 0;
            }
        } else if c == b'\'' || c == b'"' {
            quote = c;
        } else if c == b'(' {
            depth += 1;
        } else if c == b')' {
            depth = (depth - 1).max(0);
        } else if c == sep && depth == 0 {
            parts.push(&s[start..i]);
            start = i + 1;
        }
    }
    parts.push(&s[start..]);
    parts
}

/// `name: value` pairs of a declaration block; names lowercased.
pub fn declarations(block: &str) -> Vec<(String, String)> {
    let block = strip_comments(block);
    split_top_level(&block, b';')
        .into_iter()
        .filter_map(|d| {
            let colon = d.find(':')?;
            let name = d[..colon].trim().to_ascii_lowercase();
            let value = d[colon + 1..].trim();
            (!name.is_empty() && !value.is_empty()).then(|| (name, value.to_string()))
        })
        .collect()
}

/// The declaration blocks of every `@font-face` rule in a stylesheet.
pub fn font_face_blocks(css: &str) -> Vec<String> {
    let css = strip_comments(css);
    let lower = css.to_ascii_lowercase();
    let mut blocks = Vec::new();
    let mut from = 0;
    while let Some(at) = lower[from..].find("@font-face") {
        let start = from + at + "@font-face".len();
        let Some(open) = css[start..].find('{') else { break };
        let body_start = start + open + 1;
        let b = css.as_bytes();
        let (mut i, mut quote) = (body_start, 0u8);
        while i < b.len() {
            let c = b[i];
            if quote != 0 {
                if c == quote {
                    quote = 0;
                }
            } else if c == b'\'' || c == b'"' {
                quote = c;
            } else if c == b'}' {
                break;
            }
            i += 1;
        }
        blocks.push(css[body_start..i].to_string());
        from = (i + 1).min(css.len());
    }
    blocks
}

/// Argument of the CSS function `name(...)` in `s`, unquoted.
fn function_arg<'a>(s: &'a str, name: &str) -> Option<&'a str> {
    let lower = s.to_ascii_lowercase();
    let mut from = 0;
    loop {
        let at = from + lower[from..].find(name)?;
        let after = at + name.len();
        let boundary = at == 0 || !lower.as_bytes()[at - 1].is_ascii_alphanumeric() && lower.as_bytes()[at - 1] != b'-';
        if boundary && lower[after..].trim_start().starts_with('(') {
            let open = after + lower[after..].find('(')? + 1;
            let b = s.as_bytes();
            let (mut i, mut quote) = (open, 0u8);
            while i < b.len() {
                let c = b[i];
                if quote != 0 {
                    if c == quote {
                        quote = 0;
                    }
                } else if c == b'\'' || c == b'"' {
                    quote = c;
                } else if c == b')' {
                    break;
                }
                i += 1;
            }
            return Some(unquote(&s[open..i]));
        }
        from = after;
    }
}

fn supported_format(format: &str) -> bool {
    let f = format.to_ascii_lowercase();
    let f = f.strip_suffix("-variations").unwrap_or(&f);
    matches!(f, "woff" | "woff2" | "truetype" | "opentype" | "collection" | "ttf" | "otf")
}

/// The first `url()` of a `src` list FreeType can read, resolved against `base`.
pub fn pick_source(src: &str, base: Option<&str>) -> Option<String> {
    for part in split_top_level(src, b',') {
        let Some(url) = function_arg(part, "url") else { continue };
        if url.is_empty() {
            continue;
        }
        if function_arg(part, "format").is_some_and(|f| !split_top_level(f, b',').iter().any(|f| supported_format(unquote(f)))) {
            continue;
        }
        return Some(match base {
            Some(base) => resolve_url(url, base),
            None => url.to_string(),
        });
    }
    None
}

/// A face source as given to `FontFace`: a `src` list, `url(...)`, or a bare URL / path.
pub fn source_url(source: &str) -> Option<String> {
    let trimmed = source.trim();
    if trimmed.is_empty() {
        return None;
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.contains("url(") || lower.starts_with("local(") {
        return pick_source(trimmed, None);
    }
    Some(unquote(trimmed).to_string())
}

fn has_scheme(url: &str) -> bool {
    let Some(colon) = url.find(':') else { return false };
    let scheme = &url[..colon];
    colon > 1
        && scheme.as_bytes()[0].is_ascii_alphabetic()
        && scheme.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'+' || c == b'-' || c == b'.')
}

fn normalize_path(path: &str) -> String {
    let mut out: Vec<&str> = Vec::new();
    let absolute = path.starts_with('/');
    for seg in path.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                out.pop();
            }
            s => out.push(s),
        }
    }
    let joined = out.join("/");
    let trailing = path.ends_with('/') && !joined.is_empty();
    format!("{}{}{}", if absolute { "/" } else { "" }, joined, if trailing { "/" } else { "" })
}

/// Resolves a stylesheet-relative URL; `base` is an http(s)/file URL or a path.
pub fn resolve_url(url: &str, base: &str) -> String {
    if has_scheme(url) || url.starts_with("~/") || base.is_empty() {
        return url.to_string();
    }
    let base = base.split(['?', '#']).next().unwrap_or(base);
    let (prefix, base_path) = match base.find("://") {
        Some(i) => {
            let rest = &base[i + 3..];
            let host_end = rest.find('/').map(|p| i + 3 + p).unwrap_or(base.len());
            (&base[..host_end], &base[host_end..])
        }
        None => ("", base),
    };
    if url.starts_with("//") {
        let scheme = base.find(':').map(|c| &base[..c]).unwrap_or("https");
        return format!("{scheme}:{url}");
    }
    let path = if url.starts_with('/') {
        normalize_path(url)
    } else {
        let dir = match base_path.rfind('/') {
            Some(i) => &base_path[..=i],
            None => "",
        };
        normalize_path(&format!("{dir}{url}"))
    };
    let path = if !prefix.is_empty() && !path.starts_with('/') { format!("/{path}") } else { path };
    format!("{prefix}{path}")
}

/// `unicode-range` as inclusive code point ranges.
pub fn parse_unicode_range(value: &str) -> Option<Vec<(u32, u32)>> {
    let mut ranges = Vec::new();
    for part in value.split(',') {
        let part = part.trim();
        let body = part.strip_prefix("U+").or_else(|| part.strip_prefix("u+"))?;
        let range = if let Some((a, b)) = body.split_once('-') {
            (u32::from_str_radix(a, 16).ok()?, u32::from_str_radix(b, 16).ok()?)
        } else if body.contains('?') {
            let lo = u32::from_str_radix(&body.replace('?', "0"), 16).ok()?;
            let hi = u32::from_str_radix(&body.replace('?', "F"), 16).ok()?;
            (lo, hi)
        } else {
            let v = u32::from_str_radix(body, 16).ok()?;
            (v, v)
        };
        if range.0 > range.1 || range.1 > 0x10FFFF {
            return None;
        }
        ranges.push(range);
    }
    (!ranges.is_empty()).then_some(ranges)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shorthand_full() {
        let s = parse_shorthand("italic bold 16px/1.4 'Open Sans', \"Fira Code\", sans-serif").unwrap();
        assert!(s.italic);
        assert_eq!(s.weight, 700);
        assert_eq!(s.size_px, 16.0);
        assert_eq!(s.line_height.as_deref(), Some("1.4"));
        assert_eq!(s.families, ["Open Sans", "Fira Code", "sans-serif"]);
    }

    #[test]
    fn shorthand_units_and_weights() {
        let s = parse_shorthand("300 12pt Roboto").unwrap();
        assert_eq!(s.weight, 300);
        assert_eq!(s.size_px, 16.0);
        assert_eq!(s.families, ["Roboto"]);
        let s = parse_shorthand("oblique 10deg 2em My Font Family").unwrap();
        assert!(s.oblique && !s.italic);
        assert_eq!(s.families, ["My Font Family"]);
        let s = parse_shorthand("bold large serif").unwrap();
        assert_eq!(s.size_px, 18.0);
        let s = parse_shorthand("16px / 2 serif").unwrap();
        assert_eq!(s.line_height.as_deref(), Some("2"));
    }

    #[test]
    fn shorthand_invalid() {
        assert!(parse_shorthand("bold Roboto").is_none());
        assert!(parse_shorthand("16px").is_none());
        assert!(parse_shorthand("").is_none());
        // a family named like a size is still a family
        assert_eq!(parse_shorthand("16px 12px").unwrap().families, ["12px"]);
    }

    #[test]
    fn family_list() {
        assert_eq!(parse_family_list(" 'Mukta  Mahee' , Arial Black,serif"), ["Mukta  Mahee", "Arial Black", "serif"]);
        assert!(parse_family_list("").is_empty());
    }

    #[test]
    fn font_face_rules() {
        let css = r#"
            /* comment { } */
            @font-face { font-family: 'Foo'; src: url(data:font/ttf;base64,AAAA) format("truetype"); font-weight: 700 }
            p { color: red }
            @FONT-FACE{font-family:"Bar";src:local(Bar),url('bar.woff2') format('woff2'),url(bar.eot) format('embedded-opentype')}
        "#;
        let blocks = font_face_blocks(css);
        assert_eq!(blocks.len(), 2);
        let d = declarations(&blocks[0]);
        assert_eq!(d[0], ("font-family".into(), "'Foo'".into()));
        assert_eq!(d[1].1, "url(data:font/ttf;base64,AAAA) format(\"truetype\")");
        assert_eq!(pick_source(&d[1].1, None).unwrap(), "data:font/ttf;base64,AAAA");
        let d = declarations(&blocks[1]);
        assert_eq!(pick_source(&d[1].1, Some("https://cdn.test/css/x.css?v=1")).unwrap(), "https://cdn.test/css/bar.woff2");
    }

    #[test]
    fn source_picking() {
        assert_eq!(pick_source("url(a.eot) format('embedded-opentype'), url(a.svg) format(svg)", None), None);
        assert_eq!(pick_source("url(a.ttf) format('truetype-variations')", None).unwrap(), "a.ttf");
        assert_eq!(source_url("  url( \"~/fonts/a.ttf\" ) ").unwrap(), "~/fonts/a.ttf");
        assert_eq!(source_url("'/tmp/a.ttf'").unwrap(), "/tmp/a.ttf");
        assert_eq!(source_url("local(Foo)"), None);
    }

    #[test]
    fn url_resolution() {
        assert_eq!(resolve_url("../f/a.woff", "https://h.test/css/x.css"), "https://h.test/f/a.woff");
        assert_eq!(resolve_url("/f/a.woff", "https://h.test/css/x.css"), "https://h.test/f/a.woff");
        assert_eq!(resolve_url("//cdn.test/a.woff", "https://h.test/x.css"), "https://cdn.test/a.woff");
        assert_eq!(resolve_url("a.ttf", "/app/css/fonts.css"), "/app/css/a.ttf");
        assert_eq!(resolve_url("./a.ttf", "file:///app/x.css"), "file:///app/a.ttf");
        assert_eq!(resolve_url("data:font/ttf,x", "/app/x.css"), "data:font/ttf,x");
        assert_eq!(resolve_url("~/fonts/a.ttf", "/app/x.css"), "~/fonts/a.ttf");
    }

    #[test]
    fn unicode_ranges() {
        assert_eq!(parse_unicode_range("U+0-10FFFF").unwrap(), [(0, 0x10FFFF)]);
        assert_eq!(parse_unicode_range("U+4??, u+0025-00FF, U+20").unwrap(), [(0x400, 0x4FF), (0x25, 0xFF), (0x20, 0x20)]);
        assert!(parse_unicode_range("U+FF-00").is_none());
        assert!(parse_unicode_range("bogus").is_none());
    }
}
