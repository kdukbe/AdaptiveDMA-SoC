#include "xil_mmu.h"
#include "xil_types.h"

#include "shared.h"

#define SECTION_BYTES  (1024U * 1024U)
#define LOAD_WORDS     (LOAD_BUFFER_BYTES / sizeof(u32))
#define CHUNK_WORDS    16384U
#define STOP_POLL_NOPS 10000U

static void map_uncached(u32 base, u32 bytes)
{
    u32 offset;

    for (offset = 0U; offset < bytes; offset += SECTION_BYTES)
        Xil_SetTlbAttributes((INTPTR)(base + offset), NORM_NONCACHE);
}

static void idle_delay(void)
{
    u32 i;

    for (i = 0U; i < STOP_POLL_NOPS; i++)
        __asm__ volatile ("nop");
}

int main(void)
{
    volatile load_ctrl_t *ctrl;
    volatile u32 *buffer;
    u32 checksum;
    u32 index;
    u32 end;
    u32 value;
    u32 i;

    map_uncached(LOAD_BUFFER_BASE, LOAD_BUFFER_BYTES);
    Xil_SetTlbAttributes((INTPTR)LOAD_CTRL_BASE, NORM_NONCACHE);

    ctrl = (volatile load_ctrl_t *)(INTPTR)LOAD_CTRL_BASE;
    buffer = (volatile u32 *)(INTPTR)LOAD_BUFFER_BASE;

    for (i = 0U; i < LOAD_WORDS; i++)
        buffer[i] = i ^ 0xA5A55A5AU;

    checksum = 0U;
    index = 0U;

    for (;;) {
        if (ctrl->magic != LOAD_MAGIC) {
            ctrl->ready = 0U;
            ctrl->active = 0U;
            idle_delay();
            continue;
        }

        if (ctrl->ready != LOAD_READY) {
            ctrl->ready = LOAD_READY;
            load_barrier();
        }

        if (ctrl->command == LOAD_EXIT) {
            ctrl->active = 0U;
            ctrl->ready = 0U;
            load_barrier();
            break;
        }

        if (ctrl->command != LOAD_RUN) {
            ctrl->active = 0U;
            load_barrier();
            idle_delay();
            continue;
        }

        end = index + CHUNK_WORDS;
        if (end > LOAD_WORDS)
            end = LOAD_WORDS;

        for (i = index; i < end; i++) {
            value = buffer[i];
            checksum ^= value;
            buffer[i] = value + 1U;
        }

        ctrl->checksum = checksum;
        ctrl->active = 1U;
        load_barrier();

        index = end;
        if (index == LOAD_WORDS) {
            index = 0U;
            ctrl->passes = ctrl->passes + 1U;
        }
    }

    return 0;
}
