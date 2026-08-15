---
name: "Servidores remotos y hosting"
description: "Cómo entrar por SSH a un servidor y diagnosticarlo (web caída, correo, certificados, disco, Plesk o cPanel) sin romper nada. Úsala cuando el usuario hable de un servidor, un dominio, un VPS o un panel de hosting."
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

`systemctl --failed` lista de un vistazo lo caído, y en `free -h` la
columna que importa es `available` — buff/cache es memoria prestada que el
kernel devuelve solo, no memoria «gastada».

## Web caída: el orden que ahorra tiempo

1. ¿Responde el servidor? (`server_status`)
2. ¿El servicio web está vivo? (`server_logs {unit:"nginx"}` o el que sea)
3. ¿Qué dice el log de ERROR del sitio, no el de acceso? (`path` al
   `error.log` del dominio)
4. ¿Es el certificado? Fecha de caducidad y renovación automática.
5. ¿Es el DNS o el firewall? Eso se ve desde fuera, no desde dentro.

## Averías de sistema con nombre y apellidos

**Disco lleno pero `df -h` dice que hay sitio.** Inodos agotados:
`df -i` lo confirma. El culpable típico es un directorio con cientos de
miles de archivos pequeños (sesiones PHP, colas, caché) — se encuentra
contando archivos, no mirando tamaños.

**Borré el archivo gigante y el disco sigue lleno.** Un proceso lo mantiene
abierto y el espacio no se libera hasta que muera o lo suelte.
`lsof +L1` lista los archivos borrados aún abiertos, con su proceso. La
lección para la próxima: truncar en vez de borrar (`: > archivo`) libera
el espacio al instante sin tocar el proceso.

**Para encontrar qué llena un disco:** `du -xh --max-depth=1 /` e ir
bajando nivel a nivel (la `x` evita cruzar a otros sistemas de archivos y
contar cosas dos veces).

**Un proceso muere solo cada cierto tiempo.** Antes de sospechar del
código, pregunta al kernel: `journalctl -k | grep -i "out of memory"` — el
OOM killer firma sus muertes. Y la víctima no siempre es la culpable: mata
al que más ocupa cuando OTRO agotó la memoria.

**Carga alta.** La carga mezcla CPU y espera de disco: `vmstat 1 5` las
separa (columnas us/sy contra wa). Una carga de 20 con la CPU aburrida es
un disco o un NFS ahogado, y matar procesos no lo arregla.

**Funciona a mano y falla en cron.** El entorno de cron es mínimo: sin tu
PATH, sin tus variables. Rutas absolutas en todo y salida registrada
(`>> /var/log/mi-tarea.log 2>&1`) para que el fallo deje huella.

**Fallos raros de TLS o de autenticación.** Reloj desviado: `timedatectl`.
Con unos minutos de deriva aparecen certificados «no válidos todavía» y
tokens rechazados.

**«Connection refused» desde fuera con el servicio "funcionando".**
`ss -tlnp` dice quién escucha en qué puerto y en qué dirección: un
servicio atado solo a 127.0.0.1 funciona desde dentro y no existe desde
fuera. Lo que sí escucha en todas y no llega, es firewall.

## Tocar configuración sin cortar el servicio

- Validar antes de recargar: `nginx -t`, `apachectl configtest`, `sshd -t`.
  Recargar (`reload`) casi nunca corta, reiniciar (`restart`) sí puede.
- Con sshd, regla de oro: se cambia, se valida, se recarga y se abre una
  SEGUNDA sesión de prueba SIN cerrar la actual. La sesión vieja es el
  salvavidas si el cambio salió mal.

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
funcionar siempre — el cliente está fuera. Las tres comprobaciones
externas de siempre:

```sh
curl -sSI -o /dev/null -w '%{http_code}\n' https://example.com
dig +short A example.com @1.1.1.1     # el DNS que ve el mundo, no la caché local
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -dates
```

Y el cierre simétrico: un arreglo no está terminado hasta que la
comprobación desde fuera lo confirma.

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
