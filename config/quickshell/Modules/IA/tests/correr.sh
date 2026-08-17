#!/bin/sh
# Todas las baterías del harness, dos veces.
#
# Por qué dos: una caché mal aislada da falsos verdes en la segunda pasada, y
# eso ya pasó — la caché de búsqueda vivía en ~/.cache y contaminaba la tanda
# siguiente. Si las dos pasadas no dan lo mismo, hay estado compartido.
#
# No hace falta ni Quickshell ni un modelo: los .js del módulo son `.pragma
# library`, así que node los carga quitando esa línea, y los dobles de prueba en
# Python levantan el servidor falso que haga falta (buscador, web, web hostil,
# LLM, proceso colgado).
cd "$(dirname "$0")" || exit 1
BATERIAS="t_transporte t_redteam t_reloj t_websearch t_subagente t_fetch t_ssrf t_recetas t_depurador t_cerco t_podar t_guion t_puerta t_despacho t_endpoint"

for pasada in 1 2; do
    total=0; malas=0
    echo "── pasada $pasada ──"
    for t in $BATERIAS; do
        r=$(node "$t.js" 2>&1 | tail -1)
        printf '  %-16s %s\n' "$t" "$r"
        total=$((total + $(echo "$r" | grep -o '^[0-9]*')))
        malas=$((malas + $(echo "$r" | grep -oE '[0-9]+ mal' | grep -o '^[0-9]*')))
    done
    echo "  TOTAL: $total comprobaciones, $malas mal"
done
[ "$malas" -eq 0 ] || exit 1
