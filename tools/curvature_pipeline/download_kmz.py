from __future__ import annotations

import argparse
from pathlib import Path
from urllib.error import URLError
from urllib.parse import ParseResult, urljoin, urlparse
from urllib.request import HTTPRedirectHandler, build_opener

from bs4 import BeautifulSoup


DEFAULT_LIST_URL = "https://kml.roadcurvature.com/north_america/canada/"
MAX_LIST_BYTES = 2 * 1024 * 1024
MAX_DOWNLOAD_BYTES = 64 * 1024 * 1024
MAX_KMZ_LINKS = 500
DOWNLOAD_TIMEOUT_SECONDS = 20


class UnsafeDownloadUrlError(ValueError):
    pass


class DownloadSizeLimitError(ValueError):
    pass


class SafeRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validated_download_url(newurl, expected_host="kml.roadcurvature.com")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


SAFE_OPENER = build_opener(SafeRedirectHandler())


def validated_download_url(url: str, *, expected_host: str) -> ParseResult:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != expected_host:
        raise UnsafeDownloadUrlError(url)
    return parsed


def fetch_html(url: str) -> str:
    validated_download_url(url, expected_host="kml.roadcurvature.com")
    with SAFE_OPENER.open(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response:
        validated_download_url(response.geturl(), expected_host="kml.roadcurvature.com")
        payload = response.read(MAX_LIST_BYTES + 1)
    if len(payload) > MAX_LIST_BYTES:
        raise DownloadSizeLimitError(MAX_LIST_BYTES)
    return payload.decode("utf-8", errors="replace")


def discover_kmz_links(list_url: str = DEFAULT_LIST_URL, keyword: str = "c_300") -> list[str]:
    list_origin = validated_download_url(
        list_url,
        expected_host="kml.roadcurvature.com",
    )
    html = fetch_html(list_url)
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for anchor in soup.find_all("a", href=True):
        href = str(anchor["href"])
        if href.lower().endswith(".kmz") and keyword.lower() in href.lower():
            link = urljoin(list_url, href)
            validated_download_url(link, expected_host=list_origin.hostname or "")
            links.append(link)
        if len(links) > MAX_KMZ_LINKS:
            raise DownloadSizeLimitError(MAX_KMZ_LINKS)
    return sorted(dict.fromkeys(links))


def download_file(url: str, destination: Path) -> Path:
    validated_download_url(url, expected_host="kml.roadcurvature.com")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with SAFE_OPENER.open(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response, destination.open("wb") as output:
        validated_download_url(response.geturl(), expected_host="kml.roadcurvature.com")
        downloaded = 0
        while chunk := response.read(1024 * 1024):
            downloaded += len(chunk)
            if downloaded > MAX_DOWNLOAD_BYTES:
                raise DownloadSizeLimitError(MAX_DOWNLOAD_BYTES)
            output.write(chunk)
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
