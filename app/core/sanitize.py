"""Server-side HTML sanitization for user-supplied rich content (blogs).

Sanitization happens on WRITE (POST/PUT) so stored HTML is always safe to
render; GET endpoints simply serve what was persisted. Uses nh3 (Rust ammonia
bindings — the maintained bleach/DOMPurify equivalent): script/iframe/object
tags, event handler attributes, and javascript:/data: URLs are stripped, while
a conservative allowlist of formatting tags survives intact.
"""
import nh3

# Safe formatting/content tags kept from admin-authored blog HTML.
BLOG_ALLOWED_TAGS = {
    "p", "br", "hr", "span",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "strong", "b", "em", "i", "u", "s", "code", "pre", "kbd", "mark",
    "blockquote", "cite",
    "ul", "ol", "li",
    "table", "thead", "tbody", "tr", "th", "td",
    "a", "img", "figure", "figcaption",
    "sup", "sub", "small", "abbr", "details", "summary",
}

BLOG_ALLOWED_ATTRIBUTES = {
    # NOTE: "rel" on <a> is managed by nh3's link_rel — it must not be listed here.
    "a": {"href", "title", "target"},
    "img": {"src", "alt", "title", "width", "height", "loading"},
    "span": {"class"},
    "code": {"class"},
    "th": {"colspan", "rowspan", "scope"},
    "td": {"colspan", "rowspan"},
}

# Only safe schemes survive in href/src after cleaning.
BLOG_ALLOWED_URL_SCHEMES = {"http", "https", "mailto"}


def sanitize_html(value: str | None) -> str:
    """Clean an HTML fragment with the blog allowlist. Returns '' for None."""
    if not value:
        return ""
    return nh3.clean(
        str(value),
        tags=BLOG_ALLOWED_TAGS,
        attributes=BLOG_ALLOWED_ATTRIBUTES,
        url_schemes=BLOG_ALLOWED_URL_SCHEMES,
        link_rel="noopener noreferrer",
    )


def sanitize_plain_text(value: str | None) -> str:
    """Escape an excerpt/summary so it can never smuggle markup.

    Excerpts are plain text by contract — angle brackets are escaped, never
    preserved, so a payload like <img src=x onerror=...> cannot survive in the
    teaser that list pages render.
    """
    if not value:
        return ""
    import html

    return html.escape(str(value), quote=True)


def validate_http_url(value: str | None) -> str | None:
    """Allowlist check for stored URLs (cover images, links, logos).

    Only absolute http(s) URLs pass; anything else (javascript:, data:, //host,
    relative junk) is rejected. Returns the cleaned URL or None.
    """
    if not value:
        return None
    from urllib.parse import urlparse

    raw = str(value).strip()
    if not raw:
        return None
    try:
        parsed = urlparse(raw)
    except ValueError:
        return None
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return None
    return raw
