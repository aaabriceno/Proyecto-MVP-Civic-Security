import sys
from mdjlib import *

project_id, model_id, diagram_id = nid(), nid(), nid()
entities, views, rels = [], [], []
nodes = {}
ROWH, HEAD = 15, 28

def add_entity(key, name, cols, left, top, planned, w=300):
    eid, vid = nid(), nid()
    colelems, colviews = [], []
    comp_id = nid()
    y = top + HEAD
    for c in cols:
        cid = nid()
        colelems.append({"_type": "ERDColumn", "_id": cid, "_parent": ref(eid), "name": c["name"], "type": c["type"],
            **({"length": c["len"]} if c.get("len") else {}), "primaryKey": c.get("pk", False),
            "foreignKey": c.get("fk", False), "nullable": c.get("null", False), "unique": c.get("uq", False)})
        c["_id"] = cid
        colviews.append({"_type": "ERDColumnView", "_id": nid(), "_parent": ref(comp_id), "model": ref(cid),
                         "font": FONT, "left": left, "top": y, "width": w, "height": ROWH})
        y += ROWH
    h = HEAD + ROWH * len(cols) + 2
    entities.append({"_type": "ERDEntity", "_id": eid, "_parent": ref(model_id), "name": name, "columns": colelems})
    name_lbl = label(vid, eid, name, left, top, w, HEAD - 6, bold=True)
    comp = {"_type": "ERDColumnCompartmentView", "_id": comp_id, "_parent": ref(vid), "model": ref(eid),
            "subViews": colviews, "font": FONT, "left": left, "top": top + HEAD, "width": w, "height": h - HEAD}
    views.append({"_type": "ERDEntityView", "_id": vid, "_parent": ref(diagram_id), "model": ref(eid),
        "subViews": [name_lbl, comp], "font": FONT, "fillColor": GRAY_FILL if planned else GREEN_FILL,
        "lineColor": GRAY_LINE if planned else GREEN_LINE, "left": left, "top": top, "width": w, "height": h,
        "nameLabel": ref(name_lbl["_id"]), "columnCompartment": ref(comp_id)})
    nodes[key] = dict(node(vid, eid, left, top, w, h), cols={c["name"]: c for c in cols}, eid=eid)

def add_rel(name, parent, child, fkcol, pts_from="B", pts_to="T", mid=None, card_child="0..*"):
    rid = nid(); e1, e2 = nid(), nid()
    p, c = nodes[parent], nodes[child]
    rels.append({"_type": "ERDRelationship", "_id": rid, "_parent": ref(model_id), "name": name, "identifying": False,
        "end1": {"_type": "ERDRelationshipEnd", "_id": e1, "_parent": ref(rid), "reference": ref(p["eid"]), "cardinality": "1"},
        "end2": {"_type": "ERDRelationshipEnd", "_id": e2, "_parent": ref(rid), "reference": ref(c["eid"]), "cardinality": card_child}})
    # la columna FK apunta a la PK del padre
    for el in entities:
        if el["_id"] == c["eid"]:
            for col in el["columns"]:
                if col["name"] == fkcol:
                    col["referenceTo"] = ref(p["cols"]["id"]["_id"])
    views.append({"_type": "ERDRelationshipView", "_id": nid(), "_parent": ref(diagram_id), "model": ref(rid),
        "font": FONT, "head": ref(c["vid"]), "tail": ref(p["vid"]), "lineStyle": 1, "lineColor": "#374151",
        "points": seg(nodes, parent, pts_from, child, pts_to, mid)})

U = lambda n, t, **k: dict(name=n, type=t, **k)
add_entity("inc", "incidentes (implementada)", [
    U("id", "UUID", pk=True), U("tipo", "VARCHAR", len="255"), U("descripcion", "VARCHAR", len="500", null=True),
    U("ubicacion", "geography(Point,4326)"), U("estado", "VARCHAR", len="255"),
    U("idempotency_key", "UUID", uq=True), U("inserted_at", "TIMESTAMP"), U("updated_at", "TIMESTAMP")], 40, 330, False)
add_entity("conf", "confirmaciones (planificada)", [
    U("id", "UUID", pk=True), U("incidente_id", "UUID", fk=True), U("valor", "VARCHAR"), U("voter_token", "BINARY"),
    U("inserted_at", "TIMESTAMP")], 440, 330, True)
add_entity("evi", "evidencias (planificada)", [
    U("id", "UUID", pk=True), U("incidente_id", "UUID", fk=True), U("objeto_key", "TEXT"), U("estado", "VARCHAR")], 440, 490, True)
add_entity("usr", "usuarios (planificada)", [
    U("id", "UUID", pk=True), U("alias", "VARCHAR", uq=True), U("password_hash", "TEXT"), U("nivel", "VARCHAR"),
    U("verif_hash", "BINARY", uq=True, null=True), U("reputacion", "INTEGER"), U("inserted_at", "TIMESTAMP")], 40, 40, True)
add_entity("zona", "zonas_alerta (planificada)", [
    U("id", "UUID", pk=True), U("usuario_id", "UUID", fk=True), U("nombre", "VARCHAR"), U("radio_m", "SMALLINT"),
    U("celdas", "TEXT"), U("centro_cifrado", "BINARY")], 440, 40, True)
add_entity("disp", "dispositivos (planificada)", [
    U("id", "UUID", pk=True), U("usuario_id", "UUID", fk=True), U("fcm_token_cifrado", "BINARY"), U("plataforma", "VARCHAR")], 440, 190, True)

add_rel("tiene", "inc", "conf", "incidente_id", "R", "L")
add_rel("adjunta", "inc", "evi", "incidente_id", "R", "L", mid=[(390, 480), (390, 640)][:0])
add_rel("define", "usr", "zona", "usuario_id", "R", "L")
add_rel("usa", "usr", "disp", "usuario_id", "R", "L")

diagram = {"_type": "ERDDiagram", "_id": diagram_id, "_parent": ref(model_id), "name": "Modelo físico - Civic Security",
           "defaultDiagram": True, "ownedViews": views}
model = {"_type": "ERDDataModel", "_id": model_id, "_parent": ref(project_id), "name": "Base de datos Civic Security",
         "ownedElements": [diagram] + entities + rels}
save(sys.argv[1], {"_type": "Project", "_id": project_id, "name": "Civic Security - Base de datos", "ownedElements": [model]})
