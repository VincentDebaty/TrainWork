extends RefCounted
## Pièces de la compagnie, en milli-pièces entiers. Le solde n'est jamais négatif :
## une dépense supérieure au solde est refusée, jamais appliquée.

var wallet_milli: int = 0
var revenue_milli: int = 0
var deliveries: int = 0


func coins() -> float:
	return wallet_milli / 1000.0


func credit(amount_milli: int) -> void:
	if amount_milli > 0:
		wallet_milli += amount_milli
		revenue_milli += amount_milli
		deliveries += 1


## Remboursement (retrait de rails, annulation) : n'est pas un revenu d'exploitation.
func refund(amount_milli: int) -> void:
	if amount_milli > 0:
		wallet_milli += amount_milli


## Dépense `amount_milli` si le solde le permet. Renvoie false sinon (solde inchangé).
func spend(amount_milli: int) -> bool:
	if amount_milli < 0 or amount_milli > wallet_milli:
		return false
	wallet_milli -= amount_milli
	return true


func checksum() -> int:
	return (wallet_milli * 1000003) ^ (revenue_milli * 7919) ^ deliveries


func to_dict() -> Dictionary:
	return {"wallet": wallet_milli, "revenue": revenue_milli, "deliveries": deliveries}


func load_dict(data: Dictionary) -> void:
	wallet_milli = data["wallet"]
	revenue_milli = data["revenue"]
	deliveries = data["deliveries"]
