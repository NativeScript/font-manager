const url_ex = /url\(\s*(['"]?)(.*?)\1\s*\)/;

export function fontSourcePath(source: string, appPath: string): string {
  const path = source.match(url_ex)?.[2] ?? source.trim();
  return path.startsWith('~/') ? appPath + path.slice(1) : path;
}
