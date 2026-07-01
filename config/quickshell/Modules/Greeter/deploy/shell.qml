//@ pragma UseQApplication
//  Punto de entrada del greeter para greetd. greetd ejecuta:
//      qs -p /etc/greetd/quickshell
//  y esto carga el módulo del login (desplegado junto a este archivo en
//  /etc/greetd/quickshell/Modules/Greeter/). Es una copia autónoma del
//  módulo que vive en ~/.config/quickshell/Modules/Greeter.
import Quickshell
import qs.Modules.Greeter

ShellRoot { Greeter {} }
