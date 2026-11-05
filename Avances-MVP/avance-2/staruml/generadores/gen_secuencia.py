import sys
from mdjlib import *

project_id, model_id = nid(), nid()

def build_interaction(title, lifelines, messages):
    """lifelines: [(key, nombre, color)]; messages: [(src, dst, texto, sort)]"""
    collab_id, inter_id, diagram_id = nid(), nid(), nid()
    participants, msgs_el, views = [], [], []
    GAP, HEAD_TOP, HEAD_H, W = 270, 30, 40, 170
    line_top = HEAD_TOP + HEAD_H
    y0, STEP = line_top + 45, 46
    line_h = STEP * (len(messages) + 1)
    L = {}
    for i, (key, name, color) in enumerate(lifelines):
        lid, vid, lp_id = nid(), nid(), nid()
        left = 30 + i * GAP
        cx = left + W // 2
        participants.append({"_type": "UMLLifeline", "_id": lid, "_parent": ref(inter_id), "name": name})
        nc = name_compartment(vid, lid, name, left, HEAD_TOP, W, HEAD_H, bold=True)
        lp = {"_type": "UMLLinePartView", "_id": lp_id, "_parent": ref(vid), "model": ref(lid), "font": FONT,
              "left": cx - 1, "top": line_top, "width": 2, "height": line_h}
        fill, line = {"impl": (GREEN_FILL, GREEN_LINE), "blue": (BLUE_FILL, BLUE_LINE), "amber": (AMBER_FILL, AMBER_LINE),
                      "user": ("#e0e7ff", "#4338ca")}[color]
        views.append({"_type": "UMLSeqLifelineView", "_id": vid, "_parent": ref(diagram_id), "model": ref(lid),
            "subViews": [nc, lp], "font": FONT, "fillColor": fill, "lineColor": line, "left": left, "top": HEAD_TOP,
            "width": W, "height": HEAD_H + line_h, "nameCompartment": ref(nc["_id"]), "linePart": ref(lp_id), "wordWrap": True})
        L[key] = dict(lid=lid, vid=vid, lp=lp_id, cx=cx)
    for n, (src, dst, text, sort) in enumerate(messages):
        mid = nid()
        y = y0 + n * STEP
        msgs_el.append({"_type": "UMLMessage", "_id": mid, "_parent": ref(inter_id), "name": text, "messageSort": sort,
                        "source": ref(L[src]["lid"]), "target": ref(L[dst]["lid"])})
        s, t = L[src]["cx"], L[dst]["cx"]
        if src == dst:
            pts = f"{s}:{y};{s+40}:{y};{s+40}:{y+18};{s}:{y+18}"
        else:
            pts = f"{s}:{y};{t}:{y}"
        views.append({"_type": "UMLSeqMessageView", "_id": nid(), "_parent": ref(diagram_id), "model": ref(mid), "font": FONT,
            "head": ref(L[dst]["lp"]), "tail": ref(L[src]["lp"]), "lineStyle": 1, "lineColor": "#374151", "points": pts})
    diagram = {"_type": "UMLSequenceDiagram", "_id": diagram_id, "_parent": ref(inter_id), "name": title, "defaultDiagram": False,
               "ownedViews": views}
    inter = {"_type": "UMLInteraction", "_id": inter_id, "_parent": ref(collab_id), "name": title,
             "participants": participants, "messages": msgs_el, "ownedElements": [diagram]}
    return {"_type": "UMLCollaboration", "_id": collab_id, "_parent": ref(model_id), "name": title, "ownedElements": [inter]}

c1 = build_interaction("Enviar un reporte anónimo",
    [("u", "Usuario", "user"), ("a", "App Flutter", "impl"), ("p", "API Phoenix", "blue"), ("d", "PostgreSQL", "impl"), ("c", "Canal mapa:arequipa", "amber")],
    [("u", "a", "toca «Enviar reporte anónimo»", "synchCall"),
     ("a", "p", "POST /v1/incidents (idempotency-key)", "synchCall"),
     ("p", "p", "validar y limitar tasa", "synchCall"),
     ("p", "d", "INSERT (clave única)", "synchCall"),
     ("d", "p", "fila guardada", "reply"),
     ("p", "c", "broadcast incidente_nuevo", "asynchSignal"),
     ("p", "a", "201 incidente", "reply"),
     ("a", "u", "muestra «Reporte enviado»", "reply")])
c2 = build_interaction("Cargar los incidentes del mapa",
    [("u", "Usuario", "user"), ("a", "App Flutter", "impl"), ("p", "API Phoenix", "blue"), ("d", "PostgreSQL", "impl")],
    [("u", "a", "mueve el mapa", "synchCall"),
     ("a", "a", "espera 500 ms sin movimiento", "synchCall"),
     ("a", "p", "GET /v1/map/snapshot?bbox=...", "synchCall"),
     ("p", "p", "validar bbox y limitar tasa", "synchCall"),
     ("p", "d", "SELECT ... ST_Intersects (índice GiST)", "synchCall"),
     ("d", "p", "filas", "reply"),
     ("p", "a", "200 incidentes (JSON)", "reply"),
     ("a", "u", "dibuja pines y lista", "reply")])
c1["ownedElements"][0]["ownedElements"][0]["defaultDiagram"] = True
which = sys.argv[2] if len(sys.argv) > 2 else "all"
items = {"all": [c1, c2], "1": [c1], "2": [c2]}[which]
if which == "2": c2["ownedElements"][0]["ownedElements"][0]["defaultDiagram"] = True
model = {"_type": "UMLModel", "_id": model_id, "_parent": ref(project_id), "name": "Civic Security", "ownedElements": items}
save(sys.argv[1], {"_type": "Project", "_id": project_id, "name": "Civic Security - Secuencia", "ownedElements": [model]})
