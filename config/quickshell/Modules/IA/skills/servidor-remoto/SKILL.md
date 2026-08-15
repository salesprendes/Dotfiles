---
name: Servidores remotos y hosting
description: Cómo entrar por SSH a un servidor y diagnosticarlo (web caída, correo, certificados, disco, Plesk o cPanel) sin romper nada. Úsala cuando el usuario hable de un servidor, un dominio, un VPS o un panel de hosting.
---

# Servidores remotos y hosting

En una máquina ajena no hay deshacer. Todo lo que sigue está pensado para
que la parte de MIRAR sea generosa y la de TOCAR sea mínima y explicada.

## Conectar

No hace falta registrar nada: `host` admite `root@1.2.3.4`, con `:puerto` si
no es el 22, o el nombre de un servidor guardado. Si el usuario te da la
contraseña en el mensaje, pásala en `password` — viaja por entorno, nunca en
la línea de comandos.

Si falta `sshpass`, el harness te lo dirá: díselo al usuario tal cual
(`pacman -S sshpass`) en vez de reintentar.

## Orden de las lecturas

1. `server_status` — carga, memoria, discos, servicios caídos, top. Empieza
   siempre aquí: distingue en un vistazo "el servidor está mal" de "el sitio
   está mal".
2. `server_logs` — el journal con `unit`/`priority`/`since`, o un archivo
   concreto con `path` (nginx, apache, exim, el panel). Filtra por `grep`:
   traerte 300 líneas para leer 3 es quemar contexto.
3. `sftp_ls` — para ver permisos y fechas de un directorio (un despliegue a
   medias se ve por las fechas).

## Web caída: el orden que ahorra tiempo

1. ¿Responde el servidor? (`server_status`)
2. ¿El servicio web está vivo? (`server_logs {unit:"nginx"}` o el que sea)
3. ¿Qué dice el log de ERROR del sitio, no el de acceso? (`path` al
   `error.log` del dominio)
4. ¿Es el certificado? Fecha de caducidad y renovación automática.
5. ¿Es el DNS o el firewall? Eso se ve desde fuera, no desde dentro.

## Paneles de hosting

`hosting_query` trae lecturas seguras y ya escritas:

- **Plesk**: `version`, `domains`, `subscriptions`, `databases`,
  `domain_info` (con `name` = el dominio).
- **cPanel/WHM**: `version`, `accounts`, `account_info` (con `name` = la
  cuenta), `domains`, `disk`.

Para lo que no cubran, `ssh_exec` con `plesk bin …` o `whmapi1 …` — pero eso
ya es un comando crudo en un servidor de producción: llévalo en un plan.

Si el servidor resulta ser un caso con habilidad propia (Plesk, cPanel,
Proxmox, o un equipo de red Cisco, Huawei, MikroTik o UniFi), pídela con
`use_skill`: ahí están los comandos exactos y las trampas de cada uno.

## Lo que se ve desde fuera, se mira desde fuera

Un «la web no va» se confirma con `fetch_url` al dominio ANTES de entrar
al servidor: el código de respuesta (o el error de conexión, o el de
certificado) ya acota el problema. Dentro del servidor todo parece
funcionar siempre — el cliente está fuera.

## Reglas que no se saltan

- **Leer todo lo que haga falta y escribir lo mínimo.** Cualquier cambio en
  un servidor va en `propose_plan` con qué vas a tocar, en qué archivo y
  cómo lo comprobarás.
- **Copia antes de tocar.** Si vas a editar una configuración remota, el
  plan incluye copiarla primero (`cp -a x x.bak-fecha`).
- **Un reinicio de servicio no es inocente**: hay usuarios conectados.
  Dilo, propón la ventana y espera aprobación.
- **Nunca pegues credenciales en el chat.** Si aparecen en un log o en un
  archivo, el harness las tapa. No las repitas tú en tu resumen.
- Si el servidor tiene una particularidad (puerto raro, sudo sin
  contraseña, panel en otra ruta), guárdala con `learn`.
