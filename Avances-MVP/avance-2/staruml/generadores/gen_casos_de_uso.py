"""Genera el diagrama de casos de uso de Civic Security como proyecto StarUML (.mdj)."""
import base64, json, math, os, sys

used = set()
def nid():
    while True:
        s = base64.b64encode(b"\x00\x00\x00\x00" + os.urandom(10)).decode()
        if s not in used:
            used.add(s); return s

FONT = "Arial;13;0"
GREEN_FILL, GREEN_LINE = "#dcfce7", "#16a34a"
GRAY_FILL, GRAY_LINE = "#f3f4f6", "#6b7280"

project_id, model_id, diagram_id, subject_id, subject_view_id = nid(), nid(), nid(), nid(), nid()
elements, views = [], []

def ref(i): return {"$ref": i}

def label(parent, model, text, left, top, w, h, bold=False, visible=True):
    d = {"_type": "LabelView", "_id": nid(), "_parent": ref(parent), "model": ref(model),
         "font": "Arial;13;1" if bold else FONT, "left": left, "top": top, "width": w, "height": h,
         "horizontalAlignment": 2, "verticalAlignment": 5, "wordWrap": True}
    if not visible: d["visible"] = False
    if text: d["text"] = text
    return d

def name_compartment(parent, model, text, left, top, w, h):
    cid = nid()
    labels = [label(cid, model, None, left, top, w, 13, visible=False),          # stereotype
              label(cid, model, text, left + 4, top + (h - 13) // 2, w - 8, 13, bold=False),  # name
              label(cid, model, None, left, top, w, 13, visible=False),          # namespace
              label(cid, model, None, left, top, w, 13, visible=False)]          # property
    return {"_type": "UMLNameCompartmentView", "_id": cid, "_parent": ref(parent), "model": ref(model),
            "subViews": labels, "font": FONT, "left": left, "top": top, "width": w, "height": h, "wordWrap": True,
            "stereotypeLabel": ref(labels[0]["_id"]), "nameLabel": ref(labels[1]["_id"]),
            "namespaceLabel": ref(labels[2]["_id"]), "propertyLabel": ref(labels[3]["_id"])}

nodes = {}   # key -> dict(view_id, model_id, cx, cy, w, h, shape)

def add_actor(key, name, left, top, w=110, h=120):
    mid, vid = nid(), nid()
    elements.append({"_type": "UMLActor", "_id": mid, "_parent": ref(model_id), "name": name})
    nc = name_compartment(vid, mid, name, left, top + h - 40, w, 40)
    views.append({"_type": "UMLActorView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid),
                  "subViews": [nc], "font": FONT, "fillColor": "#e0e7ff", "lineColor": "#4338ca",
                  "left": left, "top": top, "width": w, "height": h,
                  "suppressAttributes": True, "suppressOperations": True, "nameCompartment": ref(nc["_id"]), "wordWrap": True})
    nodes[key] = dict(vid=vid, mid=mid, cx=left + w / 2, cy=top + h / 2 - 20, w=w * 0.5, h=h - 40, shape="rect", L=left + w / 2 - 22, R=left + w / 2 + 22, T=top, B=top + h - 40)

def add_uc(key, name, left, top, planned, w=210, h=62):
    mid, vid = nid(), nid()
    elements.append({"_type": "UMLUseCase", "_id": mid, "_parent": ref(model_id), "name": name})
    nc = name_compartment(vid, mid, name, left + 14, top + 4, w - 28, h - 8)
    ep = {"_type": "UMLExtensionPointCompartmentView", "_id": nid(), "_parent": ref(vid), "model": ref(mid),
          "visible": False, "font": FONT, "left": left, "top": top + h, "width": w, "height": 10}
    views.append({"_type": "UMLUseCaseView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid),
                  "subViews": [nc, ep], "extensionPointCompartment": ref(ep["_id"]), "wordWrap": True, "autoResize": False, "suppressAttributes": True, "suppressOperations": True, "containerView": ref(subject_view_id), "font": FONT,
                  "fillColor": GRAY_FILL if planned else GREEN_FILL, "lineColor": GRAY_LINE if planned else GREEN_LINE,
                  "left": left, "top": top, "width": w, "height": h, "nameCompartment": ref(nc["_id"])})
    nodes[key] = dict(vid=vid, mid=mid, cx=left + w / 2, cy=top + h / 2, w=w, h=h, shape="ellipse", L=left, R=left + w, T=top, B=top + h)

def edge_point(n, tx, ty):
    """Punto del borde de n en dirección al punto (tx, ty)."""
    dx, dy = tx - n["cx"], ty - n["cy"]
    if dx == 0 and dy == 0: return n["cx"], n["cy"]
    if n["shape"] == "ellipse":
        a, b = n["w"] / 2, n["h"] / 2
        t = 1 / math.sqrt((dx / a) ** 2 + (dy / b) ** 2)
    else:
        t = min((n["w"] / 2) / abs(dx) if dx else 1e9, (n["h"] / 2) / abs(dy) if dy else 1e9)
    return round(n["cx"] + dx * t), round(n["cy"] + dy * t)

def points(src, dst):
    s, d = nodes[src], nodes[dst]
    x1, y1 = edge_point(s, d["cx"], d["cy"]); x2, y2 = edge_point(d, s["cx"], s["cy"])
    return f"{x1}:{y1};{x2}:{y2}"

def side(key, which):
    n = nodes[key]
    return {"L": (n["L"], n["cy"]), "R": (n["R"], n["cy"]), "T": (n["cx"], n["T"]), "B": (n["cx"], n["B"])}[which]

def seg(a, wa, b, wb):
    (x1, y1), (x2, y2) = side(a, wa), side(b, wb)
    return f"{round(x1)}:{round(y1)};{round(x2)}:{round(y2)}"

def add_assoc(a, uc, pts=None):
    mid = nid()
    e1, e2 = nid(), nid()
    elements.append({"_type": "UMLAssociation", "_id": mid, "_parent": ref(model_id),
        "end1": {"_type": "UMLAssociationEnd", "_id": e1, "_parent": ref(mid), "reference": ref(nodes[a]["mid"])},
        "end2": {"_type": "UMLAssociationEnd", "_id": e2, "_parent": ref(mid), "reference": ref(nodes[uc]["mid"])}})
    views.append({"_type": "UMLAssociationView", "_id": nid(), "_parent": ref(diagram_id), "model": ref(mid),
        "font": FONT, "head": ref(nodes[uc]["vid"]), "tail": ref(nodes[a]["vid"]),
        "lineStyle": 1, "points": pts or points(a, uc), "lineColor": "#374151"})

def add_directed(kind, view_kind, src, dst, line_color="#374151", pts=None):
    mid = nid()
    elements.append({"_type": kind, "_id": mid, "_parent": ref(model_id),
                     "source": ref(nodes[src]["mid"]), "target": ref(nodes[dst]["mid"])})
    views.append({"_type": view_kind, "_id": nid(), "_parent": ref(diagram_id), "model": ref(mid),
        "font": FONT, "head": ref(nodes[dst]["vid"]), "tail": ref(nodes[src]["vid"]),
        "lineStyle": 1, "points": pts or points(src, dst), "lineColor": line_color, "fillColor": "#ffffff"})

# ---------------- contenido ----------------
ROW = 78
def row_y(i): return 80 + i * ROW

# columna A: casos de uso del Invitado (verde = implementado, gris = planificado)
COL_A = [("uc1", "Ver mapa de incidentes cercanos", False), ("uc2", "Filtrar por tipo", False),
         ("uc3", "Consultar detalle del incidente", False), ("uc12", "Adjuntar foto con rostros difuminados (planificado)", True),
         ("uc4", "Reportar incidente anónimo", False), ("uc5", "Ajustar ubicación del reporte", False),
         ("uc6", "Llamar al 105", False), ("uc7", "Registrarse y verificar identidad con DNI (planificado)", True),
         ("uc8", "Iniciar sesión (planificado)", True), ("uc10", "Ver mapa de calor (planificado)", True)]
for i, (k, n, planned) in enumerate(COL_A):
    add_uc(k, n, 300, row_y(i), planned, w=250)
# columna B: casos de uso del Usuario verificado
add_uc("uc9", "Confirmar o marcar como falso (planificado)", 700, row_y(2), True, w=250)
add_uc("uc11", "Suscribir zona de alerta (planificado)", 700, row_y(5), True, w=250)
add_uc("uc13", "Recibir alerta push (planificado)", 700, row_y(6), True, w=250)

add_actor("inv", "Invitado (sin cuenta)", 60, row_y(4) - 40)
add_actor("ver", "Usuario verificado", 1060, row_y(3) + 10)
add_actor("fcm", "Firebase Cloud Messaging (externo)", 1060, row_y(6) - 30, w=130)

SUBJ_L, SUBJ_T, SUBJ_W, SUBJ_H = 260, 28, 740, row_y(9) + 62 + 40 - 28
elements.append({"_type": "UMLUseCaseSubject", "_id": subject_id, "_parent": ref(model_id), "name": "Sistema Civic Security (MVP)"})
nc = name_compartment(subject_view_id, subject_id, "Sistema Civic Security (MVP)", SUBJ_L, SUBJ_T, SUBJ_W, 24)
views.insert(0, {"_type": "UMLUseCaseSubjectView", "_id": subject_view_id, "_parent": ref(diagram_id), "model": ref(subject_id),
    "subViews": [nc], "font": FONT, "fillColor": "#ffffff", "lineColor": "#6b7280",
    "left": SUBJ_L, "top": SUBJ_T, "width": SUBJ_W, "height": SUBJ_H, "nameCompartment": ref(nc["_id"]),
    "containedViews": []})

for uc in ["uc1", "uc2", "uc3", "uc4", "uc6", "uc7", "uc8", "uc10"]:
    add_assoc("inv", uc, pts=seg("inv", "R", uc, "L"))
for uc in ["uc9", "uc11"]:
    add_assoc("ver", uc, pts=seg("ver", "L", uc, "R"))
add_assoc("fcm", "uc13", pts=seg("fcm", "L", "uc13", "R"))

# generalización: Verificado -> Invitado, rodeando el sistema por arriba
vx, vy = nodes["ver"]["cx"], nodes["ver"]["cy"] - nodes["ver"]["h"] / 2
ix, iy = nodes["inv"]["cx"], nodes["inv"]["cy"] - nodes["inv"]["h"] / 2
add_directed("UMLGeneralization", "UMLGeneralizationView", "ver", "inv",
             pts=f"{round(vx)}:{round(vy)};{round(vx)}:12;{round(ix)}:12;{round(ix)}:{round(iy)}")
add_directed("UMLInclude", "UMLIncludeView", "uc4", "uc5", pts=seg("uc4", "B", "uc5", "T"))
add_directed("UMLInclude", "UMLIncludeView", "uc9", "uc3", pts=seg("uc9", "L", "uc3", "R"))
add_directed("UMLInclude", "UMLIncludeView", "uc11", "uc13", pts=seg("uc11", "B", "uc13", "T"))
add_directed("UMLExtend", "UMLExtendView", "uc12", "uc4", pts=seg("uc12", "B", "uc4", "T"))
add_directed("UMLExtend", "UMLExtendView", "uc2", "uc1", pts=seg("uc2", "T", "uc1", "B"))

views[0]["containedViews"] = [ref(nodes[k]["vid"]) for k in nodes if k.startswith("uc")]

diagram = {"_type": "UMLUseCaseDiagram", "_id": diagram_id, "_parent": ref(model_id),
           "name": "Casos de uso - Civic Security", "defaultDiagram": True, "ownedViews": views}
model = {"_type": "UMLModel", "_id": model_id, "_parent": ref(project_id), "name": "Civic Security",
         "ownedElements": [diagram] + elements}
project = {"_type": "Project", "_id": project_id, "name": "Civic Security", "ownedElements": [model]}

out = sys.argv[1]
with open(out, "w", encoding="utf-8") as f:
    json.dump(project, f, ensure_ascii=False, indent=1)
print("escrito", out, "elementos:", len(elements), "vistas:", len(views))
