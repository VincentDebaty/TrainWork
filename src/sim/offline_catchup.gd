extends RefCounted
## Rattrapage de la simulation pendant l'absence du joueur. Composant isolé : le GDD exige
## à terme un calcul simplifié sur 24 h réelles (débits moyens, sans positions de trains).
## Pour le prototype : rejouer pas à pas, plafonné à `offline_cap_sec` de `content.json`
## (10 minutes en essai), car 24 h = environ 430 000 pas, trop lent sur téléphone.
## Remplacer `catch_up` par un modèle simplifié ne touchera ni la sauvegarde ni les trains.

## Renvoie {"requested_sec", "simulated_sec", "capped", "ticks"}.
func catch_up(sim: RefCounted, elapsed_sec: float) -> Dictionary:
	var cap: float = float(sim.content.logistic("offline_cap_sec", 600))
	var allowed: float = clampf(elapsed_sec, 0.0, cap)
	var ticks: int = floori(allowed / sim.clock.step_sec)
	sim.advance_ticks(ticks)
	return {"requested_sec": elapsed_sec, "simulated_sec": ticks * sim.clock.step_sec, "capped": elapsed_sec > cap, "ticks": ticks}
