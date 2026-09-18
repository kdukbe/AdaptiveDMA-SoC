`timescale 1ns/1ps

module tb_dma_rbr;
    import dma_pkg::*;

    logic CLK;
    logic RSTN;
    int unsigned assertion_errors;
    int seed;

    axi_lite_if ctrl(CLK);
    axi_full_if mem(CLK);

    assign ctrl.ARESETN = RSTN;
    assign mem.ARESETN  = RSTN;
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

    // AXI requires VALID and its payload to remain stable while READY is low.
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

    property p_r_stable;
        @(posedge CLK) disable iff (!RSTN)
        mem.RVALID && !mem.RREADY
        |=> mem.RVALID && $stable({mem.RDATA, mem.RRESP, mem.RLAST});
    endproperty

    property p_b_stable;
        @(posedge CLK) disable iff (!RSTN)
        mem.BVALID && !mem.BREADY
        |=> mem.BVALID && $stable(mem.BRESP);
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

    assert property (p_r_stable) else begin
        assertion_errors++;
        $error("ASSERT: R changed while stalled");
    end

    assert property (p_b_stable) else begin
        assertion_errors++;
        $error("ASSERT: B changed while stalled");
    end

    // A regulator may block a transfer, but it must never create or consume a
    // handshake on only one side of itself.
    always @(posedge CLK) begin
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

            if (dut.r_wait_active && mem.RVALID && mem.RREADY) begin
                assertion_errors++;
                $error("ASSERT: read handshake occurred during RBR WAIT");
            end

            if (dut.w_wait_active && mem.WVALID && mem.WREADY) begin
                assertion_errors++;
                $error("ASSERT: write handshake occurred during RBR WAIT");
            end
        end
    end

    initial begin : test_main
        dma_environment env;
        int unsigned final_errors;

        assertion_errors = 0;
        seed = 32'h2026_0816;
        seed = $urandom(seed);

        RSTN = 1'b0;
        ctrl.init_master();
        mem.set_stalls(0);

        repeat (5) @(posedge CLK);
        @(negedge CLK);
        RSTN = 1'b1;
        repeat (3) @(posedge CLK);

        env = new(ctrl, mem, 20);
        env.run();

        env.coverage.report();
        final_errors = env.errors + assertion_errors;
        if (env.coverage.missing_count() != 0) begin
            final_errors += env.coverage.missing_count();
            $display("COVERAGE_ERROR: %0d required bins were not observed",
                     env.coverage.missing_count());
        end

        $display("SUMMARY: tests=%0d errors=%0d assertions=%0d",
                 env.driver.tests, final_errors, assertion_errors);

        if (final_errors == 0)
            $display("PASS: SystemVerilog DMA/RBR regression complete");
        else
            $display("FAIL: SystemVerilog DMA/RBR regression errors=%0d",
                     final_errors);

        $finish;
    end

    initial begin : timeout_guard
        #100_000_000;
        $fatal(1, "TB timeout");
    end

endmodule
