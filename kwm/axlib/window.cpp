#include "window.h"
#include "element.h"

#define internal static
#define local_persist static

ax_window AXLibConstructWindow(ax_application *Application, AXUIElementRef WindowRef)
{
    ax_window Window = {};

    Window.Ref = WindowRef;
    Window.Application = Application;
    Window.ID = AXLibGetWindowID(WindowRef);
    Window.Name = AXLibGetWindowTitle(WindowRef);

    Window.Position = AXLibGetWindowPosition(WindowRef);
    Window.Size = AXLibGetWindowSize(WindowRef);

    if(AXLibIsWindowMovable(WindowRef))
        AXLibAddFlags(&Window, AXWindow_Movable);

    if(AXLibIsWindowResizable(WindowRef))
        AXLibAddFlags(&Window, AXWindow_Resizable);

    AXLibGetWindowRole(WindowRef, &Window.Type.Role);
    AXLibGetWindowSubrole(WindowRef, &Window.Type.Subrole);

    return Window;
}

void AXLibDestroyWindow(ax_window *Window)
{
    if(Window->Ref)
        CFRelease(Window->Ref);

    if(Window->Type.Role)
        CFRelease(Window->Type.Role);

    if(Window->Type.Subrole)
        CFRelease(Window->Type.Subrole);

    Window->Ref = NULL;
    Window->Type.Role = NULL;
    Window->Type.Subrole = NULL;
    Window->Application = NULL;
}
