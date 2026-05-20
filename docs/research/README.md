# Research documentation

## Paper

**Title:** *Scaling Health Organisation Websites for Public-Health Emergencies: A Production-Stack Optimisation Case Study of the Africa CDC Web Platform*

**Author:** Agaba Andrew — Software Engineer, Division of Digital Health and Information Systems, Africa Centres for Disease Control and Prevention (Africa CDC)

| Format | File |
|--------|------|
| Source (Markdown) | [Scaling-Health-Organisation-Websites.md](Scaling-Health-Organisation-Websites.md) |
| PDF | Generate locally (see below) |

## Export to PDF

### Option 1 — Pandoc (recommended)

```bash
# macOS
brew install pandoc basictex

# Ubuntu
sudo apt install pandoc texlive-latex-base

cd docs/research
pandoc Scaling-Health-Organisation-Websites.md \
  -o Scaling-Health-Organisation-Websites.pdf \
  --pdf-engine=pdflatex \
  -V geometry:margin=1in \
  -V fontsize=11pt \
  -V documentclass=article
```

### Option 2 — VS Code / Cursor

Install extension “Markdown PDF”, open the `.md` file, export PDF.

### Option 3 — Word / Google Docs

Paste from Markdown or import `.md`, apply heading styles, export PDF.

### Option 4 — Browser print

Open the `.md` in a Markdown previewer with print CSS, **Print → Save as PDF**.

## Length

The source document is structured as a **journal-style article** (abstract, numbered sections, references, appendices) and exceeds **five pages** when rendered at 11pt with standard margins.
