#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xtime_l.h"

#include "shared.h"

#define DMA_BASE          XPAR_WRAPPER_0_BASEADDR

#define REG_CTRL          0x00U
#define REG_STATUS        0x04U
#define REG_SRC           0x08U
#define REG_DST           0x0CU
#define REG_BYTES         0x10U
#define REG_CYCLES        0x14U
#define REG_R_BEATS       0x20U
#define REG_W_BEATS       0x24U
#define REG_DMA_CFG       0x28U
#define REG_RBR_CFG       0x2CU
#define REG_RBR_CTRL      0x30U
#define REG_R_BYTES       0x34U
#define REG_W_BYTES       0x38U
#define REG_R_NOM         0x3CU
#define REG_W_NOM         0x40U
#define REG_R_TXNS        0x58U
#define REG_W_TXNS        0x5CU
#define REG_R_WAIT        0x60U
#define REG_W_WAIT        0x64U
#define REG_R_WINDOWS     0x68U
#define REG_W_WINDOWS     0x6CU
#define REG_ADAPT_CTRL    0x70U
#define REG_LAT_SAMPLE    0x74U
#define REG_LAT_LIMITS    0x78U
#define REG_ADAPT_POLICY  0x7CU

#define STATUS_BUSY       0x1U
#define STATUS_ERROR      0x4U
#define ADAPT_ENABLE      0x1U
#define ADAPT_RESTART     0x100U

#define NODE_BYTES        64U
#define WORDS_PER_NODE    (NODE_BYTES / sizeof(u32))
#define NODE_COUNT        16384U
#define NODE_MASK         (NODE_COUNT - 1U)
#define NODE_STEP         8191U
#define CPU_BUFFER_BYTES  (NODE_COUNT * NODE_BYTES)
#define CPU_BUFFER_WORDS  (CPU_BUFFER_BYTES / sizeof(u32))

#define WARMUP_ACCESSES   1024U
#define ACCESS_COUNT      16384U

#define DMA_BYTES         (8U * 1024U * 1024U)
#define DMA_MIB           8U
#define DMA_CLK_HZ        100000000U
#define DMA_TIMEOUT       100000000U
#define EXPECTED_BEATS    (DMA_BYTES / 8U)

#define DMA_CFG_B16_O4    0xA10U
#define DMA_CFG_B8_O4     0xA08U
#define RBR_CFG_80        0x00400040U
#define RBR_CFG_67        0x00800080U
#define RBR_CFG_50        0x01000100U
#define RBR_THRESHOLD     256U
#define RBR_NOMINAL       32U

#define LOW_PERCENT       130U
#define HIGH_PERCENT      150U
#define HOLD_SAMPLES      4U
#define LOW_CONFIRM       3U
#define HIGH_CONFIRM      2U
#define INITIAL_LEVEL     1U

#define REPEAT_COUNT      3U
#define PHASE_COUNT       4U
#define PHASE_SAMPLES     25U
#define SAMPLES_PER_RUN   (PHASE_COUNT * PHASE_SAMPLES)
#define TOTAL_SAMPLES     (REPEAT_COUNT * SAMPLES_PER_RUN)

#define MODE_CPU_ONLY     0U
#define MODE_FIXED_MAX    1U
#define MODE_STATIC_B8    2U
#define MODE_RBR_50       3U
#define MODE_RBR_67       4U
#define MODE_RBR_80       5U
#define MODE_ADAPTIVE     6U
#define MODE_COUNT        7U

typedef struct {
    const char *name;
    u32 dma_cfg;
    u32 rbr_ctrl;
    u32 rbr_cfg;
    u32 burst_beats;
    u32 adaptive;
} mode_cfg_t;

static const mode_cfg_t modes[MODE_COUNT] = {
    {"CPU_ONLY",  0U,               0U, 0U,           0U,  0U},
    {"FIXED_MAX", DMA_CFG_B16_O4,   0U, 0U,           16U, 0U},
    {"STATIC_B8", DMA_CFG_B8_O4,    0U, 0U,           8U,  0U},
    {"RBR_50",    DMA_CFG_B16_O4,   3U, RBR_CFG_50,   16U, 0U},
    {"RBR_67",    DMA_CFG_B16_O4,   3U, RBR_CFG_67,   16U, 0U},
    {"RBR_80",    DMA_CFG_B16_O4,   3U, RBR_CFG_80,   16U, 0U},
    {"ADAPTIVE",  DMA_CFG_B16_O4,   0U, 0U,           16U, 1U}
};

static const u32 phase_load[PHASE_COUNT] = {0U, 1U, 0U, 1U};
static const char *const phase_name[PHASE_COUNT] = {
    "OFF_A", "ON_A", "OFF_B", "ON_B"
};

static u32 latency_buffer[CPU_BUFFER_WORDS]
    __attribute__((aligned(0x100000)));
static u8 dma_src[DMA_BYTES] __attribute__((aligned(4096)));
static u8 dma_dst[DMA_BYTES] __attribute__((aligned(4096)));

static u32 cpu_samples[MODE_COUNT][TOTAL_SAMPLES];
static u32 mode_errors[MODE_COUNT];
static u32 mode_commands[MODE_COUNT];
static u32 mode_transitions[MODE_COUNT];
static u32 level_hits[4];
static u64 mode_dma_cycles[MODE_COUNT];
static u64 mode_r_wait[MODE_COUNT];
static u64 mode_w_wait[MODE_COUNT];
static u64 mode_r_windows[MODE_COUNT];
static u64 mode_w_windows[MODE_COUNT];
static u32 phase_commands[MODE_COUNT][PHASE_COUNT];
static u64 phase_dma_cycles[MODE_COUNT][PHASE_COUNT];
static u64 phase_r_wait[MODE_COUNT][PHASE_COUNT];
static u64 phase_w_wait[MODE_COUNT][PHASE_COUNT];
static u64 phase_r_windows[MODE_COUNT][PHASE_COUNT];
static u64 phase_w_windows[MODE_COUNT][PHASE_COUNT];
static u32 saw_level_up;
static u32 saw_level_down;
static volatile u32 result_sink;

static void reg_write(u32 offset, u32 value)
{
    Xil_Out32(DMA_BASE + offset, value);
}

static u32 reg_read(u32 offset)
{
    return Xil_In32(DMA_BASE + offset);
}

static u32 read_level(void)
{
    return (reg_read(REG_ADAPT_CTRL) >> 1) & 0x3U;
}

static u32 make_policy(u32 initial_level, u32 high_confirm,
                       u32 low_confirm, u32 hold_samples)
{
    return ((initial_level & 0x3U) << 24) |
           ((high_confirm & 0xFFU) << 16) |
           ((low_confirm & 0xFFU) << 8) |
           (hold_samples & 0xFFU);
}

static u32 __attribute__((noinline))
run_pointer_chase(volatile u32 *buffer, u32 index, u32 count)
{
    u32 i;

    for (i = 0U; i < count; i++)
        index = buffer[index * WORDS_PER_NODE];

    return index;
}

static XTime measure_cpu(volatile u32 *buffer, u32 *index,
                         XTime timer_overhead)
{
    XTime start_time;
    XTime end_time;
    XTime elapsed;

    XTime_GetTime(&start_time);
    *index = run_pointer_chase(buffer, *index, ACCESS_COUNT);
    XTime_GetTime(&end_time);

    elapsed = end_time - start_time;
    if (elapsed > timer_overhead)
        elapsed -= timer_overhead;

    return elapsed;
}

static u32 cpu_cycles_x100_per_access(XTime timer_ticks)
{
    u64 cpu_cycles;

    cpu_cycles = (u64)timer_ticks *
                 (u64)XPAR_CPU_CORTEXA9_CORE_CLOCK_FREQ_HZ;
    cpu_cycles *= 100U;
    cpu_cycles /= (u64)COUNTS_PER_SECOND;
    cpu_cycles /= (u64)ACCESS_COUNT;

    return (u32)cpu_cycles;
}

static void print_fixed_u32(u32 value)
{
    xil_printf("%d.%02d", value / 100U, value % 100U);
}

static int wait_dma_busy(void)
{
    u32 status;
    u32 count;

    for (count = 0U; count < DMA_TIMEOUT; count++) {
        status = reg_read(REG_STATUS);
        if ((status & STATUS_ERROR) != 0U)
            return -1;
        if ((status & STATUS_BUSY) != 0U)
            return 0;
    }

    return -2;
}

static int wait_dma_done(void)
{
    u32 status;
    u32 count;

    for (count = 0U; count < DMA_TIMEOUT; count++) {
        status = reg_read(REG_STATUS);
        if ((status & STATUS_ERROR) != 0U)
            return -1;
        if ((status & STATUS_BUSY) == 0U)
            return 0;
    }

    return -2;
}

static int wait_load_value(volatile u32 *value, u32 expected)
{
    XTime start_time;
    XTime now;

    XTime_GetTime(&start_time);
    do {
        if (*value == expected)
            return 0;
        XTime_GetTime(&now);
    } while ((now - start_time) < ((XTime)COUNTS_PER_SECOND * 30U));

    return -1;
}

static int init_load_core(volatile load_ctrl_t *ctrl)
{
    ctrl->magic = 0U;
    ctrl->command = LOAD_STOP;
    ctrl->ready = 0U;
    ctrl->active = 0U;
    ctrl->passes = 0U;
    ctrl->checksum = 0U;
    load_barrier();
    ctrl->magic = LOAD_MAGIC;
    load_barrier();

    xil_printf("Waiting for CPU1 load generator...\r\n");
    if (wait_load_value(&ctrl->ready, LOAD_READY) != 0)
        return -1;

    xil_printf("CPU1 load generator ready\r\n");
    return 0;
}

static int set_load(volatile load_ctrl_t *ctrl, u32 load_on)
{
    u32 expected_active;

    expected_active = load_on ? 1U : 0U;
    ctrl->command = load_on ? LOAD_RUN : LOAD_STOP;
    load_barrier();

    if (wait_load_value(&ctrl->active, expected_active) != 0)
        return -1;
    if (ctrl->ready != LOAD_READY)
        return -2;

    return 0;
}

static void program_dma(void)
{
    reg_write(REG_SRC, (u32)(INTPTR)dma_src);
    reg_write(REG_DST, (u32)(INTPTR)dma_dst);
    reg_write(REG_BYTES, DMA_BYTES);
}

static void configure_mode(u32 mode, u32 low_limit, u32 high_limit)
{
    reg_write(REG_ADAPT_CTRL, 0U);
    reg_write(REG_RBR_CTRL, 0U);
    reg_write(REG_CTRL, 0x2U);

    if (mode == MODE_CPU_ONLY)
        return;

    reg_write(REG_DMA_CFG, modes[mode].dma_cfg);
    reg_write(REG_R_BYTES, RBR_THRESHOLD);
    reg_write(REG_W_BYTES, RBR_THRESHOLD);
    reg_write(REG_R_NOM, RBR_NOMINAL);
    reg_write(REG_W_NOM, RBR_NOMINAL);
    reg_write(REG_RBR_CFG, modes[mode].rbr_cfg);
    reg_write(REG_RBR_CTRL, modes[mode].rbr_ctrl);
    program_dma();

    if (modes[mode].adaptive != 0U) {
        reg_write(REG_LAT_LIMITS, (high_limit << 16) | low_limit);
        reg_write(REG_ADAPT_POLICY,
                  make_policy(INITIAL_LEVEL, HIGH_CONFIRM,
                              LOW_CONFIRM, HOLD_SAMPLES));
        reg_write(REG_ADAPT_CTRL, ADAPT_ENABLE | ADAPT_RESTART);
    }
}

static int start_dma(void)
{
    reg_write(REG_CTRL, 0x1U);
    return wait_dma_busy();
}

static int check_dma_spots(u32 command)
{
    u32 offset_a;
    u32 offset_b;

    offset_a = (command * 104729U) & (DMA_BYTES - 1U);
    offset_b = offset_a ^ (DMA_BYTES - 1U);

    Xil_DCacheInvalidateRange((INTPTR)&dma_dst[0], 1U);
    Xil_DCacheInvalidateRange((INTPTR)&dma_dst[DMA_BYTES - 1U], 1U);
    Xil_DCacheInvalidateRange((INTPTR)&dma_dst[offset_a], 1U);
    Xil_DCacheInvalidateRange((INTPTR)&dma_dst[offset_b], 1U);

    if ((dma_dst[0] != dma_src[0]) ||
        (dma_dst[DMA_BYTES - 1U] != dma_src[DMA_BYTES - 1U]) ||
        (dma_dst[offset_a] != dma_src[offset_a]) ||
        (dma_dst[offset_b] != dma_src[offset_b]))
        return -1;

    return 0;
}

static int check_dma_full(void)
{
    u32 i;

    Xil_DCacheInvalidateRange((INTPTR)dma_dst, DMA_BYTES);
    for (i = 0U; i < DMA_BYTES; i++) {
        if (dma_dst[i] != dma_src[i]) {
            xil_printf("DATA_FAIL,offset=%d,src=%d,dst=%d\r\n",
                       i, dma_src[i], dma_dst[i]);
            return -1;
        }
    }

    return 0;
}

static int collect_dma_result(u32 mode, u32 phase)
{
    u32 r_beats;
    u32 w_beats;
    u32 r_txns;
    u32 w_txns;
    u32 expected_txns;
    u32 command;
    u32 dma_cycles;
    u32 r_wait;
    u32 w_wait;
    u32 r_windows;
    u32 w_windows;

    r_beats = reg_read(REG_R_BEATS);
    w_beats = reg_read(REG_W_BEATS);
    r_txns = reg_read(REG_R_TXNS);
    w_txns = reg_read(REG_W_TXNS);
    command = mode_commands[mode];

    if ((r_beats != EXPECTED_BEATS) || (w_beats != EXPECTED_BEATS)) {
        xil_printf("CHECK_FAIL,%s,beats,R=%d,W=%d\r\n",
                   modes[mode].name, r_beats, w_beats);
        return -1;
    }

    if (modes[mode].burst_beats != 0U) {
        expected_txns = EXPECTED_BEATS / modes[mode].burst_beats;
        if ((r_txns != expected_txns) || (w_txns != expected_txns)) {
            xil_printf("CHECK_FAIL,%s,txns,R=%d,W=%d,expected=%d\r\n",
                       modes[mode].name, r_txns, w_txns, expected_txns);
            return -2;
        }
    }

    if (check_dma_spots(command) != 0) {
        xil_printf("CHECK_FAIL,%s,data,command=%d\r\n",
                   modes[mode].name, command);
        return -3;
    }

    dma_cycles = reg_read(REG_CYCLES);
    r_wait = reg_read(REG_R_WAIT);
    w_wait = reg_read(REG_W_WAIT);
    r_windows = reg_read(REG_R_WINDOWS);
    w_windows = reg_read(REG_W_WINDOWS);

    mode_dma_cycles[mode] += dma_cycles;
    mode_r_wait[mode] += r_wait;
    mode_w_wait[mode] += w_wait;
    mode_r_windows[mode] += r_windows;
    mode_w_windows[mode] += w_windows;
    mode_commands[mode]++;

    phase_dma_cycles[mode][phase] += dma_cycles;
    phase_r_wait[mode][phase] += r_wait;
    phase_w_wait[mode][phase] += w_wait;
    phase_r_windows[mode][phase] += r_windows;
    phase_w_windows[mode][phase] += w_windows;
    phase_commands[mode][phase]++;

    return 0;
}

static int finish_dma_command(u32 mode, u32 phase)
{
    int result;

    result = wait_dma_done();
    if (result != 0)
        return result;
    return collect_dma_result(mode, phase);
}

static int run_mode(u32 mode, volatile load_ctrl_t *ctrl,
                    volatile u32 *cpu_buffer, u32 *index,
                    XTime timer_overhead, u32 low_limit, u32 high_limit)
{
    XTime elapsed;
    u32 repeat;
    u32 phase;
    u32 sample_in_phase;
    u32 sample_index;
    u32 sample;
    u32 level_before;
    u32 level_after;
    u32 status;
    int result;

    xil_printf("MODE_BEGIN,%s\r\n", modes[mode].name);

    for (repeat = 0U; repeat < REPEAT_COUNT; repeat++) {
        configure_mode(mode, low_limit, high_limit);

        for (phase = 0U; phase < PHASE_COUNT; phase++) {
            result = set_load(ctrl, phase_load[phase]);
            if (result != 0)
                return -20 - result;

            // Keep every recorded command inside one CPU1 load phase so the
            // phase throughput does not mix OFF and ON operation.
            if (mode != MODE_CPU_ONLY) {
                result = start_dma();
                if (result != 0)
                    return -10;
            }

            for (sample_in_phase = 0U;
                 sample_in_phase < PHASE_SAMPLES;) {
                if (mode != MODE_CPU_ONLY) {
                    status = reg_read(REG_STATUS);
                    if ((status & STATUS_ERROR) != 0U)
                        return -30;
                    if ((status & STATUS_BUSY) == 0U) {
                        result = collect_dma_result(mode, phase);
                        if (result != 0)
                            return -31;
                        result = start_dma();
                        if (result != 0)
                            return -32;
                        continue;
                    }
                }

                if (modes[mode].adaptive != 0U)
                    level_before = read_level();
                else
                    level_before = 255U;

                elapsed = measure_cpu(cpu_buffer, index, timer_overhead);

                if (mode != MODE_CPU_ONLY) {
                    status = reg_read(REG_STATUS);
                    if ((status & STATUS_ERROR) != 0U)
                        return -33;
                    if ((status & STATUS_BUSY) == 0U) {
                        result = collect_dma_result(mode, phase);
                        if (result != 0)
                            return -34;
                        result = start_dma();
                        if (result != 0)
                            return -35;
                        continue;
                    }
                }

                if (ctrl->active != phase_load[phase])
                    return -40;

                sample = cpu_cycles_x100_per_access(elapsed);
                sample_index = repeat * SAMPLES_PER_RUN +
                               phase * PHASE_SAMPLES + sample_in_phase;
                cpu_samples[mode][sample_index] = sample;

                if (modes[mode].adaptive != 0U) {
                    reg_write(REG_LAT_SAMPLE, sample);
                    level_after = read_level();
                    level_hits[level_after]++;

                    if (level_after > level_before)
                        saw_level_up = 1U;
                    if (level_after < level_before)
                        saw_level_down = 1U;
                    if (level_after != level_before)
                        mode_transitions[mode]++;
                } else {
                    level_after = 255U;
                }

                xil_printf("SAMPLE,%d,%s,%s,%d,%d,%d,",
                           repeat, modes[mode].name, phase_name[phase],
                           phase_load[phase], sample_in_phase,
                           (u32)elapsed);
                print_fixed_u32(sample);
                xil_printf(",%d,%d,%d\r\n",
                           level_before, level_after,
                           mode_commands[mode]);

                sample_in_phase++;
            }

            if (mode != MODE_CPU_ONLY) {
                result = finish_dma_command(mode, phase);
                if (result != 0)
                    return -50;
            }
        }

        if (mode != MODE_CPU_ONLY) {
            if (check_dma_full() != 0)
                return -51;
        }

        reg_write(REG_ADAPT_CTRL, 0U);
    }

    xil_printf("MODE_END,%s\r\n", modes[mode].name);
    return 0;
}

static void sort_values(u32 *values, u32 count)
{
    u32 i;
    u32 j;
    u32 value;

    for (i = 1U; i < count; i++) {
        value = values[i];
        j = i;
        while ((j != 0U) && (values[j - 1U] > value)) {
            values[j] = values[j - 1U];
            j--;
        }
        values[j] = value;
    }
}

static u32 mean_values(const u32 *values, u32 count)
{
    u64 sum;
    u32 i;

    sum = 0U;
    for (i = 0U; i < count; i++)
        sum += values[i];

    return (u32)(sum / count);
}

static u32 mean_cpu_only(u32 load_on)
{
    u64 sum;
    u32 count;
    u32 repeat;
    u32 phase;
    u32 sample;
    u32 index;

    sum = 0U;
    count = 0U;
    for (repeat = 0U; repeat < REPEAT_COUNT; repeat++) {
        for (phase = 0U; phase < PHASE_COUNT; phase++) {
            if (phase_load[phase] != load_on)
                continue;
            for (sample = 0U; sample < PHASE_SAMPLES; sample++) {
                index = repeat * SAMPLES_PER_RUN +
                        phase * PHASE_SAMPLES + sample;
                sum += cpu_samples[MODE_CPU_ONLY][index];
                count++;
            }
        }
    }

    return (u32)(sum / count);
}

static void print_phase_summary(u32 mode, u32 phase, u32 high_limit)
{
    u32 values[REPEAT_COUNT * PHASE_SAMPLES];
    u32 repeat;
    u32 sample;
    u32 src_index;
    u32 dst_index;
    u32 violations;
    u32 count;

    dst_index = 0U;
    violations = 0U;
    for (repeat = 0U; repeat < REPEAT_COUNT; repeat++) {
        for (sample = 0U; sample < PHASE_SAMPLES; sample++) {
            src_index = repeat * SAMPLES_PER_RUN +
                        phase * PHASE_SAMPLES + sample;
            values[dst_index] = cpu_samples[mode][src_index];
            if (values[dst_index] > high_limit)
                violations++;
            dst_index++;
        }
    }

    count = REPEAT_COUNT * PHASE_SAMPLES;
    sort_values(values, count);

    xil_printf("PHASE_SUMMARY,%s,%s,%d,",
               modes[mode].name, phase_name[phase], phase_load[phase]);
    print_fixed_u32(values[0]);
    xil_printf(",");
    print_fixed_u32(mean_values(values, count));
    xil_printf(",");
    print_fixed_u32(values[((95U * count + 99U) / 100U) - 1U]);
    xil_printf(",");
    print_fixed_u32(values[count - 1U]);
    xil_printf(",%d\r\n", violations);
}

static void print_mode_summary(u32 mode, u32 high_limit)
{
    u32 sorted[TOTAL_SAMPLES];
    u32 violations;
    u32 throughput_x100;
    u32 i;
    u64 numerator;

    violations = 0U;
    for (i = 0U; i < TOTAL_SAMPLES; i++) {
        sorted[i] = cpu_samples[mode][i];
        if (sorted[i] > high_limit)
            violations++;
    }
    sort_values(sorted, TOTAL_SAMPLES);

    if ((mode == MODE_CPU_ONLY) || (mode_dma_cycles[mode] == 0U)) {
        throughput_x100 = 0U;
    } else {
        numerator = (u64)DMA_MIB * (u64)mode_commands[mode] *
                    (u64)DMA_CLK_HZ * 100U;
        throughput_x100 = (u32)(numerator / mode_dma_cycles[mode]);
    }

    xil_printf("SUMMARY,%s,", modes[mode].name);
    print_fixed_u32(sorted[0]);
    xil_printf(",");
    print_fixed_u32(mean_values(cpu_samples[mode], TOTAL_SAMPLES));
    xil_printf(",");
    print_fixed_u32(sorted[((95U * TOTAL_SAMPLES + 99U) / 100U) - 1U]);
    xil_printf(",");
    print_fixed_u32(sorted[((99U * TOTAL_SAMPLES + 99U) / 100U) - 1U]);
    xil_printf(",");
    print_fixed_u32(sorted[TOTAL_SAMPLES - 1U]);
    xil_printf(",%d,%d,", violations, mode_commands[mode]);
    print_fixed_u32(throughput_x100);
    xil_printf(",%d,%d,%d,%d,%d,%d\r\n",
               (u32)mode_dma_cycles[mode],
               (u32)mode_r_wait[mode], (u32)mode_w_wait[mode],
               (u32)mode_r_windows[mode], (u32)mode_w_windows[mode],
               mode_transitions[mode]);
}

static void print_phase_dma_summary(u32 mode, u32 phase)
{
    u32 throughput_x100;
    u64 numerator;

    if ((mode == MODE_CPU_ONLY) ||
        (phase_dma_cycles[mode][phase] == 0U)) {
        throughput_x100 = 0U;
    } else {
        numerator = (u64)DMA_MIB *
                    (u64)phase_commands[mode][phase] *
                    (u64)DMA_CLK_HZ * 100U;
        throughput_x100 =
            (u32)(numerator / phase_dma_cycles[mode][phase]);
    }

    xil_printf("PHASE_DMA,%s,%s,%d,%d,",
               modes[mode].name, phase_name[phase], phase_load[phase],
               phase_commands[mode][phase]);
    print_fixed_u32(throughput_x100);
    xil_printf(",%d,%d,%d,%d,%d\r\n",
               (u32)phase_dma_cycles[mode][phase],
               (u32)phase_r_wait[mode][phase],
               (u32)phase_w_wait[mode][phase],
               (u32)phase_r_windows[mode][phase],
               (u32)phase_w_windows[mode][phase]);
}

int main(void)
{
    volatile load_ctrl_t *load_ctrl;
    volatile u32 *cpu_buffer;
    XTime start_time;
    XTime end_time;
    XTime timer_overhead;
    u32 baseline_off;
    u32 baseline_on;
    u32 low_limit;
    u32 high_limit;
    u32 index;
    u32 mode;
    u32 phase;
    u32 i;
    int result;

    xil_printf("\r\nFinal Adaptive DMA benchmark\r\n");

    for (i = 0U; i < NODE_COUNT; i++)
        latency_buffer[i * WORDS_PER_NODE] =
            (i + NODE_STEP) & NODE_MASK;

    for (i = 0U; i < DMA_BYTES; i++) {
        dma_src[i] = (u8)((i * 13U + (i >> 8) + 0x5AU) & 0xFFU);
        dma_dst[i] = 0U;
    }

    Xil_DCacheFlushRange((INTPTR)latency_buffer, CPU_BUFFER_BYTES);
    Xil_DCacheFlushRange((INTPTR)dma_src, DMA_BYTES);
    Xil_DCacheFlushRange((INTPTR)dma_dst, DMA_BYTES);
    Xil_SetTlbAttributes((INTPTR)latency_buffer, NORM_NONCACHE);
    Xil_SetTlbAttributes((INTPTR)LOAD_CTRL_BASE, NORM_NONCACHE);

    cpu_buffer = (volatile u32 *)latency_buffer;
    load_ctrl = (volatile load_ctrl_t *)(INTPTR)LOAD_CTRL_BASE;

    index = run_pointer_chase(cpu_buffer, 0U, WARMUP_ACCESSES);
    XTime_GetTime(&start_time);
    XTime_GetTime(&end_time);
    timer_overhead = end_time - start_time;

    result = init_load_core(load_ctrl);
    if (result != 0) {
        xil_printf("FAIL: CPU1 load generator not ready\r\n");
        return 1;
    }

    xil_printf("CONFIG,repeats=%d,phases=%d,samples_per_phase=%d,dma_bytes=%d\r\n",
               REPEAT_COUNT, PHASE_COUNT, PHASE_SAMPLES, DMA_BYTES);
    xil_printf("SAMPLE_HEADER,repeat,mode,phase,load,sample,cpu_ticks,cpu_cycles,level_before,level_after,dma_command\r\n");

    result = run_mode(MODE_CPU_ONLY, load_ctrl, cpu_buffer, &index,
                      timer_overhead, 0U, 0U);
    if (result != 0) {
        xil_printf("FAIL: CPU_ONLY result=%d\r\n", result);
        return 1;
    }

    baseline_off = mean_cpu_only(0U);
    baseline_on = mean_cpu_only(1U);
    low_limit = (baseline_off * LOW_PERCENT) / 100U;
    high_limit = (baseline_off * HIGH_PERCENT) / 100U;
    if (high_limit > 65535U)
        high_limit = 65535U;
    if (low_limit >= high_limit)
        low_limit = high_limit - 1U;

    xil_printf("LIMITS,baseline_off=");
    print_fixed_u32(baseline_off);
    xil_printf(",baseline_on=");
    print_fixed_u32(baseline_on);
    xil_printf(",low=");
    print_fixed_u32(low_limit);
    xil_printf(",high=");
    print_fixed_u32(high_limit);
    xil_printf("\r\n");

    for (mode = MODE_FIXED_MAX; mode < MODE_COUNT; mode++) {
        result = run_mode(mode, load_ctrl, cpu_buffer, &index,
                          timer_overhead, low_limit, high_limit);
        if (result != 0) {
            mode_errors[mode]++;
            xil_printf("FAIL: %s result=%d\r\n",
                       modes[mode].name, result);
            set_load(load_ctrl, 0U);
            return 1;
        }
    }

    result_sink = index;
    set_load(load_ctrl, 0U);

    if ((saw_level_up == 0U) || (saw_level_down == 0U)) {
        mode_errors[MODE_ADAPTIVE]++;
        xil_printf("CHECK_FAIL,ADAPTIVE,bidirectional,up=%d,down=%d\r\n",
                   saw_level_up, saw_level_down);
    }

    xil_printf("PHASE_SUMMARY_HEADER,mode,phase,load,min,mean,p95,max,violations\r\n");
    for (mode = 0U; mode < MODE_COUNT; mode++) {
        for (phase = 0U; phase < PHASE_COUNT; phase++)
            print_phase_summary(mode, phase, high_limit);
    }

    xil_printf("PHASE_DMA_HEADER,mode,phase,load,commands,dma_MiB_per_s,dma_cycles,r_wait,w_wait,r_windows,w_windows\r\n");
    for (mode = 0U; mode < MODE_COUNT; mode++) {
        for (phase = 0U; phase < PHASE_COUNT; phase++)
            print_phase_dma_summary(mode, phase);
    }

    xil_printf("SUMMARY_HEADER,mode,min,mean,p95,p99,max,violations,dma_commands,dma_MiB_per_s,dma_cycles,r_wait,w_wait,r_windows,w_windows,transitions\r\n");
    for (mode = 0U; mode < MODE_COUNT; mode++)
        print_mode_summary(mode, high_limit);

    xil_printf("LEVEL_HITS,L0=%d,L1=%d,L2=%d,L3=%d,up=%d,down=%d\r\n",
               level_hits[0], level_hits[1], level_hits[2], level_hits[3],
               saw_level_up, saw_level_down);
    xil_printf("CPU1,passes=%d,checksum=0x%08x\r\n",
               load_ctrl->passes, load_ctrl->checksum);

    for (mode = 0U; mode < MODE_COUNT; mode++) {
        if (mode_errors[mode] != 0U) {
            xil_printf("FAIL: errors in %s=%d\r\n",
                       modes[mode].name, mode_errors[mode]);
            return 1;
        }
    }

    xil_printf("PASS: final adaptive benchmark complete, sink=%d\r\n",
               result_sink);
    return 0;
}
