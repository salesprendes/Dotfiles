---
name: "DNS y dominios"
description: "Diagnosticar DNS con método: registros A/AAAA/CNAME/MX/TXT, delegación, TTL y propagación, y los fallos típicos al migrar un dominio o estrenar servidor. Úsala si se habla de un dominio que no resuelve, de DNS, de nameservers o de una migración."
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

Dos matices que enderezan diagnósticos: `dig` pregunta directo al DNS y se
salta `/etc/hosts` y la caché local — `getent hosts example.com` enseña lo
que las aplicaciones de ESA máquina ven de verdad. Y
`dig A example.com @1.1.1.1 +norecurse` pregunta al resolutor qué tiene en
caché sin obligarle a resolver: útil para saber si el registro viejo sigue
vivo ahí sin renovarle la estancia.

Sin `dig` en el equipo, `drill` o `resolvectl query` valen igual.

## Fallos con nombre y apellidos

**«El dominio no resuelve».** Sube por la cadena: ¿responden los NS del
registro (`dig NS`)? ¿Responde ese NS si le preguntas directo? Una
delegación a nameservers que ya no existen es el clásico de dominio
migrado a medias.

**«A mí me funciona».** Cachés. El que pregunta tiene el registro viejo en
su resolutor o en su sistema — o una entrada olvidada en `/etc/hosts`, que
`getent hosts` delata y `dig` no ve. Compara `@1.1.1.1` contra `@8.8.8.8`
y contra el autoritativo antes de discutir.

**«Acabo de crear el registro y sigue sin existir».** Caché negativa: el
resolutor guardó el NXDOMAIN de antes de crearlo, y lo retiene durante el
TTL negativo que fija el SOA. El autoritativo ya responde bien y el
resolutor insiste en que no existe. No hay arreglo, solo espera o probar
otro resolutor — la lección es crear el registro ANTES de publicar el
nombre en ninguna parte.

**Migración de servidor.** El orden que evita el desastre: bajar el TTL a
300 segundos al menos un día antes del cambio, migrar el contenido,
cambiar el registro A, comprobar en el autoritativo, y SOLO al final subir
el TTL. Cambiar el A con un TTL de 24 h significa un día entero de tráfico
repartido entre los dos servidores. Y ojo: algunos resolutores alargan los
TTL muy bajos por su cuenta — la propagación no es una ola, es cada caché
caducando a su ritmo.

**CNAME donde no debe.** Un CNAME no puede convivir con otros registros en
el mismo nombre — en el ápex (example.com a secas) rompe la zona o el
correo. Ahí van A/AAAA, o el ALIAS/ANAME del proveedor si existe.

**www sí y sin www no (o al revés).** Son DOS registros. Compruébalos por
separado, siempre.

**El correo se fue con la web.** Al migrar la web, los MX se quedan donde
estaban salvo que también migres el correo. Antes de cambiar nameservers
enteros, copia la zona vieja completa: los TXT de SPF/DKIM y los subdominios
raros no se reinventan de memoria.

**Dos SPF.** Dos registros TXT que empiecen por `v=spf1` en el mismo
nombre son un error permanente de SPF y el correo sale perjudicado: solo
puede haber UNO, fusionando los mecanismos en él. Y SPF admite 10
búsquedas DNS como máximo — cada `include:` cuenta, y pasarse también es
fallo.

**«De repente nada del dominio funciona».** Antes de buscar averías finas,
lo gordo: `whois example.com` — un dominio **caducado** o en
`clientHold` explica el apagón total mejor que cualquier registro. La
fecha de expiración y el estado están ahí.

**Resuelve a medias o solo desde algunos sitios.** `dig +trace
example.com` recorre la delegación desde la raíz y enseña en qué escalón
se tuerce. Si hay varios NS y uno sirve una zona vieja (serial distinto en
`dig SOA @cada-ns`), la transferencia de zona entre primario y
secundarios está rota: eso da fallos intermitentes que vuelven locos. El
arreglo habitual es subir el serial del SOA en el primario y recargar —
una zona editada a mano sin subir el serial no se transfiere jamás. Y una
advertencia sobre `+trace`: no usa tu resolutor, pregunta directo a raíz,
TLD y autoritativos, así que en una red que solo permite DNS hacia el
resolutor interno falla aunque todo esté sano — no es señal de avería.

**Glue records.** Si los nameservers viven dentro del propio dominio
(`ns1.example.com` para `example.com`), el TLD necesita sus IP pegadas a
la delegación (el glue), y eso se edita en el REGISTRADOR, no en la zona.
Cambiar la IP del nameserver solo en la zona funciona unos días — hasta
que las cachés caducan y el dominio entero se apaga sin que nadie haya
tocado nada esa semana. `dig +trace example.com` enseña qué IP entrega el
TLD para los NS.

**CAA y certificados.** «No me emiten el certificado y el DNS está bien»:
`dig +short CAA example.com`. Un CAA que no autoriza a la CA elegida
(p. ej. `letsencrypt.org`) bloquea la emisión en silencio. Y si el nombre
no tiene CAA propio, la CA sube por el árbol hasta el ápex — el CAA del
padre manda sobre todos los subdominios que no declaren el suyo.

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

## Verificar desde fuera

Tras cualquier cambio, el mismo trío de siempre: el autoritativo (la
verdad), dos públicos (`@1.1.1.1` y `@8.8.8.8`) y el TTL que queda en la
respuesta. Cuando los tres coinciden, el cambio está hecho — lo que falte
es caché ajena y tiene fecha de caducidad conocida.

## Reglas

- Guarda una copia de la zona antes de tocarla (exportarla o pegarla en el
  chat de trabajo del plan).
- Cambios de NS o de MX van en `propose_plan`: se equivoca uno y el dominio
  entero desaparece o el correo rebota durante horas.
- Tras el cambio, verifica contra el autoritativo Y contra un público, y di
  cuánto TTL queda para que lo vea todo el mundo.
- Las particularidades del dominio (dónde vive su DNS, glue, DS activo)
  se apuntan con `learn`: son lo primero que hace falta la próxima vez.
