const fs=require("fs"),vm=require("vm"),cp=require("child_process");
const { execFileSync, spawn } = cp;
const D="/home/salesprendes/.config/quickshell/Modules/IA/";
function load(f,names){let s=fs.readFileSync(D+f,"utf8").replace(/^\.pragma.*$/mg,"");
  const c={};vm.createContext(c);vm.runInContext(s+"\n;__x={"+names.map(n=>n+":typeof "+n+"!==\"undefined\"?"+n+":null").join(",")+"};",c);return c.__x;}
const TU=load("TextUtils.js",["urlZone","urlLeakScan"]);
const LT=load("tools/LocalTools.js",["files"]);
let ok=0,ko=0;
function t(d,a,b){const p=JSON.stringify(a)===JSON.stringify(b);p?ok++:ko++;if(!p)console.log("FALLO:",d,"→",JSON.stringify(a),"≠",JSON.stringify(b));}
// zona vacía = internet
for(const u of ["https://quickshell.org/docs","http://8.8.8.8/","https://172.15.0.1/",
                "https://100.63.0.1/","https://example.com","https://192.169.1.1/",
                "https://11.0.0.1/","https://[2606:4700::1111]/","https://[2001:4860:4860::8888]:443/","https://sub.dominio.es:8443/x"])
  t("internet "+u, TU.urlZone(u), "");
// zona no vacía = red interna
for(const u of ["http://localhost:8000/v1","http://127.0.0.1/","http://127.1.2.3/",
                "http://[::1]:9/","http://192.168.1.1/admin","http://10.0.0.5/",
                "http://172.16.0.1/","http://172.31.255.1/","http://169.254.169.254/latest/meta-data/",
                "http://100.64.0.1/","http://[fc00::1]/","http://[fe80::1]/","http://[fd00::5]:8080/","http://fe80::1/",
                "http://router/","http://nas.local/","http://panel.internal/",
                "http://user:pw@127.0.0.1/x","HTTP://LOCALHOST/x"])
  { if(TU.urlZone(u)==="") {ko++;console.log("FALLO: debía ser interna",u);} else ok++; }
// urlLeakScan sigue viendo las fugas y ahora también la zona
t("fuga clave", TU.urlLeakScan("https://x.es/?token=abcdefghijkl").length>0, true);
t("interna avisa", TU.urlLeakScan("http://192.168.1.1/").length>0, true);
t("normal calla", TU.urlLeakScan("https://quickshell.org/"), "");

// ── EL RESOLUTOR, que es quien decide de verdad ─────────────────────────────
// El análisis de la URL en JavaScript es la primera capa y sirve para pintar la
// tarjeta. Quien de verdad impide la conexión es el resolutor: mira TODAS las
// direcciones del nombre antes de que salga ni un paquete, y fija la elegida
// con --resolve para que no quede ventana entre comprobar y conectar.
const _b = LT.files("fetch_url", { url: "http://x/" }, { home: process.env.HOME });
const RESOLUTOR = _b.env.QS_RES;
function zona(ip, lan) {
    const u = ip.indexOf(":") !== -1 ? "http://[" + ip + "]/" : "http://" + ip + "/";
    const r = cp.execFileSync("python3", ["-c", RESOLUTOR],
        { env: Object.assign({}, process.env, { QS_HOP: u, QS_LAN: lan || "" }),
          encoding: "utf8" });
    return r.slice(0, 2) === "ko" ? "INTERNA" : "FUERA";
}
for (const ip of ["127.0.0.1","127.5.5.5","::1","10.1.2.3","192.168.0.7","169.254.169.254",
                  "172.16.0.1","172.20.3.4","172.31.9.9","100.64.1.1","100.99.1.1",
                  "100.110.1.1","100.127.1.1","fc00::1","fd12::9","fe80::1",
                  "::ffff:127.0.0.1","::ffff:192.168.1.1","0.0.0.0","224.0.0.1"])
    t("el resolutor niega " + ip, zona(ip), "INTERNA");
for (const ip of ["8.8.8.8","1.1.1.1","172.15.0.1","172.32.0.1","100.63.0.1","100.128.0.1",
                  "192.169.0.1","11.0.0.1","2606:4700::1111","::ffff:8.8.8.8"])
    t("y deja pasar " + ip, zona(ip), "FUERA");
// Con aprobación explícita la puerta se abre, que para eso existe.
t("con QS_LAN=1 sí pasa la local", zona("127.0.0.1", "1"), "FUERA");

// ── IPv4 mapeada dentro de IPv6 ─────────────────────────────────────────────
// ::ffff:127.0.0.1 ES 127.0.0.1: el sistema la enruta igual. Sin desnudarla, el
// rodeo más barato para saltarse toda la comprobación era escribir la misma
// dirección de otra forma.
for (const u of ["http://[::ffff:127.0.0.1]/", "http://[::ffff:192.168.1.1]/admin",
                 "http://[::ffff:10.0.0.1]/", "http://[::ffff:169.254.169.254]/",
                 "http://[::ffff:172.16.0.1]/"])
  { if (TU.urlZone(u) === "") { ko++; console.log("FALLO: mapeada no detectada", u) } else ok++ }
// y una pública mapeada NO debe bloquearse
t("mapeada pública pasa", TU.urlZone("http://[::ffff:8.8.8.8]/"), "");
for (const ip of ["::ffff:127.0.0.1","::ffff:192.168.1.1","::ffff:10.0.0.1",
                  "::ffff:169.254.169.254","::ffff:172.16.0.1"])
  t("shell mapeada " + ip, zona(ip), "INTERNA");
t("shell mapeada pública", zona("::ffff:8.8.8.8"), "FUERA");

// ── QUE LA PETICIÓN NO LLEGUE A SALIR ───────────────────────────────────────
// Todo lo de arriba comprueba lo que se DEVUELVE. Esto comprueba lo que no se
// hace: una máquina de casa no debe recibir ni la petición. Para eso no vale
// mirar la respuesta —hay que preguntarle al otro lado—, así que el soplón
// escribe un testigo en cuanto alguien le habla, y su AUSENCIA es la prueba.
//
// La forma del ataque es la del salto de en medio: internet → casa → internet.
// Con la comprobación puesta solo en la última IP, el salto intermedio se hacía
// (que es la acción: /admin/reboot no necesita que le lean la respuesta) y el
// final era público, así que el filtro decía que todo bien.
{
    const os = require("os"), path = require("path");
    const PUERTO_S = 8947;
    const testigo = path.join(os.tmpdir(), "t_ssrf_testigo_" + process.pid);
    try { fs.unlinkSync(testigo) } catch (e) {}
    const soplon = spawn("python3", [__dirname + "/soplon.py", String(PUERTO_S), testigo],
                         { stdio: "ignore" });
    const espera = Date.now() + 1500;
    while (Date.now() < espera) { try { execFileSync("sh", ["-c", "sleep 0.1"]) } catch (e) {} 
        if (fs.existsSync("/proc/" + soplon.pid)) break }
    try {
        execFileSync("sh", ["-c", "sleep 0.7"]);
        // localtest.me es un nombre PÚBLICO que resuelve a 127.0.0.1: es
        // exactamente el caso que el análisis de la URL no puede ver.
        const b = LT.files("fetch_url", { url: "http://localtest.me:" + PUERTO_S + "/admin/reboot" },
                           { home: process.env.HOME });
        b.env.QS_LAN = "";     // sin aprobación: es lo que se está probando
        let salida = "";
        try {
            salida = execFileSync(b.cmd[0], b.cmd.slice(1),
                { env: Object.assign({}, process.env, b.env), encoding: "utf8", timeout: 30000 });
        } catch (e) { salida = "EXCEPCION " + e.message }
        t("se niega y lo explica", /red local o la propia máquina/.test(salida), true);
        t("y NO llegó a pedirle nada al servicio interno", fs.existsSync(testigo), false);
        // Y con aprobación explícita sí se le habla: la puerta existe, pero se
        // abre a mano.
        const b2 = LT.files("fetch_url", { url: "http://localtest.me:" + PUERTO_S + "/admin/reboot" },
                            { home: process.env.HOME });
        b2.env.QS_LAN = "1";
        try {
            execFileSync(b2.cmd[0], b2.cmd.slice(1),
                { env: Object.assign({}, process.env, b2.env), encoding: "utf8", timeout: 30000 });
        } catch (e) {}
        t("con aprobación sí se le pide", fs.existsSync(testigo), true);
    } finally { soplon.kill() }
}

console.log(`\n${ok} bien, ${ko} mal`);
process.exit(ko?1:0);
