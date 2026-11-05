import sys
from mdjlib import *

project_id, model_id, sm_id, region_id, diagram_id = nid(), nid(), nid(), nid(), nid()
vertices, transitions, views = [], [], []
nodes = {}

def hidden_comp(t, parent, model, left, top, w):
    return {"_type": t, "_id": nid(), "_parent": ref(parent), "model": ref(model), "visible": False,
            "font": FONT, "left": left, "top": top, "width": w, "height": 10}

def add_state(key, name, left, top, w, h, planned):
    mid, vid = nid(), nid()
    vertices.append({"_type": "UMLState", "_id": mid, "_parent": ref(region_id), "name": name})
    nc = name_compartment(vid, mid, name, left, top, w, 24, bold=True)
    subs = [nc, hidden_comp("UMLInternalActivityCompartmentView", vid, mid, left, top + 24, w),
            hidden_comp("UMLInternalTransitionCompartmentView", vid, mid, left, top + 34, w),
            hidden_comp("UMLDecompositionCompartmentView", vid, mid, left, top + 44, w)]
    views.append({"_type": "UMLStateView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid), "subViews": subs,
        "font": FONT, "fillColor": GRAY_FILL if planned else GREEN_FILL, "lineColor": GRAY_LINE if planned else GREEN_LINE,
        "left": left, "top": top, "width": w, "height": h, "nameCompartment": ref(nc["_id"]),
        "internalActivityCompartment": ref(subs[1]["_id"]), "internalTransitionCompartment": ref(subs[2]["_id"]),
        "decompositionCompartment": ref(subs[3]["_id"])})
    nodes[key] = node(vid, mid, left, top, w, h)

def add_pseudo(key, left, top):
    mid, vid = nid(), nid()
    vertices.append({"_type": "UMLPseudostate", "_id": mid, "_parent": ref(region_id), "name": "Inicio", "kind": "initial"})
    views.append({"_type": "UMLPseudostateView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid), "font": FONT,
                  "left": left, "top": top, "width": 20, "height": 20})
    nodes[key] = node(vid, mid, left, top, 20, 20)

def add_final(key, left, top):
    mid, vid = nid(), nid()
    vertices.append({"_type": "UMLFinalState", "_id": mid, "_parent": ref(region_id), "name": "Fin"})
    views.append({"_type": "UMLFinalStateView", "_id": vid, "_parent": ref(diagram_id), "model": ref(mid), "font": FONT,
                  "left": left, "top": top, "width": 24, "height": 24})
    nodes[key] = node(vid, mid, left, top, 24, 24)

def add_tr(src, dst, text, wa, wb, mid=None, planned=False):
    tid = nid()
    transitions.append({"_type": "UMLTransition", "_id": tid, "_parent": ref(region_id), "name": text,
                        "source": ref(nodes[src]["mid"]), "target": ref(nodes[dst]["mid"])})
    views.append({"_type": "UMLTransitionView", "_id": nid(), "_parent": ref(diagram_id), "model": ref(tid), "font": FONT,
        "head": ref(nodes[dst]["vid"]), "tail": ref(nodes[src]["vid"]), "lineStyle": 1,
        "lineColor": GRAY_LINE if planned else "#374151", "points": seg(nodes, src, wa, dst, wb, mid)})

add_pseudo("ini", 30, 180)
add_state("sv", "Sin verificar (estado inicial)", 270, 150, 190, 70, False)
add_state("v", "Verificado", 780, 30, 160, 60, True)
add_state("d", "Descartado", 780, 300, 160, 60, True)
add_final("fin", 1150, 180)

add_tr("ini", "sv", "POST /v1/incidents", "R", "L")
add_tr("sv", "v", "3 confirmaciones de cuentas verificadas a menos de 1 km (planificado)", "R", "L", planned=True)
add_tr("sv", "d", "3 votos «Es falso» antes de verificarse (planificado)", "R", "L", planned=True)
add_tr("v", "fin", "a los 5 años se elimina el detalle", "R", "T", planned=True)
add_tr("d", "fin", "a los 5 años se elimina el detalle", "R", "B", planned=True)

region = {"_type": "UMLRegion", "_id": region_id, "_parent": ref(sm_id), "name": "Region1", "vertices": vertices, "transitions": transitions}
diagram = {"_type": "UMLStatechartDiagram", "_id": diagram_id, "_parent": ref(sm_id), "name": "Estados del incidente",
           "defaultDiagram": True, "ownedViews": views}
sm = {"_type": "UMLStateMachine", "_id": sm_id, "_parent": ref(model_id), "name": "Ciclo de vida de un incidente",
      "regions": [region], "ownedElements": [diagram]}
model = {"_type": "UMLModel", "_id": model_id, "_parent": ref(project_id), "name": "Civic Security", "ownedElements": [sm]}
save(sys.argv[1], {"_type": "Project", "_id": project_id, "name": "Civic Security - Estados", "ownedElements": [model]})
