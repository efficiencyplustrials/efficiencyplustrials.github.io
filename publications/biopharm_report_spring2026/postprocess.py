"""Post-process article.docx: center images, color select Efficiency+ mentions red."""
from zipfile import ZipFile
import lxml.etree as ET
import os

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
ns = {'w': W}
DOCX = 'article.docx'

# Only color Efficiency+ red in paragraphs containing these phrases
RED_CONTEXTS = [
    'This motivated the formation of',
    'we wanted Efficiency+ to be different',
]

with ZipFile(DOCX, 'r') as zin:
    names = zin.namelist()
    contents = {n: zin.read(n) for n in names}

doc = ET.fromstring(contents['word/document.xml'])

# --- Center image paragraphs ---
for p in doc.findall('.//w:p', ns):
    if p.findall('.//w:drawing', ns):
        ppr = p.find('w:pPr', ns)
        if ppr is None:
            ppr = ET.SubElement(p, f'{{{W}}}pPr')
            p.insert(0, ppr)
        jc = ppr.find('w:jc', ns)
        if jc is None:
            jc = ET.SubElement(ppr, f'{{{W}}}jc')
        jc.set(f'{{{W}}}val', 'center')

# --- Color select "Efficiency+" mentions red ---
def para_text(p):
    return ''.join(t.text for t in p.findall('.//w:t', ns) if t.text)

def should_color(p):
    txt = para_text(p)
    return any(ctx in txt for ctx in RED_CONTEXTS)

count = 0
for p in doc.findall('.//w:p', ns):
    if not should_color(p):
        continue
    for r in list(p.findall('.//w:r', ns)):
        t = r.find('w:t', ns)
        if t is None or t.text is None or 'Efficiency+' not in t.text:
            continue
        if t.text.strip() == 'Efficiency+':
            rpr = r.find('w:rPr', ns)
            if rpr is None:
                rpr = ET.SubElement(r, f'{{{W}}}rPr')
                r.insert(0, rpr)
            color = rpr.find('w:color', ns)
            if color is None:
                color = ET.SubElement(rpr, f'{{{W}}}color')
            color.set(f'{{{W}}}val', 'FF0000')
            count += 1
        else:
            parent = None
            for el in doc.iter():
                if r in list(el):
                    parent = el
                    break
            if parent is None:
                continue
            idx = list(parent).index(r)
            old_rpr = r.find('w:rPr', ns)
            parts = t.text.split('Efficiency+')
            parent.remove(r)
            pos = idx
            for i, part in enumerate(parts):
                if part:
                    nr = ET.Element(f'{{{W}}}r')
                    if old_rpr is not None:
                        nr.append(ET.fromstring(ET.tostring(old_rpr)))
                    nt = ET.SubElement(nr, f'{{{W}}}t')
                    nt.text = part
                    if part.startswith(' ') or part.endswith(' '):
                        nt.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
                    parent.insert(pos, nr)
                    pos += 1
                if i < len(parts) - 1:
                    rr = ET.Element(f'{{{W}}}r')
                    rrpr = ET.SubElement(rr, f'{{{W}}}rPr')
                    if old_rpr is not None:
                        for ch in old_rpr:
                            if not ch.tag.endswith('}color'):
                                rrpr.append(ET.fromstring(ET.tostring(ch)))
                    c = ET.SubElement(rrpr, f'{{{W}}}color')
                    c.set(f'{{{W}}}val', 'FF0000')
                    rt = ET.SubElement(rr, f'{{{W}}}t')
                    rt.text = 'Efficiency+'
                    parent.insert(pos, rr)
                    pos += 1
                    count += 1

contents['word/document.xml'] = ET.tostring(doc, xml_declaration=True, encoding='UTF-8', standalone=True)
os.remove(DOCX)
with ZipFile(DOCX, 'w') as zout:
    for n in names:
        zout.writestr(n, contents[n])

print(f'Centered images, colored {count} Efficiency+ instances red')
