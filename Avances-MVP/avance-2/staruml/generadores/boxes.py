from mdjlib import *

class Diagram:
    def __init__(self, dtype, dname, pname):
        self.project_id, self.model_id, self.diagram_id = nid(), nid(), nid()
        self.dtype, self.dname, self.pname = dtype, dname, pname
        self.elements, self.views, self.nodes, self.children = [], [], {}, {}

    def box(self, kind, key, name, left, top, w, h, planned=None, container=None, header=26, fill=None, line=None):
        """kind: UMLNode | UMLComponent. planned: None neutro, True gris, False verde."""
        view_kind = {"UMLNode": "UMLNodeView", "UMLComponent": "UMLComponentView"}[kind]
        mid, vid = nid(), nid()
        self.elements.append({"_type": kind, "_id": mid, "_parent": ref(self.model_id), "name": name})
        nc = name_compartment(vid, mid, name, left, top + 2, w, header - 4, bold=bool(self.children_marker(key)))
        fill = fill or {None: "#ffffff", True: GRAY_FILL, False: GREEN_FILL}[planned]
        line = line or {None: "#374151", True: GRAY_LINE, False: GREEN_LINE}[planned]
        view = {"_type": view_kind, "_id": vid, "_parent": ref(self.diagram_id), "model": ref(mid), "subViews": [nc],
                "font": FONT, "fillColor": fill, "lineColor": line, "left": left, "top": top, "width": w, "height": h,
                "nameCompartment": ref(nc["_id"]), "suppressAttributes": True, "suppressOperations": True, "wordWrap": True}
        if container:
            view["containerView"] = ref(self.nodes[container]["vid"])
            self.children.setdefault(container, []).append(vid)
        self.views.append(view)
        self.nodes[key] = node(vid, mid, left, top, w, h)

    def children_marker(self, key): return False

    def edge(self, kind, src, dst, name, wa, wb, mid=None, planned=False, directed=True):
        eid = nid()
        if kind == "UMLDependency":
            el = {"_type": "UMLDependency", "_id": eid, "_parent": ref(self.model_id), "name": name,
                  "source": ref(self.nodes[src]["mid"]), "target": ref(self.nodes[dst]["mid"])}
            vk = "UMLDependencyView"
        else:
            e1, e2 = nid(), nid()
            el = {"_type": "UMLCommunicationPath", "_id": eid, "_parent": ref(self.model_id), "name": name,
                  "end1": {"_type": "UMLAssociationEnd", "_id": e1, "_parent": ref(eid), "reference": ref(self.nodes[src]["mid"])},
                  "end2": {"_type": "UMLAssociationEnd", "_id": e2, "_parent": ref(eid), "reference": ref(self.nodes[dst]["mid"])}}
            vk = "UMLCommunicationPathView"
        self.elements.append(el)
        self.views.append({"_type": vk, "_id": nid(), "_parent": ref(self.diagram_id), "model": ref(eid), "font": FONT,
            "head": ref(self.nodes[dst]["vid"]), "tail": ref(self.nodes[src]["vid"]), "lineStyle": 1,
            "lineColor": GRAY_LINE if planned else "#374151", "points": seg(self.nodes, src, wa, dst, wb, mid)})

    def write(self, path):
        for v in self.views:
            if v["_type"] in ("UMLNodeView", "UMLComponentView"):
                key = next(k for k, n in self.nodes.items() if n["vid"] == v["_id"])
                if key in self.children: v["containedViews"] = [ref(c) for c in self.children[key]]
        diagram = {"_type": self.dtype, "_id": self.diagram_id, "_parent": ref(self.model_id), "name": self.dname,
                   "defaultDiagram": True, "ownedViews": self.views}
        model = {"_type": "UMLModel", "_id": self.model_id, "_parent": ref(self.project_id), "name": "Civic Security",
                 "ownedElements": [diagram] + self.elements}
        save(path, {"_type": "Project", "_id": self.project_id, "name": self.pname, "ownedElements": [model]})
