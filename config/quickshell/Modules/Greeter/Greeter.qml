// Raíz del login. Una superficie por monitor; el estado vive en GreeterState,
// que no se crea hasta que se carga esto (los singletons son perezosos).
import Quickshell
import qs.Modules.Greeter

Scope {
    Variants {
        model: Quickshell.screens
        delegate: GreeterSurface {}
    }
}
