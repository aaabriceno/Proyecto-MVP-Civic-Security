"""Utilidades comunes para generar proyectos StarUML (.mdj)."""
import base64, json, os

FONT = "Arial;13;0"
GREEN_FILL, GREEN_LINE = "#dcfce7", "#16a34a"
GRAY_FILL, GRAY_LINE = "#f3f4f6", "#6b7280"
BLUE_FILL, BLUE_LINE = "#dbeafe", "#2563eb"
AMBER_FILL, AMBER_LINE = "#fef3c7", "#b45309"
_used = set()

def nid():
    while True:
        s = base64.b64encode(b"\x00\x00\x00\x00" + os.urandom(10)).decode()
        if s not in _used:
            _used.add(s); return s

def ref(i): return {"$ref": i}

def label(parent, model, text, left, top, w, h, bold=False, visible=True, align=2, wrap=True):
    d = {"_type": "LabelView", "_id": nid(), "_parent": ref(parent), "model": ref(model),
         "font": "Arial;13;1" if bold else FONT, "left": left, "top": top, "width": w, "height": h,
         "horizontalAlignment": align, "verticalAlignment": 5, "wordWrap": wrap}
    if not visible: d["visible"] = False
    if text: d["text"] = text
    return d

def name_compartment(parent, model, text, left, top, w, h, bold=False):
    cid = nid()
    ls = [label(cid, model, None, left, top, w, 13, visible=False),
          label(cid, model, text, left + 4, top + max((h - 13) // 2, 0), w - 8, 13, bold=bold),
          label(cid, model, None, left, top, w, 13, visible=False),
          label(cid, model, None, left, top, w, 13, visible=False)]
    return {"_type": "UMLNameCompartmentView", "_id": cid, "_parent": ref(parent), "model": ref(model),
            "subViews": ls, "font": FONT, "left": left, "top": top, "width": w, "height": h, "wordWrap": True,
            "stereotypeLabel": ref(ls[0]["_id"]), "nameLabel": ref(ls[1]["_id"]),
            "namespaceLabel": ref(ls[2]["_id"]), "propertyLabel": ref(ls[3]["_id"])}

def rect_anchor(n, which):
    return {"L": (n["L"], n["cy"]), "R": (n["R"], n["cy"]), "T": (n["cx"], n["T"]), "B": (n["cx"], n["B"])}[which]

def seg(nodes, a, wa, b, wb, mid=None):
    p = [rect_anchor(nodes[a], wa)] + (mid or []) + [rect_anchor(nodes[b], wb)]
    return ";".join(f"{round(x)}:{round(y)}" for x, y in p)

def node(vid, mid, left, top, w, h):
    return dict(vid=vid, mid=mid, L=left, R=left + w, T=top, B=top + h, cx=left + w / 2, cy=top + h / 2, w=w, h=h)

def save(path, project):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(project, f, ensure_ascii=False, indent=1)
    print("escrito", path)
