extends RefCounted
## Coûts de construction (D-017) : rails et gares se paient, le retrait rembourse une
## part (50 % en essai). Le solde n'est jamais négatif : une pose trop chère est refusée
## en entier, avec le montant manquant. Le réseau lui-même (RailNetwork) reste gratuit et
## pur ; seul ce service touche aux pièces.

const RailNetwork = preload("res://src/rail/rail_network.gd")

var content: RefCounted
var economy: RefCounted
var network: RailNetwork


func _init(p_content: RefCounted, p_economy: RefCounted, p_network: RailNetwork) -> void:
	content = p_content
	economy = p_economy
	network = p_network


func rail_cost() -> int:
	return content.build_cost("rail_cost_milli", 0)


func station_cost() -> int:
	return content.build_cost("station_cost_milli", 0)


## Coût d'un segment : un segment qui touche un pont coûte le prix du pont.
func edge_cost(a: Vector2i, b: Vector2i) -> int:
	if network.map.bridge_cells.has(a) or network.map.bridge_cells.has(b):
		return content.build_cost("bridge_cost_milli", rail_cost())
	return rail_cost()


func _edges_cost(edges: Array[Vector4i], only_valid: bool) -> int:
	var total: int = 0
	var results: Array[int] = []
	if only_valid:
		results = network.simulate_edges(edges)
	for i: int in edges.size():
		if not only_valid or results[i] == RailNetwork.Result.OK:
			total += edge_cost(Vector2i(edges[i].x, edges[i].y), Vector2i(edges[i].z, edges[i].w))
	return total


func refund_of(cost: int) -> int:
	return cost * content.build_cost("refund_percent", 0) / 100


## Pose des segments : tout ou rien côté pièces. Renvoie le rapport de
## RailNetwork.place_edges, plus "insufficient" et "needed" (milli-pièces) si refusé.
func place_edges(edges: Array[Vector4i]) -> Dictionary:
	var cost: int = _edges_cost(edges, true)
	if cost > economy.wallet_milli:
		return {"placed": 0, "placed_edges": [] as Array[Vector4i], "refused": {}, "insufficient": true, "needed": cost}
	var report: Dictionary = network.place_edges(edges)
	economy.spend(_edges_cost(report["placed_edges"], false))
	report["insufficient"] = false
	report["needed"] = 0
	return report


## Coût que coûterait la pose de ces segments (ceux qui seraient valides).
func quote_edges(edges: Array[Vector4i]) -> int:
	return _edges_cost(edges, true)


func place_station(cell: Vector2i, orientation: int) -> int:
	var check: int = network.check_station(cell, orientation)
	if check != RailNetwork.Result.OK:
		return check
	if station_cost() > economy.wallet_milli:
		return RailNetwork.Result.INSUFFICIENT_FUNDS
	var result: int = network.place_station(cell, orientation)
	if result == RailNetwork.Result.OK:
		economy.spend(station_cost())
	return result


func remove_edge(a: Vector2i, b: Vector2i) -> bool:
	if not network.remove_edge(a, b):
		return false
	economy.refund(refund_of(edge_cost(a, b)))
	return true


func remove_edges_at(cell: Vector2i) -> int:
	var count: int = 0
	for n: Vector2i in network.graph.neighbors(cell):
		if remove_edge(cell, n):
			count += 1
	return count


func remove_station(cell: Vector2i) -> bool:
	if not network.remove_station(cell):
		return false
	economy.refund(refund_of(station_cost()))
	return true


## Annulation d'une pose : retire les segments et rembourse leur coût intégral.
## Renvoie le nombre de segments qui n'ont pas pu être retirés (sous un train).
func undo_added(edges: Array[Vector4i]) -> int:
	var blocked: int = 0
	for e: Vector4i in edges:
		if network.remove_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w)):
			economy.refund(edge_cost(Vector2i(e.x, e.y), Vector2i(e.z, e.w)))
		else:
			blocked += 1
	return blocked


## Annulation d'un retrait : rétablit les segments en rendant le remboursement reçu.
## Refusée (false) si le solde ne le permet pas.
func undo_removed(edges: Array[Vector4i]) -> bool:
	var due: int = 0
	for e: Vector4i in edges:
		due += refund_of(edge_cost(Vector2i(e.x, e.y), Vector2i(e.z, e.w)))
	if due > economy.wallet_milli:
		return false
	for e: Vector4i in edges:
		network.place_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w))
	economy.spend(due)
	return true
