//! `@font-face` descriptors of a face.

use crate::css;

#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Which {
    Family = 0,
    Style = 1,
    Weight = 2,
    Stretch = 3,
    UnicodeRange = 4,
    FeatureSettings = 5,
    VariationSettings = 6,
    Display = 7,
    AscentOverride = 8,
    DescentOverride = 9,
    LineGapOverride = 10,
    Kerning = 11,
    VariantLigatures = 12,
    Variant = 13,
}

impl Which {
    pub fn from_i32(v: i32) -> Option<Self> {
        use Which::*;
        Some(match v {
            0 => Family,
            1 => Style,
            2 => Weight,
            3 => Stretch,
            4 => UnicodeRange,
            5 => FeatureSettings,
            6 => VariationSettings,
            7 => Display,
            8 => AscentOverride,
            9 => DescentOverride,
            10 => LineGapOverride,
            11 => Kerning,
            12 => VariantLigatures,
            13 => Variant,
            _ => return None,
        })
    }

    pub fn from_css(name: &str) -> Option<Self> {
        use Which::*;
        Some(match name {
            "font-family" => Family,
            "font-style" => Style,
            "font-weight" => Weight,
            "font-stretch" => Stretch,
            "unicode-range" => UnicodeRange,
            "font-feature-settings" => FeatureSettings,
            "font-variation-settings" => VariationSettings,
            "font-display" => Display,
            "ascent-override" => AscentOverride,
            "descent-override" => DescentOverride,
            "line-gap-override" => LineGapOverride,
            "font-kerning" => Kerning,
            "font-variant-ligatures" => VariantLigatures,
            "font-variant" => Variant,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    Normal,
    Italic,
    Oblique,
}

/// Same ordinals as the iOS and Windows FontDisplay.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Display {
    Auto = 0,
    Block = 1,
    Fallback = 2,
    Optional = 3,
    Swap = 4,
}

#[derive(Debug, Clone)]
pub struct Descriptors {
    pub family: String,
    /// Inclusive; equal unless the face is variable.
    pub weight: (i32, i32),
    pub style: Style,
    pub oblique_angle: String,
    pub display: Display,
    pub stretch: String,
    pub unicode_range: String,
    pub ranges: Vec<(u32, u32)>,
    pub feature_settings: String,
    pub variation_settings: String,
    pub ascent_override: String,
    pub descent_override: String,
    pub line_gap_override: String,
    pub kerning: String,
    pub variant_ligatures: String,
    pub variant: String,
}

fn parse_weight(value: &str) -> Option<(i32, i32)> {
    let v = value.trim().to_ascii_lowercase();
    match v.as_str() {
        "normal" => return Some((400, 400)),
        "bold" => return Some((700, 700)),
        _ => {}
    }
    let mut parts = v.split_ascii_whitespace().map(|p| match p {
        "normal" => Some(400.0),
        "bold" => Some(700.0),
        p => p.parse::<f64>().ok().filter(|w| (1.0..=1000.0).contains(w)),
    });
    let a = parts.next()??.round() as i32;
    let b = match parts.next() {
        Some(b) => b?.round() as i32,
        None => a,
    };
    if parts.next().is_some() {
        return None;
    }
    Some((a.min(b), a.max(b)))
}

impl Descriptors {
    pub fn new(family: &str) -> Self {
        Self {
            family: css::unquote(family).to_string(),
            weight: (400, 400),
            style: Style::Normal,
            oblique_angle: String::new(),
            display: Display::Auto,
            stretch: "normal".into(),
            unicode_range: "U+0-10FFFF".into(),
            ranges: vec![(0, 0x10FFFF)],
            feature_settings: "normal".into(),
            variation_settings: "normal".into(),
            ascent_override: "normal".into(),
            descent_override: "normal".into(),
            line_gap_override: "normal".into(),
            kerning: "auto".into(),
            variant_ligatures: "normal".into(),
            variant: "normal".into(),
        }
    }

    pub fn italic(&self) -> bool {
        self.style != Style::Normal
    }

    /// Applies a descriptor from its CSS text; false when the value is invalid (nothing changes).
    pub fn set(&mut self, which: Which, value: &str) -> bool {
        let value = value.trim();
        let text = || value.to_string();
        match which {
            Which::Family => return false,
            Which::Weight => match parse_weight(value) {
                Some(w) => self.weight = w,
                None => return false,
            },
            Which::Style => {
                let lower = value.to_ascii_lowercase();
                match lower.as_str() {
                    "normal" => (self.style, self.oblique_angle) = (Style::Normal, String::new()),
                    "italic" => (self.style, self.oblique_angle) = (Style::Italic, String::new()),
                    _ => match lower.strip_prefix("oblique") {
                        Some(rest) if rest.is_empty() || rest.starts_with(char::is_whitespace) => {
                            let angle = rest.trim();
                            self.style = Style::Oblique;
                            self.oblique_angle = if angle.is_empty() { "0deg".into() } else { angle.into() };
                        }
                        _ => return false,
                    },
                }
            }
            Which::Display => {
                self.display = match value.to_ascii_lowercase().as_str() {
                    "auto" => Display::Auto,
                    "block" => Display::Block,
                    "fallback" => Display::Fallback,
                    "optional" => Display::Optional,
                    "swap" => Display::Swap,
                    _ => return false,
                }
            }
            Which::UnicodeRange => match css::parse_unicode_range(value) {
                Some(r) => (self.ranges, self.unicode_range) = (r, text()),
                None => return false,
            },
            Which::Stretch => self.stretch = text(),
            Which::FeatureSettings => self.feature_settings = text(),
            Which::VariationSettings => self.variation_settings = text(),
            Which::AscentOverride => self.ascent_override = text(),
            Which::DescentOverride => self.descent_override = text(),
            Which::LineGapOverride => self.line_gap_override = text(),
            Which::Kerning => self.kerning = text(),
            Which::VariantLigatures => self.variant_ligatures = text(),
            Which::Variant => self.variant = text(),
        }
        true
    }

    pub fn get(&self, which: Which) -> String {
        match which {
            Which::Family => self.family.clone(),
            Which::Weight => match self.weight {
                (400, 400) => "normal".into(),
                (700, 700) => "bold".into(),
                (a, b) if a == b => a.to_string(),
                (a, b) => format!("{a} {b}"),
            },
            Which::Style => match self.style {
                Style::Normal => "normal".into(),
                Style::Italic => "italic".into(),
                Style::Oblique if self.oblique_angle.is_empty() || self.oblique_angle == "0deg" => "oblique".into(),
                Style::Oblique => format!("oblique {}", self.oblique_angle),
            },
            Which::Display => match self.display {
                Display::Auto => "auto",
                Display::Block => "block",
                Display::Fallback => "fallback",
                Display::Optional => "optional",
                Display::Swap => "swap",
            }
            .into(),
            Which::UnicodeRange => self.unicode_range.clone(),
            Which::Stretch => self.stretch.clone(),
            Which::FeatureSettings => self.feature_settings.clone(),
            Which::VariationSettings => self.variation_settings.clone(),
            Which::AscentOverride => self.ascent_override.clone(),
            Which::DescentOverride => self.descent_override.clone(),
            Which::LineGapOverride => self.line_gap_override.clone(),
            Which::Kerning => self.kerning.clone(),
            Which::VariantLigatures => self.variant_ligatures.clone(),
            Which::Variant => self.variant.clone(),
        }
    }

    /// Applies the declarations of the first `@font-face` rule in `css`, or of a bare declaration list.
    pub fn update(&mut self, css_text: &str) {
        let blocks = css::font_face_blocks(css_text);
        let body = blocks.first().map(String::as_str).unwrap_or(css_text);
        for (name, value) in css::declarations(body) {
            if let Some(which) = Which::from_css(&name) {
                self.set(which, &value);
            }
        }
    }

    /// Whether the face has glyphs for some character of `text` per its unicode-range.
    pub fn covers(&self, text: &str) -> bool {
        text.is_empty()
            || text
                .chars()
                .any(|c| self.ranges.iter().any(|&(lo, hi)| (lo..=hi).contains(&(c as u32))))
    }

    /// Lower is better: weight distance plus a style penalty (CSS font matching, simplified).
    pub fn score(&self, weight: i32, italic: bool, oblique: bool) -> i64 {
        let (lo, hi) = self.weight;
        let weight_diff = if weight < lo { lo - weight } else if weight > hi { weight - hi } else { 0 };
        let style = match (self.style, italic, oblique) {
            (Style::Normal, false, false) | (Style::Italic, true, _) | (Style::Oblique, _, true) => 0,
            (Style::Italic, false, true) | (Style::Oblique, true, false) => 500,
            _ => 1000,
        };
        weight_diff as i64 + style
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults() {
        let d = Descriptors::new("'Roboto'");
        assert_eq!(d.family, "Roboto");
        assert_eq!(d.get(Which::Weight), "normal");
        assert_eq!(d.get(Which::Style), "normal");
        assert_eq!(d.get(Which::Display), "auto");
        assert_eq!(d.get(Which::Stretch), "normal");
        assert_eq!(d.get(Which::Kerning), "auto");
        assert_eq!(d.get(Which::UnicodeRange), "U+0-10FFFF");
    }

    #[test]
    fn setters() {
        let mut d = Descriptors::new("x");
        assert!(d.set(Which::Weight, "700"));
        assert_eq!(d.get(Which::Weight), "bold");
        assert!(d.set(Which::Weight, "100 900"));
        assert_eq!(d.weight, (100, 900));
        assert!(!d.set(Which::Weight, "bolder"));
        assert!(!d.set(Which::Weight, "0"));
        assert_eq!(d.weight, (100, 900));
        assert!(d.set(Which::Style, "oblique 12deg"));
        assert_eq!(d.get(Which::Style), "oblique 12deg");
        assert!(d.set(Which::Style, "Oblique"));
        assert_eq!(d.get(Which::Style), "oblique");
        assert!(!d.set(Which::Style, "obliquex"));
        assert!(d.set(Which::Display, "SWAP"));
        assert_eq!(d.display, Display::Swap);
        assert!(!d.set(Which::Display, "later"));
        assert!(!d.set(Which::Family, "y"));
        assert!(d.set(Which::UnicodeRange, "U+0-7F"));
        assert!(d.covers("abc") && !d.covers("é") && d.covers(""));
    }

    #[test]
    fn update_from_css() {
        let mut d = Descriptors::new("Roboto");
        d.update("@font-face { font-family: Other; font-weight: 300; font-style: italic; font-display: swap; ascent-override: 90%; src: url(a.ttf) }");
        assert_eq!(d.family, "Roboto");
        assert_eq!(d.weight, (300, 300));
        assert!(d.italic());
        assert_eq!(d.display, Display::Swap);
        assert_eq!(d.ascent_override, "90%");
        d.update("font-weight: bold; font-variant-ligatures: none");
        assert_eq!(d.weight, (700, 700));
        assert_eq!(d.variant_ligatures, "none");
    }

    #[test]
    fn scoring() {
        let mut regular = Descriptors::new("x");
        let mut bold = Descriptors::new("x");
        bold.set(Which::Weight, "bold");
        assert!(regular.score(700, false, false) > bold.score(700, false, false));
        assert!(regular.score(400, false, false) < bold.score(400, false, false));
        regular.set(Which::Style, "italic");
        assert_eq!(regular.score(400, true, false), 0);
        assert_eq!(regular.score(400, false, true), 500);
        let mut variable = Descriptors::new("x");
        variable.set(Which::Weight, "100 900");
        assert_eq!(variable.score(650, false, false), 0);
    }
}
