//! aerc text/html filter — clean up vendor-noisy HTML, then convert to Markdown.
//!
//! Replaces the BeautifulSoup-based prototype. Single binary so we avoid the
//! python interpreter startup + a separate html-to-markdown subprocess.
//!
//! Pipeline:
//!   1. Parse with html5ever (via kuchikiki).
//!   2. DOM surgery:
//!        * normalise text nodes: drop zero-width / format chars (ZWSP, ZWJ,
//!          ZWNJ, BOM, soft-hyphen, …) and replace NBSP-class spaces with
//!          regular spaces. Marketing emails stuff hundreds of these into
//!          preview-text padding; without this, link emptiness checks miss
//!          and runs of garbage survive into the markdown.
//!        * strip all comments (catches Outlook MSO conditionals),
//!        * drop namespaced Outlook/Word elements (o:p, v:shape, w:WordDocument …),
//!        * drop <head>/<style>/<script>/<iframe>/<img>/<colgroup>/<col>
//!          plus other non-textual media (figure/picture/source/svg/canvas/
//!          video/audio/area/map/noscript) so their wrappers can collapse,
//!        * replace <br> with a literal newline text node,
//!        * for every <table>, decide layout-vs-data with a small heuristic
//!          (innermost first); flatten layout tables into <p> per row, and
//!          drop tables whose cells are all blank regardless of heuristic.
//!   3. Serialize cleaned DOM → htmd::HtmlToMarkdown::convert.
//!   4. Reflow soft-wrapped paragraphs, then post-process: drop empty
//!      markdown links, strip trailing whitespace, collapse intra-line
//!      space runs, and collapse runs of blank lines.
use std::error::Error;
use std::io::{self, Read, Write};
use std::sync::OnceLock;

use kuchikiki::traits::*;
use kuchikiki::{parse_html, NodeRef};
use regex::Regex;

fn main() -> Result<(), Box<dyn Error>> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;

    let doc = parse_html().one(input);

    strip_comments(&doc);
    // HTML5 parsing keeps Outlook/Word namespaced tags (o:p, w:WordDocument,
    // v:shape, …) as elements with a literal colon in `local`; the parser
    // doesn't populate `prefix` for non-XHTML input. Match on either.
    drop_elements(&doc, |el| {
        el.name.prefix.is_some() || el.name.local.contains(':')
    });
    drop_elements(&doc, |el| {
        matches!(
            &*el.name.local,
            "head"
                | "style"
                | "script"
                | "iframe"
                | "img"
                | "colgroup"
                | "col"
                | "figure"
                | "picture"
                | "source"
                | "svg"
                | "canvas"
                | "video"
                | "audio"
                | "area"
                | "map"
                | "noscript"
        )
    });
    // Must run before drop_empty_anchors so anchors padded with ZWSPs etc.
    // become text-empty.
    normalise_text_nodes(&doc);
    replace_brs(&doc);
    flatten_tables(&doc);
    // Marketing emails wrap a brand logo in <a href="…"><img></a>; once we
    // drop the <img>, the anchor has no visible text and htmd renders it as
    // `[](url)`. Strip those empty anchors.
    drop_empty_anchors(&doc);

    let mut html_buf = Vec::new();
    doc.serialize(&mut html_buf)?;
    let cleaned_html = String::from_utf8(html_buf)?;

    let md = htmd::HtmlToMarkdown::builder()
        .options(htmd::options::Options {
            bullet_list_marker: htmd::options::BulletListMarker::Dash,
            ul_bullet_spacing: 1,
            ol_number_spacing: 1,
            ..Default::default()
        })
        .build()
        .convert(&cleaned_html)?;
    let md = reflow_paragraphs(&md);
    let md = drop_empty_md_links(&md);
    let md = strip_empty_table_lines(&md);
    let md = trim_trailing_ws(&md);
    let md = collapse_intra_line_spaces(&md);
    let md = drop_empty_headings(&md);
    let md = normalise_heading_levels(&md);
    let md = wrap_lines(&md, wrap_width());
    let md = collapse_blank_runs(&md);
    let md = md.trim_start_matches('\n').to_string();

    io::stdout().write_all(md.as_bytes())?;
    Ok(())
}

// ─── DOM helpers ────────────────────────────────────────────────────────────

/// Replace zero-width / format chars with nothing and NBSP-class spaces with
/// a regular space inside every text node. Done in-place on the live tree so
/// later passes (drop_empty_anchors, table-cell blankness checks) see the
/// cleaned text.
fn normalise_text_nodes(root: &NodeRef) {
    let texts: Vec<NodeRef> = root
        .inclusive_descendants()
        .filter(|n| n.as_text().is_some())
        .collect();
    for t in texts {
        let txt = t.as_text().unwrap();
        let cleaned = clean_invisibles(&txt.borrow());
        *txt.borrow_mut() = cleaned;
    }
}

fn clean_invisibles(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            // Zero-width / format characters that emails use as preview-text
            // padding. Drop entirely.
            '\u{00AD}' // soft hyphen
            | '\u{034F}' // combining grapheme joiner (Klaviyo et al.)
            | '\u{061C}' // arabic letter mark
            | '\u{115F}' // hangul choseong filler
            | '\u{1160}' // hangul jungseong filler
            | '\u{17B4}' // khmer vowel inherent aq
            | '\u{17B5}' // khmer vowel inherent aa
            | '\u{180E}' // mongolian vowel separator
            | '\u{200B}' // zero-width space
            | '\u{200C}' // ZWNJ
            | '\u{200D}' // ZWJ
            | '\u{200E}' // LRM
            | '\u{200F}' // RLM
            | '\u{202A}'..='\u{202E}' // bidi formatting
            | '\u{2060}' // word joiner
            | '\u{2061}'..='\u{2064}'
            | '\u{2066}'..='\u{2069}' // bidi isolates
            | '\u{3164}' // hangul filler
            | '\u{FE00}'..='\u{FE0F}' // variation selectors
            | '\u{FEFF}' // BOM / zero-width nbsp
            | '\u{FFA0}' // halfwidth hangul filler
            | '\u{E0020}'..='\u{E007F}' // tag characters
            => {}
            // NBSP-class horizontal whitespace → plain space so post-processing
            // can collapse runs and trim() works as expected.
            '\u{00A0}'
            | '\u{2000}'..='\u{200A}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            => out.push(' '),
            _ => out.push(c),
        }
    }
    out
}

fn strip_comments(root: &NodeRef) {
    let comments: Vec<NodeRef> = root
        .inclusive_descendants()
        .filter(|n| n.as_comment().is_some())
        .collect();
    for c in comments {
        c.detach();
    }
}

fn drop_elements<F>(root: &NodeRef, predicate: F)
where
    F: Fn(&kuchikiki::ElementData) -> bool,
{
    let victims: Vec<NodeRef> = root
        .inclusive_descendants()
        .filter(|n| n.as_element().map(&predicate).unwrap_or(false))
        .collect();
    for v in victims {
        v.detach();
    }
}

fn drop_empty_anchors(root: &NodeRef) {
    let anchors: Vec<NodeRef> = root
        .inclusive_descendants()
        .filter(|n| local_name_is(n, "a"))
        .collect();
    for a in anchors {
        if subtree_text(&a).trim().is_empty() {
            a.detach();
        }
    }
}

fn subtree_text(n: &NodeRef) -> String {
    let mut buf = String::new();
    for d in n.inclusive_descendants() {
        if let Some(t) = d.as_text() {
            buf.push_str(&t.borrow());
        }
    }
    buf
}

fn replace_brs(root: &NodeRef) {
    let brs: Vec<NodeRef> = root
        .inclusive_descendants()
        .filter(|n| local_name_is(n, "br"))
        .collect();
    for br in brs {
        br.insert_before(NodeRef::new_text("\n"));
        br.detach();
    }
}

fn local_name_is(n: &NodeRef, name: &str) -> bool {
    n.as_element()
        .map(|el| &*el.name.local == name)
        .unwrap_or(false)
}

fn attr(n: &NodeRef, name: &str) -> Option<String> {
    n.as_element()
        .and_then(|el| el.attributes.borrow().get(name).map(str::to_owned))
}

fn depth(n: &NodeRef) -> usize {
    let mut d = 0;
    let mut p = n.parent();
    while let Some(parent) = p {
        d += 1;
        p = parent.parent();
    }
    d
}

// ─── Table flattening ───────────────────────────────────────────────────────

fn flatten_tables(root: &NodeRef) {
    // Collect deepest-first so an outer table's cells already contain
    // paragraph rewrites of any inner tables before we look at it.
    let mut tables: Vec<(usize, NodeRef)> = root
        .inclusive_descendants()
        .filter(|n| local_name_is(n, "table"))
        .map(|n| (depth(&n), n))
        .collect();
    tables.sort_by(|a, b| b.0.cmp(&a.0));

    for (_, table) in tables {
        if table.parent().is_none() {
            continue; // already swallowed by an outer rewrite
        }
        // A table that contains no visible text is pure scaffolding — drop
        // it regardless of the data-vs-layout heuristic. Without this, htmd
        // emits `|  |  |  |` lines for empty marketing tables.
        if subtree_text(&table).trim().is_empty() {
            table.detach();
            continue;
        }
        if is_data_table(&table) {
            continue;
        }
        flatten_one_table(&table);
    }
}

/// Heuristic: most marketing/notification HTML uses `<table>` purely for
/// column layout, so we default to "layout" and only treat tables as data
/// when there's positive evidence:
///   * has `<th>` anywhere, or
///   * has `<thead>` / `<caption>`, or
///   * uniform >=2-cell rows with a real `border` attribute.
/// Explicit `role="presentation"` / `role="none"` always wins as layout,
/// and any nested `<table>` strongly implies layout.
fn is_data_table(t: &NodeRef) -> bool {
    if let Some(role) = attr(t, "role") {
        let r = role.trim().to_ascii_lowercase();
        if r == "presentation" || r == "none" {
            return false;
        }
    }
    if descendant_named(t, "th").is_some() {
        return true;
    }
    if descendant_named(t, "thead").is_some() || descendant_named(t, "caption").is_some() {
        return true;
    }
    if has_nested_table(t) {
        return false;
    }

    let rows = collect_rows(t);
    if rows.len() < 2 {
        return false;
    }
    let counts: Vec<usize> = rows.iter().map(count_cells).collect();
    let max_c = *counts.iter().max().unwrap_or(&0);
    let min_c = *counts.iter().min().unwrap_or(&0);
    if max_c < 2 {
        return false;
    }

    let border = attr(t, "border").unwrap_or_default();
    let has_border = border
        .parse::<i32>()
        .map(|n| n > 0)
        .unwrap_or(!border.is_empty());

    min_c == max_c && has_border
}

fn descendant_named(root: &NodeRef, tag: &str) -> Option<NodeRef> {
    root.descendants().find(|n| local_name_is(n, tag))
}

fn has_nested_table(t: &NodeRef) -> bool {
    t.descendants().any(|n| local_name_is(&n, "table"))
}

fn collect_rows(t: &NodeRef) -> Vec<NodeRef> {
    t.descendants()
        .filter(|n| local_name_is(n, "tr"))
        .collect()
}

fn count_cells(tr: &NodeRef) -> usize {
    tr.children()
        .filter(|n| local_name_is(n, "td") || local_name_is(n, "th"))
        .count()
}

fn make_paragraph() -> NodeRef {
    // Parse a tiny fragment and steal the <p>. kuchikiki re-exports both
    // markup5ever 0.11 and 0.12 transitively (via html5ever and htmd's
    // html5ever 0.38), so calling NodeRef::new_element directly forces us to
    // pick a markup5ever version that matches kuchikiki's internals. Going
    // through the parser sidesteps the version juggling for ~free: cloning
    // a NodeRef is just an Rc bump, and append() auto-detaches.
    parse_html()
        .one("<p></p>")
        .descendants()
        .find(|n| local_name_is(n, "p"))
        .expect("kuchikiki always materialises the parsed <p>")
}

fn flatten_one_table(table: &NodeRef) {
    let rows = collect_rows(table);

    let mut paragraphs: Vec<NodeRef> = Vec::new();
    for tr in rows {
        let cells: Vec<NodeRef> = tr
            .children()
            .filter(|n| local_name_is(n, "td") || local_name_is(n, "th"))
            .collect();
        if cells.is_empty() {
            continue;
        }

        let p = make_paragraph();
        let mut wrote = false;
        for cell in cells {
            let kids: Vec<NodeRef> = cell.children().collect();
            if kids.iter().all(is_blank) {
                continue;
            }
            if wrote {
                p.append(NodeRef::new_text(" "));
            }
            for kid in kids {
                kid.detach();
                p.append(kid);
            }
            wrote = true;
        }
        if wrote {
            paragraphs.push(p);
        }
    }

    for p in paragraphs {
        table.insert_before(p);
    }
    table.detach();
}

fn is_blank(n: &NodeRef) -> bool {
    if let Some(t) = n.as_text() {
        return t.borrow().trim().is_empty();
    }
    n.as_comment().is_some()
}

// ─── Markdown post-processing ───────────────────────────────────────────────

fn structural_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(r"^(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|[-*_]{3,}\s*$)").unwrap()
    })
}

fn ref_link_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^\[[^\]]+\]:\s").unwrap())
}

fn blank_runs_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"\n{3,}").unwrap())
}

fn is_structural_line(line: &str) -> bool {
    let s = line.trim_start();
    structural_re().is_match(s)
        || ref_link_re().is_match(s)
        || s.starts_with('|')
        || line.starts_with("    ")
}

fn join_wrapped(lines: &[&str]) -> String {
    let mut text = String::new();
    for line in lines {
        let stripped = line.trim();
        if text.is_empty() {
            text.push_str(stripped);
        } else if text.ends_with(' ')
            || text.ends_with('-')
            || stripped
                .chars()
                .next()
                .map(|c| matches!(c, '.' | ',' | ':' | ';' | '!' | '?' | ')' | ']'))
                .unwrap_or(false)
        {
            text.push_str(stripped);
        } else {
            text.push(' ');
            text.push_str(stripped);
        }
    }
    text
}

/// Reflow soft-wrapped paragraphs back into single lines so the pager can do
/// its own wrapping. Code fences, list items, blockquotes, headings, tables,
/// reference-link definitions and indented blocks are kept verbatim.
fn reflow_paragraphs(md: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut paragraph: Vec<&str> = Vec::new();
    let mut in_fence = false;

    for line in md.split('\n') {
        let starts_fence = line.starts_with("```") || line.starts_with("~~~");
        if starts_fence {
            if !paragraph.is_empty() {
                out.push(join_wrapped(&paragraph));
                paragraph.clear();
            }
            in_fence = !in_fence;
            out.push(line.to_string());
        } else if in_fence || line.trim().is_empty() || is_structural_line(line) {
            if !paragraph.is_empty() {
                out.push(join_wrapped(&paragraph));
                paragraph.clear();
            }
            out.push(line.to_string());
        } else {
            paragraph.push(line);
        }
    }
    if !paragraph.is_empty() {
        out.push(join_wrapped(&paragraph));
    }

    let mut joined = out.join("\n");
    if md.ends_with('\n') && !joined.ends_with('\n') {
        joined.push('\n');
    }
    joined
}

fn collapse_blank_runs(md: &str) -> String {
    blank_runs_re().replace_all(md, "\n\n").into_owned()
}

fn heading_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(#{1,6})(\s)").unwrap())
}

fn empty_heading_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^#{1,6}\s*$").unwrap())
}

/// Empty `<hN>` elements (commonly leftover wrappers around stripped images)
/// serialise as bare `###`/`######` lines. Drop them so heading-level
/// normalisation isn't skewed by phantom levels.
fn drop_empty_headings(md: &str) -> String {
    md.split('\n')
        .filter(|line| !empty_heading_re().is_match(line))
        .collect::<Vec<_>>()
        .join("\n")
}

fn list_marker_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(?:[-*+]\s+|\d+\.\s+)").unwrap())
}

fn token_re() -> &'static Regex {
    // A wrap token is any whitespace-separated chunk, but markdown links
    // (`[text](url)`, `![alt](src)`) and inline code (`` `code` ``) embed
    // spaces that must not split the chunk. Tokenise as one-or-more of
    // (link | code | non-space char) so trailing punctuation like `,` after
    // a link is absorbed into the same token instead of orphaning onto its
    // own line when the link itself fills the wrap budget.
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"(?:!?\[[^\]]*\]\([^)]*\)|`[^`]*`|[^\s])+").unwrap())
}

fn wrap_width() -> usize {
    // Allow override for terminals wider/narrower than 80.
    std::env::var("AERC_FILTER_WIDTH")
        .ok()
        .and_then(|s| s.parse().ok())
        .filter(|&w: &usize| w >= 40 && w <= 240)
        .unwrap_or(80)
}

/// Email HTML routinely opens with `<h2>` (the subject is the implicit
/// `<h1>`) or skips levels (`<h1>` → `<h3>`). Renormalise so the shallowest
/// heading becomes `#` and gaps between levels collapse — the result reads
/// as a coherent outline regardless of the source's heading hygiene.
fn normalise_heading_levels(md: &str) -> String {
    let mut min_level = 7usize;
    let mut in_fence = false;
    for line in md.split('\n') {
        if line.starts_with("```") || line.starts_with("~~~") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence {
            continue;
        }
        if let Some(c) = heading_re().captures(line) {
            min_level = min_level.min(c[1].len());
        }
    }
    if min_level > 6 {
        return md.to_string();
    }
    let shift = min_level - 1;

    let mut out = String::with_capacity(md.len());
    let mut stack: Vec<(usize, usize)> = Vec::new(); // (input_level, output_level)
    let mut in_fence = false;
    for (i, line) in md.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        if line.starts_with("```") || line.starts_with("~~~") {
            in_fence = !in_fence;
            out.push_str(line);
            continue;
        }
        if in_fence {
            out.push_str(line);
            continue;
        }
        if let Some(c) = heading_re().captures(line) {
            let in_level = c[1].len() - shift;
            while let Some(&(lvl, _)) = stack.last() {
                if lvl >= in_level {
                    stack.pop();
                } else {
                    break;
                }
            }
            let out_level = stack
                .last()
                .map(|&(_, o)| (o + 1).min(6))
                .unwrap_or(1);
            stack.push((in_level, out_level));
            out.push_str(&"#".repeat(out_level));
            out.push_str(&line[c[1].len()..]);
        } else {
            out.push_str(line);
        }
    }
    out
}

/// Hard-wrap paragraphs at `width` columns on word boundaries. Markdown
/// links/images and inline code are kept intact even if a single token
/// exceeds the limit. Fenced code, indented code, headings, tables, and
/// reference-link definitions are left untouched. Blockquote and list
/// continuation lines preserve their leading prefix/indent.
fn wrap_lines(md: &str, width: usize) -> String {
    let mut out = String::with_capacity(md.len());
    let mut in_fence = false;
    for (i, line) in md.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        let starts_fence = line.starts_with("```") || line.starts_with("~~~");
        if starts_fence {
            in_fence = !in_fence;
            out.push_str(line);
            continue;
        }
        if in_fence
            || line.starts_with("    ")
            || line.starts_with('\t')
            || line.trim().is_empty()
        {
            out.push_str(line);
            continue;
        }
        let trimmed = line.trim_start();
        if trimmed.starts_with('#')
            || trimmed.starts_with('|')
            || ref_link_re().is_match(trimmed)
            || structural_re()
                .find(trimmed)
                .map(|m| m.as_str().contains(['_', '*', '-']) && trimmed.chars().all(|c| matches!(c, '-' | '*' | '_' | ' ')))
                .unwrap_or(false)
        {
            out.push_str(line);
            continue;
        }

        let leading: String = line.chars().take_while(|c| *c == ' ').collect();
        let after_indent = &line[leading.len()..];

        let mut quote_end = 0;
        for (idx, ch) in after_indent.char_indices() {
            if ch == '>' || ch == ' ' {
                quote_end = idx + ch.len_utf8();
            } else {
                break;
            }
        }
        let quote_prefix = if after_indent[..quote_end].contains('>') {
            &after_indent[..quote_end]
        } else {
            ""
        };
        let body = &after_indent[quote_prefix.len()..];

        let (list_marker, content) = if let Some(m) = list_marker_re().find(body) {
            (&body[..m.end()], &body[m.end()..])
        } else {
            ("", body)
        };
        let cont_indent = " ".repeat(list_marker.chars().count());
        let first_prefix = format!("{}{}{}", leading, quote_prefix, list_marker);
        let cont_prefix = format!("{}{}{}", leading, quote_prefix, cont_indent);

        let tokens: Vec<&str> = token_re().find_iter(content).map(|m| m.as_str()).collect();
        if tokens.is_empty() {
            out.push_str(line);
            continue;
        }

        out.push_str(&first_prefix);
        let mut col = first_prefix.chars().count();
        let mut at_line_start = true;
        for tok in tokens {
            let tlen = tok.chars().count();
            if !at_line_start && col + 1 + tlen > width {
                out.push('\n');
                out.push_str(&cont_prefix);
                col = cont_prefix.chars().count();
                at_line_start = true;
            }
            if !at_line_start {
                out.push(' ');
                col += 1;
            }
            out.push_str(tok);
            col += tlen;
            at_line_start = false;
        }
    }
    out
}

fn empty_link_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"\[ *\]\([^)]*\)").unwrap())
}

fn intra_space_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"  +").unwrap())
}

fn empty_table_line_re() -> &'static Regex {
    // Lines that are pure table scaffolding: pipes, dashes, colons, spaces.
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^[ \t|:\-]+$").unwrap())
}

/// Drop residual `[](url)` and `[ ](url)` left after image stripping. htmd
/// has already serialised them by this point so DOM-level scrubbing can
/// miss cases where the empty text only became visible after htmd's own
/// inline-element collapsing.
fn drop_empty_md_links(md: &str) -> String {
    empty_link_re().replace_all(md, "").into_owned()
}

/// Markdown lines that contain only `|`, `-`, `:`, and whitespace are
/// table scaffolding from a layout table whose cells were all blank
/// post-cleanup. Drop them.
fn strip_empty_table_lines(md: &str) -> String {
    md.split('\n')
        .filter(|line| {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                return true; // preserve real blank lines
            }
            if !trimmed.contains('|') {
                return true;
            }
            !empty_table_line_re().is_match(trimmed)
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn trim_trailing_ws(md: &str) -> String {
    md.split('\n')
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n")
}

/// Collapse runs of 2+ spaces to a single space, but leave 4-space-indented
/// code blocks and table cells (`|` separators are already handled) alone.
fn collapse_intra_line_spaces(md: &str) -> String {
    let mut out = String::with_capacity(md.len());
    let mut in_fence = false;
    for (i, line) in md.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        let starts_fence = line.starts_with("```") || line.starts_with("~~~");
        if starts_fence {
            in_fence = !in_fence;
            out.push_str(line);
            continue;
        }
        if in_fence || line.starts_with("    ") || line.starts_with('\t') {
            out.push_str(line);
            continue;
        }
        // Preserve leading indentation (list continuation, blockquote prefix)
        // by only collapsing runs after the first non-space character.
        let leading: String = line.chars().take_while(|c| *c == ' ').collect();
        let body = &line[leading.len()..];
        out.push_str(&leading);
        out.push_str(&intra_space_re().replace_all(body, " "));
    }
    out
}
