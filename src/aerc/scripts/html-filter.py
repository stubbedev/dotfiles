"""Aerc text/html filter: clean up HTML, then run html-to-markdown.

Marketing/notification emails carry a lot of noise that doesn't survive
well through a generic HTML→markdown pass:

  * Outlook MSO conditional comments and other vendor HTML comments
  * Outlook/Word namespaced tags (o:p, v:shape, w:*, …)
  * <table> used purely for visual layout
  * <br> tags that html-to-markdown turns into trailing-space soft-breaks

Walk the parsed tree with BeautifulSoup and rewrite/strip those before
handing the cleaned HTML off to html-to-markdown.
"""
import re
import subprocess
import sys

from bs4 import BeautifulSoup, Comment


def _is_structural_markdown_line(line):
    stripped = line.lstrip()
    return bool(
        re.match(r"^(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|[-*_]{3,}\s*$)", stripped)
        or re.match(r"^\[[^\]]+\]:\s", stripped)
        or stripped.startswith("|")
        or line.startswith("    ")
    )


def _join_wrapped_lines(lines):
    text = ""
    for line in lines:
        stripped = line.strip()
        if not text:
            text = stripped
        elif text.endswith((" ", "-")) or stripped.startswith((".", ",", ":", ";", "!", "?", ")", "]")):
            text += stripped
        else:
            text += " " + stripped
    return text


def _reflow_markdown_paragraphs(markdown):
    output = []
    paragraph = []
    in_fence = False

    def flush_paragraph():
        if paragraph:
            output.append(_join_wrapped_lines(paragraph))
            paragraph.clear()

    for line in markdown.splitlines():
        if line.startswith("```") or line.startswith("~~~"):
            flush_paragraph()
            in_fence = not in_fence
            output.append(line)
        elif in_fence or not line.strip() or _is_structural_markdown_line(line):
            flush_paragraph()
            output.append(line)
        else:
            paragraph.append(line)

    flush_paragraph()
    return "\n".join(output) + ("\n" if markdown.endswith("\n") else "")


soup = BeautifulSoup(sys.stdin.read(), "html.parser")

# Strip every HTML comment — catches MSO conditionals like
# <!--[if mso]>…<![endif]--> (and their hidden Outlook content) along with
# tracking-pixel comments and other vendor noise.
for c in soup.find_all(string=lambda t: isinstance(t, Comment)):
    c.extract()

# Outlook/Word namespaced elements (o:p, v:shape, w:WordDocument, …).
for tag in list(soup.find_all()):
    if tag.name and ":" in tag.name:
        tag.decompose()

# <br> → real newline. Avoids html-to-markdown's two-space soft-break
# marker showing through the pager.
for br in soup.find_all("br"):
    br.replace_with("\n")

# Flatten layout tables. Reverse iteration processes innermost tables
# first so outer tables see paragraphs (not nested tables) in their cells.
for table in reversed(soup.find_all("table")):
    rows = []
    for tr in table.find_all("tr"):
        cells = []
        for cell in tr.find_all(["td", "th"]):
            inner = "".join(str(c) for c in cell.contents).strip()
            if inner:
                cells.append(inner)
        if cells:
            rows.append(" ".join(cells))
    for row_html in rows:
        frag = BeautifulSoup(f"<p>{row_html}</p>", "html.parser")
        table.insert_before(frag)
    table.decompose()

# colgroup/col are leftovers from the table layout; useless on their own.
for tag in soup.find_all(["colgroup", "col"]):
    tag.decompose()

result = subprocess.run(
    [
        "html-to-markdown",
        "--skip-images",
        "--preprocess",
        "--preset", "aggressive",
    ],
    input=str(soup),
    text=True,
    capture_output=True,
    check=True,
)

# Layout tables and stripped <br>s leave behind long runs of empty lines.
# Collapse any stretch of 3+ blank lines to a single blank line.
markdown = _reflow_markdown_paragraphs(result.stdout)
sys.stdout.write(re.sub(r"\n{3,}", "\n\n", markdown))
