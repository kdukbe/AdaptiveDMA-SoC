#ifndef FINAL_SHARED_H
#define FINAL_SHARED_H

#include "xil_types.h"

/* Reserved DDR regions.  They do not overlap the CPU0 application's arrays. */
#define LOAD_CODE_BASE    0x18000000U
#define LOAD_BUFFER_BASE  0x1C000000U
#define LOAD_BUFFER_BYTES (8U * 1024U * 1024U)
#define LOAD_CTRL_BASE    0x1FF00000U

#define LOAD_MAGIC        0x4C4F4144U
#define LOAD_READY        0x52454144U

#define LOAD_STOP         0U
#define LOAD_RUN          1U
#define LOAD_EXIT         2U

typedef struct {
    volatile u32 magic;
    volatile u32 command;
    volatile u32 ready;
    volatile u32 active;
    volatile u32 passes;
    volatile u32 checksum;
} load_ctrl_t;

static inline void load_barrier(void)
{
    __asm__ volatile ("dmb sy" ::: "memory");
}

#endif
