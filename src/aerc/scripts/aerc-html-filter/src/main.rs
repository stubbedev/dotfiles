//! aerc text/html filter — clean up vendor-noisy HTML, then convert to Markdown.
//!
//! Replaces the BeautifulSoup-based prototype. Single binary so we avoid the
//! python interpreter startup + a separate html-to-markdown subprocess.
//!
//! Pipeline:
//!   1. Parse with html5ever (via kuchikiki).
//!   2. DOM surgery:
//!        * strip all comments (catches Outlook MSO conditionals),
//!        * drop namespaced Outlook/Word elements (o:p, v:shape, w:WordDocument …),
//!        * drop <head>/<style>/<script>/<iframe>/<img>/<colgroup>/<col>,
//!        * replace <br> with a literal newline text node,
//!        * for every <table>, decide layout-vs-data with a small heuristic
//!          (innermost first); flatten layout tables into <p> per row.
//!   3. Serialize cleaned DOM → htmd::HtmlToMarkdown::convert.
//!   4. Reflow soft-wrapped paragraphs and collapse runs of blank lines.
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
            "head" | "style" | "script" | "iframe" | "img" | "colgroup" | "col"
        )
    });
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
    let md = collapse_blank_runs(&md);

    io::stdout().write_all(md.as_bytes())?;
    Ok(())
}

// ─── DOM helpers ────────────────────────────────────────────────────────────

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
