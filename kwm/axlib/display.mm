#include "display.h"
#include "event.h"

#define internal static
#define CGSDefaultConnection _CGSDefaultConnection()

typedef int CGSConnectionID;
extern "C" CGSConnectionID _CGSDefaultConnection(void);
extern "C" CGSSpaceType CGSSpaceGetType(CGSConnectionID CID, CGSSpaceID SID);
extern "C" CFArrayRef CGSCopyManagedDisplaySpaces(const CGSConnectionID CID);
extern "C" CGDirectDisplayID CGSMainDisplayID(void);

internal std::map<CGDirectDisplayID, ax_display> Displays;
internal unsigned int MaxDisplayCount = 5;
internal unsigned int ActiveDisplayCount = 0;

/* NOTE(koekeishiya): If the display UUID is stored, return the corresponding
                      CGDirectDisplayID. Otherwise we return 0 */
internal CGDirectDisplayID
AXLibContainsDisplay(CFStringRef DisplayIdentifier)
{
    std::map<CGDirectDisplayID, ax_display>::iterator It;
    for(It = Displays.begin(); It != Displays.end(); ++It)
    {
        CFStringRef ActiveIdentifier = It->second.Identifier;
        if(CFStringCompare(DisplayIdentifier, ActiveIdentifier, 0) == kCFCompareEqualTo)
            return It->first;
    }

    return 0;
}

/* NOTE(koekeishiya): CGDirectDisplayID of a display can change when swapping GPUs, but the
                      UUID remain the same. This function performs the CGDirectDisplayID update. */
internal inline void
AXLibChangeDisplayID(CGDirectDisplayID OldDisplayID, CGDirectDisplayID NewDisplayID)
{
    ax_display Display = Displays[OldDisplayID];
    Displays[NewDisplayID] = Display;
    Displays[NewDisplayID].ID = NewDisplayID;
    Displays.erase(OldDisplayID);
}

/* NOTE(koekeishiya): Find the UUID for a given CGDirectDisplayID. */
internal CFStringRef
AXLibGetDisplayIdentifier(CGDirectDisplayID DisplayID)
{
    CFUUIDRef DisplayUUID = CGDisplayCreateUUIDFromDisplayID(DisplayID);
    if(DisplayUUID)
    {
        CFStringRef Identifier = CFUUIDCreateString(NULL, DisplayUUID);
        CFRelease(DisplayUUID);
        return Identifier;
    }

    return NULL;
}

/* NOTE(koekeishiya): Find the UUID of the active space for a given ax_display. */
internal CFStringRef
AXLibGetActiveSpaceIdentifier(ax_display *Display)
{
    CFStringRef ActiveSpace = NULL;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            ActiveSpace = (__bridge CFStringRef) [[NSString alloc] initWithString:DisplayDictionary[@"Current Space"][@"uuid"]];
            break;
        }
    }

    CFRelease(DisplayDictionaries);
    return ActiveSpace;
}

/* NOTE(koekeishiya): Find the CGSSpaceID of the active space for a given ax_display. */
internal CGSSpaceID
AXLibGetActiveSpaceID(ax_display *Display)
{
    CGSSpaceID ActiveSpace = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            ActiveSpace = [DisplayDictionary[@"Current Space"][@"id64"] intValue];
            break;
        }
    }

    CFRelease(DisplayDictionaries);
    return ActiveSpace;
}

/* NOTE(koekeishiya): Find the active ax_space for a given ax_display. */
internal inline ax_space *
AXLibGetActiveSpace(ax_display *Display)
{
    CGSSpaceID ActiveSpace = AXLibGetActiveSpaceID(Display);
    return &Display->Spaces[ActiveSpace];
}

internal ax_space
AXLibConstructSpace(CFStringRef Identifier, CGSSpaceID SpaceID, CGSSpaceType SpaceType)
{
    ax_space Space;

    Space.Identifier = Identifier;
    Space.ID = SpaceID;
    Space.Type = SpaceType;

    return Space;
}

/* NOTE(koekeishiya): Constructs ax_space structs for every space of a given ax_display. */
internal void
AXLibConstructSpacesForDisplay(ax_display *Display)
{
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;
    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            NSDictionary *SpaceDictionaries = DisplayDictionary[@"Spaces"];
            for(NSDictionary *SpaceDictionary in (__bridge NSArray *)SpaceDictionaries)
            {
                CGSSpaceID SpaceID = [SpaceDictionary[@"id64"] intValue];
                CGSSpaceType SpaceType = [SpaceDictionary[@"type"] intValue];
                CFStringRef SpaceUUID = (__bridge CFStringRef) [[NSString alloc] initWithString:SpaceDictionary[@"uuid"]];
                Display->Spaces[SpaceID] = AXLibConstructSpace(SpaceUUID, SpaceID, SpaceType);
            }
            break;
        }
    }

    CFRelease(DisplayDictionaries);
}

/* NOTE(koekeishiya): Initializes an ax_display for a given CGDirectDisplayID. Also populates the list of spaces. */
internal ax_display
AXLibConstructDisplay(CGDirectDisplayID DisplayID, unsigned int ArrangementID)
{
    ax_display Display = {};

    Display.ID = DisplayID;
    Display.ArrangementID = ArrangementID;
    Display.Identifier = AXLibGetDisplayIdentifier(DisplayID);
    Display.Frame = CGDisplayBounds(DisplayID);
    AXLibConstructSpacesForDisplay(&Display);
    Display.Space = AXLibGetActiveSpace(&Display);

    return Display;
}

/* NOTE(koekeishiya): Updates an ax_display for a given CGDirectDisplayID. Repopulates the list of spaces. */
internal void
AXLibRefreshDisplay(ax_display *Display, CGDirectDisplayID DisplayID, unsigned int ArrangementID)
{
    Display->ArrangementID = ArrangementID;
    Display->Frame = CGDisplayBounds(DisplayID);

    std::map<CGSSpaceID, ax_space>::iterator It;
    for(It = Display->Spaces.begin(); It != Display->Spaces.end(); ++It)
        CFRelease(It->second.Identifier);

    Display->Spaces.clear();
    AXLibConstructSpacesForDisplay(Display);
    Display->Space = AXLibGetActiveSpace(Display);
}

/* NOTE(koekeishiya): Repopulate map with information about all connected displays. */
internal void
AXLibRefreshDisplays()
{
    CGDirectDisplayID *CGDirectDisplayList = (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MaxDisplayCount);
    CGGetActiveDisplayList(MaxDisplayCount, CGDirectDisplayList, &ActiveDisplayCount);

    for(std::size_t Index = 0; Index < ActiveDisplayCount; ++Index)
    {
        CGDirectDisplayID ID = CGDirectDisplayList[Index];
        if(Displays.find(ID) == Displays.end())
        {
            Displays[ID] = AXLibConstructDisplay(ID, Index);
        }
        else
        {
            AXLibRefreshDisplay(&Displays[ID], ID, Index);
        }
    }

    free(CGDirectDisplayList);
}

internal inline void
AXLibAddDisplay(CGDirectDisplayID DisplayID)
{
    CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
    CGDirectDisplayID StoredDisplayID = AXLibContainsDisplay(DisplayIdentifier);
    if(!StoredDisplayID)
    {
        /* NOTE(koekeishiya): New display detected. */
        AXLibConstructEvent(AXEvent_DisplayAdded, NULL);
    }
    else if(StoredDisplayID != DisplayID)
    {
        /* NOTE(koekeishiya): Display already exists, but the associated CGDirectDisplayID was invalidated.
                              Does this also cause the associated CGSSpaceIDs to reset and is it necessary
                              to reassign these based on the space UUIDS (?) */
        AXLibChangeDisplayID(StoredDisplayID, DisplayID);
    }
    else
    {
        /* NOTE(koekeishiya): For some reason OSX added a display with a CGDirectDisplayID that
                              is still in use by the same display we added earlier (?) */
    }

    AXLibRefreshDisplays();
    /* TODO(koekeishiya): Should probably pass an identifier for the added display. */
    AXLibConstructEvent(AXEvent_DisplayAdded, NULL);
}

internal inline void
AXLibRemoveDisplay(CGDirectDisplayID DisplayID)
{
    CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
    CGDirectDisplayID StoredDisplayID = AXLibContainsDisplay(DisplayIdentifier);
    if(StoredDisplayID)
    {
        /* NOTE(koekeishiya): If the display is asleep and not physically disconnected,
                              we want the state to persist. */
        if(!CGDisplayIsAsleep(StoredDisplayID))
        {
            /* NOTE(koekeishiya): Display has been removed. Reset state. */
            if(Displays[StoredDisplayID].Identifier)
                CFRelease(Displays[StoredDisplayID].Identifier);

            Displays.erase(StoredDisplayID);
        }
    }

    AXLibRefreshDisplays();
    /* TODO(koekeishiya): Should probably pass an identifier for the removed display. */
    AXLibConstructEvent(AXEvent_DisplayRemoved, NULL);
}

internal inline void
AXLibResizeDisplay(CGDirectDisplayID DisplayID)
{
    /* TODO(koekeishiya): How does this affect a multi-monitor setup. If the primary monitor
                          has origin (0, 0) and size (1440, 900), and a secondary monitor has origin (1440, 0)
                          and size (1920, 1080). If the primary monitor changes resolution to (1920, 1200), do
                          we also need to refresh display bounds of the secondary monitor (?) */

    /* NOTE(koekeishiya): Refresh all displays for now. */
    AXLibRefreshDisplays();
}

/* NOTE(koekeishiya): Caused by a change in monitor arrangements (?) */
internal inline void
AXLibMoveDisplay(CGDirectDisplayID DisplayID)
{
    /* NOTE(koekeishiya): Probably have to update arrangement-index as well as display bounds for all displays. */
    AXLibRefreshDisplays();
}


/* NOTE(koekeishiya): Get notified about display changes. */
void AXDisplayReconfigurationCallBack(CGDirectDisplayID DisplayID, CGDisplayChangeSummaryFlags Flags, void *UserInfo)
{
    if(Flags & kCGDisplayAddFlag)
    {
        printf("%d: Display detected\n", DisplayID);
        AXLibAddDisplay(DisplayID);
    }

    if(Flags & kCGDisplayRemoveFlag)
    {
        printf("%d: Display removed\n", DisplayID);
        AXLibRemoveDisplay(DisplayID);
    }

    if(Flags & kCGDisplayDesktopShapeChangedFlag)
    {
        printf("%d: Display resolution changed\n", DisplayID);
        AXLibResizeDisplay(DisplayID);
    }

    if(Flags & kCGDisplayMovedFlag)
    {
        printf("%d: Display moved\n", DisplayID);
        AXLibMoveDisplay(DisplayID);
    }

    if (Flags & kCGDisplaySetMainFlag)
    {
        printf("%d: Display became main\n", DisplayID);
    }

    if (Flags & kCGDisplaySetModeFlag)
    {
        printf("%d: Display changed mode\n", DisplayID);
    }

    if (Flags & kCGDisplayEnabledFlag)
    {
        printf("%d: Display enabled\n", DisplayID);
    }

    if (Flags & kCGDisplayDisabledFlag)
    {
        printf("%d: Display disabled\n", DisplayID);
    }
}

/* NOTE(koekeishiya): Populate map with information about all connected displays. */
void AXLibActiveDisplays()
{
    CGDirectDisplayID *CGDirectDisplayList = (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MaxDisplayCount);
    CGGetActiveDisplayList(MaxDisplayCount, CGDirectDisplayList, &ActiveDisplayCount);

    for(std::size_t Index = 0; Index < ActiveDisplayCount; ++Index)
    {
        CGDirectDisplayID ID = CGDirectDisplayList[Index];
        Displays[ID] = AXLibConstructDisplay(ID, Index);
    }

    free(CGDirectDisplayList);
    CGDisplayRegisterReconfigurationCallback(AXDisplayReconfigurationCallBack, NULL);

    /* NOTE(koekeishiya): Print the recorded ax_display information. */
    std::map<CGDirectDisplayID, ax_display>::iterator DisplayIt;
    std::map<CGSSpaceID, ax_space>::iterator SpaceIt;
    for(DisplayIt = Displays.begin(); DisplayIt != Displays.end(); ++DisplayIt)
    {
        ax_display *Display = &DisplayIt->second;
        printf("ActiveCGSSpaceID: %d\n", Display->Space->ID);
        for(SpaceIt = Display->Spaces.begin(); SpaceIt != Display->Spaces.end(); ++SpaceIt)
        {
            printf("CGSSpaceID: %d, CGSSpaceType: %d\n", SpaceIt->second.ID, SpaceIt->second.Type);
            CFShow(SpaceIt->second.Identifier);
        }
    }
}

/* NOTE(koekeishiya): The main display is the display which currently holds the window that accepts key-input. */
ax_display *AXLibMainDisplay()
{
    CGDirectDisplayID MainDisplay = CGSMainDisplayID();
    return &Displays[MainDisplay];
}