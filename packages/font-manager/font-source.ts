const url_ex = /url\(\s*(['"]?)(.*?)\1\s*\)/;

/** The location in a CSS `src` value (`url(...)`, quoted or not), or a bare path or URL as given. */
export function fontSourcePath(source: string, appPath: string): string {
  const path = source.match(url_ex)?.[2] ?? source.trim();
  return path.startsWith('~/') ? appPath + path.slice(1) : path;
}
