---
name: "Kubernetes k3s: pods, volúmenes y CrashLoopBackOff"
description: "Diagnosticar y arreglar un clúster k3s/kubernetes: un pod que se reinicia en bucle (CrashLoopBackOff), un servicio que no responde en una IP 10.43.x.x, un volumen Longhorn al que hay que llegar desde el host, un StatefulSet que no recrea su pod. Úsala cuando el usuario hable de kubernetes, k3s, kubectl, pods, un contenedor caído o longhorn."
triggers: "kubectl, crashloopbackoff, statefulset, deployment, namespace, kubelet, helm, longhorn, ingress, replicas, evicted, imagepullbackoff, pod, k3s, k8s"
---

# Kubernetes k3s: pods, volúmenes y CrashLoopBackOff

**Los pods se pueden borrar sin miedo porque el controlador los recrea; los
volúmenes de datos NO — ahí se aparta (`mv` con sufijo), nunca se borra.**

**Agrupa las LECTURAS en un solo comando.** Cada llamada remota cuesta una
tarjeta de aprobación y un veredicto del supervisor: un diagnóstico hecho a
razón de un `kubectl` por llamada son veinte tarjetas y veinte esperas
(medido: 42 tarjetas en una sesión que cabían en 8). Las lecturas
relacionadas van juntas, separadas por `;` para que un fallo no corte el
resto:

```sh
sudo k3s kubectl get pods -A --request-timeout=8s; sudo k3s kubectl get svc -A --request-timeout=8s; sudo k3s kubectl get events -n <ns> --sort-by=.lastTimestamp --request-timeout=8s | tail -20
```

Y SIEMPRE `--request-timeout=8s` en cada kubectl: sin él, contra una API
lenta el comando se come el tope de 90 s del harness y muere cortado
(pasó dos veces en esa misma sesión). Las ESCRITURAS (delete, scale,
apply) van solas, una por llamada — agrupar solo vale para mirar.

## Acceso

En un nodo k3s el usuario normal no suele tener kubeconfig: `kubectl` a secas
falla o no existe. La forma que funciona es con el binario integrado y root:

```sh
sudo k3s kubectl get pods -A
```

Si la API tarda o da timeout no asumas clúster roto: reintenta una vez y
sigue — el resultado puede haberse aplicado aunque el cliente diera timeout
(un `delete pod` con timeout puede dejar el pod en Terminating igualmente).
Comprueba el estado real antes de repetir la orden.

## CrashLoopBackOff: el método

1. Estado y dónde corre:
   `sudo k3s kubectl get pod <pod> -n <ns> -o wide`
   (la columna RESTARTS dice cuánto lleva así; 600 reinicios = días, el
   problema NO es de ahora).
2. El log del intento anterior, no solo el actual:
   `sudo k3s kubectl logs <pod> -n <ns> --previous --tail=25`
3. Lee el **último ERROR antes del shutdown**, no el primero del arranque:
   muchos procesos arrancan bien, replican estado y mueren al primer uso
   real. El error de arranque es ruido; el de la muerte es la causa.
4. Los eventos en orden temporal:
   `sudo k3s kubectl get events -n <ns> --sort-by=.lastTimestamp`

Backoff: entre reinicio y reinicio el contenedor está parado pero el
volumen sigue montado en el host — esa ventana vale para arreglar ficheros
del volumen sin carreras contra el proceso.

## Borré el pod y no vuelve

Un pod de StatefulSet/Deployment que no se recrea casi siempre es que las
réplicas están a 0 (alguien lo escaló durante una avería anterior y lo
olvidó). Compara lo que hay con lo que se aplicó por última vez:

```sh
sudo k3s kubectl get sts <sts> -n <ns> -o jsonpath="{.spec.replicas} {.metadata.annotations}"
```

Si `last-applied-configuration` dice `"replicas":1` y el spec dice 0, la
intención original era 1:

```sh
sudo k3s kubectl scale sts <sts> -n <ns> --replicas=1
```

Ojo si hay ArgoCD u otro GitOps por medio (mira las anotaciones): entonces
el valor bueno está en el repo, no en `last-applied`, y escalar a mano se
revierte solo.

## Llegar a los datos de un PVC Longhorn desde el host

Para tocar un fichero dentro de un volumen sin depender de `kubectl exec`
(la imagen puede no tener shell, o el contenedor vivir 10 segundos):

1. PVC → volumen: `sudo k3s kubectl get pvc -A` (columna VOLUME, un
   `pvc-<uuid>`).
2. ¿En qué nodo está montado? El pod manda:
   `sudo k3s kubectl get pod <pod> -n <ns> -o wide` — el volumen RWO está
   en ese nodo, no necesariamente donde estás conectado.
3. En ese nodo: `mount | grep pvc-<uuid>` → la ruta útil es la de
   `/var/lib/kubelet/pods/<uid-pod>/volumes/kubernetes.io~csi/pvc-<uuid>/mount`.
4. Verifica antes de tocar (`sudo stat -c "%n %s bytes" <fichero>`) y
   aparta en vez de borrar:
   `sudo mv <fichero> /root/<fichero>.corrupt-$(date +%F)`.

Trampa medida: la ruta lleva el **UID del pod**, que cambia cada vez que el
pod se recrea — no guardes la ruta, vuelve a sacarla con `mount | grep`.
Y si el pod está Terminating o borrado, el volumen se desmonta y el `mv`
dará "No such file or directory": espera a que el pod nuevo monte el
volumen y hazlo en la ventana de backoff.

Caso real que fija el patrón: un InfluxDB 3 llevaba días en CrashLoopBackOff
por un WAL de 0 bytes (`WAL file too small ... got 0 bytes` al arrancar y
`File exists`/`another process has written to the WAL` al morir). Apartar
ese fichero vacío del volumen y dejar que el pod se recrease lo arregló;
borrar "todo el wal" habría perdido datos buenos.

## Un servicio no responde en 10.43.x.x

`10.43.x.x` es la red de Services de k3s (`10.42.x.x` la de pods). Un
"connection refused" ahí NO se diagnostica con firewall ni con `ss` en el
host: se mira si hay endpoints detrás.

```sh
sudo k3s kubectl get svc -A | grep -i <nombre>
sudo k3s kubectl get pods -A | grep -i <nombre>
```

Service con ClusterIP pero pod caído (CrashLoopBackOff, 0/1, o ninguno) =
refused. Arregla el pod y el Service vuelve solo.

## Verificación al terminar

- El pod en `1/1 Running` y, lo importante, **RESTARTS sin subir** unos
  minutos después (un arreglo falso se ve porque el contador sigue).
- El consumidor de verdad confirmado: si otro servicio dependía del pod
  (una API, un colector), comprueba SU salida, no solo el pod — que el
  cliente funcione es el cierre, igual que en `servidor-remoto`.
- Si apartaste ficheros, di dónde quedaron y cuándo se pueden borrar.

Para el hipervisor debajo (nodos Proxmox) usa la habilidad `proxmox`; para
diagnóstico general del sistema operativo del nodo, `diagnostico-linux`.
