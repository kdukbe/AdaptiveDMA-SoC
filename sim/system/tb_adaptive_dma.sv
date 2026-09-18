`timescale 1ns/1ps

module tb_adaptive_dma;
    import dma_pkg::*;

    localparam int unsigned SRC_ADDR = 32'h0000_0fc0;
    localparam int unsigned DST_ADDR = 32'h0008_0fc0;
    localparam int unsigned COPY_BYTES = 65536;

    logic CLK;
    logic RSTN;
    int unsigned errors;
    int unsigned assertion_errors;
    bit [3:0] level_mask;
    bit [3:0] rbr_level_mask;
    bit saw_rbr_wait;

    byte unsigned payload[];

    axi_lite_if ctrl(CLK);
    axi_full_if mem(CLK);

    assign ctrl.ARESETN = RSTN;
    assign mem.ARESETN = RSTN;
    assign mem.rbr_r_wait = dut.r_wait_active;
    assign mem.rbr_w_wait = dut.w_wait_active;

    axi_mem u_mem(mem);

    top dut (
        .CLK(CLK),
        .RSTN(RSTN),

        .S_AXI_AWADDR(ctrl.AWADDR),
        .S_AXI_AWVALID(ctrl.AWVALID),
        .S_AXI_AWREADY(ctrl.AWREADY),
        .S_AXI_WDATA(ctrl.WDATA),
        .S_AXI_WSTRB(ctrl.WSTRB),
        .S_AXI_WVALID(ctrl.WVALID),
        .S_AXI_WREADY(ctrl.WREADY),
        .S_AXI_BRESP(ctrl.BRESP),
        .S_AXI_BVALID(ctrl.BVALID),
        .S_AXI_BREADY(ctrl.BREADY),
        .S_AXI_ARADDR(ctrl.ARADDR),
        .S_AXI_ARVALID(ctrl.ARVALID),
        .S_AXI_ARREADY(ctrl.ARREADY),
        .S_AXI_RDATA(ctrl.RDATA),
        .S_AXI_RRESP(ctrl.RRESP),
        .S_AXI_RVALID(ctrl.RVALID),
        .S_AXI_RREADY(ctrl.RREADY),

        .M_AXI_ARADDR(mem.ARADDR),
        .M_AXI_ARLEN(mem.ARLEN),
        .M_AXI_ARSIZE(mem.ARSIZE),
        .M_AXI_ARBURST(mem.ARBURST),
        .M_AXI_ARVALID(mem.ARVALID),
        .M_AXI_ARREADY(mem.ARREADY),
        .M_AXI_RDATA(mem.RDATA),
        .M_AXI_RRESP(mem.RRESP),
        .M_AXI_RLAST(mem.RLAST),
        .M_AXI_RVALID(mem.RVALID),
        .M_AXI_RREADY(mem.RREADY),

        .M_AXI_AWADDR(mem.AWADDR),
        .M_AXI_AWLEN(mem.AWLEN),
        .M_AXI_AWSIZE(mem.AWSIZE),
        .M_AXI_AWBURST(mem.AWBURST),
        .M_AXI_AWVALID(mem.AWVALID),
        .M_AXI_AWREADY(mem.AWREADY),
        .M_AXI_WDATA(mem.WDATA),
        .M_AXI_WSTRB(mem.WSTRB),
        .M_AXI_WLAST(mem.WLAST),
        .M_AXI_WVALID(mem.WVALID),
        .M_AXI_WREADY(mem.WREADY),
        .M_AXI_BRESP(mem.BRESP),
        .M_AXI_BVALID(mem.BVALID),
        .M_AXI_BREADY(mem.BREADY)
    );

    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    function automatic logic [31:0] make_policy(
        input logic [1:0] initial_level,
        input logic [7:0] high_count,
        input logic [7:0] low_count,
        input logic [7:0] hold_count
    );
        return {6'd0, initial_level, high_count, low_count, hold_count};
    endfunction

    task automatic read_level(output logic [1:0] level);
        logic [31:0] value;
        ctrl.read(REG_ADAPT_CTRL, value);
        level = value[2:1];
        if (!value[3]) begin
            errors++;
            $display("ERROR: Adaptive configuration reported invalid");
        end
    endtask

    task automatic wait_busy;
        logic [31:0] status;
        int unsigned count;

        count = 0;
        status = 32'd0;
        while (!status[0] && (count < 1000)) begin
            ctrl.read(REG_STATUS, status);
            count++;
        end
        if (!status[0]) begin
            errors++;
            $display("ERROR: DMA did not enter BUSY");
        end
    endtask

    task automatic wait_done;
        logic [31:0] status;
        int unsigned count;

        count = 0;
        status = 32'd1;
        while (status[0] && (count < 500000)) begin
            ctrl.read(REG_STATUS, status);
            if (status[2]) begin
                errors++;
                $display("ERROR: DMA error status");
            end
            count++;
        end
        if (status[0]) begin
            errors++;
            $display("ERROR: DMA completion timeout");
        end
    endtask

    task automatic drive_to_level(input logic [1:0] target,
                                  input logic [31:0] sample);
        logic [1:0] level;
        logic [31:0] status;
        int unsigned count;

        read_level(level);
        count = 0;
        while ((level != target) && (count < 40)) begin
            ctrl.write(REG_LAT_SAMPLE, sample);
            read_level(level);
            ctrl.read(REG_STATUS, status);
            if (!status[0]) begin
                errors++;
                $display("ERROR: DMA ended before Adaptive transition");
                count = 40;
            end
            // Software feedback arrives much slower than an AXI beat.  Keep
            // each selected level active long enough to exercise its RBR path.
            repeat (40) @(posedge CLK);
            count++;
        end

        if (level != target) begin
            errors++;
            $display("ERROR: level=%0d target=%0d after %0d samples",
                     level, target, count);
        end else begin
            $display("LEVEL: reached L%0d after %0d samples", target, count);
        end
    endtask

    property p_ar_stable;
        @(posedge CLK) disable iff (!RSTN)
        mem.ARVALID && !mem.ARREADY
        |=> mem.ARVALID && $stable({mem.ARADDR, mem.ARLEN,
                                   mem.ARSIZE, mem.ARBURST});
    endproperty

    property p_aw_stable;
        @(posedge CLK) disable iff (!RSTN)
        mem.AWVALID && !mem.AWREADY
        |=> mem.AWVALID && $stable({mem.AWADDR, mem.AWLEN,
                                   mem.AWSIZE, mem.AWBURST});
    endproperty

    property p_w_stable;
        @(posedge CLK) disable iff (!RSTN)
        mem.WVALID && !mem.WREADY
        |=> mem.WVALID && $stable({mem.WDATA, mem.WSTRB, mem.WLAST});
    endproperty

    assert property (p_ar_stable) else begin
        assertion_errors++;
        $error("ASSERT: AR changed while stalled");
    end

    assert property (p_aw_stable) else begin
        assertion_errors++;
        $error("ASSERT: AW changed while stalled");
    end

    assert property (p_w_stable) else begin
        assertion_errors++;
        $error("ASSERT: W changed while stalled");
    end

    always @(posedge CLK) begin
        if (RSTN && dut.adapt_enable && dut.adapt_config_valid) begin
            level_mask[dut.adapt_level] <= 1'b1;
            rbr_level_mask[dut.adapt_level] <= 1'b1;
            if ((dut.cfg_burst_beats != 8'd16) ||
                (dut.cfg_rd_out_limit != 2'd2) ||
                (dut.cfg_wr_out_limit != 2'd2) ||
                (dut.cfg_rbr_enable != 2'd3)) begin
                errors++;
                $display("ERROR: RBR policy common configuration mismatch");
            end
            case (dut.adapt_level)
                2'd0: begin
                    if ((dut.cfg_r_delta_q8 != 16'd256) ||
                        (dut.cfg_w_delta_q8 != 16'd256)) errors++;
                end
                2'd1: begin
                    if ((dut.cfg_r_delta_q8 != 16'd128) ||
                        (dut.cfg_w_delta_q8 != 16'd128)) errors++;
                end
                2'd2: begin
                    if ((dut.cfg_r_delta_q8 != 16'd64) ||
                        (dut.cfg_w_delta_q8 != 16'd64)) errors++;
                end
                default: begin
                    if ((dut.cfg_r_delta_q8 != 16'd0) ||
                        (dut.cfg_w_delta_q8 != 16'd0)) errors++;
                end
            endcase
        end

        if (dut.r_wait_active || dut.w_wait_active)
            saw_rbr_wait <= 1'b1;

        if (RSTN) begin
            if ((mem.RVALID && mem.RREADY) !=
                (dut.dma_rvalid && dut.dma_rready)) begin
                assertion_errors++;
                $error("ASSERT: read regulator handshake mismatch");
            end
            if ((mem.WVALID && mem.WREADY) !=
                (dut.dma_wvalid && dut.dma_wready)) begin
                assertion_errors++;
                $error("ASSERT: write regulator handshake mismatch");
            end
        end
    end

    initial begin : test_main
        logic [1:0] level;
        logic [31:0] status;

        errors = 0;
        assertion_errors = 0;
        level_mask = 4'b0000;
        rbr_level_mask = 4'b0000;
        saw_rbr_wait = 1'b0;

        payload = new[COPY_BYTES];
        foreach (payload[i])
            payload[i] = byte'((i * 29 + 8'h63) & 8'hff);

        RSTN = 1'b0;
        ctrl.init_master();
        mem.set_stalls(1'b1);
        repeat (5) @(posedge CLK);
        @(negedge CLK);
        RSTN = 1'b1;
        repeat (3) @(posedge CLK);

        mem.load_region(SRC_ADDR, payload);
        mem.fill_region(DST_ADDR, COPY_BYTES, 8'haa);

        // Initial L3, two confirmations in each direction and one held sample.
        ctrl.write(REG_LAT_LIMITS, {16'd16000, 16'd14000});
        ctrl.write(REG_ADAPT_POLICY,
                   make_policy(2'd3, 8'd2, 8'd2, 8'd1));
        ctrl.write(REG_ADAPT_CTRL, ADAPT_ENABLE | ADAPT_RESTART);
        read_level(level);
        if (level != 2'd3) begin
            errors++;
            $display("ERROR: restart did not load L3");
        end

        ctrl.write(REG_SRC, SRC_ADDR);
        ctrl.write(REG_DST, DST_ADDR);
        ctrl.write(REG_BYTES, COPY_BYTES);
        ctrl.write(REG_CTRL, 32'h0000_0001);
        wait_busy();

        // One DMA command remains active while hardware moves down and back up.
        drive_to_level(2'd0, 32'd18000);
        drive_to_level(2'd3, 32'd12000);

        ctrl.read(REG_STATUS, status);
        if (!status[0]) begin
            errors++;
            $display("ERROR: Adaptive sequence did not fully overlap DMA");
        end

        wait_done();
        errors += mem.compare_region(DST_ADDR, payload);

        // The board program runs several commands without resetting the
        // Adaptive controller. Repeat that sequence here so restart/reset
        // mistakes are not hidden by a one-command test.
        for (int unsigned command = 1; command < 8; command++) begin
            mem.fill_region(DST_ADDR, COPY_BYTES, 8'haa);
            ctrl.write(REG_CTRL, 32'h0000_0001);
            wait_busy();

            if (command[0])
                drive_to_level(2'd0, 32'd18000);
            else
                drive_to_level(2'd3, 32'd12000);

            wait_done();
            errors += mem.compare_region(DST_ADDR, payload);
        end

        errors += mem.protocol_errors;
        errors += mem.wlast_errors;
        errors += ctrl.protocol_errors;
        errors += assertion_errors;

        if (rbr_level_mask != 4'b1111) begin
            errors++;
            $display("COVERAGE_ERROR: rbr=%04b", rbr_level_mask);
        end
        if (!saw_rbr_wait) begin
            errors++;
            $display("COVERAGE_ERROR: wait=%0b", saw_rbr_wait);
        end

        $display("SUMMARY: rbr=%04b wait=%0b errors=%0d",
                 rbr_level_mask, saw_rbr_wait, errors);
        if (errors == 0)
            $display("PASS: Adaptive DMA integration test complete");
        else
            $display("FAIL: Adaptive DMA integration errors=%0d", errors);

        $finish;
    end

    initial begin : timeout_guard
        #20_000_000;
        $fatal(1, "TB timeout");
    end

endmodule
