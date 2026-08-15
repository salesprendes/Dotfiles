---
name: DNS y dominios
description: Diagnosticar DNS con método: registros A/AAAA/CNAME/MX/TXT, delegación, TTL y propagación, y los fallos típicos al migrar un dominio o estrenar servidor. Úsala si se habla de un dominio que no resuelve, de DNS, de nameservers o de una migración.
---

# DNS y dominios

El DNS falla en silencio y con retraso: lo que tocas ahora se nota cuando
caduca el TTL, y lo que ves tú no es lo que ve el cliente. Por eso aquí la
regla es **preguntar siempre a dos sitios**: al servidor autoritativo (la
verdad) y a un resolutor público (lo que ve el mundo).

## Las preguntas, en orden

```sh
dig +short NS example.com            # ¿quién manda sobre la zona?
dig +short A example.com             # ¿adónde apunta?
dig +short A example.com @1.1.1.1    # ¿y según el mundo?
dig +short A example.com @ns1.elhoster.com   # ¿y según el autoritativo?
dig +short MX example.com
dig +short TXT example.com
```

Si el autoritativo dice una cosa y el resolutor otra, **no está roto: está
propagando**. `dig SOA` da el serial de la zona y `dig +noall +answer` con
el TTL dice cuánto queda de espera. No toques más mientras tanto.

Sin `dig` en el equipo, `drill` o `resolvectl query` valen igual.

## Fallos con nombre y apellidos

**«El dominio no resuelve».** Sube por la cadena: ¿responden los NS del
registro (`dig NS`)? ¿Responde ese NS si le preguntas directo? Una
delegación a nameservers que ya no existen es el clásico de dominio
migrado a medias.

**«A mí me funciona».** Cachés. El que pregunta tiene el registro viejo en
su resolutor o en su sistema. Compara `@1.1.1.1` contra `@8.8.8.8` y contra
el autoritativo antes de discutir.

**Migración de servidor.** El orden que evita el desastre: bajar el TTL a
300 días antes del cambio, migrar el contenido, cambiar el registro A,
comprobar en el autoritativo, y SOLO al final subir el TTL. Cambiar el A
con un TTL de 24 h significa un día entero de tráfico repartido entre los
dos servidores.

**CNAME donde no debe.** Un CNAME no puede convivir con otros registros en
el mismo nombre — en el ápex (example.com a secas) rompe la zona o el
correo. Ahí van A/AAAA, o el ALIAS/ANAME del proveedor si existe.

**www sí y sin www no (o al revés).** Son DOS registros. Compruébalos por
separado, siempre.

**El correo se fue con la web.** Al migrar la web, los MX se quedan donde
estaban salvo que también migres el correo. Antes de cambiar nameservers
enteros, copia la zona vieja completa: los TXT de SPF/DKIM y los subdominios
raros no se reinventan de memoria.

**«De repente nada del dominio funciona».** Antes de buscar averías finas,
lo gordo: `whois example.com` — un dominio **caducado** o en
`clientHold` explica el apagón total mejor que cualquier registro. La
fecha de expiración y el estado están ahí.

**Resuelve a medias o solo desde algunos sitios.** `dig +trace
example.com` recorre la delegación desde la raíz y enseña en qué escalón
se tuerce. Si hay varios NS y uno sirve una zona vieja (serial distinto en
`dig SOA @cada-ns`), la transferencia de zona entre primarios y
secundarios está rota: eso da fallos intermitentes que vuelven locos.

**DNSSEC.** Si `dig` normal funciona y los clientes con validación
(muchos resolutores públicos) fallan, `dig +dnssec example.com` y estado
`SERVFAIL` delatan una firma rota o un DS en el registrador que ya no casa
(típico tras migrar de proveedor sin retirar el DS). El arreglo es
actualizar o retirar el DS en el registrador, no tocar la zona a ciegas.

**PTR (DNS inverso).** `dig -x <ip>`. No afecta a la web pero sí al
correo: un servidor de correo sin PTR coherente con su HELO va a spam. El
PTR lo cambia el dueño de la IP (el proveedor del servidor), no la zona
del dominio.

## En los paneles

En Plesk y cPanel la zona se edita en el panel, no en los archivos de bind:
el panel la regenera (misma regla de siempre). Y ojo con el dominio cuyo
DNS NO está en el panel — editar ahí una zona que nadie consulta es muy
entretenido y no arregla nada. `dig NS` primero, siempre.

## Reglas

- Guarda una copia de la zona antes de tocarla (exportarla o pegarla en el
  chat de trabajo del plan).
- Cambios de NS o de MX van en `propose_plan`: se equivoca uno y el dominio
  entero desaparece o el correo rebota durante horas.
- Tras el cambio, verifica contra el autoritativo Y contra un público, y di
  cuánto TTL queda para que lo vea todo el mundo.
