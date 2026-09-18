`timescale 1ns/1ps

package dma_pkg;

    localparam logic [6:0] REG_CTRL      = 7'h00;
    localparam logic [6:0] REG_STATUS    = 7'h04;
    localparam logic [6:0] REG_SRC       = 7'h08;
    localparam logic [6:0] REG_DST       = 7'h0c;
    localparam logic [6:0] REG_BYTES     = 7'h10;
    localparam logic [6:0] REG_CYCLES    = 7'h14;
    localparam logic [6:0] REG_R_BEATS   = 7'h20;
    localparam logic [6:0] REG_W_BEATS   = 7'h24;
    localparam logic [6:0] REG_DMA_CFG   = 7'h28;
    localparam logic [6:0] REG_RBR_CFG   = 7'h2c;
    localparam logic [6:0] REG_RBR_CTRL  = 7'h30;
    localparam logic [6:0] REG_R_BYTES   = 7'h34;
    localparam logic [6:0] REG_W_BYTES   = 7'h38;
    localparam logic [6:0] REG_R_NOM     = 7'h3c;
    localparam logic [6:0] REG_W_NOM     = 7'h40;
    localparam logic [6:0] REG_R_TXNS    = 7'h58;
    localparam logic [6:0] REG_W_TXNS    = 7'h5c;
    localparam logic [6:0] REG_R_WAIT    = 7'h60;
    localparam logic [6:0] REG_W_WAIT    = 7'h64;
    localparam logic [6:0] REG_R_WINDOWS = 7'h68;
    localparam logic [6:0] REG_W_WINDOWS = 7'h6c;
    localparam logic [6:0] REG_ADAPT_CTRL = 7'h70;
    localparam logic [6:0] REG_LAT_SAMPLE = 7'h74;
    localparam logic [6:0] REG_LAT_LIMITS = 7'h78;
    localparam logic [6:0] REG_ADAPT_POLICY = 7'h7c;

    localparam logic [31:0] ADAPT_ENABLE     = 32'h0000_0001;
    localparam logic [31:0] ADAPT_RESTART    = 32'h0000_0100;

    localparam logic [11:0] ADAPT_L0_DMA = 12'hA10;
    localparam logic [11:0] ADAPT_L1_DMA = 12'hA10;
    localparam logic [11:0] ADAPT_L2_DMA = 12'hA10;
    localparam logic [11:0] ADAPT_L3_DMA = 12'hA10;

    localparam logic [31:0] ADAPT_L0_RBR = 32'h0100_0100;
    localparam logic [31:0] ADAPT_L1_RBR = 32'h0080_0080;
    localparam logic [31:0] ADAPT_L2_RBR = 32'h0040_0040;
    localparam logic [31:0] ADAPT_L3_RBR = 32'h0000_0000;

    typedef enum int unsigned {
        RBR_OFF   = 0,
        RBR_100   = 1,
        RBR_FIXED = 2
    } rbr_mode_e;

    // Base transaction: fields shared by every DMA copy test.
    class dma_item;
        string name;

        rand bit [31:0] src_addr;
        rand bit [31:0] dst_addr;
        rand int unsigned transfer_bytes;
        rand int unsigned burst_beats;
        rand int unsigned rd_out_code;
        rand int unsigned wr_out_code;
        rand bit random_stalls;
        rand int unsigned pattern_seed;
        bit runtime_disable;

        byte unsigned payload[];

        constraint c_addr {
            src_addr inside {[32'h0000_1000:32'h0003_e000]};
            dst_addr inside {[32'h0008_0000:32'h000b_e000]};
            src_addr[2:0] == 3'b000;
            dst_addr[2:0] == 3'b000;
        }

        constraint c_size {
            transfer_bytes inside {64, 128, 256, 512, 1024, 2048, 4096};
            src_addr + transfer_bytes < 32'h0010_0000;
            dst_addr + transfer_bytes < 32'h0010_0000;
        }

        constraint c_solve_order {
            solve transfer_bytes before src_addr;
            solve transfer_bytes before dst_addr;
        }

        constraint c_dma_cfg {
            burst_beats inside {1, 2, 4, 8, 16};
            rd_out_code inside {[0:2]};
            wr_out_code inside {[0:2]};
        }

        function new(string name = "dma_item");
            this.name = name;
        endfunction

        function void post_randomize();
            build_payload();
        endfunction

        function void build_payload();
            payload = new[transfer_bytes];
            foreach (payload[i])
                payload[i] = byte'((i * 37 + pattern_seed * 13 + 8'h5a) & 8'hff);
        endfunction

        function int unsigned out_limit(input int unsigned code);
            case (code)
                0: return 1;
                1: return 2;
                default: return 4;
            endcase
        endfunction
    endclass


    // Derived transaction: adds the regulator-specific policy fields.
    class rbr_item extends dma_item;
        rand rbr_mode_e mode;
        rand int unsigned threshold_bytes;
        rand int unsigned delta_q8;
        int unsigned nominal_cycles;

        constraint c_rbr {
            threshold_bytes inside {64, 128, 256, 512};
            threshold_bytes <= transfer_bytes;
            if (mode == RBR_OFF)
                delta_q8 == 0;
            else if (mode == RBR_100)
                delta_q8 == 0;
            else
                delta_q8 inside {128, 256, 768};
        }


        constraint c_rbr_solve_order {
            solve transfer_bytes before threshold_bytes;
            solve mode before delta_q8;
        }

        function new(string name = "rbr_item");
            super.new(name);
        endfunction

        function void post_randomize();
            nominal_cycles = threshold_bytes / 8;
            super.post_randomize();
        endfunction

        function void prepare();
            nominal_cycles = threshold_bytes / 8;
            build_payload();
        endfunction
    endclass


    class dma_result;
        rbr_item item;
        string name;
        int unsigned errors;
        int unsigned cycles;
        int unsigned r_beats;
        int unsigned w_beats;
        int unsigned r_txns;
        int unsigned w_txns;
        int unsigned r_wait;
        int unsigned w_wait;
        int unsigned r_windows;
        int unsigned w_windows;
        int unsigned max_r_pending;
        int unsigned max_w_pending;
    endclass


    // Generates a small directed suite followed by constrained-random cases.
    class dma_generator;
        mailbox #(dma_item) outbox;
        int unsigned generated;
        int unsigned random_count;

        function new(mailbox #(dma_item) outbox,
                     int unsigned random_count = 20);
            this.outbox = outbox;
            this.random_count = random_count;
            this.generated = 0;
        endfunction

        task automatic send_directed(
            input string name,
            input bit [31:0] src,
            input bit [31:0] dst,
            input int unsigned bytes,
            input int unsigned burst,
            input int unsigned rd_code,
            input int unsigned wr_code,
            input rbr_mode_e mode,
            input int unsigned threshold,
            input int unsigned delta,
            input bit stalls,
            input bit runtime_disable = 0
        );
            rbr_item item;

            item = new(name);
            item.src_addr       = src;
            item.dst_addr       = dst;
            item.transfer_bytes = bytes;
            item.burst_beats    = burst;
            item.rd_out_code    = rd_code;
            item.wr_out_code    = wr_code;
            item.mode           = mode;
            item.threshold_bytes = threshold;
            item.delta_q8       = delta;
            item.random_stalls  = stalls;
            item.runtime_disable = runtime_disable;
            item.pattern_seed   = generated + 1;
            item.prepare();
            outbox.put(item);
            generated++;
        endtask

        task run();
            rbr_item item;
            bit random_ok;

            // Basic copy and a transfer whose bursts must split at 4KB.
            send_directed("basic_bypass", 32'h0000_2000, 32'h0008_2000,
                          64, 16, 2, 2, RBR_OFF, 64, 0, 0);
            send_directed("split_4k", 32'h0000_0fc0, 32'h0008_0fc0,
                          512, 16, 2, 2, RBR_OFF, 128, 0, 0);

            // Runtime burst choices.
            send_directed("burst_1", 32'h0000_4000, 32'h0008_4000,
                          256, 1, 2, 2, RBR_OFF, 64, 0, 0);
            send_directed("burst_2", 32'h0000_5000, 32'h0008_5000,
                          256, 2, 2, 2, RBR_OFF, 64, 0, 0);
            send_directed("burst_4", 32'h0000_6000, 32'h0008_6000,
                          256, 4, 2, 2, RBR_OFF, 64, 0, 0);
            send_directed("burst_8", 32'h0000_7000, 32'h0008_7000,
                          512, 8, 2, 2, RBR_OFF, 128, 0, 0);
            send_directed("burst_16", 32'h0000_8000, 32'h0008_8000,
                          1024, 16, 2, 2, RBR_OFF, 256, 0, 0);

            // Runtime outstanding choices.
            send_directed("outstanding_1", 32'h0000_a000, 32'h0008_a000,
                          1024, 16, 0, 0, RBR_OFF, 256, 0, 1);
            send_directed("outstanding_2", 32'h0000_b000, 32'h0008_b000,
                          1024, 16, 1, 1, RBR_OFF, 256, 0, 1);
            send_directed("outstanding_4", 32'h0000_c000, 32'h0008_c000,
                          1024, 16, 2, 2, RBR_OFF, 256, 0, 1);

            // True bypass, THR=100%, and fixed throttling are separate modes.
            send_directed("rbr_100", 32'h0001_0000, 32'h0009_0000,
                          512, 16, 2, 2, RBR_100, 128, 0, 0);
            send_directed("rbr_67", 32'h0001_1000, 32'h0009_1000,
                          1024, 16, 2, 2, RBR_FIXED, 256, 128, 0);
            send_directed("rbr_50_stall", 32'h0001_2000, 32'h0009_2000,
                          1024, 16, 2, 2, RBR_FIXED, 256, 256, 1);
            send_directed("rbr_25", 32'h0001_3000, 32'h0009_3000,
                          1024, 16, 2, 2, RBR_FIXED, 256, 768, 0);

            // Turn RBR off while WAIT is active. The held AXI beat must resume
            // without being lost or duplicated.
            send_directed("runtime_disable", 32'h0001_4000, 32'h0009_4000,
                          4096, 16, 2, 2, RBR_FIXED, 128, 768, 0, 1);

            // Randomization explores combinations not manually enumerated.
            for (int unsigned i = 0; i < random_count; i++) begin
                item = new($sformatf("random_%0d", i));
                random_ok = 0;
                for (int unsigned retry = 0; retry < 20; retry++) begin
                    if (item.randomize()) begin
                        random_ok = 1;
                        break;
                    end
                end
                if (!random_ok)
                    $fatal(1, "Randomization failed for item %0d", i);
                item.pattern_seed = 100 + i;
                item.prepare();
                outbox.put(item);
                generated++;
            end

            outbox.put(null);
        endtask
    endclass


    // Passive stream/order checker. It never drives the DUT.
    class dma_scoreboard;
        virtual axi_full_if mem;

        byte unsigned expected_q[$];
        bit active;
        int unsigned errors;
        int unsigned r_bytes_seen;
        int unsigned w_bytes_seen;
        int unsigned r_pending;
        int unsigned w_pending;
        int unsigned max_r_pending;
        int unsigned max_w_pending;
        int unsigned rd_limit;
        int unsigned wr_limit;

        function new(virtual axi_full_if mem);
            this.mem = mem;
            active = 0;
            errors = 0;
        endfunction

        function void begin_item(dma_item item);
            expected_q.delete();
            errors         = 0;
            r_bytes_seen   = 0;
            w_bytes_seen   = 0;
            r_pending      = 0;
            w_pending      = 0;
            max_r_pending  = 0;
            max_w_pending  = 0;
            rd_limit       = item.out_limit(item.rd_out_code);
            wr_limit       = item.out_limit(item.wr_out_code);
            active         = 1;
        endfunction

        function void end_item();
            active = 0;
            if (expected_q.size() != 0) begin
                errors++;
                $display("SCOREBOARD_ERROR: %0d bytes were read but not written",
                         expected_q.size());
            end
            if ((r_pending != 0) || (w_pending != 0)) begin
                errors++;
                $display("SCOREBOARD_ERROR: pending R/W=%0d/%0d", r_pending, w_pending);
            end
        endfunction

        task run();
            byte unsigned exp_byte;

            forever begin
                @(posedge mem.ACLK);
                if (!mem.ARESETN) begin
                    expected_q.delete();
                    r_pending = 0;
                    w_pending = 0;
                end else if (active) begin
                    if (mem.ARVALID && mem.ARREADY) begin
                        r_pending++;
                        if (r_pending > max_r_pending)
                            max_r_pending = r_pending;
                        if (r_pending > rd_limit) begin
                            errors++;
                            $display("SCOREBOARD_ERROR: read outstanding %0d > %0d",
                                     r_pending, rd_limit);
                        end
                    end

                    if (mem.RVALID && mem.RREADY) begin
                        for (int unsigned k = 0; k < 8; k++) begin
                            expected_q.push_back(mem.RDATA[k*8 +: 8]);
                            r_bytes_seen++;
                        end
                        if (mem.RLAST && (r_pending != 0))
                            r_pending--;
                    end

                    if (mem.AWVALID && mem.AWREADY) begin
                        w_pending++;
                        if (w_pending > max_w_pending)
                            max_w_pending = w_pending;
                        if (w_pending > wr_limit) begin
                            errors++;
                            $display("SCOREBOARD_ERROR: write outstanding %0d > %0d",
                                     w_pending, wr_limit);
                        end
                    end

                    if (mem.WVALID && mem.WREADY) begin
                        for (int unsigned k = 0; k < 8; k++) begin
                            if (mem.WSTRB[k]) begin
                                if (expected_q.size() == 0) begin
                                    errors++;
                                    $display("SCOREBOARD_ERROR: write arrived before read data");
                                end else begin
                                    exp_byte = expected_q.pop_front();
                                    if (mem.WDATA[k*8 +: 8] !== exp_byte) begin
                                        errors++;
                                        $display("SCOREBOARD_ERROR: stream exp=%02h got=%02h",
                                                 exp_byte, mem.WDATA[k*8 +: 8]);
                                    end
                                end
                                w_bytes_seen++;
                            end
                        end
                    end

                    if (mem.BVALID && mem.BREADY && (w_pending != 0))
                        w_pending--;
                end
            end
        endtask
    endclass


    // Coverage is represented by masks so it works in XSim without a UVM or
    // simulator-specific coverage database.
    class dma_coverage;
        bit [4:0] burst_mask;
        bit [2:0] rd_out_mask;
        bit [2:0] wr_out_mask;
        bit [2:0] mode_mask;
        bit [2:0] size_mask;
        bit [2:0] delta_mask;
        bit       saw_4k_split;
        bit       saw_backpressure;
        bit       saw_multiple_read;
        bit       saw_multiple_write;
        bit       saw_runtime_disable;

        function void sample(rbr_item item, dma_result result);
            case (item.burst_beats)
                1:  burst_mask[0] = 1'b1;
                2:  burst_mask[1] = 1'b1;
                4:  burst_mask[2] = 1'b1;
                8:  burst_mask[3] = 1'b1;
                16: burst_mask[4] = 1'b1;
            endcase

            rd_out_mask[item.rd_out_code] = 1'b1;
            wr_out_mask[item.wr_out_code] = 1'b1;
            mode_mask[item.mode] = 1'b1;

            if (item.transfer_bytes <= 256)
                size_mask[0] = 1'b1;
            else if (item.transfer_bytes <= 1024)
                size_mask[1] = 1'b1;
            else
                size_mask[2] = 1'b1;

            case (item.delta_q8)
                0:   delta_mask[0] = 1'b1;
                128: delta_mask[1] = 1'b1;
                default: delta_mask[2] = 1'b1;
            endcase

            if ((item.src_addr[11:0] + item.transfer_bytes > 4096) ||
                (item.dst_addr[11:0] + item.transfer_bytes > 4096))
                saw_4k_split = 1'b1;
            if (item.random_stalls)
                saw_backpressure = 1'b1;
            if (result.max_r_pending > 1)
                saw_multiple_read = 1'b1;
            if (result.max_w_pending > 1)
                saw_multiple_write = 1'b1;
            if (item.runtime_disable)
                saw_runtime_disable = 1'b1;
        endfunction

        function int unsigned missing_count();
            int unsigned count;
            count = 0;
            for (int unsigned i = 0; i < 5; i++)
                if (!burst_mask[i]) count++;
            for (int unsigned i = 0; i < 3; i++) begin
                if (!rd_out_mask[i]) count++;
                if (!wr_out_mask[i]) count++;
                if (!mode_mask[i]) count++;
                if (!size_mask[i]) count++;
                if (!delta_mask[i]) count++;
            end
            if (!saw_4k_split) count++;
            if (!saw_backpressure) count++;
            if (!saw_multiple_read) count++;
            if (!saw_multiple_write) count++;
            if (!saw_runtime_disable) count++;
            return count;
        endfunction

        function void report();
            $display("COVERAGE: burst=%05b rd_out=%03b wr_out=%03b mode=%03b",
                     burst_mask, rd_out_mask, wr_out_mask, mode_mask);
            $display("COVERAGE: size=%03b delta=%03b 4k=%0b stall=%0b multi_r/w=%0b/%0b runtime_off=%0b",
                     size_mask, delta_mask, saw_4k_split, saw_backpressure,
                     saw_multiple_read, saw_multiple_write, saw_runtime_disable);
        endfunction
    endclass


    class dma_driver;
        virtual axi_lite_if ctrl;
        virtual axi_full_if mem;
        mailbox #(dma_item) inbox;
        mailbox #(dma_result) result_box;
        dma_scoreboard scoreboard;

        int unsigned tests;
        int unsigned errors;
        bit done;

        function new(virtual axi_lite_if ctrl,
                     virtual axi_full_if mem,
                     mailbox #(dma_item) inbox,
                     mailbox #(dma_result) result_box,
                     dma_scoreboard scoreboard);
            this.ctrl = ctrl;
            this.mem = mem;
            this.inbox = inbox;
            this.result_box = result_box;
            this.scoreboard = scoreboard;
            tests = 0;
            errors = 0;
            done = 0;
        endfunction

        function int unsigned expected_txns(
            input int unsigned start_addr,
            input int unsigned bytes,
            input int unsigned max_burst
        );
            int unsigned addr;
            int unsigned beats_left;
            int unsigned beats_4k;
            int unsigned beats;
            int unsigned txns;

            addr = start_addr;
            beats_left = bytes / 8;
            txns = 0;
            while (beats_left != 0) begin
                beats_4k = (4096 - (addr & 32'hfff)) / 8;
                beats = max_burst;
                if (beats > beats_left)
                    beats = beats_left;
                if (beats > beats_4k)
                    beats = beats_4k;
                addr += beats * 8;
                beats_left -= beats;
                txns++;
            end
            return txns;
        endfunction

        task automatic read_reg(input logic [6:0] addr,
                                output int unsigned value);
            logic [31:0] data;
            ctrl.read(addr, data);
            value = data;
        endtask

        task automatic wait_dma(output int unsigned wait_errors);
            logic [31:0] status;
            bit saw_busy;
            int unsigned count;

            wait_errors = 0;
            saw_busy = 0;
            for (count = 0; count < 200000; count++) begin
                ctrl.read(REG_STATUS, status);
                if (status[2]) begin
                    wait_errors++;
                    $display("DMA_ERROR: engine error bit set");
                    return;
                end
                if (status[0]) begin
                    saw_busy = 1;
                    break;
                end
            end

            if (!saw_busy) begin
                wait_errors++;
                $display("DMA_ERROR: busy was not observed");
                return;
            end

            for (count = 0; count < 200000; count++) begin
                ctrl.read(REG_STATUS, status);
                if (status[2]) begin
                    wait_errors++;
                    $display("DMA_ERROR: engine error bit set");
                    return;
                end
                if (!status[0])
                    return;
            end

            wait_errors++;
            $display("DMA_ERROR: timeout waiting for completion");
        endtask

        task automatic execute(dma_item base_item);
            rbr_item item;
            dma_result result;
            int unsigned local_errors;
            int unsigned wait_errors;
            int unsigned expected_r_txns;
            int unsigned expected_w_txns;
            int unsigned expected_windows;
            int unsigned mem_errors_before;
            int unsigned wlast_errors_before;
            int unsigned lite_errors_before;

            if (!$cast(item, base_item))
                $fatal(1, "Driver received a non-RBR item");

            result = new();
            result.item = item;
            result.name = item.name;
            local_errors = 0;
            mem_errors_before  = mem.protocol_errors;
            wlast_errors_before = mem.wlast_errors;
            lite_errors_before = ctrl.protocol_errors;

            mem.load_region(item.src_addr, item.payload);
            mem.fill_region(item.dst_addr, item.transfer_bytes, 8'haa);
            mem.set_stalls(item.random_stalls);
            scoreboard.begin_item(item);

            // Soft reset clears the datapath/counters but keeps configuration.
            ctrl.write(REG_CTRL, 32'h0000_0002);
            ctrl.write(REG_RBR_CTRL, 32'd0);
            ctrl.write(REG_DMA_CFG,
                       item.burst_beats |
                       (item.rd_out_code << 8) |
                       (item.wr_out_code << 10));
            ctrl.write(REG_RBR_CFG, {item.delta_q8[15:0], item.delta_q8[15:0]});
            ctrl.write(REG_R_BYTES, item.threshold_bytes);
            ctrl.write(REG_W_BYTES, item.threshold_bytes);
            ctrl.write(REG_R_NOM, item.nominal_cycles);
            ctrl.write(REG_W_NOM, item.nominal_cycles);
            if (item.mode == RBR_OFF)
                ctrl.write(REG_RBR_CTRL, 32'd0);
            else
                ctrl.write(REG_RBR_CTRL, 32'd3);

            ctrl.write(REG_SRC, item.src_addr);
            ctrl.write(REG_DST, item.dst_addr);
            ctrl.write(REG_BYTES, item.transfer_bytes);
            ctrl.write(REG_CTRL, 32'h0000_0001);

            if (item.runtime_disable) begin
                fork
                    begin
                        wait (mem.rbr_r_wait || mem.rbr_w_wait);
                        ctrl.write(REG_RBR_CTRL, 32'd0);
                    end
                    begin
                        repeat (200000) @(posedge mem.ACLK);
                        $fatal(1, "Runtime-disable test did not reach RBR WAIT");
                    end
                join_any
                disable fork;
            end

            wait_dma(wait_errors);
            local_errors += wait_errors;
            scoreboard.end_item();

            read_reg(REG_CYCLES, result.cycles);
            read_reg(REG_R_BEATS, result.r_beats);
            read_reg(REG_W_BEATS, result.w_beats);
            read_reg(REG_R_TXNS, result.r_txns);
            read_reg(REG_W_TXNS, result.w_txns);
            read_reg(REG_R_WAIT, result.r_wait);
            read_reg(REG_W_WAIT, result.w_wait);
            read_reg(REG_R_WINDOWS, result.r_windows);
            read_reg(REG_W_WINDOWS, result.w_windows);

            result.max_r_pending = scoreboard.max_r_pending;
            result.max_w_pending = scoreboard.max_w_pending;

            local_errors += mem.compare_region(item.dst_addr, item.payload);
            local_errors += scoreboard.errors;
            local_errors += mem.protocol_errors - mem_errors_before;
            local_errors += mem.wlast_errors - wlast_errors_before;
            local_errors += ctrl.protocol_errors - lite_errors_before;

            if ((result.r_beats != item.transfer_bytes / 8) ||
                (result.w_beats != item.transfer_bytes / 8)) begin
                local_errors++;
                $display("COUNT_ERROR: beats R/W=%0d/%0d expected=%0d",
                         result.r_beats, result.w_beats, item.transfer_bytes / 8);
            end

            expected_r_txns = expected_txns(item.src_addr,
                                            item.transfer_bytes,
                                            item.burst_beats);
            expected_w_txns = expected_txns(item.dst_addr,
                                            item.transfer_bytes,
                                            item.burst_beats);
            if ((result.r_txns != expected_r_txns) ||
                (result.w_txns != expected_w_txns)) begin
                local_errors++;
                $display("COUNT_ERROR: txns R/W=%0d/%0d expected=%0d/%0d",
                         result.r_txns, result.w_txns,
                         expected_r_txns, expected_w_txns);
            end

            expected_windows = item.transfer_bytes / item.threshold_bytes;
            if (item.mode == RBR_OFF) begin
                if ((result.r_windows != 0) || (result.w_windows != 0) ||
                    (result.r_wait != 0) || (result.w_wait != 0)) begin
                    local_errors++;
                    $display("RBR_ERROR: bypass produced window/wait counts");
                end
            end else if (item.runtime_disable) begin
                if (((result.r_windows + result.w_windows) == 0) ||
                    ((result.r_wait + result.w_wait) == 0)) begin
                    local_errors++;
                    $display("RBR_ERROR: runtime disable never observed a window/WAIT");
                end
            end else begin
                if ((result.r_windows != expected_windows) ||
                    (result.w_windows != expected_windows)) begin
                    local_errors++;
                    $display("RBR_ERROR: windows R/W=%0d/%0d expected=%0d",
                             result.r_windows, result.w_windows, expected_windows);
                end
            end

            result.errors = local_errors;
            errors += local_errors;
            tests++;

            $display("TEST %-18s bytes=%4d burst=%2d out=%0d/%0d mode=%0d cycles=%0d wait=%0d/%0d result=%s",
                     item.name, item.transfer_bytes, item.burst_beats,
                     item.out_limit(item.rd_out_code), item.out_limit(item.wr_out_code),
                     item.mode, result.cycles, result.r_wait, result.w_wait,
                     (local_errors == 0) ? "PASS" : "FAIL");

            result_box.put(result);
        endtask

        task run();
            dma_item item;

            forever begin
                inbox.get(item);
                if (item == null)
                    break;
                execute(item);
            end
            done = 1;
            result_box.put(null);
        endtask
    endclass


    class dma_environment;
        mailbox #(dma_item) gen_to_drv;
        mailbox #(dma_result) drv_to_cov;
        dma_generator generator;
        dma_scoreboard scoreboard;
        dma_driver driver;
        dma_coverage coverage;
        virtual axi_lite_if ctrl;
        virtual axi_full_if mem;

        int unsigned errors;
        bit collection_done;

        function new(virtual axi_lite_if ctrl,
                     virtual axi_full_if mem,
                     int unsigned random_count = 20);
            this.ctrl = ctrl;
            this.mem = mem;
            gen_to_drv = new();
            drv_to_cov = new();
            scoreboard = new(mem);
            generator = new(gen_to_drv, random_count);
            driver = new(ctrl, mem, gen_to_drv, drv_to_cov, scoreboard);
            coverage = new();
            errors = 0;
            collection_done = 0;
        endfunction

        task collect_results();
            dma_result result;
            forever begin
                drv_to_cov.get(result);
                if (result == null)
                    break;
                errors += result.errors;
                coverage.sample(result.item, result);
            end
            collection_done = 1;
        endtask

        task run();
            // Generator, driver, scoreboard and collector are independent
            // threads. Mailboxes synchronize them without global timing hacks.
            fork
                generator.run();
                driver.run();
                scoreboard.run();
                collect_results();
            join_none

            wait (driver.done && collection_done);
            #1;
            errors = driver.errors;
        endtask
    endclass

endpackage
