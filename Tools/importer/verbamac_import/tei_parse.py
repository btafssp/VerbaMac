"""Parse Perseus TEI entryFree elements → compact HTML + plaintext + lemma."""

from __future__ import annotations

import html as html_mod
import re
from dataclasses import dataclass
from typing import Iterator, Optional
from xml.etree import ElementTree as ET

from .betacode import beta_key_plain, beta_to_unicode
from .normalize import greek_lemma_norm, latin_lemma_norm, looks_greek


@dataclass
class Article:
    lemma: str
    lemma_norm: str
    lang: str  # 'lat' | 'grc'
    html: str
    plain: str
    key: str = ""
    homograph: str = ""


# TEI P4 often has no namespace; some dumps add TEIform attrs we ignore.
_SKIP_TAGS = {"teiHeader", "teiheader", "fileDesc", "encodingDesc", "profileDesc", "revisionDesc"}


def _local(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[-1]
    return tag


def _text_content(el: ET.Element) -> str:
    parts: list[str] = []
    if el.text:
        parts.append(el.text)
    for child in el:
        parts.append(_text_content(child))
        if child.tail:
            parts.append(child.tail)
    return "".join(parts)


def _escape(s: str) -> str:
    return html_mod.escape(s, quote=False)


def _orth_display(orth_el: Optional[ET.Element], key: str, lang: str) -> str:
    raw = _text_content(orth_el).strip() if orth_el is not None else (key or "")
    raw = re.sub(r"\s+", " ", raw)
    if lang == "grc":
        if looks_greek(raw):
            return raw
        return beta_to_unicode(raw)
    return raw


_GREEK_LANGS = ("greek", "grc")
_XREF_TOKEN = re.compile(r"[^\s,;:]+")


def _el_greek(el: ET.Element, inherited: bool) -> bool:
    """TEI `lang` scoping: lang="greek" turns Beta Code conversion on; any other lang turns it off."""
    lang = (el.get("lang") or "").lower()
    if not lang:
        return inherited
    return lang in _GREEK_LANGS


def _greek_text(el: ET.Element, gk: bool) -> str:
    """Text content with Beta Code converted wherever the TEI lang scope is Greek."""
    g = _el_greek(el, gk)
    parts: list[str] = [_conv(el.text or "", g)]
    for child in el:
        parts.append(_greek_text(child, g))
        parts.append(_conv(child.tail or "", g))
    return "".join(parts)


def _conv(s: str, gk: bool) -> str:
    if gk and s and s.strip() and not looks_greek(s):
        return beta_to_unicode(s)
    return s


def xref_target(ref_text_beta: str) -> tuple[str, str]:
    """(Unicode lemma, homograph digits) for an LSJ <ref>: first token, trailing digits = homograph."""
    m = _XREF_TOKEN.search(ref_text_beta.strip())
    tok = m.group(0) if m else ""
    hm = re.match(r"^(.*?)(\d+)$", tok)
    base, hom = (hm.group(1), hm.group(2)) if hm else (tok, "")
    base = base.rstrip(".")
    lemma = base if looks_greek(base) else beta_to_unicode(base)
    return lemma, hom


# "v. εἴδω B." / "v. ἄγω II." — section label printed right after the cross-ref.
# Needs a capital letter or a Roman numeral first ("c." = cum, "11." = a citation).
_SEC = r"(?:[A-H]\.|[IVX]+\.)(?:\s*(?:[IVX]+\.|\d{1,2}\.|[a-h]\.))*"
_XREF_SEC = re.compile(
    r'(<a class="xref"[^>]*?href="verba-xref:grc\?l=[^"]*?)(")([^>]*>[^<]*</a>)(\s*)(?:<cite>(' + _SEC + r')</cite>|(' + _SEC + r')(?=[\s,;:)<]))'
)


def section_key(label: str) -> str:
    """"B." → "B", "C.VI." → "C.VI", "I. I." → "I.I"."""
    return ".".join(p for p in re.split(r"[.\s]+", label) if p)


def _attach_xref_sections(html: str) -> str:
    def sub(m: re.Match) -> str:
        label = m.group(5) or m.group(6)
        key = section_key(label)
        shown = f"<cite>{label}</cite>" if m.group(5) else label
        return (f'{m.group(1)}&amp;s={key}{m.group(2)} data-section="{key}"{m.group(3)}{m.group(4)}'
                f'{shown}')
    return _XREF_SEC.sub(sub, html)


def _entry_to_html(entry: ET.Element, lemma: str, lang: str) -> tuple[str, str]:
    """Return (html, plain) for one entryFree."""
    h1_lang = ' lang="greek"' if lang == "grc" else ""
    chunks: list[str] = [f'<article class="entry" data-lang="{lang}">', f'<h1 class="orth"{h1_lang}>{_escape(lemma)}</h1>']
    plain_parts: list[str] = [lemma]
    sense_seen: list[bool] = [False]  # mutable flag for nested walk()
    headword_orth_seen: list[bool] = [False]
    # Section anchors: level → sense n ("A", "II", "3", "b"); id "sec-B.II.3" (first wins).
    sense_path: dict[int, str] = {}
    used_ids: set[str] = set()
    # LSJ: Greek text outside explicit lang="greek" elements stays Latin-script (bibl, English).
    entry_gk = False

    def text(s: Optional[str], gk: bool) -> None:
        if s:
            chunks.append(_escape(_conv(s, gk)))

    def children(el: ET.Element, in_sense: bool, gk: bool) -> None:
        text(el.text, gk)
        for child in el:
            walk(child, in_sense, gk)

    def walk(el: ET.Element, in_sense: bool = False, parent_gk: bool = entry_gk) -> None:
        tag = _local(el.tag).lower()
        if tag in _SKIP_TAGS:
            return
        gk = _el_greek(el, parent_gk)

        def tail() -> None:
            text(el.tail, parent_gk)

        if tag == "orth":
            if not headword_orth_seen[0] and not in_sense:
                headword_orth_seen[0] = True
                # already in h1 — keep useful tail but drop a leading comma/space
                if el.tail:
                    t = el.tail.lstrip()
                    if t.startswith(","):
                        t = t[1:].lstrip()
                    if t:
                        chunks.append(" " + _escape(_conv(t, parent_gk)))
                return
            # Later <orth> (principal parts, oi)=da inside εἴδω): print it, don't drop it.
            raw = re.sub(r"\s+", " ", _greek_text(el, parent_gk)).strip()
            cls = ' lang="greek"' if gk else ""
            chunks.append(f'<span class="orth"{cls}>{_escape(raw)}</span>')
            plain_parts.append(raw)
            tail()
            return

        if tag in ("itype", "pos", "gen", "number", "mood", "tense", "voice", "case", "gender"):
            raw = _greek_text(el, parent_gk).strip()
            if raw:
                lang_attr = ' lang="greek"' if gk else ""
                chunks.append(f' <span class="{tag}"{lang_attr}>{_escape(raw)}</span>')
                plain_parts.append(raw)
            tail()
            return

        if tag == "etym":
            chunks.append('<span class="etym">')
            children(el, in_sense, gk)
            chunks.append("</span>")
            plain_parts.append(_greek_text(el, parent_gk))
            tail()
            return

        if tag == "sense":
            level = el.get("level") or ""
            sense_n = el.get("n") or ""
            lead = not sense_seen[0]
            sense_seen[0] = True
            level_attr = _escape(level)
            n_attr = f' data-n="{_escape(sense_n)}"' if sense_n else ""
            if sense_n and level.isdigit():
                lv = int(level)
                for k in [k for k in sense_path if k >= lv]:
                    del sense_path[k]
                sense_path[lv] = sense_n
                path = ".".join(sense_path[k] for k in sorted(sense_path))
                n_attr += f' data-path="{_escape(path)}"'
                if path not in used_ids:
                    used_ids.add(path)
                    n_attr += f' id="sec-{_escape(path)}"'

            if lead:
                chunks.append(f'<span class="sense sense-lead" data-level="{level_attr}"{n_attr}>')
            else:
                chunks.append(f'<div class="sense" data-level="{level_attr}"{n_attr}>')
                if sense_n:
                    chunks.append(f'<span class="sense-n">{_escape(sense_n)}.</span> ')
            children(el, True, gk)
            chunks.append("</span>" if lead else "</div>")
            plain_parts.append(_greek_text(el, parent_gk))
            tail()
            return

        if tag == "hi":
            rend = (el.get("rend") or "").lower()
            open_t, close_t = ("<b><i>", "</i></b>") if "ital" in rend else ("<b>", "</b>")
            chunks.append(open_t)
            children(el, in_sense, gk)
            chunks.append(close_t)
            tail()
            return

        if tag in ("foreign", "pron", "head"):
            flang = el.get("lang") or ""
            body = _greek_text(el, parent_gk)
            lang_attr = f' lang="{_escape(flang)}"' if flang else ""
            chunks.append(f'<span{lang_attr}>{_escape(body)}</span>')
            plain_parts.append(body)
            tail()
            return

        if tag == "ref" and lang == "grc":
            raw_beta = _text_content(el)
            shown = re.sub(r"\s+", " ", _greek_text(el, parent_gk)).strip()
            target, hom = xref_target(raw_beta) if gk else ("", "")
            if target:
                from urllib.parse import quote as _q
                href = "verba-xref:grc?l=" + _q(target, safe="") + (f"&h={hom}" if hom else "")
                hom_attr = f' data-hom="{hom}"' if hom else ""
                chunks.append(f'<a class="xref" lang="greek" href="{_escape(href)}" '
                              f'data-target="{_escape(target)}"{hom_attr}>{_escape(shown)}</a>')
            else:
                chunks.append(_escape(shown))
            plain_parts.append(shown)
            tail()
            return

        if tag == "tr":
            t = _greek_text(el, parent_gk).strip()
            chunks.append(f'<span class="tr">{_escape(t)}</span>')
            plain_parts.append(t)
            tail()
            return

        if tag == "quote":
            t = _greek_text(el, parent_gk).strip()
            if gk:
                chunks.append(f'<q lang="greek">{_escape(t)}</q>')
            else:
                chunks.append(f"<q>{_escape(t)}</q>")
            plain_parts.append(t)
            tail()
            return

        if tag == "cit":
            chunks.append('<span class="cit">')
            children(el, in_sense, gk)
            chunks.append("</span>")
            tail()
            return

        if tag == "bibl":
            t = re.sub(r"\s+", " ", _greek_text(el, parent_gk)).strip()
            chunks.append(f"<cite>{_escape(t)}</cite>")
            tail()
            return

        if tag == "author":
            t = _greek_text(el, parent_gk).strip()
            chunks.append(f'<span class="author">{_escape(t)}</span>')
            tail()
            return

        if tag in ("entryfree", "div0", "div1", "div2", "text", "body", "tei.2", "tei"):
            if el.text and el.text.strip():
                text(el.text, gk)
            for child in el:
                walk(child, in_sense, gk)
            tail()
            return

        # default: unwrap (xr, lbl, gramGrp, tns, …) — still honour lang scope
        children(el, in_sense, gk)
        tail()

    for child in entry:
        walk(child)

    chunks.append(
        '<p class="credit"><small>Text: Perseus Digital Library (CC BY-SA)' + (' — Liddell–Scott–Jones' if lang == 'grc' else '') + '; '
        "NEH funding. Imported for VerbaMac.</small></p>"
    )
    chunks.append("</article>")
    html = "".join(chunks)
    html = re.sub(r"[ \t]+\n", "\n", html)
    if lang == "grc":
        html = _attach_xref_sections(html)
    plain = re.sub(r"\s+", " ", " ".join(plain_parts)).strip()
    return html, plain


def parse_entry_element(entry: ET.Element, lang_hint: Optional[str] = None) -> Optional[Article]:
    tag = _local(entry.tag).lower()
    if tag != "entryfree":
        return None
    key = entry.get("key") or ""
    # skip non-main if marked
    etype = (entry.get("type") or "main").lower()
    if etype not in ("main", ""):
        # still import most; only skip obvious junk
        if etype in ("dummy",):
            return None

    orth = None
    for child in entry:
        if _local(child.tag).lower() == "orth":
            orth = child
            break

    # detect language
    orth_lang = (orth.get("lang") if orth is not None else None) or ""
    if lang_hint:
        lang = lang_hint
    elif orth_lang in ("la", "lat", "latin"):
        lang = "lat"
    elif orth_lang in ("greek", "grc"):
        lang = "grc"
    elif looks_greek(key) or looks_greek(_text_content(orth) if orth is not None else ""):
        lang = "grc"
    else:
        # Beta-heavy keys → greek; ASCII keys → latin
        if re.search(r"[/\\=()|*]", key) or re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_/\\=()|*]*", key or ""):
            # Heuristic: if orth lang missing and key has beta diacritics → grc
            if re.search(r"[/\\=()|]", key):
                lang = "grc"
            else:
                lang = "lat"
        else:
            lang = "lat"

    homograph = ""
    if lang == "grc" and key and not looks_greek(key):
        # LSJ: key is clean Beta Code with optional homograph digit (a)/atos1).
        m = re.match(r"^(.*?)(\d+)$", key)
        base_key = m.group(1) if m else key
        homograph = m.group(2) if m else ""
        lemma = beta_to_unicode(base_key)
    else:
        lemma = _orth_display(orth, key, lang)
    if lang == "grc":
        # lemma_norm from Unicode lemma; also accept beta key
        lemma_norm = greek_lemma_norm(lemma)
        if not lemma_norm and key:
            lemma_norm = greek_lemma_norm(beta_to_unicode(key))
        if not lemma_norm and key:
            # last resort: stripped beta ascii as greek letters via conversion
            lemma_norm = greek_lemma_norm(beta_to_unicode(beta_key_plain(key)))
    else:
        lemma_norm = latin_lemma_norm(lemma) or latin_lemma_norm(key)

    if not lemma_norm:
        return None

    html, plain = _entry_to_html(entry, lemma, lang)
    return Article(lemma=lemma, lemma_norm=lemma_norm, lang=lang, html=html, plain=plain,
                   key=key, homograph=homograph)


def iter_entries_from_file(path: str, lang_hint: Optional[str] = None) -> Iterator[Article]:
    """Stream entryFree elements from a large TEI XML file."""
    # Recover mode for entity-heavy Perseus dumps without DTD resolution
    context = ET.iterparse(path, events=("end",))
    for event, el in context:
        if _local(el.tag).lower() == "entryfree":
            art = parse_entry_element(el, lang_hint=lang_hint)
            if art:
                yield art
            el.clear()


def parse_fragment_file(path: str, lang_hint: Optional[str] = None) -> list[Article]:
    """Parse a file that is a single entryFree or a tiny TEI wrapper."""
    text = open(path, encoding="utf-8", errors="replace").read()
    text = text.strip()
    if not text.startswith("<?xml") and not text.startswith("<"):
        raise ValueError(f"Not XML: {path}")
    # strip DOCTYPE to avoid entity resolution failures
    text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.I)
    if _local_start_tag(text) == "entryfree" or text.lstrip().startswith("<entryFree"):
        wrapped = f"<root>{text}</root>"
        root = ET.fromstring(wrapped)
        out = []
        for el in root:
            art = parse_entry_element(el, lang_hint=lang_hint)
            if art:
                out.append(art)
        return out
    # full TEI — fall back to iterparse via temp rewrite without DOCTYPE
    import tempfile, os

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".xml", delete=False) as tmp:
        tmp.write(re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.I))
        tmp_path = tmp.name
    try:
        return list(iter_entries_from_file(tmp_path, lang_hint=lang_hint))
    finally:
        os.unlink(tmp_path)


def _local_start_tag(text: str) -> str:
    m = re.match(r"\s*<([A-Za-z0-9.]+)", text)
    return (m.group(1) if m else "").lower()


_XREF_A = re.compile(r'<a class="xref"([^>]*?)data-target="([^"]*)"([^>]*)>([^<]*)</a>')


def finalize_xrefs(articles: list["Article"]) -> dict[str, int]:
    """Second pass over LSJ once all headwords are known (user policy):
    - target matching no headword → plain Greek text (span, no link);
    - capital-marked target whose headwords are all lowercase → lowercase the shown text
      (Εἴδω → εἴδω); a capitalized headword (Ἥφαιστος) keeps the capital."""
    heads: dict[str, list[str]] = {}
    for a in articles:
        if a.lang == "grc":
            heads.setdefault(a.lemma_norm, []).append(a.lemma)
    stats = {"dead": 0, "lowered": 0, "kept_capital": 0, "links": 0}

    def sub(m: re.Match) -> str:
        target = html_mod.unescape(m.group(2))
        shown = m.group(4)
        lemmas = heads.get(greek_lemma_norm(target), [])
        if not lemmas:
            stats["dead"] += 1
            return f'<span class="xref-plain" lang="greek">{shown}</span>'
        stats["links"] += 1
        if target[:1].isupper():
            has_cap = any(l[:1].isupper() for l in lemmas)
            has_low = any(l[:1].islower() for l in lemmas)
            if has_low and not has_cap:
                stats["lowered"] += 1
                shown = shown[:1].lower() + shown[1:]
            else:
                stats["kept_capital"] += 1
        return f'<a class="xref"{m.group(1)}data-target="{m.group(2)}"{m.group(3)}>{shown}</a>'

    for a in articles:
        if a.lang == "grc" and 'class="xref"' in a.html:
            a.html = _XREF_A.sub(sub, a.html)
    return stats
