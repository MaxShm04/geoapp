"""Flächen einer Ebene (Regionen, Kreise) passgenau in ihren Umriss legen.

Länder, Regionen und Kreise stammen aus verschiedenen Quellen (Natural Earth 1:50m, 1:10m,
geoBoundaries) und passen an den Rändern nicht genau aufeinander. Hier werden sie so zugeschnitten
und vereinfacht, dass jede Ebene die nächsthöhere lückenlos abdeckt.
"""
import shapely
from shapely.strtree import STRtree

# Lücken zwischen Umriss und Flächen gehen an einen Nachbarn, wenn sie höchstens so weit entfernt
# liegen (in Grad). Weiter entfernte Teile (abgelegene Inseln ohne Region) bleiben frei.
GAP_MAX_DISTANCE_DEG = 0.2
# Breite des Saums, über den die gemeinsame Grenze einer Lücke mit ihren Nachbarn gemessen wird.
GAP_TOUCH_DEG = 1e-5


def fit_to_outline(geometries: list, outline) -> list:
    """Schneidet die Flächen auf den Umriss zu und füllt Lücken, so dass sie den Umriss lückenlos
    und ohne Überlappung abdecken. Die Flächen stammen aus anderen Quellen als der Umriss und
    passen an den Rändern nicht genau. Ohne das scheint dort die Landfläche grau durch.

    Jede Lücke geht an den Nachbarn mit der längsten gemeinsamen Grenze (Seen, Küstenstreifen,
    Ränder an Landesgrenzen), ohne Nachbarn an den nächsten innerhalb von GAP_MAX_DISTANCE_DEG.
    """
    outline = shapely.make_valid(outline)
    result = [shapely.make_valid(g).intersection(outline) for g in geometries]
    # Überlappungen entfernen: Die spätere Fläche gibt das Stück an die frühere ab.
    tree = STRtree(result)
    for i in range(len(result)):
        for j in tree.query(result[i], predicate="intersects"):
            if j < i and result[i].intersection(result[j]).area > 0:
                result[i] = result[i].difference(result[j])
    result = [_polygons_only(g) for g in result]

    gaps = outline.difference(shapely.union_all([g for g in result if not g.is_empty]))
    tree = STRtree(result)
    for gap in shapely.get_parts(_polygons_only(gaps)):
        if gap.is_empty:
            continue
        seam = gap.buffer(GAP_TOUCH_DEG)
        touching = [int(i) for i in tree.query(seam, predicate="intersects")]
        if touching:
            best = max(touching, key=lambda i: result[i].intersection(seam).area)
        else:
            nearest = tree.query_nearest(gap, max_distance=GAP_MAX_DISTANCE_DEG)
            if not len(nearest):
                continue
            best = int(nearest[0])
        result[best] = _polygons_only(shapely.union_all([result[best], gap]))
    return result


def _polygons_only(geometry):
    """Nur die Flächen einer Geometrie (Schnitte erzeugen an Berührpunkten auch Linien und Punkte)."""
    parts = [g for g in shapely.get_parts(shapely.make_valid(geometry))
             if g.geom_type in ("Polygon", "MultiPolygon") and not g.is_empty]
    return shapely.union_all(parts) if parts else shapely.Polygon()


def simplify_coverage(geometries: list, tolerance: float) -> list:
    """Vereinfacht Flächen, die sich lückenlos berühren, gemeinsam und lässt die Außenkante, wie sie
    ist, damit sie auf dem Umriss bleibt. Ist die Abdeckung nicht sauber, bleibt alles unvereinfacht."""
    try:
        simplified = shapely.coverage_simplify(geometries, tolerance, simplify_boundary=False)
    except Exception:
        print(f"    Abdeckung nicht sauber, {len(geometries)} Flächen unvereinfacht")
        return geometries
    return [s if not s.is_empty else g for g, s in zip(geometries, simplified)]
