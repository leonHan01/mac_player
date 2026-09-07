// A deterministic client-API fixture. Deliberately exports no synchronous
// mpv_command/mpv_get_property, and never opens media or creates a renderer.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int id, error; uint64_t userdata; void *data; } Event;
typedef struct { int64_t entry; } Start;
typedef struct { int reason, error; int64_t entry; } End;
typedef struct { const char *name; int format; void *data; } Property;
typedef struct {
    Event event;
    union { Start start; End end; Property property; } payload;
    union { double number; int flag; } value;
    char name[64];
} Slot;

static Slot events[1024];
static int read_index, write_index, command_count, awaiting_reply;
static uint64_t command_id;
static char last_command[4][4096];
static void (*wakeup)(void *);
static void *wakeup_context;

static Slot *push(int id) {
    if (write_index >= 1024) abort();
    Slot *slot = &events[write_index++];
    memset(slot, 0, sizeof(*slot));
    slot->event.id = id;
    return slot;
}
static void notify(void) { if (wakeup) wakeup(wakeup_context); }
void *mpv_create(void) {
    read_index = write_index = command_count = awaiting_reply = 0;
    wakeup = NULL;
    return (void *)1;
}
int mpv_initialize(void *p) { return 0; }
void mpv_destroy(void *p) { wakeup = NULL; }
int mpv_set_option_string(void *p, const char *key, const char *value) { return 0; }
int mpv_observe_property(void *p, uint64_t id, const char *key, int format) { return 0; }
void mpv_set_wakeup_callback(void *p, void (*callback)(void *), void *context) {
    wakeup = callback;
    wakeup_context = context;
}
void *mpv_wait_event(void *p, double timeout) {
    static Event none;
    return read_index < write_index ? &events[read_index++].event : &none;
}
int mpv_command_async(void *p, uint64_t id, const char **args) {
    // The production queue must preserve ordering without blocking its caller.
    if (awaiting_reply) abort();
    awaiting_reply = 1;
    command_id = id;
    command_count++;
    memset(last_command, 0, sizeof(last_command));
    for (int i = 0; i < 4 && args[i]; i++)
        snprintf(last_command[i], sizeof(last_command[i]), "%s", args[i]);
    return 0;
}
int mpv_render_context_create(void *out, void *p, void *params) { abort(); }
void mpv_render_context_free(void *p) { abort(); }
void mpv_render_context_set_update_callback(void *p, void *cb, void *context) { abort(); }
int mpv_render_context_render(void *p, void *params) { abort(); }

int fake_command_count(void) { return command_count; }
int fake_awaiting_reply(void) { return awaiting_reply; }
const char *fake_argument(int i) { return last_command[i]; }
void fake_reply(int error) {
    if (!awaiting_reply) abort();
    if (error >= 0 && !strcmp(last_command[0], "screenshot-to-file")) {
        FILE *file = fopen(last_command[1], "wb");
        if (!file) abort();
        fputs("fixture", file);
        fclose(file);
    }
    awaiting_reply = 0;
    Slot *slot = push(5);
    slot->event.userdata = command_id;
    slot->event.error = error;
    notify();
}
void fake_start(int64_t entry) {
    Slot *slot = push(6);
    slot->payload.start.entry = entry;
    slot->event.data = &slot->payload.start;
    notify();
}
void fake_end(int64_t entry, int reason) {
    Slot *slot = push(7);
    slot->payload.end = (End){reason, reason == 4 ? -1 : 0, entry};
    slot->event.data = &slot->payload.end;
    notify();
}
void fake_property(const char *name, double value, int format) {
    Slot *slot = push(22);
    snprintf(slot->name, sizeof(slot->name), "%s", name);
    slot->payload.property.name = slot->name;
    slot->payload.property.format = format;
    if (format == 5) {
        slot->value.number = value;
        slot->payload.property.data = &slot->value.number;
    } else if (format == 3) {
        slot->value.flag = value != 0;
        slot->payload.property.data = &slot->value.flag;
    }
    slot->event.data = &slot->payload.property;
    notify();
}
