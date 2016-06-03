#ifndef AXLIB_EVENT_H
#define AXLIB_EVENT_H

struct ax_event;

#define EVENT_CALLBACK(name) void name(ax_event *Event)
typedef EVENT_CALLBACK(EventCallback);

/* NOTE(koekeishiya): Declare ax_event_type callbacks as external functions.
 *                    These callbacks should be defined in user-code as necessary. */
extern EVENT_CALLBACK(Callback_AXEvent_WindowCreated);
extern EVENT_CALLBACK(Callback_AXEvent_WindowDestroyed);
extern EVENT_CALLBACK(Callback_AXEvent_WindowMoved);
extern EVENT_CALLBACK(Callback_AXEvent_WindowResized);
extern EVENT_CALLBACK(Callback_AXEvent_WindowMinimized);
extern EVENT_CALLBACK(Callback_AXEvent_WindowDeminimized);
extern EVENT_CALLBACK(Callback_AXEvent_KeyDown);
extern EVENT_CALLBACK(Callback_AXEvent_MouseMoved);

enum ax_event_type
{
    AXEvent_WindowCreated,
    AXEvent_WindowDestroyed,

    AXEvent_WindowMoved,
    AXEvent_WindowResized,
    AXEvent_WindowMinimized,
    AXEvent_WindowDeminimized,

    AXEvent_KeyDown,
    AXEvent_MouseMoved
};

struct ax_event
{
    ax_event_type Type;
    EventCallback *Handle;
    void *Context;
};

void AXLibAddEvent(ax_event Event);
void AXLibProcessEventQueue();

/* NOTE(koekeishiya): Construct an ax_event with the appropriate callback through macro expansion. */
#define AXLibConstructEvent(EventType, EventContext) \
    do { ax_event Event = {}; \
         Event.Type = EventType; \
         Event.Context = EventContext; \
         Event.Handle = &Callback_##EventType; \
         AXLibAddEvent(Event); \
       } while(0)

#endif
