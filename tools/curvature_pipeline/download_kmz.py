from __future__ import annotations

import argparse
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urljoin
from urllib.request import urlopen

from bs4 import BeautifulSoup


DEFAULT_LIST_URL = "https://kml.roadcurvature.com/north_america/canada/"


def fetch_html(url: str) -> str:
    with urlopen(url) as response:
        return response.read().decode("utf-8", errors="replace")


def discover_kmz_links(list_url: str = DEFAULT_LIST_URL, keyword: str = "c_300") -> list[str]:
    html = fetch_html(list_url)
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for anchor in soup.find_all("a", href=True):
        href = anchor["href"]
        if href.lower().endswith(".kmz") and keyword.lower() in href.lower():
            links.append(urljoin(list_url, href))
    return sorted(dict.fromkeys(links))


def download_file(url: str, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urlopen(url) as response, destination.open("wb") as output:
        output.write(response.read())
    return destination


def download_kmz_files(
    output_dir: Path,
    list_url: str = DEFAULT_LIST_URL,
    keyword: str = "c_300",
) -> list[Path]:
    links = discover_kmz_links(list_url=list_url, keyword=keyword)
    paths: list[Path] = []
    for link in links:
        target = output_dir / Path(link).name
        paths.append(download_file(link, target))
    return paths


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Download roadcurvature KMZ files")
    parser.add_argument("-o", "--output-dir", default="data/kmz", help="Directory for downloaded KMZ files")
    parser.add_argument("--list-url", default=DEFAULT_LIST_URL, help="Page that contains KMZ links")
    parser.add_argument("--keyword", default="c_300", help="Substring required in KMZ link")
    args = parser.parse_args(argv)

    output_dir = Path(args.output_dir)
    try:
        downloaded = download_kmz_files(output_dir, list_url=args.list_url, keyword=args.keyword)
    except (URLError, OSError) as exc:
        raise SystemExit(f"download failed: {exc}") from exc

    print(f"downloaded {len(downloaded)} file(s)")
    for path in downloaded:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
