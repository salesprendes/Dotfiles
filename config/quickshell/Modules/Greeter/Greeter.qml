//  ╔══════════════════════════════════════════════════════════╗
//  ║   Greeter — raíz del login. Una superficie por monitor.    ║
//  ║   Todo el estado vive en el singleton GreeterState (que se ║
//  ║   instancia solo al cargar este componente, no con la barra║
//  ║   normal: los singletons de Quickshell son perezosos).     ║
//  ╚══════════════════════════════════════════════════════════╝
import Quickshell
import qs.Modules.Greeter

Scope {
    Variants {
        model: Quickshell.screens
        delegate: GreeterSurface {}
    }
}
