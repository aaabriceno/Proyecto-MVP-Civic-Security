import sys
from mdjlib import *

def build(dname, pname, classes, deps, out):
    project_id, model_id, diagram_id = nid(), nid(), nid()
    elements, views, nodes = [], [], {}
    ROW = 15
    for c in classes:
        mid, vid = nid(), nid()
        attrs, ops = [], []
        for a in c.get("attrs", []):
            n, t = a.split(":", 1) if ":" in a else (a, "")
            attrs.append({"_type": "UMLAttribute", "_id": nid(), "_parent": ref(mid), "name": n.strip(), "type": t.strip()})
        for o in c.get("ops", []):
            name, params = o.split("(", 1); params = params.rstrip(")")
            op = {"_type": "UMLOperation", "_id": nid(), "_parent": ref(mid), "name": name.strip()}
            ps = []
            for p in [x.strip() for x in params.split(",") if x.strip()]:
                ps.append({"_type": "UMLParameter", "_id": nid(), "_parent": ref(op["_id"]), "name": p, "direction": "in"})
            if ps: op["parameters"] = ps
            ops.append(op)
        elements.append({"_type": "UMLClass", "_id": mid, "_parent": ref(model_id), "name": c["name"],
                         "attributes": attrs, "operations": ops})
        left, top, w = c["x"], c["y"], c.get("w", 250)
        head = 28
        ah = ROW * len(attrs) + 6 if attrs else 8
        oh = ROW * len(ops) + 6 if ops else 8
        h = head + ah + oh
        nc = name_compartment(vid, mid, c["name"], left, top, w, head, bold=True)
        ac_id, oc_id = nid(), nid()
        aviews = [{"_type": "UMLAttributeView", "_id": nid(), "_parent": ref(ac_id), "model": ref(a["_id"]), "font": FONT,
                   "left": left + 4, "top": top + head + 3 + i * ROW, "width": w - 8, "height": ROW} for i, a in enumerate(attrs)]
        oviews = [{"_type": "UMLOperationView", "_id": nid(), "_parent": ref(oc_id), "model": ref(o["_id"]), "font": FONT,
                   "left": left + 4, "top": top + head + ah + 3 + i * ROW, "width": w - 8, "height": ROW} for i, o in enumerate(ops)]
        acv = {"_type": "UMLAttributeCompartmentView", "_id": ac_id, "_parent": ref(vid), "model": ref(mid), "subViews": aviews,
               "font": FONT, "left": left, "top": top + head, "width": w, "height": ah}
        ocv = {"_type": "UMLOperationCompartmentView", "_id": oc_id, "_parent": ref(vid), "model": ref(mid), "subViews": oviews,
               "font": FONT, "left": left, "top": top + head + ah, "width": w, "height": oh}
        rcv = {"_type": "UMLReceptionCompartmentView", "_id": nid(), "_parent": ref(vid), "model": ref(mid), "visible": False,
               "font": FONT, "left": left, "top": top + h, "width": w, "height": 10}
        tcv = {"_type": "UMLTemplateParameterCompartmentView", "_id": nid(), "_parent": ref(vid), "model": ref(mid), "visible": False,
               "font": FONT, "left": left, "top": top + h, "width": w, "height": 10}
        fill, line = {"impl": (GREEN_FILL, GREEN_LINE), "web": (AMBER_FILL, AMBER_LINE), "blue": (BLUE_FILL, BLUE_LINE),
                      "gray": (GRAY_FILL, GRAY_LINE)}[c.get("color", "impl")]
        views.append({"_type": "UMLClassView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid),
            "subViews": [nc, acv, ocv, rcv, tcv], "font": FONT, "fillColor": fill, "lineColor": line,
            "left": left, "top": top, "width": w, "height": h, "nameCompartment": ref(nc["_id"]),
            "attributeCompartment": ref(ac_id), "operationCompartment": ref(oc_id),
            "receptionCompartment": ref(rcv["_id"]), "templateParameterCompartment": ref(tcv["_id"]),
            "suppressAttributes": not attrs, "suppressOperations": False, "wordWrap": True})
        nodes[c["key"]] = node(vid, mid, left, top, w, h)
    for (a, wa, b, wb, name, mid_pts) in deps:
        did = nid()
        elements.append({"_type": "UMLDependency", "_id": did, "_parent": ref(model_id), "name": name,
                         "source": ref(nodes[a]["mid"]), "target": ref(nodes[b]["mid"])})
        views.append({"_type": "UMLDependencyView", "_id": nid(), "_parent": ref(diagram_id), "model": ref(did), "font": FONT,
            "head": ref(nodes[b]["vid"]), "tail": ref(nodes[a]["vid"]), "lineStyle": 1, "lineColor": "#374151",
            "points": seg(nodes, a, wa, b, wb, mid_pts)})
    diagram = {"_type": "UMLClassDiagram", "_id": diagram_id, "_parent": ref(model_id), "name": dname,
               "defaultDiagram": True, "ownedViews": views}
    model = {"_type": "UMLModel", "_id": model_id, "_parent": ref(project_id), "name": "Civic Security",
             "ownedElements": [diagram] + elements}
    save(out, {"_type": "Project", "_id": project_id, "name": pname, "ownedElements": [model]})

if __name__ == "__main__":
    classes = [
        dict(key="sock", name="UserSocket", x=30, y=30, color="web", ops=["connect(params, socket, connect_info)", "id(socket)"]),
        dict(key="chan", name="MapaChannel", x=330, y=30, color="web", ops=["join(topic, payload, socket)", "handle_in(evento, payload, socket)"]),
        dict(key="rl", name="RateLimit", x=630, y=30, color="blue", ops=["check(bucket, cliente)", "limits(bucket)"]),
        dict(key="ic", name="IncidentController", x=30, y=200, color="web", ops=["create(conn, params)"]),
        dict(key="mc", name="MapController", x=330, y=200, color="web", ops=["snapshot(conn, params)"]),
        dict(key="fb", name="FallbackController", x=630, y=200, color="web", ops=["call(conn, error)"]),
        dict(key="incs", name="Incidents", x=30, y=340, color="blue", ops=["create_incident(attrs, idempotency_key)", "list_recent(bbox, since)"]),
        dict(key="bbox", name="Bbox", x=330, y=340, color="blue", ops=["parse(texto)"]),
        dict(key="inc", name="Incident", x=30, y=470, w=300, attrs=["id : uuid", "tipo : enum (6 valores)", "descripcion : string", "ubicacion : Geo.Point", "estado : enum (3 valores)", "idempotency_key : uuid", "lat : float (virtual)", "lng : float (virtual)"], ops=["create_changeset(incident, attrs)", "same_content?(incident, changeset)", "coords(incident)"]),
    ]
    deps = [("ic", "B", "incs", "T", "usa", None), ("mc", "B", "incs", "T", "usa", None), ("mc", "B", "bbox", "T", "usa", None),
            ("incs", "B", "inc", "T", "crea y consulta", None), ("ic", "B", "fb", "B", "action_fallback", [(155, 300), (755, 300)]),
            ("ic", "T", "chan", "B", "broadcast", None), ("sock", "R", "chan", "L", "enruta", None), ("sock", "T", "rl", "T", "limita", [(155, 8), (755, 8)])]
    build("Clases del backend", "Civic Security - Clases del backend", classes, deps, sys.argv[1])
