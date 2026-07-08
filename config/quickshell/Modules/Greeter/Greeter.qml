// Raíz del login. Una superficie por monitor; el estado vive en el singleton
// GreeterState, que solo se instancia al cargar esto (los singletons de
// Quickshell son perezosos).
import Quickshell
import qs.Modules.Greeter

Scope {
    Variants {
        model: Quickshell.screens
        delegate: GreeterSurface {}
    }
}
