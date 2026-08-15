---
name: Secretos y tokens en el código
description: Prevenir y reaccionar ante credenciales filtradas en un repositorio: rotar la clave primero, escanear con gitleaks o trufflehog, limpiar el historial con git filter-repo y blindar el repo para que no vuelva a pasar. Úsala si se ha filtrado una clave, hay una contraseña o token en un commit, aparece un API key en el código, o hay que escanear secretos antes de publicar un repo.
---

# Secretos en el código

**Un secreto que ha tocado un repositorio se da por COMPROMETIDO.** El
orden es siempre el mismo: rotar primero, limpiar después, e investigar qué
se hizo con él. Nunca al revés: borrar el commit sin rotar deja la clave
viva y regala una falsa sensación de arreglo, que es peor que no hacer
nada porque desactiva la alarma.

## 1. Detectar

Escanear el repo Y el historial completo, porque un secreto borrado ayer
sigue en los objetos de git: quitarlo del archivo no lo quita de ningún
commit anterior, y clonar el repo se lleva todos los commits.

```bash
# Todo el historial del repo actual
gitleaks detect --source . -v

# Alternativa que además verifica si la credencial sigue viva
trufflehog git file://. --only-verified
```

Escanear es lectura: gratis, sin aprobación, y lo primero que se hace ante
la mínima sospecha. Un falso positivo se descarta en segundos, un falso
negativo por no mirar dura años.

## 2. Reaccionar a una filtración, en este orden

1. **Rotar la credencial en el proveedor.** Generar la nueva, desplegarla
   donde se usa, revocar la vieja. Hasta este momento, todo lo demás puede
   esperar: es el único paso que cierra la puerta de verdad.
2. **Revisar los logs de uso del proveedor** desde la fecha del commit que
   la expuso (no desde hoy: la clave lleva expuesta desde que se subió).
   Accesos desde IPs raras, horas raras, operaciones que nadie recuerda.
   Si hay uso sospechoso, esto acaba de convertirse en un incidente, no en
   una limpieza.
3. **Limpiar el historial solo si el repo es público o compartido.** En un
   repo privado de una persona, con la clave ya rotada, reescribir la
   historia aporta poco y molesta mucho. Cuando toca:

   ```bash
   git filter-repo --replace-text <(echo 'CLAVE_FILTRADA==>***ROTADA***')
   ```

   Avisando antes de que **reescribe la historia**: todos los clones
   quedan huérfanos y todo el mundo debe reclonar. Esto y el push forzado
   posterior van en `propose_plan`, siempre.
4. **En GitHub, los forks y las cachés no se limpian solos.** El commit
   sigue accesible por su hash en los forks y en la caché de la
   plataforma aunque el repo original ya esté limpio. Para un repo público
   hay que contactar con el soporte de la plataforma, y por eso mismo el
   paso 1 no era opcional.

## 3. Prevenir

Los secretos viajan por entorno o por gestor, nunca por el repo:

| Dónde vive el secreto | Dónde NO |
|---|---|
| Variable de entorno o llavero del sistema | Hardcodeado en el código |
| Vault o gestor de secretos del equipo | Un `secrets.txt` en el repo |
| `.env` FUERA de git, con `.env.example` dentro (mismas claves, valores vacíos) | El `.env` real subido al repo |
| Secretos enmascarados del propio CI | El YAML del pipeline |

Y la red de seguridad: gitleaks como hook de pre-commit, que atrapa el
secreto ANTES de que exista el commit, cuando quitarlo aún es gratis.

```bash
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

## Trampas con nombre y apellidos

- **La URL con la contraseña dentro** (`https://usuario:clave@host`). No
  parece un secreto, pero lo es, y acaba en logs, en historiales de shell
  y en mensajes de error que se pegan en tickets.
- **El volcado de base de datos** subido «para la demo»: dentro van
  hashes de contraseñas, tokens de sesión y datos personales. Un dump
  jamás entra en un repo.
- **«Era solo el repo interno.»** Los repos internos se vuelven públicos,
  se comparten con contratistas y se clonan a portátiles que se pierden.
  El estándar es el mismo para todos los repos, porque la visibilidad de
  hoy no predice la de mañana.

## Herramientas del harness

Escanear, leer historial y revisar diffs: lectura, sin aprobación. Rotar
credenciales en el proveedor, `git filter-repo` y el push forzado que le
sigue: en `propose_plan`, detallando quién tendrá que reclonar. Las
particularidades del sitio (qué gestor de secretos se usa, qué repos ya se
escanean en CI, dónde se rotó qué y cuándo) se guardan con `learn`.

## Verificación final

Tres comprobaciones antes de dar el caso por cerrado: la clave vieja
**revocada de verdad** (probarla y ver que falla), el escaneo del historial
limpio tras la reescritura, y el pre-commit instalado y probado con un
secreto de mentira para confirmar que lo bloquea.
